import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/database/database_service.dart';
import '../../../core/database/holiday_sql.dart';
import '../../../core/error/failure.dart';
import 'models/collection_row.dart';
import 'models/weekly_collection_row.dart';

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

      final conditions = <String>[
        'DATE(rs.due_date) = ?',
        "l.status = 'active'",
        notOnEnabledHolidaySql,
      ];
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
      final conditions = <String>[
        "l.status = 'active'",
      ];
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

      // Placeholder order (positional binding): the 4 date-range clauses each
      // use BETWEEN ? AND ?, in the order they appear in the SQL below — the
      // amountPaid correlated subquery, the installmentAmount and scheduleStatus
      // subqueries, and the repayment_schedule join. Date args come first, then
      // the WHERE filter placeholders (c.group_id, l.loan_type).
      //
      // NOTE: the payments aggregate is a correlated subquery, NOT a join — a
      // join would cross-multiply against the (per-installment) repayment
      // schedule rows and double-count every payment/installment in range.
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
          COALESCE((
            SELECT SUM(p.amount - COALESCE(st.amount, 0.0))
            FROM payments p
            LEFT JOIN savings_transactions st
              ON st.reference_loan_payment_id = p.id AND st.type = 'overpayment'
            WHERE p.loan_id = l.id AND p.status = 'completed'
              AND DATE(p.payment_date) BETWEEN ? AND ?
          ), 0.0) AS amountPaid,
          COALESCE(
            (SELECT rs.amount - COALESCE(rs.paid_amount, 0.0)
             FROM repayment_schedule rs
             WHERE rs.loan_id = l.id AND DATE(rs.due_date) BETWEEN ? AND ?
               AND rs.status != 'paid'
               AND $notOnEnabledHolidaySql
             ORDER BY rs.due_date ASC LIMIT 1),
            0.0
          ) AS installmentAmount,
          l.outstanding_balance AS outstandingBalance,
          l.status AS status,
          l.notes AS remarks,
cg.name AS groupName,
          COALESCE((
            SELECT rs.status FROM repayment_schedule rs
            WHERE rs.loan_id = l.id AND DATE(rs.due_date) BETWEEN ? AND ?
              AND rs.status != 'paid'
              AND $notOnEnabledHolidaySql
            ORDER BY rs.due_date ASC LIMIT 1
          ), 'paid') AS scheduleStatus
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        LEFT JOIN customer_groups cg ON c.group_id = cg.id
        INNER JOIN repayment_schedule rs
          ON rs.loan_id = l.id AND DATE(rs.due_date) BETWEEN ? AND ?
            AND $notOnEnabledHolidaySql
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

  Future<Result<List<WeeklyCollectionRow>>> getWeeklyCollection() async {
    try {
      final db = await _database;
      final today = DateTime.now();

      // One row per active weekly loan with per-installment tracking.
      // We join with repayment_schedule to get the current due installment
      // (first unpaid installment by due_date) and compute overdue status.
      final rows = await db.rawQuery('''
        SELECT
          c.id AS customerId,
          c.full_name AS customerName,
          c.phone AS phone,
          c.guarantor_1_name AS guarantorName,
          c.guarantor_1_phone AS guarantorPhone,
          l.id AS loanId,
          l.loan_type AS loanType,
          l.amount AS amountDisbursed,
          l.amount * l.interest_rate / 100.0 AS interestAmount,
          l.total_repayment AS expectedAmount,
          l.outstanding_balance AS outstandingBalance,
          l.loan_date AS loanDate,
          l.start_date AS paymentAnchorDate,
          l.status AS status,
          COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0.0) AS amountPaid,
          COALESCE((
            SELECT rs.amount
            FROM repayment_schedule rs
            WHERE rs.loan_id = l.id
            ORDER BY rs.installment_number ASC LIMIT 1
          ), l.weekly_payment) AS weeklyInstallment,
          COALESCE((
            SELECT rs.installment_number
            FROM repayment_schedule rs
            WHERE rs.loan_id = l.id AND rs.status != 'paid'
              AND $notOnEnabledHolidaySql
            ORDER BY rs.due_date ASC LIMIT 1
          ), (SELECT COUNT(*) FROM repayment_schedule rs WHERE rs.loan_id = l.id)) AS currentInstallmentNumber,
          COALESCE((
            SELECT rs.due_date
            FROM repayment_schedule rs
            WHERE rs.loan_id = l.id AND rs.status != 'paid'
              AND $notOnEnabledHolidaySql
            ORDER BY rs.due_date ASC LIMIT 1
          ), (SELECT rs.due_date FROM repayment_schedule rs WHERE rs.loan_id = l.id ORDER BY rs.installment_number DESC LIMIT 1)) AS currentInstallmentDueDate,
          COALESCE((
            SELECT rs.amount
            FROM repayment_schedule rs
            WHERE rs.loan_id = l.id AND rs.status != 'paid'
              AND $notOnEnabledHolidaySql
            ORDER BY rs.due_date ASC LIMIT 1
          ), (SELECT rs.amount FROM repayment_schedule rs WHERE rs.loan_id = l.id ORDER BY rs.installment_number DESC LIMIT 1)) AS currentInstallmentAmount,
          COALESCE((
            SELECT COALESCE(rs.paid_amount, 0.0)
            FROM repayment_schedule rs
            WHERE rs.loan_id = l.id AND rs.status != 'paid'
              AND $notOnEnabledHolidaySql
            ORDER BY rs.due_date ASC LIMIT 1
          ), (SELECT COALESCE(rs.paid_amount, 0.0) FROM repayment_schedule rs WHERE rs.loan_id = l.id ORDER BY rs.installment_number DESC LIMIT 1)) AS currentInstallmentPaidAmount,
          COALESCE((
            SELECT rs.status
            FROM repayment_schedule rs
            WHERE rs.loan_id = l.id AND rs.status != 'paid'
              AND $notOnEnabledHolidaySql
            ORDER BY rs.due_date ASC LIMIT 1
          ), 'paid') AS currentInstallmentStatus
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        LEFT JOIN payments p ON p.loan_id = l.id AND p.status = 'completed'
        LEFT JOIN savings_transactions st
          ON st.reference_loan_payment_id = p.id AND st.type = 'overpayment'
        WHERE l.loan_type = 'weekly' AND l.status IN ('active', 'completed')
        GROUP BY l.id
        ORDER BY c.full_name COLLATE NOCASE ASC
      ''', const []);

      final weeklyRows = rows.map((row) {
        final currentInstallmentDueDate = row['currentInstallmentDueDate'] as String? ?? '';
        final currentInstallmentStatus = row['currentInstallmentStatus'] as String? ?? 'pending';
        final currentInstallmentAmount = (row['currentInstallmentAmount'] as num?)?.toDouble() ?? 0.0;
        final currentInstallmentPaidAmount = (row['currentInstallmentPaidAmount'] as num?)?.toDouble() ?? 0.0;
        
        // Calculate days overdue
        int daysOverdue = 0;
        if (currentInstallmentDueDate.isNotEmpty && currentInstallmentStatus != 'paid') {
          final dueDate = DateTime.tryParse(currentInstallmentDueDate);
          if (dueDate != null) {
            final diff = today.difference(dueDate).inDays;
            if (diff > 0) {
              daysOverdue = diff;
            }
          }
        }

        // Determine collected this period: amount paid towards the current installment
        // If the installment is paid/partial, this is the paid_amount. Otherwise 0.
        double collectedThisPeriod = 0.0;
        if (currentInstallmentStatus == 'paid' || currentInstallmentStatus == 'partial') {
          collectedThisPeriod = currentInstallmentPaidAmount;
        }

        return WeeklyCollectionRow(
          customerId: row['customerId'] as String? ?? '',
          customerName: row['customerName'] as String? ?? '',
          phone: row['phone'] as String? ?? '',
          guarantorName: row['guarantorName'] as String? ?? '',
          guarantorPhone: row['guarantorPhone'] as String? ?? '',
          loanId: row['loanId'] as String? ?? '',
          loanType: row['loanType'] as String? ?? 'weekly',
          amountDisbursed: (row['amountDisbursed'] as num?)?.toDouble() ?? 0.0,
          interestAmount: (row['interestAmount'] as num?)?.toDouble() ?? 0.0,
          expectedAmount: (row['expectedAmount'] as num?)?.toDouble() ?? 0.0,
          weeklyInstallment: (row['weeklyInstallment'] as num?)?.toDouble() ?? 0.0,
          amountPaid: (row['amountPaid'] as num?)?.toDouble() ?? 0.0,
          outstandingBalance: (row['outstandingBalance'] as num?)?.toDouble() ?? 0.0,
          installmentDue: ((row['currentInstallmentAmount'] as num?)?.toDouble() ?? 0.0)
              - ((row['currentInstallmentPaidAmount'] as num?)?.toDouble() ?? 0.0),
          loanDate: row['loanDate'] as String? ?? '',
          paymentAnchorDate: row['paymentAnchorDate'] as String? ?? '',
          status: row['status'] as String? ?? 'active',
          currentInstallmentNumber: (row['currentInstallmentNumber'] as num?)?.toInt() ?? 0,
          currentInstallmentDueDate: currentInstallmentDueDate,
          currentInstallmentAmount: currentInstallmentAmount,
          currentInstallmentPaidAmount: currentInstallmentPaidAmount,
          currentInstallmentStatus: currentInstallmentStatus,
          daysOverdue: daysOverdue,
          collectedThisPeriod: collectedThisPeriod,
        );
      }).toList(growable: false);

      return Result.success(weeklyRows);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load weekly collection data.', cause: e));
    }
  }

  Future<Result<List<WeeklyCollectionRow>>> getWeeklyCollectionByDate(DateTime date) async {
    return getWeeklyCollectionByDateRange(date, date);
  }

  Future<Result<List<WeeklyCollectionRow>>> getWeeklyCollectionByDateRange(DateTime start, DateTime end) async {
    try {
      final db = await _database;
      final startStr = start.toIso8601String().split('T').first;
      final endStr = end.toIso8601String().split('T').first;

      // Filter by the current installment's due_date falling within the range.
      final rows = await db.rawQuery('''
        SELECT
          c.id AS customerId,
          c.full_name AS customerName,
          c.phone AS phone,
          c.guarantor_1_name AS guarantorName,
          c.guarantor_1_phone AS guarantorPhone,
          l.id AS loanId,
          l.loan_type AS loanType,
          l.amount AS amountDisbursed,
          l.amount * l.interest_rate / 100.0 AS interestAmount,
          l.total_repayment AS expectedAmount,
          l.outstanding_balance AS outstandingBalance,
          l.loan_date AS loanDate,
          l.start_date AS paymentAnchorDate,
          l.status AS status,
          COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0.0) AS amountPaid,
          COALESCE((
            SELECT rs.amount
            FROM repayment_schedule rs
            WHERE rs.loan_id = l.id
            ORDER BY rs.installment_number ASC LIMIT 1
          ), l.weekly_payment) AS weeklyInstallment,
          COALESCE((
            SELECT rs.installment_number
            FROM repayment_schedule rs
            WHERE rs.loan_id = l.id AND rs.status != 'paid'
              AND $notOnEnabledHolidaySql
            ORDER BY rs.due_date ASC LIMIT 1
          ), (SELECT COUNT(*) FROM repayment_schedule rs WHERE rs.loan_id = l.id)) AS currentInstallmentNumber,
          COALESCE((
            SELECT rs.due_date
            FROM repayment_schedule rs
            WHERE rs.loan_id = l.id AND rs.status != 'paid'
              AND $notOnEnabledHolidaySql
            ORDER BY rs.due_date ASC LIMIT 1
          ), (SELECT rs.due_date FROM repayment_schedule rs WHERE rs.loan_id = l.id ORDER BY rs.installment_number DESC LIMIT 1)) AS currentInstallmentDueDate,
          COALESCE((
            SELECT rs.amount
            FROM repayment_schedule rs
            WHERE rs.loan_id = l.id AND rs.status != 'paid'
              AND $notOnEnabledHolidaySql
            ORDER BY rs.due_date ASC LIMIT 1
          ), (SELECT rs.amount FROM repayment_schedule rs WHERE rs.loan_id = l.id ORDER BY rs.installment_number DESC LIMIT 1)) AS currentInstallmentAmount,
          COALESCE((
            SELECT COALESCE(rs.paid_amount, 0.0)
            FROM repayment_schedule rs
            WHERE rs.loan_id = l.id AND rs.status != 'paid'
              AND $notOnEnabledHolidaySql
            ORDER BY rs.due_date ASC LIMIT 1
          ), (SELECT COALESCE(rs.paid_amount, 0.0) FROM repayment_schedule rs WHERE rs.loan_id = l.id ORDER BY rs.installment_number DESC LIMIT 1)) AS currentInstallmentPaidAmount,
          COALESCE((
            SELECT rs.status
            FROM repayment_schedule rs
            WHERE rs.loan_id = l.id AND rs.status != 'paid'
              AND $notOnEnabledHolidaySql
            ORDER BY rs.due_date ASC LIMIT 1
          ), 'paid') AS currentInstallmentStatus
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        LEFT JOIN payments p ON p.loan_id = l.id AND p.status = 'completed'
        LEFT JOIN savings_transactions st
          ON st.reference_loan_payment_id = p.id AND st.type = 'overpayment'
        WHERE l.loan_type = 'weekly' AND l.status IN ('active', 'completed')
          AND (
            (SELECT rs.due_date
             FROM repayment_schedule rs
             WHERE rs.loan_id = l.id AND rs.status != 'paid'
               AND $notOnEnabledHolidaySql
             ORDER BY rs.due_date ASC LIMIT 1) BETWEEN ? AND ?
            OR NOT EXISTS (
              SELECT 1 FROM repayment_schedule rs
              WHERE rs.loan_id = l.id AND rs.status != 'paid'
                AND $notOnEnabledHolidaySql
            )
          )
        GROUP BY l.id
        ORDER BY c.full_name COLLATE NOCASE ASC
      ''', [startStr, endStr]);

      final weeklyRows = rows.map((row) {
        final currentInstallmentDueDate = row['currentInstallmentDueDate'] as String? ?? '';
        final currentInstallmentStatus = row['currentInstallmentStatus'] as String? ?? 'pending';
        final currentInstallmentAmount = (row['currentInstallmentAmount'] as num?)?.toDouble() ?? 0.0;
        final currentInstallmentPaidAmount = (row['currentInstallmentPaidAmount'] as num?)?.toDouble() ?? 0.0;
        final today = DateTime.now();

        int daysOverdue = 0;
        if (currentInstallmentDueDate.isNotEmpty && currentInstallmentStatus != 'paid') {
          final dueDate = DateTime.tryParse(currentInstallmentDueDate);
          if (dueDate != null) {
            final diff = today.difference(dueDate).inDays;
            if (diff > 0) daysOverdue = diff;
          }
        }

        double collectedThisPeriod = 0.0;
        if (currentInstallmentStatus == 'paid' || currentInstallmentStatus == 'partial') {
          collectedThisPeriod = currentInstallmentPaidAmount;
        }

        return WeeklyCollectionRow(
          customerId: row['customerId'] as String? ?? '',
          customerName: row['customerName'] as String? ?? '',
          phone: row['phone'] as String? ?? '',
          guarantorName: row['guarantorName'] as String? ?? '',
          guarantorPhone: row['guarantorPhone'] as String? ?? '',
          loanId: row['loanId'] as String? ?? '',
          loanType: row['loanType'] as String? ?? 'weekly',
          amountDisbursed: (row['amountDisbursed'] as num?)?.toDouble() ?? 0.0,
          interestAmount: (row['interestAmount'] as num?)?.toDouble() ?? 0.0,
          expectedAmount: (row['expectedAmount'] as num?)?.toDouble() ?? 0.0,
          weeklyInstallment: (row['weeklyInstallment'] as num?)?.toDouble() ?? 0.0,
          amountPaid: (row['amountPaid'] as num?)?.toDouble() ?? 0.0,
          outstandingBalance: (row['outstandingBalance'] as num?)?.toDouble() ?? 0.0,
          installmentDue: currentInstallmentAmount - currentInstallmentPaidAmount,
          loanDate: row['loanDate'] as String? ?? '',
          paymentAnchorDate: row['paymentAnchorDate'] as String? ?? '',
          status: row['status'] as String? ?? 'active',
          currentInstallmentNumber: (row['currentInstallmentNumber'] as num?)?.toInt() ?? 0,
          currentInstallmentDueDate: currentInstallmentDueDate,
          currentInstallmentAmount: currentInstallmentAmount,
          currentInstallmentPaidAmount: currentInstallmentPaidAmount,
          currentInstallmentStatus: currentInstallmentStatus,
          daysOverdue: daysOverdue,
          collectedThisPeriod: collectedThisPeriod,
        );
      }).toList(growable: false);

      return Result.success(weeklyRows);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load weekly collection data by date range.', cause: e));
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
