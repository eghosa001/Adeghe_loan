import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_service.dart';
import '../../../core/error/failure.dart';
import 'models/audit_log_entity.dart';

class AuditLogRepository {
  AuditLogRepository(this._dbService);
  final DatabaseService _dbService;

  Future<Database> get _database async {
    return _dbService.database;
  }

  Future<Result<void>> log(String user, String action, String details) async {
    try {
      final db = await _database;
      final entry = AuditLog(
        id: const Uuid().v4(),
        user: user,
        action: action,
        timestamp: DateTime.now(),
        details: details,
      );
      await db.insert('audit_logs', entry.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      return const Result.success(null);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to write audit log.', cause: e));
    }
  }

  Future<Result<List<AuditLog>>> getAll() async {
    try {
      final db = await _database;
      final rows = await db.query('audit_logs', orderBy: 'timestamp DESC');
      final logs = rows.map(AuditLog.fromMap).toList(growable: false);
      return Result.success(logs);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load audit logs.', cause: e));
    }
  }
}
