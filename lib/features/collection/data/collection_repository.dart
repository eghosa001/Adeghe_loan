import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/database/database_service.dart';
import '../../../core/error/failure.dart';
import 'models/collection_row.dart';

class CollectionRepository {
  CollectionRepository(this._dbService);
  final DatabaseService _dbService;

  Future<Database> get _database async {
    return _dbService.database;
  }

  Future<Result<List<CollectionRow>>> getDailyCollection(DateTime date) async {
    try {
      final db = await _database;
      final dateStr = date.toIso8601String().split('T').first;
      final rows = await db.rawQuery('''
        SELECT
          c.full_name AS customerName,
          c.phone AS phone,
          l.id AS loanId,
          l.loan_type AS loanType,
          l.total_repayment AS amountDue,
          COALESCE(SUM(p.amount), 0.0) AS amountPaid,
          l.outstanding_balance AS outstandingBalance,
          l.status AS status,
          l.notes AS remarks
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        LEFT JOIN payments p ON p.loan_id = l.id
          AND DATE(p.payment_date) = ?
        WHERE l.status = 'active'
        GROUP BY l.id
        ORDER BY c.full_name COLLATE NOCASE ASC
      ''', [dateStr]);

      final collectionRows = rows.map((row) {
        final amountPaid = (row['amountPaid'] as num?)?.toDouble() ?? 0.0;
        final amountDue = (row['amountDue'] as num?)?.toDouble() ?? 0.0;
        return CollectionRow(
          customerName: row['customerName'] as String? ?? '',
          phone: row['phone'] as String? ?? '',
          loanId: row['loanId'] as String? ?? '',
          loanType: row['loanType'] as String? ?? '',
          amountDue: amountDue,
          amountPaid: amountPaid,
          outstandingBalance:
              (row['outstandingBalance'] as num?)?.toDouble() ?? 0.0,
          status: row['status'] as String? ?? '',
          remarks: row['remarks'] as String?,
        );
      }).toList(growable: false);

      return Result.success(collectionRows);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load collection data.', cause: e));
    }
  }

  Future<Result<List<CollectionRow>>> getCollectionsByDateRange(
      DateTime start, DateTime end) async {
    try {
      final db = await _database;
      final startStr = start.toIso8601String().split('T').first;
      final endStr = end.toIso8601String().split('T').first;
      final rows = await db.rawQuery('''
        SELECT
          c.full_name AS customerName,
          c.phone AS phone,
          l.id AS loanId,
          l.loan_type AS loanType,
          l.total_repayment AS amountDue,
          COALESCE(SUM(p.amount), 0.0) AS amountPaid,
          l.outstanding_balance AS outstandingBalance,
          l.status AS status,
          l.notes AS remarks
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        LEFT JOIN payments p ON p.loan_id = l.id
          AND DATE(p.payment_date) BETWEEN ? AND ?
        WHERE l.status = 'active'
        GROUP BY l.id
        ORDER BY c.full_name COLLATE NOCASE ASC
      ''', [startStr, endStr]);

      final collectionRows = rows.map((row) {
        final amountPaid = (row['amountPaid'] as num?)?.toDouble() ?? 0.0;
        final amountDue = (row['amountDue'] as num?)?.toDouble() ?? 0.0;
        return CollectionRow(
          customerName: row['customerName'] as String? ?? '',
          phone: row['phone'] as String? ?? '',
          loanId: row['loanId'] as String? ?? '',
          loanType: row['loanType'] as String? ?? '',
          amountDue: amountDue,
          amountPaid: amountPaid,
          outstandingBalance:
              (row['outstandingBalance'] as num?)?.toDouble() ?? 0.0,
          status: row['status'] as String? ?? '',
          remarks: row['remarks'] as String?,
        );
      }).toList(growable: false);

      return Result.success(collectionRows);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load collection data by date range.',
              cause: e));
    }
  }
}
