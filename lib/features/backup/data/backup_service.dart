import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_service.dart';
import '../../../core/security/secure_storage_service.dart';

class BackupService {
  BackupService(this._databaseService, this._secureStorage);

  final DatabaseService _databaseService;
  final SecureStorageService _secureStorage;
  bool _transferInProgress = false;

  static const _dbArchiveEntry = 'loantrack.db';
  static const _documentsArchivePrefix = 'secure_documents/';
  static const List<int> _containerHeader = [0x4c, 0x54, 0x42, 0x4b, 0x31];
  static const _ivLength = 12;

  static String _randomHexSuffix() {
    final r = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 8; i++) {
      buffer.write(r.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  static bool isSqliteFile(List<int> bytes) {
    if (bytes.length < 16) return false;
    return String.fromCharCodes(bytes.take(16).toList()) ==
        'SQLite format 3\u0000';
  }

  static bool isZipArchive(List<int> bytes) {
    return bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B &&
        bytes[2] == 0x03 && bytes[3] == 0x04;
  }

  static bool isEncryptedContainer(List<int> bytes) {
    if (bytes.length < _containerHeader.length) return false;
    for (var i = 0; i < _containerHeader.length; i++) {
      if (bytes[i] != _containerHeader[i]) return false;
    }
    return true;
  }

  Future<encrypt.Key> _containerKey() async => encrypt.Key(
    Uint8List.fromList(
      sha256.convert(utf8.encode(await _secureStorage.getDatabaseKey())).bytes,
    ),
  );

  Future<Uint8List> _encryptContainer(Uint8List plaintext) async {
    final iv = encrypt.IV.fromSecureRandom(_ivLength);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(await _containerKey(), mode: encrypt.AESMode.gcm),
    );
    final cipher = encrypter.encryptBytes(plaintext, iv: iv);
    return Uint8List.fromList([..._containerHeader, ...iv.bytes, ...cipher.bytes]);
  }

  Future<Uint8List?> _decryptContainer(List<int> bytes) async {
    if (!isEncryptedContainer(bytes) ||
        bytes.length <= _containerHeader.length + _ivLength) return null;
    final ivStart = _containerHeader.length;
    final iv = encrypt.IV(Uint8List.fromList(
        bytes.sublist(ivStart, ivStart + _ivLength)));
    final ciphertext = Uint8List.fromList(bytes.sublist(ivStart + _ivLength));
    try {
      final encrypter = encrypt.Encrypter(
        encrypt.AES(await _containerKey(), mode: encrypt.AESMode.gcm),
      );
      return Uint8List.fromList(
        encrypter.decryptBytes(encrypt.Encrypted(ciphertext), iv: iv),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Directory> get backupDirectory async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(join(root.path, AppConstants.backupFolderName));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _secureDocumentsDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}secure_documents',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> createBackup() async {
    if (_transferInProgress) {
      throw Exception('A backup is already in progress. Please wait.');
    }
    _transferInProgress = true;
    try {
      return await _databaseService.withExclusiveAccess(() async {
        final source = File(await _databaseService.databasePath);
        if (!await source.exists()) {
          throw Exception('Database file not found for backup.');
        }
        final archive = Archive();
        final dbBytes = await source.readAsBytes();
        archive.addFile(ArchiveFile(_dbArchiveEntry, dbBytes.length, dbBytes));
        final docsDirectory = await _secureDocumentsDirectory();
        final docFiles = await docsDirectory.list().where((e) => e is File)
            .cast<File>().toList();
        for (final doc in docFiles) {
          final bytes = await doc.readAsBytes();
          archive.addFile(ArchiveFile(
            '$_documentsArchivePrefix${basename(doc.path)}', bytes.length, bytes));
        }
        final zipBytes = ZipEncoder().encode(archive);
        if (zipBytes == null) throw Exception('Backup archive could not be written.');
        final payload = await _encryptContainer(Uint8List.fromList(zipBytes));
        final backupFileName =
            'adeghe_backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}_'
            '${_randomHexSuffix()}.${AppConstants.backupFileExtension}';
        final target = File(join((await backupDirectory).path, backupFileName));
        await target.writeAsBytes(payload, flush: true);
        if (Platform.isWindows) {
          try {
            final user = Platform.environment['USERNAME'] ?? '';
            if (user.isNotEmpty) {
              await Process.run('icacls', [target.path, '/inheritance:r', '/grant:r', '$user:R']);
            }
          } catch (_) {}
        }
        return target;
      });
    } finally {
      _transferInProgress = false;
    }
  }

  Future<void> maybeAutoBackup() async {
    try {
      final db = await _databaseService.database;
      final enabledRows = await db.query('settings',
          where: "key = 'auto_backup_enabled'", limit: 1);
      final enabledValue = enabledRows.isEmpty ? '1' : enabledRows.first['value'];
      if (enabledValue != '1') return;
      final lastRows = await db.query('settings',
          where: "key = 'last_backup_date'", limit: 1);
      final last = lastRows.isEmpty
          ? null
          : DateTime.tryParse(lastRows.first['value'] as String? ?? '');
      if (last != null && DateTime.now().difference(last).inHours < 24) return;
      await createBackup();
      final reopened = await _databaseService.database;
      await reopened.insert('settings', {
        'key': 'last_backup_date', 'value': DateTime.now().toIso8601String()
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {}
  }

  Future<List<File>> listBackups() async {
    final directory = await backupDirectory;
    final backups = await directory.list().where((entry) =>
        entry is File && entry.path.endsWith(AppConstants.backupFileExtension))
        .cast<File>().toList();
    backups.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return backups;
  }

  Future<void> deleteBackup(String fileName) async {
    if (basename(fileName) != fileName) throw Exception('Invalid backup file name.');
    final file = File(join((await backupDirectory).path, fileName));
    if (await file.exists()) await file.delete();
  }

  Future<void> restoreBackup(File backupFile) async {
    if (_transferInProgress) {
      throw Exception('A backup or restore is already in progress. Please wait.');
    }
    _transferInProgress = true;
    try {
      if (!await backupFile.exists()) throw Exception('Selected backup file does not exist.');
      var bytes = await backupFile.readAsBytes();
      if (bytes.isEmpty) throw Exception('Selected backup file is empty.');

      final isEncrypted = BackupService.isEncryptedContainer(bytes);
      final isLegacyRaw = !isEncrypted && BackupService.isSqliteFile(bytes.take(16).toList());
      final isLegacyZip = !isEncrypted && BackupService.isZipArchive(bytes);
      if (isEncrypted) {
        final decrypted = await _decryptContainer(bytes);
        if (decrypted == null) {
          throw Exception('This backup was encrypted with a different app key and cannot be restored on this device.');
        }
        bytes = decrypted;
        if (!isZipArchive(bytes)) throw Exception('Decrypted backup is not a valid archive.');
      } else if (!isLegacyRaw && !isLegacyZip) {
        throw Exception('Selected file is not a valid database backup.');
      }

      final targetPath = await _databaseService.databasePath;
      final tempPath = '$targetPath.restore.tmp';
      final tempFile = File(tempPath);
      if (await tempFile.exists()) await tempFile.delete();

      Map<String, Uint8List> documentFiles = {};
      if (isLegacyRaw) {
        await backupFile.copy(tempPath);
      } else {
        final archive = ZipDecoder().decodeBytes(bytes);
        Uint8List? dbContent;
        for (final entry in archive.files) {
          if (entry.isFile && entry.name == _dbArchiveEntry) {
            dbContent = entry.content;
          } else if (entry.isFile && entry.name.startsWith(_documentsArchivePrefix)) {
            final content = entry.content;
            if (content == null) {
              if (await tempFile.exists()) await tempFile.delete();
              throw Exception('A document inside the backup could not be read.');
            }
            final name = basename(entry.name);
            if (name.isNotEmpty && name != '.' && name != '..') {
              documentFiles[name] = content;
            }
          }
        }
        if (dbContent == null || dbContent.isEmpty) {
          if (await tempFile.exists()) await tempFile.delete();
          throw Exception('Backup archive does not contain a database.');
        }
        await tempFile.writeAsBytes(dbContent, flush: true);
      }

      final verified = await _databaseService.verifyDatabaseFile(tempPath);
      if (!verified) {
        if (await tempFile.exists()) await tempFile.delete();
        throw Exception('Backup could not be opened with the app key. Restore aborted — your current data is unchanged.');
      }

      final rollbackPath = '$targetPath.old';
      final rollbackFile = File(rollbackPath);
      final targetFile = File(targetPath);
      final docsDirectory = await _secureDocumentsDirectory();
      final docsRollbackPath = '${docsDirectory.path}.restore-old';
      final docsRollbackDirectory = Directory(docsRollbackPath);
      var databaseSwapped = false;
      var documentsSwapped = false;

      await _databaseService.withExclusiveAccess(() async {
        try {
          // Keep both old datasets until the entire restore has succeeded.
          if (await rollbackFile.exists()) await rollbackFile.delete();
          if (await docsRollbackDirectory.exists()) {
            await docsRollbackDirectory.delete(recursive: true);
          }
          if (await targetFile.exists()) await targetFile.rename(rollbackPath);
          databaseSwapped = true;
          await tempFile.rename(targetPath);

          // Swap the whole document directory so a document write failure can
          // restore the exact previous document set instead of a partial set.
          if (await docsDirectory.exists()) await docsDirectory.rename(docsRollbackPath);
          documentsSwapped = true;
          await docsDirectory.create(recursive: true);
          for (final entry in documentFiles.entries) {
            await File(join(docsDirectory.path, entry.key))
                .writeAsBytes(entry.value, flush: true);
          }

          // Only discard rollback copies after DB and documents both succeed.
          if (await rollbackFile.exists()) await rollbackFile.delete();
          if (await docsRollbackDirectory.exists()) {
            await docsRollbackDirectory.delete(recursive: true);
          }
        } catch (_) {
          // Roll back documents first. If this fails, retain the old directory.
          try {
            if (documentsSwapped) {
              if (await docsDirectory.exists()) await docsDirectory.delete(recursive: true);
              if (await docsRollbackDirectory.exists()) {
                await docsRollbackDirectory.rename(docsDirectory.path);
              }
            }
          } catch (_) {}

          // Crucially, delete the newly installed DB before restoring the old DB.
          // The previous code only restored when the target did NOT exist, which
          // could leave the new DB active and then delete the only rollback copy.
          try {
            if (databaseSwapped && await targetFile.exists()) await targetFile.delete();
            if (await rollbackFile.exists() && !await targetFile.exists()) {
              await rollbackFile.rename(targetPath);
            }
          } catch (_) {}

          if (await tempFile.exists()) await tempFile.delete();
          rethrow;
        }
      });
    } finally {
      _transferInProgress = false;
    }
  }
}
