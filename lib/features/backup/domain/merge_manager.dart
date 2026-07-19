import 'dart:io';

import '../../../core/error/failure.dart';

class MergeManager {
  Future<Result<void>> mergeBackup(File backupFile) async {
    return const Result.failure(
      DatabaseFailure('Merge functionality is not yet implemented.'),
    );
  }

  Future<Result<List<String>>> getConflicts() async {
    return const Result.success(<String>[]);
  }

  Future<Result<void>> resolveConflict(
      String conflictId, String resolution) async {
    return const Result.failure(
      DatabaseFailure('Conflict resolution is not yet implemented.'),
    );
  }
}
