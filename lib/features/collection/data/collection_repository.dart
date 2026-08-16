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

  /// SQL expression yielding a completed payment's ATTRIBUTED collection date
  /// for the Daily Collection — the owner rule: Saturday/Sunday payments count
  /// on the PRECEDING Friday ("as monday is a new week"), so a daily collection
  /// never shows rows on a weekend and Friday absorbs Fri + Sat + Sun. Weekday
  /// payments keep their own date. Requires `$alias.payment_date` to be a
  /// `yyyy-MM-dd` local-date string.
  String _attributedPaymentDateSql(String alias) => '''
    CASE
      WHEN strftime('%w', $alias.payment_date) = '6'
        THEN date($alias.payment_date, '-1 day')
      WHEN strftime('%w', $alias.payment_date) = '0'
        THEN date($alias.payment_date, '-2 days')
      ELSE date($alias.payment_date)
    END''';

  Future<Result<List<CollectionRow>>> getDailyCollection(DateTime date,
      {String? groupId, String? loanType}) async {
    try {
      // The daily collection has no Saturday/Sunday rows: a weekend payment is
      // shown on the preceding Friday, so a weekend date always reads empty.
      if (date.weekday == DateTime.saturday ||
          date.weekday == DateTime.sunday) {
        return Result.success(const <CollectionRow>[]);
      }
      final db = await _database;
      final dateStr = date.toIso8601String().split('T').first;
      final todayStr = DateTime.now().toIso8601String().split('T').first;
      // A payment counts toward a viewed weekday when its ATTRIBUTED date
      // (payment date, or the preceding Friday for Sat/Sun) equals that day.
      final payDateSql = _attributedPaymentDateSql('p');
      final payVisibleSql = _attributedPaymentDateSql('px');
      final payCompletedSql = _attributedPaymentDateSql('pc');

      // A loan is shown for the selected date when it either has an
      // installment due that day (non-holiday) OR received a completed payment
      // attributed to that day. The second clause is what lets a late payment
      // that was applied to an older missed installment still appear as "Paid"
      // on the day the money is counted toward (a weekday, or Friday for a
      // weekend payment). Completed loans are only shown on a day they actually
      // received a completed payment (typically the day the final payment
      // closed the loan) — otherwise a fully-paid loan would clutter every
      // later list while its past installments are all paid.
      final conditions = <String>[
        '''
          (l.status = 'active'
           OR EXISTS (
             SELECT 1 FROM payments pc
             WHERE pc.loan_id = l.id AND pc.status = 'completed'
               AND $payCompletedSql = ?
           )
          )
        ''',
        '''
          (rs.loan_id IS NOT NULL
           OR EXISTS (
             SELECT 1 FROM payments px
             WHERE px.loan_id = l.id AND px.status = 'completed'
               AND $payVisibleSql = ?
           )
          )
        ''',
      ];
      // Placeholder order (positional binding): the amountPaid correlated
      // subquery binds first (the attributed-date `?` in the SELECT list), then
      // the overdue subquery's `?` (today's date), then the LEFT JOIN's
      // due-date `?`, then the payment-visibility EXISTS `?`, then the
      // completed-loan payment EXISTS `?`, then the filter placeholders
      // (c.group_id, l.loan_type).
      final args = <dynamic>[dateStr, todayStr, dateStr, dateStr, dateStr];

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
          CASE WHEN rs.loan_id IS NULL THEN 0.0
               ELSE COALESCE(l.custom_collection_amount, rs.amount)
          END AS amountDue,
          COALESCE((
            SELECT SUM(p.amount - COALESCE(st.amount, 0.0))
            FROM payments p
            LEFT JOIN savings_transactions st
              ON st.reference_loan_payment_id = p.id AND st.type = 'overpayment'
            WHERE p.loan_id = l.id AND p.status = 'completed'
              AND $payDateSql = ?
          ), 0.0) AS amountPaid,
          COALESCE(rs.amount, 0.0) AS installmentAmount,
          COALESCE(rs.paid_amount, 0.0) AS schedulePaidAmount,
          COALESCE(rs.status, 'pending') AS scheduleStatus,
          l.outstanding_balance AS outstandingBalance,
          l.status AS status,
          l.notes AS remarks,
          cg.name AS groupName,
          COALESCE((
            SELECT SUM(rs2.amount - COALESCE(rs2.paid_amount, 0.0))
            FROM repayment_schedule rs2
            WHERE rs2.loan_id = l.id AND rs2.status != 'paid'
              AND DATE(rs2.due_date) < ?
          ), 0.0) AS overdueAmount
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        LEFT JOIN customer_groups cg ON c.group_id = cg.id
        LEFT JOIN repayment_schedule rs
          ON rs.loan_id = l.id AND DATE(rs.due_date) = ?
            AND $notOnEnabledHolidaySql
        WHERE $whereClause
        GROUP BY l.id
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
          schedulePaidAmount:
              (row['schedulePaidAmount'] as num?)?.toDouble() ?? 0.0,
          outstandingBalance:
              (row['outstandingBalance'] as num?)?.toDouble() ?? 0.0,
          status: row['status'] as String? ?? '',
          scheduleStatus: row['scheduleStatus'] as String? ?? 'pending',
          groupName: row['groupName'] as String?,
          remarks: row['remarks'] as String?,
          overdueAmount: (row['overdueAmount'] as num?)?.toDouble() ?? 0.0,
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
      final todayStr = DateTime.now().toIso8601String().split('T').first;
      // A payment counts toward the range when its ATTRIBUTED date (payment
      // date, or the preceding Friday for Sat/Sun) falls inside [start, end] —
      // this keeps a range that ends on a Friday (or ends Sat/Sun) absorbing
      // the weekend, while a range that starts on a weekend WITHOUT its Friday
      // still excludes the weekend's money (the Friday it belongs to is
      // outside the range).
      final payDateSql = _attributedPaymentDateSql('p');
      final payVisibleSql = _attributedPaymentDateSql('px');
      // Include completed loans so paid installments remain visible for
      // historical/reference purposes (paid weekly loans should still show).
      final conditions = <String>[
        "l.status IN ('active','completed')",
        // A loan is shown for the range when it either has an installment due
        // in the range (non-holiday) OR received a completed payment attributed
        // to the range — the second clause keeps a payment received on a
        // non-installment day (holiday/weekend) or a late payment clearing an
        // older missed installment visible on the period the money is counted
        // toward.
        '''
          (
            EXISTS (
              SELECT 1 FROM repayment_schedule rs2
              WHERE rs2.loan_id = l.id
                AND DATE(rs2.due_date) BETWEEN ? AND ?
                AND $notOnEnabledHolidaySql
            )
            OR EXISTS (
              SELECT 1 FROM payments px
              WHERE px.loan_id = l.id AND px.status = 'completed'
                AND $payVisibleSql BETWEEN ? AND ?
            )
          )
        ''',
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
      // use BETWEEN ? AND ? for the amountPaid correlated subquery, the
      // installmentAmount and scheduleStatus subqueries, and the
      // repayment_schedule join, PLUS one overdue subquery `?` (today's date)
      // that sits in the SELECT list just before the join, PLUS the WHERE
      // OR-EXISTS payment-day visibility clause (4 args). Order in the SQL
      // text: amountPaid, installmentAmount, scheduleStatus (each 2 args), the
      // overdue `?`, the join's BETWEEN, the visibility OR-EXISTS (installment
      // BETWEEN, payment BETWEEN), then the WHERE filter placeholders
      // (c.group_id, l.loan_type).
      //
      // NOTE: the payments aggregate is a correlated subquery, NOT a join â€” a
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
              AND $payDateSql BETWEEN ? AND ?
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
          ), 'paid') AS scheduleStatus,
          COALESCE((
            SELECT SUM(rs2.amount - COALESCE(rs2.paid_amount, 0.0))
            FROM repayment_schedule rs2
            WHERE rs2.loan_id = l.id AND rs2.status != 'paid'
              AND DATE(rs2.due_date) < ?
          ), 0.0) AS overdueAmount
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        LEFT JOIN customer_groups cg ON c.group_id = cg.id
        LEFT JOIN repayment_schedule rs
          ON rs.loan_id = l.id AND DATE(rs.due_date) BETWEEN ? AND ?
            AND $notOnEnabledHolidaySql
        WHERE $whereClause
        GROUP BY l.id
        ORDER BY c.full_name COLLATE NOCASE ASC
      ''', [startStr, endStr, startStr, endStr, startStr, endStr, todayStr, startStr, endStr, startStr, endStr, startStr, endStr, ...args]);

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
          overdueAmount: (row['overdueAmount'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList(growable: false);

      return Result.success(collectionRows);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load collection data by date range.',
              cause: e));
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
      final todayStr = DateTime.now().toIso8601String().split('T').first;

      // A loan is shown for the range when it has an installment due in the
      // range (non-holiday) — the WEEK the customer pays for. Payments are NOT
      // money-date visible anymore: the row is tied to the in-range installment
      // the money applies to (oldest-first), so a late payment for an older
      // missed installment lights up THAT installment's week, never the week
      // the money arrived. `collectedThisPeriod` is the amount already applied
      // to the displayed in-range installment (`tgt.paid_amount`), which is
      // money-rule safe — the schedule is recalculated from completed payments
      // minus overpayment surpluses credited to savings.
      //
      // The row's installment fields come from the FIRST installment in range,
      // preferring an unpaid one; when every installment in range is paid the
      // first (paid) installment is shown so the green tick/Paid state is
      // preserved.
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
          COALESCE(tgt.paid_amount, 0.0) AS collectedThisPeriod,
          COALESCE((
            SELECT rs.amount
            FROM repayment_schedule rs
            WHERE rs.loan_id = l.id
            ORDER BY rs.installment_number ASC LIMIT 1
          ), l.weekly_payment) AS weeklyInstallment,
          tgt.installment_number AS currentInstallmentNumber,
          tgt.due_date AS currentInstallmentDueDate,
          tgt.amount AS currentInstallmentAmount,
          tgt.paid_amount AS currentInstallmentPaidAmount,
          tgt.status AS currentInstallmentStatus,
          COALESCE((
            SELECT SUM(rs.amount - COALESCE(rs.paid_amount, 0.0))
            FROM repayment_schedule rs
            WHERE rs.loan_id = l.id AND rs.status != 'paid'
              AND DATE(rs.due_date) < ?
          ), 0.0) AS overdueAmount,
          COALESCE((
            SELECT sa.balance
            FROM savings_accounts sa
            WHERE sa.customer_id = c.id
          ), 0.0) AS savingsBalance
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        LEFT JOIN (
          SELECT t.loan_id,
                 t.installment_number,
                 t.due_date,
                 t.amount,
                 t.paid_amount,
                 t.status
          FROM repayment_schedule t
          WHERE t.installment_number = (
            SELECT COALESCE(
              (SELECT MIN(rs.installment_number)
               FROM repayment_schedule rs
               WHERE rs.loan_id = t.loan_id
                 AND DATE(rs.due_date) BETWEEN ? AND ?
                 AND rs.status != 'paid'
                 AND $notOnEnabledHolidaySql),
              (SELECT MIN(rs.installment_number)
               FROM repayment_schedule rs
               WHERE rs.loan_id = t.loan_id
                 AND DATE(rs.due_date) BETWEEN ? AND ?
                 AND $notOnEnabledHolidaySql),
              (SELECT MIN(rs.installment_number)
               FROM repayment_schedule rs
               WHERE rs.loan_id = t.loan_id
                 AND rs.status != 'paid'
                 AND $notOnEnabledHolidaySql)
            )
          )
        ) tgt ON tgt.loan_id = l.id
        LEFT JOIN payments p ON p.loan_id = l.id AND p.status = 'completed'
        LEFT JOIN savings_transactions st
          ON st.reference_loan_payment_id = p.id AND st.type = 'overpayment'
        WHERE l.loan_type = 'weekly' AND l.status IN ('active', 'completed')
          AND EXISTS (
            SELECT 1 FROM repayment_schedule rs
            WHERE rs.loan_id = l.id
              AND DATE(rs.due_date) BETWEEN ? AND ?
              AND $notOnEnabledHolidaySql
          )
        GROUP BY l.id
        ORDER BY l.start_date ASC, c.full_name COLLATE NOCASE ASC
      ''', [
        todayStr, startStr, endStr, startStr, endStr, startStr, endStr,
      ]);
      // Placeholder order (positional binding — the SQL text binds in this
      // exact order): the overdue `?` (today), then the tgt derived table's two
      // MIN installment subqueries (each BETWEEN), then the installment
      // visibility EXISTS (BETWEEN). No payment-date clauses remain — weekly
      // rows are tied to their in-range installment only.

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

        // What the customer has actually paid towards the displayed week's
        // installment (schedule `paid_amount`, money-rule safe). This
        // attributes money to the WEEK IT PAYS FOR — a late payment for an
        // older missed installment shows on that installment's week, not on
        // the week the money arrived.
        final collectedThisPeriod =
            (row['collectedThisPeriod'] as num?)?.toDouble() ?? 0.0;

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
          overdueAmount: (row['overdueAmount'] as num?)?.toDouble() ?? 0.0,
          savingsBalance: (row['savingsBalance'] as num?)?.toDouble() ?? 0.0,
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
