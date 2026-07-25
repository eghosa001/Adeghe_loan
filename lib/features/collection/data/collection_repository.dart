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

  Future<Result<List<CollectionRow>>> getDailyCollection(DateTime date,
      {String? groupId}) async {
    try {
      final db = await _database;
      final dateStr = date.toIso8601String().split('T').first;

      final groupClause =
          groupId != null && groupId.isNotEmpty ? 'AND c.group_id = ?' : '';
      final queryArgs = groupId != null && groupId.isNotEmpty
          ? [dateStr, groupId]
          : [dateStr];

      // Query repayment_schedule so both past and future scheduled
      // installments are shown for the selected date.
      final rows = await db.rawQuery('''
        SELECT
          c.full_name AS customerName,
          c.phone AS phone,
          l.id AS loanId,
          l.loan_type AS loanType,
          rs.amount AS amountDue,
          rs.paid_amount AS amountPaid,
          rs.status AS scheduleStatus,
          l.outstanding_balance AS outstandingBalance,
          l.status AS status,
          l.notes AS remarks
        FROM repayment_schedule rs
        INNER JOIN loans l ON rs.loan_id = l.id
        INNER JOIN customers c ON l.customer_id = c.id
        WHERE DATE(rs.due_date) = ?
          AND l.status = 'active'
          $groupClause
        ORDER BY c.full_name COLLATE NOCASE ASC
      ''', queryArgs);

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
          scheduleStatus: row['scheduleStatus'] as String? ?? 'pending',
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
          scheduleStatus: 'pending',
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
