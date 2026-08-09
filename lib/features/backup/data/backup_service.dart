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

  /// Serializes backup create/restore. Without this, an auto-backup firing at
  /// unlock could run concurrently with a manual backup (or a restore), both
  /// reading/writing the live DB and writing to the same backup folder.
  bool _transferInProgress = false;

  static const _dbArchiveEntry = 'loantrack.db';
  static const _documentsArchivePrefix = 'secure_documents/';

  /// Marker for the encrypted container format: `LTBK` + a version byte. New
  /// backups are an AES-GCM-encrypted ZIP; older backups (raw encrypted DB or
  /// a plain ZIP) are still accepted on restore.
  static const List<int> _containerHeader = [0x4c, 0x54, 0x42, 0x4b, 0x31];
  static const _ivLength = 12; // Standard for GCM

  /// 8 random hex chars, appended to backup filenames so two backups created in
  /// the same instant can never collide.
  static String _randomHexSuffix() {
    final r = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 8; i++) {
      buffer.write(r.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  /// A real SQLite (or SQLCipher) file begins with the 16-byte format magic.
  static bool isSqliteFile(List<int> bytes) {
    if (bytes.length < 16) return false;
    return String.fromCharCodes(bytes.take(16).toList()) ==
        'SQLite format 3\u0000';
  }

  /// Determines whether [bytes] look like a ZIP archive (legacy container
  /// format).
  static bool isZipArchive(List<int> bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
  }

  /// Determines whether [bytes] start with the encrypted-container marker
  /// (`LTBK1`), i.e. an AES-GCM-encrypted ZIP written by this app.
  static bool isEncryptedContainer(List<int> bytes) {
    if (bytes.length < _containerHeader.length) return false;
    for (var i = 0; i < _containerHeader.length; i++) {
      if (bytes[i] != _containerHeader[i]) return false;
    }
    return true;
  }

  /// Deterministic 32-byte AES key derived from the app's database key, so the
  /// backup container uses the same secret already held in secure storage.
  Future<encrypt.Key> _containerKey() async => encrypt.Key(
    Uint8List.fromList(
      sha256.convert(utf8.encode(await _secureStorage.getDatabaseKey())).bytes,
    ),
  );

  /// Encrypts [plaintext] as `LTBK1 + IV + AES-GCM ciphertext`.
  Future<Uint8List> _encryptContainer(Uint8List plaintext) async {
    final iv = encrypt.IV.fromSecureRandom(_ivLength);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(await _containerKey(), mode: encrypt.AESMode.gcm),
    );
    final cipher = encrypter.encryptBytes(plaintext, iv: iv);
    return Uint8List.fromList([
      ..._containerHeader,
      ...iv.bytes,
      ...cipher.bytes,
    ]);
  }

  /// Decrypts an [encrypt.ContainerFormat] ([_encryptContainer]) payload back to
  /// its ZIP bytes, returning null if the header is missing or the key does not
  /// match (e.g. a restored device with a different DB key).
  Future<Uint8List?> _decryptContainer(List<int> bytes) async {
    if (!isEncryptedContainer(bytes) ||
        bytes.length <= _containerHeader.length + _ivLength) {
      return null;
    }
    final ivStart = _containerHeader.length;
    final iv = encrypt.IV(
      Uint8List.fromList(bytes.sublist(ivStart, ivStart + _ivLength)),
    );
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
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Directory> _secureDocumentsDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}secure_documents',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Creates a backup containing the encrypted database AND the encrypted
  /// customer documents in `secure_documents/` (ZIP container). The DB is
  /// closed for the duration and reopened under exclusive access so no other
  /// caller can grab a half-open connection mid-backup (M14).
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
        final docFiles = await docsDirectory
            .list()
            .where((e) => e is File)
            .cast<File>()
            .toList();
        for (final doc in docFiles) {
          final bytes = await doc.readAsBytes();
          archive.addFile(
            ArchiveFile(
              '$_documentsArchivePrefix${basename(doc.path)}',
              bytes.length,
              bytes,
            ),
          );
        }

        final zipBytes = ZipEncoder().encode(archive);
        if (zipBytes == null) {
          throw Exception('Backup archive could not be written.');
        }

        // Encrypt the container with the app key so the ZIP (and its file names
        // and sizes) never sit on disk in the clear. The enclosed DB and document
        // files are already encrypted separately; this adds an outer layer.
        final payload = await _encryptContainer(Uint8List.fromList(zipBytes));

        final backupFileName =
            'adeghe_backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}_'
            '${_randomHexSuffix()}.${AppConstants.backupFileExtension}';
        final target = File(join((await backupDirectory).path, backupFileName));
        await target.writeAsBytes(payload, flush: true);

        // On Windows, attempt to restrict the backup file's ACL to the current
        // user. This is best-effort and will not fail the backup if it cannot be
        // applied.
        if (Platform.isWindows) {
          try {
            final user = Platform.environment['USERNAME'] ?? '';
            if (user.isNotEmpty) {
              await Process.run('icacls', [
                target.path,
                '/inheritance:r',
                '/grant:r',
                '$user:R',
              ]);
            }
          } catch (_) {
            // Ignore failures; backup creation succeeded regardless of ACL.
          }
        }

        return target;
      });
    } finally {
      _transferInProgress = false;
    }
  }

  /// Creates a backup automatically when enabled in settings and none was made
  /// in the last 24 hours. Safe to call on unlock — errors are swallowed so a
  /// backup failure never blocks the user.
  Future<void> maybeAutoBackup() async {
    try {
      final db = await _databaseService.database;
      final enabledRows = await db.query(
        'settings',
        where: "key = 'auto_backup_enabled'",
        limit: 1,
      );
      // A missing row means "default on" — the settings screen renders the
      // toggle as enabled when no value exists (`?? '1'`). Previously the two
      // disagreed, so a fresh install silently never auto-backed-up.
      final enabledValue = enabledRows.isEmpty
          ? '1'
          : enabledRows.first['value'];
      if (enabledValue != '1') return;

      final lastRows = await db.query(
        'settings',
        where: "key = 'last_backup_date'",
        limit: 1,
      );
      final last = lastRows.isEmpty
          ? null
          : DateTime.tryParse(lastRows.first['value'] as String? ?? '');
      if (last != null && DateTime.now().difference(last).inHours < 24) return;

      await createBackup();
      final reopened = await _databaseService.database;
      await reopened.insert('settings', {
        'key': 'last_backup_date',
        'value': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      // Auto-backup is best-effort; never surface errors here.
    }
  }

  Future<List<File>> listBackups() async {
    final directory = await backupDirectory;
    final backups = await directory
        .list()
        .where(
          (entry) =>
              entry is File &&
              entry.path.endsWith(AppConstants.backupFileExtension),
        )
        .cast<File>()
        .toList();
    backups.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    return backups;
  }

  Future<void> deleteBackup(String fileName) async {
    // Guard against path traversal: `fileName` may come from user-typed input
    // or a stale list entry and must never resolve outside the backup folder.
    if (basename(fileName) != fileName) {
      throw Exception('Invalid backup file name.');
    }
    final file = File(join((await backupDirectory).path, fileName));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> restoreBackup(File backupFile) async {
    if (_transferInProgress) {
      throw Exception(
        'A backup or restore is already in progress. Please wait.',
      );
    }
    _transferInProgress = true;
    try {
      if (!await backupFile.exists()) {
        throw Exception('Selected backup file does not exist.');
      }

      var bytes = await backupFile.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('Selected backup file is empty.');
      }

      // Three supported formats:
      //  - encrypted container (current): LTBK1 + AES-GCM-encrypted ZIP
      //  - legacy: a raw (encrypted) SQLite database copy
      //  - legacy: a plain ZIP holding the DB plus secure_documents/
      final isEncrypted = BackupService.isEncryptedContainer(bytes);
      final isLegacyRaw =
          !isEncrypted && BackupService.isSqliteFile(bytes.take(16).toList());
      final isLegacyZip = !isEncrypted && BackupService.isZipArchive(bytes);
      if (isEncrypted) {
        // Decrypt back to ZIP bytes using the current DB key. A backup taken on
        // a device with a different DB key cannot be decrypted.
        final decrypted = await _decryptContainer(bytes);
        if (decrypted == null) {
          throw Exception(
            'This backup was encrypted with a different app key and cannot be '
            'restored on this device.',
          );
        }
        bytes = decrypted;
        if (!isZipArchive(bytes)) {
          throw Exception('Decrypted backup is not a valid archive.');
        }
      } else if (!isLegacyRaw && !isLegacyZip) {
        throw Exception('Selected file is not a valid database backup.');
      }

      // Extract candidate DB bytes into a temp file BEFORE touching the live DB.
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
          } else if (entry.isFile &&
              entry.name.startsWith(_documentsArchivePrefix)) {
            // A missing/null entry payload is corruption, not an empty document —
            // restoring it would write a zero-byte file that can never decrypt.
            final content = entry.content;
            if (content == null) {
              if (await tempFile.exists()) await tempFile.delete();
              throw Exception(
                'A document inside the backup could not be read.',
              );
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

      // Verify the candidate DB opens with the app key. The live database is NOT
      // touched until verification succeeds.
      final verified = await _databaseService.verifyDatabaseFile(tempPath);
      if (!verified) {
        if (await tempFile.exists()) await tempFile.delete();
        throw Exception(
          'Backup could not be opened with the app key. Restore aborted — '
          'your current data is unchanged.',
        );
      }

      // Swap: close the live DB, move the current one aside, move the verified
      // backup into place. Roll back on any failure. The swap runs under
      // exclusive access so no concurrent caller can open the DB mid-swap, and
      // the database is reopened (or the old file rolled back) before any caller
      // proceeds (M14).
      final rollbackPath = '$targetPath.old';
      final rollbackFile = File(rollbackPath);
      final targetFile = File(targetPath);
      await _databaseService.withExclusiveAccess(() async {
        try {
          if (await rollbackFile.exists()) await rollbackFile.delete();
          if (await targetFile.exists()) {
            await targetFile.rename(rollbackPath);
          }
          await tempFile.rename(targetPath);

          // Replace the encrypted document files so they match the restored DB.
          // This runs inside the exclusive block (atomic with the DB swap) and
          // ALWAYS reconciles: any local document file not present in the backup
          // is removed, so a backup that contains no documents cannot leave stale
          // files from another dataset behind, and a failed reconcile triggers
          // the same rollback that protects the database file.
          final docsDirectory = await _secureDocumentsDirectory();
          final existing = await docsDirectory
              .list()
              .where((e) => e is File)
              .cast<File>()
              .toList();
          for (final file in existing) {
            if (await file.exists()) await file.delete();
          }
          for (final entry in documentFiles.entries) {
            await File(
              join(docsDirectory.path, entry.key),
            ).writeAsBytes(entry.value, flush: true);
          }
        } catch (_) {
          if (await rollbackFile.exists() && !await targetFile.exists()) {
            await rollbackFile.rename(targetPath);
          }
          if (await tempFile.exists()) await tempFile.delete();
          rethrow;
        } finally {
          if (await rollbackFile.exists()) await rollbackFile.delete();
        }
      });
    } finally {
      _transferInProgress = false;
    }
  }
}
