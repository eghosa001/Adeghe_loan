import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_service.dart';

class BackupService {
  BackupService(this._databaseService);

  final DatabaseService _databaseService;

  Future<Directory> get backupDirectory async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(join(root.path, AppConstants.backupFolderName));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> createBackup() async {
    await _databaseService.close();
    final source = File(await _databaseService.databasePath);
    if (!await source.exists()) {
      throw Exception('Database file not found for backup.');
    }

    final backupFileName =
        'loantrack_backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}${AppConstants.backupFileExtension}';
    final target = File(join((await backupDirectory).path, backupFileName));
    final result = await source.copy(target.path);
    await _databaseService.database;
    return result;
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

    await _databaseService.close();
    final targetPath = await _databaseService.databasePath;
    final targetFile = File(targetPath);
    await targetFile.writeAsBytes(await backupFile.readAsBytes(), flush: true);
    await _databaseService.database;
  }
}
