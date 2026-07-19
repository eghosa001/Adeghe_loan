import '../data/backup_service.dart';

class AutoBackupScheduler {
  AutoBackupScheduler(this._backupService);
  final BackupService _backupService;

  static const Duration _backupInterval = Duration(days: 7);

  Future<DateTime?> getLastBackupTime() async {
    final backups = await _backupService.listBackups();
    if (backups.isEmpty) return null;
    return backups.first.lastModifiedSync();
  }

  Future<bool> shouldBackup() async {
    final lastBackup = await getLastBackupTime();
    if (lastBackup == null) return true;
    return DateTime.now().difference(lastBackup) >= _backupInterval;
  }

  Future<void> runIfDue() async {
    if (await shouldBackup()) {
      await _backupService.createBackup();
    }
  }
}
