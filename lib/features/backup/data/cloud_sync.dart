import 'dart:io';

import '../../../core/error/failure.dart';

class BackupMetadata {
  BackupMetadata({
    required this.id,
    required this.fileName,
    required this.uploadedAt,
    required this.sizeBytes,
  });

  final String id;
  final String fileName;
  final DateTime uploadedAt;
  final int sizeBytes;
}

class CloudSync {
  Future<Result<BackupMetadata>> uploadBackup(File backupFile) async {
    return const Result.failure(
      NetworkFailure('Cloud sync is not available — no backend configured.'),
    );
  }

  Future<Result<File>> downloadBackup(String id) async {
    return const Result.failure(
      NetworkFailure('Cloud sync is not available — no backend configured.'),
    );
  }

  Future<Result<List<BackupMetadata>>> getBackupList() async {
    return const Result.failure(
      NetworkFailure('Cloud sync is not available — no backend configured.'),
    );
  }
}
