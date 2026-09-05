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
  static const _manifestArchiveEntry = 'backup_manifest.json';
  static const _documentsArchivePrefix = 'secure_documents/';
  static const List<int> _legacyContainerHeader = [0x4c, 0x54, 0x42, 0x4b, 0x31];
  static const List<int> _portableContainerHeader = [0x4c, 0x54, 0x42, 0x4b, 0x32];
  static const _ivLength = 12;
  static const _portableSaltLength = 16;
  static const _backupVersion = 2;

  static String _randomHexSuffix() {
    final r = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 8; i++) buffer.write(r.nextInt(16).toRadixString(16));
    return buffer.toString();
  }

  static bool isSqliteFile(List<int> bytes) => bytes.length >= 16 &&
      String.fromCharCodes(bytes.take(16).toList()) == 'SQLite format 3\u0000';

  static bool isZipArchive(List<int> bytes) => bytes.length >= 4 &&
      bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;

  static bool _hasHeader(List<int> bytes, List<int> header) {
    if (bytes.length < header.length) return false;
    for (var i = 0; i < header.length; i++) if (bytes[i] != header[i]) return false;
    return true;
  }

  static bool isEncryptedContainer(List<int> bytes) =>
      _hasHeader(bytes, _legacyContainerHeader) || _hasHeader(bytes, _portableContainerHeader);

  static bool isPortableContainer(List<int> bytes) => _hasHeader(bytes, _portableContainerHeader);

  Future<encrypt.Key> _legacyContainerKey() async => encrypt.Key(Uint8List.fromList(
      sha256.convert(utf8.encode(await _secureStorage.getDatabaseKey())).bytes));

  Future<encrypt.Key> _portableContainerKey({String? recoveryPassword, List<int>? derivedKey, required List<int> salt}) async {
    final encoded = recoveryPassword != null
        ? SecureStorageService.deriveBackupKey(recoveryPassword, salt: salt)
        : SecureStorageService.deriveBackupKeyFromDerivedKey(
            base64UrlEncode(Uint8List.fromList(derivedKey!)), salt: salt);
    return encrypt.Key(Uint8List.fromList(base64Url.decode(encoded)));
  }

  Future<Uint8List> _encryptContainer(Uint8List plaintext, {String? recoveryPassword}) async {
    final salt = Uint8List.fromList(List.generate(_portableSaltLength, (_) => Random.secure().nextInt(256)));
    final iv = encrypt.IV.fromSecureRandom(_ivLength);
    final derived = recoveryPassword == null
        ? await _secureStorage.getRecoveryDerivedKey()
        : null;
    if (recoveryPassword == null && derived == null) {
      throw Exception('A recovery password must be configured before creating a portable backup.');
    }
    final key = await _portableContainerKey(
      recoveryPassword: recoveryPassword,
      derivedKey: derived == null ? null : base64Url.decode(derived),
      salt: salt,
    );
    final cipher = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm))
        .encryptBytes(plaintext, iv: iv);
    return Uint8List.fromList([..._portableContainerHeader, ...salt, ...iv.bytes, ...cipher.bytes]);
  }

  Future<Uint8List?> _decryptContainer(List<int> bytes, {String? recoveryPassword}) async {
    if (!isEncryptedContainer(bytes)) return null;
    final portable = isPortableContainer(bytes);
    final headerLength = portable ? _portableContainerHeader.length : _legacyContainerHeader.length;
    final minimum = headerLength + (portable ? _portableSaltLength : 0) + _ivLength + 16;
    if (bytes.length < minimum) return null;
    var offset = headerLength;
    List<int>? salt;
    if (portable) {
      if (recoveryPassword == null || recoveryPassword.isEmpty) return null;
      salt = bytes.sublist(offset, offset + _portableSaltLength);
      offset += _portableSaltLength;
    }
    final iv = encrypt.IV(Uint8List.fromList(bytes.sublist(offset, offset + _ivLength)));
    offset += _ivLength;
    try {
      final key = portable
          ? await _portableContainerKey(recoveryPassword: recoveryPassword, salt: salt!)
          : await _legacyContainerKey();
      final plain = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm))
          .decryptBytes(encrypt.Encrypted(Uint8List.fromList(bytes.sublist(offset))), iv: iv);
      return Uint8List.fromList(plain);
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
    final directory = Directory('${root.path}${Platform.pathSeparator}secure_documents');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> createBackup({String? recoveryPassword}) async {
    if (_transferInProgress) throw Exception('A backup is already in progress. Please wait.');
    _transferInProgress = true;
    try {
      return await _databaseService.withExclusiveAccess(() async {
        final source = File(await _databaseService.databasePath);
        if (!await source.exists()) throw Exception('Database file not found for backup.');
        final dbKey = await _secureStorage.getDatabaseKey();
        final archive = Archive();
        final dbBytes = await source.readAsBytes();
        archive.addFile(ArchiveFile(_dbArchiveEntry, dbBytes.length, dbBytes));
        final manifest = jsonEncode({
          'format': 'LTBK2',
          'version': _backupVersion,
          'database_key': dbKey,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        final manifestBytes = utf8.encode(manifest);
        archive.addFile(ArchiveFile(_manifestArchiveEntry, manifestBytes.length, manifestBytes));
        final docsDirectory = await _secureDocumentsDirectory();
        final docFiles = await docsDirectory.list().where((e) => e is File).cast<File>().toList();
        final seenNames = <String>{};
        for (final doc in docFiles) {
          final name = basename(doc.path);
          if (name.isEmpty || name == '.' || name == '..' || !seenNames.add(name)) {
            throw Exception('Backup contains an invalid or duplicate document filename.');
          }
          final bytes = await doc.readAsBytes();
          archive.addFile(ArchiveFile('$_documentsArchivePrefix$name', bytes.length, bytes));
        }
        final zipBytes = ZipEncoder().encode(archive);
        if (zipBytes == null) throw Exception('Backup archive could not be written.');
        final payload = await _encryptContainer(Uint8List.fromList(zipBytes), recoveryPassword: recoveryPassword);
        final backupFileName = 'adeghe_backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}_${_randomHexSuffix()}.${AppConstants.backupFileExtension}';
        final target = File(join((await backupDirectory).path, backupFileName));
        await target.writeAsBytes(payload, flush: true);
        if (Platform.isWindows) {
          try {
            final user = Platform.environment['USERNAME'] ?? '';
            if (user.isNotEmpty) await Process.run('icacls', [target.path, '/inheritance:r', '/grant:r', '$user:R']);
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
      final enabledRows = await db.query('settings', where: "key = 'auto_backup_enabled'", limit: 1);
      if ((enabledRows.isEmpty ? '1' : enabledRows.first['value']) != '1') return;
      final lastRows = await db.query('settings', where: "key = 'last_backup_date'", limit: 1);
      final last = lastRows.isEmpty ? null : DateTime.tryParse(lastRows.first['value'] as String? ?? '');
      if (last != null && DateTime.now().difference(last).inHours < 24) return;
      await createBackup();
      final reopened = await _databaseService.database;
      await reopened.insert('settings', {'key': 'last_backup_date', 'value': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {}
  }

  Future<List<File>> listBackups() async {
    final directory = await backupDirectory;
    final backups = await directory.list().where((entry) => entry is File && entry.path.endsWith(AppConstants.backupFileExtension)).cast<File>().toList();
    backups.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return backups;
  }

  Future<void> deleteBackup(String fileName) async {
    if (basename(fileName) != fileName) throw Exception('Invalid backup file name.');
    final file = File(join((await backupDirectory).path, fileName));
    if (await file.exists()) await file.delete();
  }

  Future<void> restoreBackup(File backupFile, {String? recoveryPassword}) async {
    if (_transferInProgress) throw Exception('A backup or restore is already in progress. Please wait.');
    _transferInProgress = true;
    try {
      if (!await backupFile.exists()) throw Exception('Selected backup file does not exist.');
      final originalBytes = await backupFile.readAsBytes();
      if (originalBytes.isEmpty) throw Exception('Selected backup file is empty.');
      final encrypted = isEncryptedContainer(originalBytes);
      final portable = isPortableContainer(originalBytes);
      final legacyRaw = !encrypted && isSqliteFile(originalBytes);
      final legacyZip = !encrypted && isZipArchive(originalBytes);
      if (encrypted) {
        if (portable && (recoveryPassword == null || recoveryPassword.isEmpty)) {
          throw Exception('This portable backup requires its recovery password.');
        }
        final decrypted = await _decryptContainer(originalBytes, recoveryPassword: recoveryPassword);
        if (decrypted == null) throw Exception(portable
            ? 'The recovery password is incorrect or the backup is damaged.'
            : 'This backup was encrypted with a different app key and cannot be restored on this device.');
        if (!isZipArchive(decrypted)) throw Exception('Decrypted backup is not a valid archive.');
      } else if (!legacyRaw && !legacyZip) {
        throw Exception('Selected file is not a valid database backup.');
      }

      var archiveBytes = originalBytes;
      if (encrypted) archiveBytes = (await _decryptContainer(originalBytes, recoveryPassword: recoveryPassword))!;
      final targetPath = await _databaseService.databasePath;
      final tempFile = File('$targetPath.restore.tmp');
      if (await tempFile.exists()) await tempFile.delete();
      var recoveredDbKey = await _secureStorage.getDatabaseKey();
      final originalDbKey = recoveredDbKey;
      final documentFiles = <String, Uint8List>{};
      if (legacyRaw) {
        await backupFile.copy(tempFile.path);
      } else {
        final archive = ZipDecoder().decodeBytes(archiveBytes);
        Uint8List? dbContent;
        Map<String, dynamic>? manifest;
        final seen = <String>{};
        for (final entry in archive.files) {
          if (!entry.isFile) continue;
          if (entry.name == _dbArchiveEntry) {
            if (dbContent != null) throw Exception('Backup contains duplicate database entries.');
            dbContent = Uint8List.fromList(entry.content);
          } else if (entry.name == _manifestArchiveEntry) {
            if (manifest != null) throw Exception('Backup contains duplicate manifest entries.');
            try {
              final decoded = jsonDecode(utf8.decode(entry.content));
              if (decoded is! Map) throw const FormatException();
              manifest = Map<String, dynamic>.from(decoded);
            } catch (_) {
              throw Exception('Backup manifest is invalid.');
            }
          } else if (entry.name.startsWith(_documentsArchivePrefix)) {
            final name = basename(entry.name);
            if (name.isEmpty || name == '.' || name == '..' || !seen.add(name)) {
              throw Exception('Backup contains an invalid or duplicate document entry.');
            }
            documentFiles[name] = Uint8List.fromList(entry.content);
          }
        }
        if (dbContent == null || dbContent.isEmpty) throw Exception('Backup archive does not contain a database.');
        if (portable) {
          if (manifest == null || manifest['format'] != 'LTBK2' || manifest['version'] != _backupVersion) {
            throw Exception('Portable backup manifest is missing or unsupported.');
          }
          final key = manifest['database_key'];
          if (key is! String || key.length < 32 || key.length > 64 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key)) {
            throw Exception('Portable backup contains an invalid database key.');
          }
          try {
            if (base64Url.decode(key).length != 32) throw const FormatException();
          } catch (_) {
            throw Exception('Portable backup contains an invalid database key.');
          }
          recoveredDbKey = key;
        }
        await tempFile.writeAsBytes(dbContent, flush: true);
      }

      if (!await _databaseService.verifyDatabaseFile(tempFile.path, encryptionKey: recoveredDbKey)) {
        if (await tempFile.exists()) await tempFile.delete();
        throw Exception('Backup database could not be opened with its encryption key. Restore aborted — current data is unchanged.');
      }

      final targetFile = File(targetPath);
      final rollbackFile = File('$targetPath.old');
      final docsDirectory = await _secureDocumentsDirectory();
      final docsRollbackDirectory = Directory('${docsDirectory.path}.restore-old');
      var databaseSwapped = false;
      var documentsSwapped = false;
      var keyChanged = false;

      await _databaseService.withExclusiveAccess(() async {
        try {
          if (await rollbackFile.exists()) await rollbackFile.delete();
          if (await docsRollbackDirectory.exists()) await docsRollbackDirectory.delete(recursive: true);
          if (await targetFile.exists()) await targetFile.rename(rollbackFile.path);
          databaseSwapped = true;
          await tempFile.rename(targetPath);
          if (await docsDirectory.exists()) await docsDirectory.rename(docsRollbackDirectory.path);
          documentsSwapped = true;
          await docsDirectory.create(recursive: true);
          for (final entry in documentFiles.entries) {
            await File(join(docsDirectory.path, entry.key)).writeAsBytes(entry.value, flush: true);
          }
          if (portable) {
            await _secureStorage.setDatabaseKey(recoveredDbKey);
            keyChanged = true;
          }
          if (await rollbackFile.exists()) await rollbackFile.delete();
          if (await docsRollbackDirectory.exists()) await docsRollbackDirectory.delete(recursive: true);
        } catch (_) {
          try {
            if (documentsSwapped) {
              if (await docsDirectory.exists()) await docsDirectory.delete(recursive: true);
              if (await docsRollbackDirectory.exists()) await docsRollbackDirectory.rename(docsDirectory.path);
            }
          } catch (_) {}
          try {
            if (databaseSwapped && await targetFile.exists()) await targetFile.delete();
            if (await rollbackFile.exists() && !await targetFile.exists()) await rollbackFile.rename(targetPath);
          } catch (_) {}
          if (keyChanged || portable) {
            try { await _secureStorage.setDatabaseKey(originalDbKey); } catch (_) {}
          }
          if (await tempFile.exists()) await tempFile.delete();
          rethrow;
        }
      });
    } finally {
      _transferInProgress = false;
    }
  }
}
