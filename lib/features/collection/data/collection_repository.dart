import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/database/database_service.dart';
import '../../../core/database/holiday_sql.dart';
import '../../../core/error/failure.dart';
import 'models/collection_row.dart';

class CollectionRepository {
  CollectionRepository(this._dbService);
  final DatabaseService _dbService;

  Future<Database> get _database async {
    return _dbService.database;
  }

  Future<Result<List<CollectionRow>>> getDailyCollection(DateTime date,
      {String? groupId, String? loanType}) async {
    try {
      final db = await _database;
      final dateStr = date.toIso8601String().split('T').first;

      final conditions = <String>['DATE(rs.due_date) = ?', "l.status = 'active'", notOnEnabledHolidaySql];
      final args = <dynamic>[dateStr];

      if (groupId != null && groupId.isNotEmpty) {
        conditions.add('c.group_id = ?');
        args.add(groupId);
      }
      if (loanType != null && loanType.isNotEmpty) {
        conditions.add('l.loan_type = ?');
        args.add(loanType);
      }

      final whereClause = conditions.join(' AND ');

      final rows = await db.rawQuery('''
        SELECT
          c.id AS customerId,
          c.full_name AS customerName,
          c.phone AS phone,
          l.id AS loanId,
          l.loan_type AS loanType,
          COALESCE(l.custom_collection_amount, rs.amount) AS amountDue,
          rs.paid_amount AS amountPaid,
          rs.amount AS installmentAmount,
          rs.status AS scheduleStatus,
          l.outstanding_balance AS outstandingBalance,
          l.status AS status,
          l.notes AS remarks,
          cg.name AS groupName
        FROM repayment_schedule rs
        INNER JOIN loans l ON rs.loan_id = l.id
        INNER JOIN customers c ON l.customer_id = c.id
        LEFT JOIN customer_groups cg ON c.group_id = cg.id
        WHERE $whereClause
        ORDER BY c.full_name COLLATE NOCASE ASC
      ''', args);

      final collectionRows = rows.map((row) {
        final amountPaid = (row['amountPaid'] as num?)?.toDouble() ?? 0.0;
        final amountDue = (row['amountDue'] as num?)?.toDouble() ?? 0.0;
        final installmentAmount = (row['installmentAmount'] as num?)?.toDouble() ?? 0.0;
        return CollectionRow(
          customerId: row['customerId'] as String? ?? '',
          customerName: row['customerName'] as String? ?? '',
          phone: row['phone'] as String? ?? '',
          loanId: row['loanId'] as String? ?? '',
          loanType: row['loanType'] as String? ?? '',
          amountDue: amountDue,
          amountPaid: amountPaid,
          installmentAmount: installmentAmount,
          outstandingBalance:
              (row['outstandingBalance'] as num?)?.toDouble() ?? 0.0,
          status: row['status'] as String? ?? '',
          scheduleStatus: row['scheduleStatus'] as String? ?? 'pending',
          groupName: row['groupName'] as String?,
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
      DateTime start, DateTime end, {String? loanType, String? groupId}) async {
    try {
      final db = await _database;
      final startStr = start.toIso8601String().split('T').first;
      final endStr = end.toIso8601String().split('T').first;
      final conditions = <String>["l.status = 'active'"];
      final args = <dynamic>[];

      if (groupId != null && groupId.isNotEmpty) {
        conditions.add('c.group_id = ?');
        args.add(groupId);
      }
      if (loanType != null && loanType.isNotEmpty) {
        conditions.add('l.loan_type = ?');
        args.add(loanType);
      }

      final whereClause = conditions.join(' AND ');

      // The SQL binds 8 date placeholders FIRST (the two BETWEEN ? AND ? in the
      // installmentAmount and scheduleStatus subqueries, plus the BETWEEN ? AND
      // ? in the repayment_schedule and payments JOINs), THEN the WHERE filter
      // placeholders (c.group_id, l.loan_type). So the date args must come
      // before the filter args — passing filters first bound them to the date
      // slots and produced garbage/empty results whenever a filter was active.
      final rows = await db.rawQuery('''
        SELECT
          c.id AS customerId,
          c.full_name AS customerName,
          c.phone AS phone,
          l.id AS loanId,
          l.loan_type AS loanType,
          COALESCE(SUM(CASE WHEN rs.status != 'paid'
                            THEN (rs.amount - COALESCE(rs.paid_amount, 0.0))
                            ELSE 0.0 END), 0.0) AS amountDue,
          COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0.0) AS amountPaid,
          COALESCE(
            (SELECT rs.amount FROM repayment_schedule rs
             WHERE rs.loan_id = l.id AND DATE(rs.due_date) BETWEEN ? AND ?
               AND $notOnEnabledHolidaySql
             ORDER BY rs.due_date ASC LIMIT 1),
            l.daily_payment,
            l.weekly_payment
          ) AS installmentAmount,
          l.outstanding_balance AS outstandingBalance,
          l.status AS status,
          l.notes AS remarks,
          cg.name AS groupName,
          (SELECT rs.status FROM repayment_schedule rs
           WHERE rs.loan_id = l.id AND DATE(rs.due_date) BETWEEN ? AND ?
             AND $notOnEnabledHolidaySql
           ORDER BY rs.due_date ASC LIMIT 1) AS scheduleStatus
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        LEFT JOIN customer_groups cg ON c.group_id = cg.id
        LEFT JOIN repayment_schedule rs
          ON rs.loan_id = l.id AND DATE(rs.due_date) BETWEEN ? AND ?
            AND $notOnEnabledHolidaySql
        LEFT JOIN payments p ON p.loan_id = l.id
          AND DATE(p.payment_date) BETWEEN ? AND ?
          AND p.status = 'completed'
        LEFT JOIN savings_transactions st
          ON st.reference_loan_payment_id = p.id AND st.type = 'overpayment'
        WHERE $whereClause
        GROUP BY l.id
        ORDER BY c.full_name COLLATE NOCASE ASC
      ''', [startStr, endStr, startStr, endStr, startStr, endStr, startStr, endStr, ...args]);

      final collectionRows = rows.map((row) {
        final amountPaid = (row['amountPaid'] as num?)?.toDouble() ?? 0.0;
        final amountDue = (row['amountDue'] as num?)?.toDouble() ?? 0.0;
        final installmentAmount = (row['installmentAmount'] as num?)?.toDouble() ?? 0.0;
        return CollectionRow(
          customerId: row['customerId'] as String? ?? '',
          customerName: row['customerName'] as String? ?? '',
          phone: row['phone'] as String? ?? '',
          loanId: row['loanId'] as String? ?? '',
          loanType: row['loanType'] as String? ?? '',
          amountDue: amountDue,
          amountPaid: amountPaid,
          installmentAmount: installmentAmount,
          outstandingBalance:
              (row['outstandingBalance'] as num?)?.toDouble() ?? 0.0,
          status: row['status'] as String? ?? '',
          scheduleStatus: row['scheduleStatus'] as String? ?? 'pending',
          groupName: row['groupName'] as String?,
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

  Future<Result<List<CollectionRow>>> getFutureSchedule({int daysAhead = 30}) async {
    try {
      final db = await _database;
      final today = DateTime.now();
      final todayStr = today.toIso8601String().split('T').first;
      final futureEnd = today.add(Duration(days: daysAhead));
      final endStr = futureEnd.toIso8601String().split('T').first;

      final rows = await db.rawQuery('''
        SELECT
          c.id AS customerId,
          c.full_name AS customerName,
          c.phone AS phone,
          l.id AS loanId,
          l.loan_type AS loanType,
          rs.amount AS amountDue,
          COALESCE(rs.paid_amount, 0.0) AS amountPaid,
          rs.amount AS installmentAmount,
          rs.due_date AS dueDate,
          l.outstanding_balance AS outstandingBalance,
          l.status AS status,
          rs.status AS scheduleStatus,
          l.notes AS remarks,
          cg.name AS groupName
        FROM repayment_schedule rs
        INNER JOIN loans l ON rs.loan_id = l.id
        INNER JOIN customers c ON l.customer_id = c.id
        LEFT JOIN customer_groups cg ON c.group_id = cg.id
        WHERE DATE(rs.due_date) BETWEEN ? AND ?
          AND l.status = 'active'
          AND rs.status != 'paid'
          AND $notOnEnabledHolidaySql
        ORDER BY rs.due_date ASC, c.full_name COLLATE NOCASE ASC
      ''', [todayStr, endStr]);

      final scheduleRows = rows.map((row) {
        final amountPaid = (row['amountPaid'] as num?)?.toDouble() ?? 0.0;
        final amountDue = (row['amountDue'] as num?)?.toDouble() ?? 0.0;
        final installmentAmount = (row['installmentAmount'] as num?)?.toDouble() ?? 0.0;
        return CollectionRow(
          customerId: row['customerId'] as String? ?? '',
          customerName: row['customerName'] as String? ?? '',
          phone: row['phone'] as String? ?? '',
          loanId: row['loanId'] as String? ?? '',
          loanType: row['loanType'] as String? ?? '',
          amountDue: amountDue,
          amountPaid: amountPaid,
          installmentAmount: installmentAmount,
          outstandingBalance:
              (row['outstandingBalance'] as num?)?.toDouble() ?? 0.0,
          status: row['status'] as String? ?? '',
          scheduleStatus: row['scheduleStatus'] as String? ?? 'pending',
          groupName: row['groupName'] as String?,
          remarks: row['remarks'] as String?,
          dueDate: row['dueDate'] as String?,
        );
      }).toList(growable: false);

      return Result.success(scheduleRows);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load future collection schedule.',
              cause: e));
    }
  }
}
