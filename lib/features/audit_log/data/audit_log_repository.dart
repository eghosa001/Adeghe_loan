import 'package:sqflite_sqlcipher/sqflite.dart';

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
        id: DateTime.now().microsecondsSinceEpoch.toString(),
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

  Future<Result<List<AuditLog>>> getByDateRange(
      DateTime start, DateTime end) async {
    try {
      final db = await _database;
      final rows = await db.query(
        'audit_logs',
        where: 'timestamp BETWEEN ? AND ?',
        whereArgs: [start.toIso8601String(), end.toIso8601String()],
        orderBy: 'timestamp DESC',
      );
      final logs = rows.map(AuditLog.fromMap).toList(growable: false);
      return Result.success(logs);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load audit logs by date range.', cause: e));
    }
  }

  Future<Result<List<AuditLog>>> getRecent(int limit) async {
    try {
      final db = await _database;
      final rows = await db.query(
        'audit_logs',
        orderBy: 'timestamp DESC',
        limit: limit,
      );
      final logs = rows.map(AuditLog.fromMap).toList(growable: false);
      return Result.success(logs);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load recent audit logs.', cause: e));
    }
  }
}
