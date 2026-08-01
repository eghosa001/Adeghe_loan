import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_service.dart';

class BackupService {
  BackupService(this._databaseService);

  final DatabaseService _databaseService;

  static const _dbArchiveEntry = 'loantrack.db';
  static const _documentsArchivePrefix = 'secure_documents/';

  /// A real SQLite (or SQLCipher) file begins with the 16-byte format magic.
  static bool isSqliteFile(List<int> bytes) {
    if (bytes.length < 16) return false;
    return String.fromCharCodes(bytes.take(16).toList()) ==
        'SQLite format 3\u0000';
  }

  /// Determines whether [bytes] look like a ZIP archive (container format).
  static bool isZipArchive(List<int> bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
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
        '${root.path}${Platform.pathSeparator}secure_documents');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Creates a backup containing the encrypted database AND the encrypted
  /// customer documents in `secure_documents/` (ZIP container).
  Future<File> createBackup() async {
    await _databaseService.close();
    try {
      final source = File(await _databaseService.databasePath);
      if (!await source.exists()) {
        throw Exception('Database file not found for backup.');
      }

      final archive = Archive();
      final dbBytes = await source.readAsBytes();
      archive.addFile(
          ArchiveFile(_dbArchiveEntry, dbBytes.length, dbBytes));

      final docsDirectory = await _secureDocumentsDirectory();
      final docFiles = await docsDirectory
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      for (final doc in docFiles) {
        final bytes = await doc.readAsBytes();
        archive.addFile(ArchiveFile(
            '$_documentsArchivePrefix${basename(doc.path)}',
            bytes.length,
            bytes));
      }

      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        throw Exception('Backup archive could not be written.');
      }

      final backupFileName =
          'adeghe_backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}${AppConstants.backupFileExtension}';
      final target = File(join((await backupDirectory).path, backupFileName));
      await target.writeAsBytes(zipBytes, flush: true);
      return target;
    } finally {
      await _databaseService.database;
    }
  }

  /// Creates a backup automatically when enabled in settings and none was made
  /// in the last 24 hours. Safe to call on unlock — errors are swallowed so a
  /// backup failure never blocks the user.
  Future<void> maybeAutoBackup() async {
    try {
      final db = await _databaseService.database;
      final enabledRows = await db.query('settings',
          where: "key = 'auto_backup_enabled'", limit: 1);
      if (enabledRows.isEmpty || enabledRows.first['value'] != '1') return;

      final lastRows = await db.query('settings',
          where: "key = 'last_backup_date'", limit: 1);
      final last = lastRows.isEmpty
          ? null
          : DateTime.tryParse(lastRows.first['value'] as String? ?? '');
      if (last != null && DateTime.now().difference(last).inHours < 24) return;

      await createBackup();
      final reopened = await _databaseService.database;
      await reopened.insert(
        'settings',
        {
          'key': 'last_backup_date',
          'value': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Auto-backup is best-effort; never surface errors here.
    }
  }

  Future<List<File>> listBackups() async {
    final directory = await backupDirectory;
    final backups = await directory
        .list()
        .where((entry) =>
            entry is File && entry.path.endsWith(AppConstants.backupFileExtension))
        .cast<File>()
        .toList();
    backups.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return backups;
  }

  Future<void> deleteBackup(String fileName) async {
    final file = File(join((await backupDirectory).path, fileName));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> restoreBackup(File backupFile) async {
    if (!await backupFile.exists()) {
      throw Exception('Selected backup file does not exist.');
    }

    final bytes = await backupFile.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Selected backup file is empty.');
    }

    // Two supported formats:
    //  - legacy: a raw (encrypted) SQLite database copy
    //  - current: a ZIP container holding the DB plus secure_documents/
    final isLegacy = BackupService.isSqliteFile(bytes.take(16).toList());
    if (!isLegacy && !BackupService.isZipArchive(bytes)) {
      throw Exception('Selected file is not a valid database backup.');
    }

    // Extract candidate DB bytes into a temp file BEFORE touching the live DB.
    final targetPath = await _databaseService.databasePath;
    final tempPath = '$targetPath.restore.tmp';
    final tempFile = File(tempPath);
    if (await tempFile.exists()) await tempFile.delete();

    Map<String, Uint8List> documentFiles = {};
    if (isLegacy) {
      await backupFile.copy(tempPath);
    } else {
      final archive = ZipDecoder().decodeBytes(bytes);
      Uint8List? dbContent;
      for (final entry in archive.files) {
        if (entry.isFile && entry.name == _dbArchiveEntry) {
          dbContent = entry.content;
        } else if (entry.isFile &&
            entry.name.startsWith(_documentsArchivePrefix)) {
          documentFiles[basename(entry.name)] = entry.content ?? Uint8List(0);
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
          'your current data is unchanged.');
    }

    // Swap: close the live DB, move the current one aside, move the verified
    // backup into place. Roll back on any failure.
    final rollbackPath = '$targetPath.old';
    final rollbackFile = File(rollbackPath);
    final targetFile = File(targetPath);
    await _databaseService.close();
    try {
      if (await rollbackFile.exists()) await rollbackFile.delete();
      if (await targetFile.exists()) {
        await targetFile.rename(rollbackPath);
      }
      await tempFile.rename(targetPath);
    } catch (_) {
      if (await rollbackFile.exists() && !await targetFile.exists()) {
        await rollbackFile.rename(targetPath);
      }
      if (await tempFile.exists()) await tempFile.delete();
      rethrow;
    } finally {
      if (await rollbackFile.exists()) await rollbackFile.delete();
    }

    // Replace the encrypted document files that came with the backup, then
    // reopen the database.
    try {
      if (documentFiles.isNotEmpty) {
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
          await File(join(docsDirectory.path, entry.key))
              .writeAsBytes(entry.value, flush: true);
        }
      }
    } finally {
      await _databaseService.database;
    }
  }
}
