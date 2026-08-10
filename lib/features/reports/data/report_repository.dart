import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/database/database_service.dart';
import '../../../core/database/holiday_sql.dart';
import '../../../core/error/failure.dart';
import '../../../core/utils/date_utils.dart';
import 'models/report_summary.dart';
import 'models/report_models.dart';

class ReportRepository {
  ReportRepository(this._dbService);
  final DatabaseService _dbService;

  Future<Database> get _database async {
    return _dbService.database;
  }

  static double _toDouble(Map<String, dynamic> row, String key) =>
      (row[key] as num?)?.toDouble() ?? 0.0;

  static int _toInt(Map<String, dynamic> row, String key) =>
      (row[key] as int?) ?? 0;

  Future<Result<ReportSummary>> getReportSummary(
      DateTime startDate, DateTime endDate,
      {String? loanType}) async {
    try {
      final db = await _database;
      final startStr = AppDateUtils.formatForStorage(startDate);
      final endStr = AppDateUtils.formatForStorage(endDate);

      // When a specific loan type is requested, only that type is queried and
      // the other bucket is returned empty so combined totals are not skewed.
      // The heavy client-report/overdue detail queries are only needed by the
      // per-type report screens — the combined dashboard summary never reads
      // them, so skip them when loanType == null (a ~40ms×2 saving per render).
      final includeDetail = loanType != null;
      final dailySummary = (loanType == null || loanType == 'daily')
          ? await _getLoanTypeSummary(db, 'daily', startStr, endStr,
              includeDetail: includeDetail)
          : LoanTypeReportSummary.empty();
      final weeklySummary = (loanType == null || loanType == 'weekly')
          ? await _getLoanTypeSummary(db, 'weekly', startStr, endStr,
              includeDetail: includeDetail)
          : LoanTypeReportSummary.empty();

      // Distinct customer count across the filtered loan types (avoids
      // double counting customers with both a daily and a weekly loan).
      final customerRows = await db.rawQuery(
        'SELECT COUNT(DISTINCT l.customer_id) AS count FROM loans l '
        "WHERE l.status IN ('active', 'defaulted')"
        '${loanType != null ? ' AND l.loan_type = ?' : ''}',
        loanType != null ? [loanType] : [],
      );
      final totalCustomers = _toInt(customerRows.first, 'count');

      // Combined totals across all loan types
      final totalDisbursed =
          dailySummary.amountDisbursed + weeklySummary.amountDisbursed;
      final totalCollected =
          dailySummary.amountCollected + weeklySummary.amountCollected;
      final activeLoans =
          dailySummary.activeLoans + weeklySummary.activeLoans;
      final completedLoans =
          dailySummary.completedLoans + weeklySummary.completedLoans;

      // Combined client reports and overdue entries
      final clientReports = [
        ...dailySummary.clientReports,
        ...weeklySummary.clientReports,
      ];
      final overdueEntries = [
        ...dailySummary.overdueEntries,
        ...weeklySummary.overdueEntries,
      ];

      return Result.success(ReportSummary(
        dailyLoans: dailySummary,
        weeklyLoans: weeklySummary,
        totalDisbursed: totalDisbursed,
        totalCollected: totalCollected,
        netProfit: totalCollected - totalDisbursed,
        activeLoans: activeLoans,
        completedLoans: completedLoans,
        defaultedLoans: dailySummary.defaultedLoans + weeklySummary.defaultedLoans,
        totalCustomers: totalCustomers,
        clientReports: clientReports,
        overdueEntries: overdueEntries,
      ));
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to generate report summary.', cause: e));
    }
  }

  Future<LoanTypeReportSummary> _getLoanTypeSummary(
    Database db,
    String? loanType,
    String startStr,
    String endStr, {
    bool includeDetail = true,
  }) async {
    // Build WHERE clause fragments for loan type filtering
    final ltClause = loanType != null ? ' AND l.loan_type = ?' : '';
    final ltParam = loanType;
    final todayStr = AppDateUtils.formatForStorage(DateTime.now());

    // Batch 1: Scalar queries (can run in parallel)
    final scalars = await Future.wait([
      // 1: Active loans count
      db.rawQuery(
        'SELECT COUNT(*) AS count FROM loans l WHERE l.status = ? AND l.loan_date <= ?$ltClause',
        ltParam != null
            ? ['active', endStr, ltParam]
            : ['active', endStr],
      ),
      // 2: Completed loans count
      db.rawQuery(
        'SELECT COUNT(*) AS count FROM loans l WHERE l.status = ? AND l.loan_date <= ?$ltClause',
        ltParam != null
            ? ['completed', endStr, ltParam]
            : ['completed', endStr],
      ),
      // 3: Overdue loans count (active/defaulted loans with unpaid installments
      //    whose due date is strictly before today — future dues are NOT overdue)
      //    Note: We check l.loan_date <= today (not endStr) so we capture all
      //    currently overdue loans regardless of the report period filter.
      db.rawQuery(
        'SELECT COUNT(DISTINCT l.id) AS count FROM loans l '
        "WHERE l.status IN ('active', 'defaulted') AND l.loan_date <= ? "
        'AND EXISTS (SELECT 1 FROM repayment_schedule rs WHERE rs.loan_id = l.id AND rs.status != ? AND DATE(rs.due_date) < ? '
        'AND $notOnEnabledHolidaySql)'
        '$ltClause',
        ltParam != null
            ? [todayStr, 'paid', todayStr, ltParam]
            : [todayStr, 'paid', todayStr],
      ),
      // 4: Amount disbursed in period (cancelled loans never disbursed)
      db.rawQuery(
        'SELECT COALESCE(SUM(l.amount), 0) AS total FROM loans l '
        "WHERE l.status IN ('active', 'completed', 'defaulted') AND l.loan_date BETWEEN ? AND ?$ltClause",
        ltParam != null ? [startStr, endStr, ltParam] : [startStr, endStr],
      ),
      // 5: Outstanding balance (active loans)
      db.rawQuery(
        'SELECT COALESCE(SUM(l.outstanding_balance), 0) AS total FROM loans l '
        'WHERE l.status = ?$ltClause',
        ltParam != null ? ['active', ltParam] : ['active'],
      ),
      // 6: Amount collected in period (excluding overpayments credited to savings)
      db.rawQuery(
        'SELECT COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0) AS total '
        'FROM payments p '
        'JOIN loans l ON p.loan_id = l.id '
        'LEFT JOIN savings_transactions st '
        '  ON st.reference_loan_payment_id = p.id '
        " AND st.type = 'overpayment' "
        "WHERE p.status = 'completed' AND p.payment_date BETWEEN ? AND ?$ltClause",
        ltParam != null
            ? [startStr, endStr, ltParam]
            : [startStr, endStr],
      ),
      // 7: Expected collections (sum of unpaid portion of installments due in
      //    period) — only for active loans; cancelled/defaulted are not expected
      db.rawQuery(
        'SELECT COALESCE(SUM(rs.amount - COALESCE(rs.paid_amount, 0)), 0) AS total FROM repayment_schedule rs '
        'JOIN loans l ON rs.loan_id = l.id '
        "WHERE rs.due_date BETWEEN ? AND ? AND rs.status != 'paid' AND l.status = 'active'$ltClause",
        ltParam != null
            ? [startStr, endStr, ltParam]
            : [startStr, endStr],
      ),
      // 8: Interest earned (cancelled loans never earned interest)
      db.rawQuery(
        'SELECT COALESCE(SUM(l.amount * l.interest_rate / 100), 0) AS total FROM loans l '
        "WHERE l.status IN ('active', 'completed', 'defaulted') AND l.loan_date BETWEEN ? AND ?$ltClause",
        ltParam != null ? [startStr, endStr, ltParam] : [startStr, endStr],
      ),
      // 9: Fees earned (insurance + commission + processing + admin + other)
      db.rawQuery(
        'SELECT COALESCE(SUM(l.amount * l.insurance_fee / 100 + l.amount * l.commission / 100 + l.processing_fee + l.admin_fee + l.other_charges), 0) AS total FROM loans l '
        "WHERE l.status IN ('active', 'completed', 'defaulted') AND l.loan_date BETWEEN ? AND ?$ltClause",
        ltParam != null ? [startStr, endStr, ltParam] : [startStr, endStr],
      ),
      // 10: Savings from overpayments
      db.rawQuery(
        'SELECT COALESCE(SUM(st.amount), 0) AS total FROM savings_transactions st '
        'JOIN payments p ON st.reference_loan_payment_id = p.id '
        'JOIN loans l ON p.loan_id = l.id '
        "WHERE st.type = 'overpayment' AND p.status = 'completed' "
        'AND substr(st.created_at, 1, 10) BETWEEN ? AND ?$ltClause',
        ltParam != null
            ? [startStr, endStr, ltParam]
            : [startStr, endStr],
      ),
      // 11: Defaulted loans count
      db.rawQuery(
        "SELECT COUNT(*) AS count FROM loans l WHERE l.status = 'defaulted' AND loan_date <= ?$ltClause",
        ltParam != null ? [endStr, ltParam] : [endStr],
      ),
      // 12: Distinct customer count (active/defaulted loans)
      db.rawQuery(
        'SELECT COUNT(DISTINCT l.customer_id) AS count FROM loans l '
        "WHERE l.status IN ('active', 'defaulted')$ltClause",
        ltParam != null ? [ltParam] : [],
      ),
    ]);

    final activeLoans = _toInt(scalars[0].first, 'count');
    final completedLoans = _toInt(scalars[1].first, 'count');
    final overdueLoans = _toInt(scalars[2].first, 'count');
    final amountDisbursed = _toDouble(scalars[3].first, 'total');
    final outstandingBalance = _toDouble(scalars[4].first, 'total');
    final amountCollected = _toDouble(scalars[5].first, 'total');
    final expectedCollections = _toDouble(scalars[6].first, 'total');
    final interestEarned = _toDouble(scalars[7].first, 'total');
    final feesEarned = _toDouble(scalars[8].first, 'total');
    final savingsFromOverpayments = _toDouble(scalars[9].first, 'total');
    final defaultedLoans = _toInt(scalars[10].first, 'count');
    final customerCount = _toInt(scalars[11].first, 'count');

    final collectionEfficiency = expectedCollections > 0
        ? ((amountCollected / expectedCollections) * 100).clamp(0.0, 100.0)
        : 0.0;

    // Batch 2: Heavy queries (client reports + overdue entries) — only needed
    // by the per-type report screens; the combined dashboard summary skips them.
    List<ClientReport> clientReports = [];
    List<OverdueEntry> overdueEntries = [];
    if (includeDetail) {
      final heavy = await Future.wait([
        // 12: Client reports
        db.rawQuery(
        'SELECT '
        'c.id AS customerId, '
        'c.full_name AS customerName, '
        'c.phone AS phone, '
        'c.guarantor_1_name AS guarantorName, '
        'c.guarantor_1_phone AS guarantorPhone, '
        'l.id AS loanId, '
        'l.loan_type AS loanType, '
        'l.amount AS amountBorrowed, '
        'CASE WHEN l.loan_type = \'weekly\' THEN DATE(l.start_date, \'-7 days\') ELSE l.loan_date END AS loanDate, '
        'l.outstanding_balance AS outstandingBalance, '
        'l.status AS loanStatus, '
        'l.interest_rate AS interestRate, '
        'cg.name AS groupName, '
        'COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0.0) AS totalPaid, '
        '(SELECT COALESCE(SUM(st2.amount), 0.0) FROM savings_transactions st2 '
        ' JOIN payments p2 ON st2.reference_loan_payment_id = p2.id '
        " WHERE p2.loan_id = l.id AND p2.status = 'completed' AND st2.type = 'overpayment') AS savingsAmount "
        'FROM loans l '
        'INNER JOIN customers c ON l.customer_id = c.id '
        'LEFT JOIN customer_groups cg ON c.group_id = cg.id '
        'LEFT JOIN payments p ON p.loan_id = l.id '
        "AND p.status = 'completed' "
        'LEFT JOIN savings_transactions st '
        'ON st.reference_loan_payment_id = p.id AND st.type = \'overpayment\' '
        // Include loans within the selected period and include completed loans
        'WHERE l.loan_date BETWEEN ? AND ? AND l.status IN (\'active\', \'defaulted\', \'completed\') $ltClause '
        'GROUP BY l.id '
        'ORDER BY l.outstanding_balance DESC',
        ltParam != null
            ? [startStr, endStr, ltParam]
            : [startStr, endStr],
      ),
      // 13: Overdue entries
      db.rawQuery(
        'SELECT '
        'c.id AS customerId, '
        'c.full_name AS customerName, '
        'c.phone AS phone, '
        'c.guarantor_1_name AS guarantorName, '
        'c.guarantor_1_phone AS guarantorPhone, '
        'l.id AS loanId, '
        'l.loan_type AS loanType, '
        'rs.installment_number AS installmentNumber, '
        'rs.due_date AS dueDate, '
        'rs.amount AS amountDue, '
        'rs.paid_amount AS paidAmount, '
        'cg.name AS groupName '
        'FROM repayment_schedule rs '
        'INNER JOIN loans l ON rs.loan_id = l.id '
        'INNER JOIN customers c ON l.customer_id = c.id '
        'LEFT JOIN customer_groups cg ON c.group_id = cg.id '
        "WHERE l.status IN ('active', 'defaulted') AND rs.status != 'paid' AND DATE(rs.due_date) < ?$ltClause "
        'AND $notOnEnabledHolidaySql '
        'ORDER BY rs.due_date ASC',
        ltParam != null ? [todayStr, ltParam] : [todayStr],
      ),
    ]);

      final nowDate = DateTime.now();

      clientReports = (heavy[0] as List<Map<String, dynamic>>)
          .map((row) {
            final borrowed = (row['amountBorrowed'] as num?)?.toDouble() ?? 0.0;
            final rate = (row['interestRate'] as num?)?.toDouble() ?? 0.0;
            return ClientReport(
                customerId: row['customerId'] as String? ?? '',
                customerName: row['customerName'] as String? ?? '',
                phone: row['phone'] as String? ?? '',
                loanId: row['loanId'] as String? ?? '',
                loanType: row['loanType'] as String? ?? '',
                amountBorrowed: borrowed,
                outstandingBalance:
                    (row['outstandingBalance'] as num?)?.toDouble() ?? 0.0,
                totalPaid: (row['totalPaid'] as num?)?.toDouble() ?? 0.0,
                loanStatus: row['loanStatus'] as String? ?? '',
                groupName: row['groupName'] as String?,
                guarantorName: row['guarantorName'] as String? ?? '',
                guarantorPhone: row['guarantorPhone'] as String? ?? '',
                loanDate: row['loanDate'] as String? ?? '',
                interestAmount: borrowed * rate / 100,
                savingsAmount: (row['savingsAmount'] as num?)?.toDouble() ?? 0.0,
              );
          })
          .toList();

      overdueEntries = (heavy[1] as List<Map<String, dynamic>>)
          .map((row) {
        final dueStr = row['dueDate'] as String? ?? endStr;
        final dueDate = DateTime.tryParse(dueStr) ?? nowDate;
        final overdueDays = nowDate.difference(dueDate).inDays;
        return OverdueEntry(
          customerId: row['customerId'] as String? ?? '',
          customerName: row['customerName'] as String? ?? '',
          phone: row['phone'] as String? ?? '',
          loanId: row['loanId'] as String? ?? '',
          loanType: row['loanType'] as String? ?? '',
          installmentNumber: row['installmentNumber'] as int? ?? 0,
          dueDate: dueStr,
          amountDue: (row['amountDue'] as num?)?.toDouble() ?? 0.0,
          paidAmount: (row['paidAmount'] as num?)?.toDouble() ?? 0.0,
          overdueDays: overdueDays,
          groupName: row['groupName'] as String?,
          guarantorName: row['guarantorName'] as String? ?? '',
          guarantorPhone: row['guarantorPhone'] as String? ?? '',
        );
      }).toList();
    }

    return LoanTypeReportSummary(
      activeLoans: activeLoans,
      completedLoans: completedLoans,
      overdueLoans: overdueLoans,
      defaultedLoans: defaultedLoans,
      amountDisbursed: amountDisbursed,
      outstandingBalance: outstandingBalance,
      amountCollected: amountCollected,
      expectedCollections: expectedCollections,
      collectionEfficiency: collectionEfficiency,
      interestEarned: interestEarned,
      feesEarned: feesEarned,
      savingsFromOverpayments: savingsFromOverpayments,
      customerCount: customerCount,
      clientReports: clientReports,
      overdueEntries: overdueEntries,
    );
  }

  Future<Result<List<OverdueEntry>>> getOverdueReport({String? loanType}) async {
    try {
      final db = await _database;
      final todayStr = AppDateUtils.formatForStorage(DateTime.now());

      final rows = await db.rawQuery(
        'SELECT '
        'c.id AS customerId, '
        'c.full_name AS customerName, '
        'c.phone AS phone, '
        'c.guarantor_1_name AS guarantorName, '
        'c.guarantor_1_phone AS guarantorPhone, '
        'l.id AS loanId, '
        'l.loan_type AS loanType, '
        'rs.installment_number AS installmentNumber, '
        'rs.due_date AS dueDate, '
        'rs.amount AS amountDue, '
        'rs.paid_amount AS paidAmount, '
        'cg.name AS groupName '
        'FROM repayment_schedule rs '
        'INNER JOIN loans l ON rs.loan_id = l.id '
        'INNER JOIN customers c ON l.customer_id = c.id '
        'LEFT JOIN customer_groups cg ON c.group_id = cg.id '
        "WHERE l.status IN ('active', 'defaulted') AND rs.status != 'paid' "
        'AND DATE(rs.due_date) < ? '
        'AND $notOnEnabledHolidaySql '
        '${loanType != null ? 'AND l.loan_type = ?' : ''} '
        'ORDER BY rs.due_date ASC',
        loanType != null ? [todayStr, loanType] : [todayStr],
      );

      final nowDate = DateTime.now();
      final entries = rows.map((row) {
        final dueStr = row['dueDate'] as String? ?? '';
        final dueDate = DateTime.tryParse(dueStr) ?? nowDate;
        final overdueDays = nowDate.difference(dueDate).inDays;
        return OverdueEntry(
          customerId: row['customerId'] as String? ?? '',
          customerName: row['customerName'] as String? ?? '',
          phone: row['phone'] as String? ?? '',
          loanId: row['loanId'] as String? ?? '',
          loanType: row['loanType'] as String? ?? '',
          installmentNumber: row['installmentNumber'] as int? ?? 0,
          dueDate: dueStr,
          amountDue: (row['amountDue'] as num?)?.toDouble() ?? 0.0,
          paidAmount: (row['paidAmount'] as num?)?.toDouble() ?? 0.0,
          overdueDays: overdueDays,
          groupName: row['groupName'] as String?,
          guarantorName: row['guarantorName'] as String? ?? '',
          guarantorPhone: row['guarantorPhone'] as String? ?? '',
        );
      }).toList();


      return Result.success(entries);
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to fetch overdue report.', cause: e));
    }
  }

  /// Customer Report: every non-archived customer with loan aggregates. Loan
  /// amounts follow the money rule (cancelled loans never disbursed; collected
  /// = completed payments minus savings overpayments) so the report reconciles
  /// with the summary and profit figures.
  Future<Result<List<CustomerReportRow>>> getCustomerReport() async {
    try {
      final db = await _database;
      final rows = await db.rawQuery(
        'SELECT '
        'c.id AS customerId, '
        'c.full_name AS customerName, '
        'c.phone AS phone, '
        'c.email AS email, '
        'cg.name AS groupName, '
        'c.date_registered AS dateRegistered, '
        'COUNT(DISTINCT CASE WHEN l.status != \'cancelled\' THEN l.id END) AS loanCount, '
        'COUNT(DISTINCT CASE WHEN l.status = \'active\' THEN l.id END) AS activeLoanCount, '
        'COALESCE(SUM(CASE WHEN l.status IN (\'active\', \'completed\', \'defaulted\') THEN l.amount ELSE 0 END), 0) AS totalDisbursed, '
        '(SELECT COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0) '
        ' FROM payments p '
        ' LEFT JOIN savings_transactions st '
        '   ON st.reference_loan_payment_id = p.id AND st.type = \'overpayment\' '
        ' JOIN loans pl ON p.loan_id = pl.id '
        ' WHERE pl.customer_id = c.id AND p.status = \'completed\') AS totalCollected, '
        'COALESCE(SUM(CASE WHEN l.status = \'active\' THEN l.outstanding_balance ELSE 0 END), 0) AS outstandingBalance, '
        'COALESCE((SELECT sa.balance FROM savings_accounts sa WHERE sa.customer_id = c.id), 0) AS savingsBalance '
        'FROM customers c '
        'LEFT JOIN customer_groups cg ON c.group_id = cg.id '
        'LEFT JOIN loans l ON l.customer_id = c.id '
        "WHERE c.status != 'archived' "
        'GROUP BY c.id '
        'ORDER BY c.full_name COLLATE NOCASE ASC',
      );
      final result = rows
          .map((row) => CustomerReportRow(
                customerId: row['customerId'] as String? ?? '',
                customerName: row['customerName'] as String? ?? '',
                phone: row['phone'] as String? ?? '',
                email: row['email'] as String? ?? '',
                groupName: row['groupName'] as String?,
                dateRegistered: row['dateRegistered'] as String? ?? '',
                loanCount: _toInt(row, 'loanCount'),
                activeLoanCount: _toInt(row, 'activeLoanCount'),
                totalDisbursed: _toDouble(row, 'totalDisbursed'),
                totalCollected: _toDouble(row, 'totalCollected'),
                outstandingBalance: _toDouble(row, 'outstandingBalance'),
                savingsBalance: _toDouble(row, 'savingsBalance'),
              ))
          .toList();
      return Result.success(result);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load customer report.', cause: e));
    }
  }

  /// Savings Report: every savings account with lifetime ledger sums. The
  /// overpayment surplus only counts overpayments linked to completed payments
  /// (reversed payments' overpayments are excluded, per the money rule).
  Future<Result<List<SavingsReportRow>>> getSavingsReport() async {
    try {
      final db = await _database;
      final rows = await db.rawQuery(
        'SELECT '
        'sa.customer_id AS customerId, '
        'c.full_name AS customerName, '
        'c.phone AS phone, '
        'cg.name AS groupName, '
        'sa.balance AS balance, '
        'COALESCE((SELECT SUM(st.amount) FROM savings_transactions st '
        ' LEFT JOIN payments p ON st.reference_loan_payment_id = p.id '
        " WHERE st.savings_account_id = sa.id "
        " AND (st.type = 'deposit' "
        "   OR (st.type = 'overpayment' AND p.status = 'completed'))), 0) AS totalDeposits, "
        'COALESCE((SELECT SUM(st.amount) FROM savings_transactions st '
        " WHERE st.savings_account_id = sa.id AND st.type = 'withdrawal'), 0) AS totalWithdrawals, "
        '(SELECT COALESCE(SUM(st.amount), 0) FROM savings_transactions st '
        ' JOIN payments p ON st.reference_loan_payment_id = p.id '
        " WHERE st.savings_account_id = sa.id AND st.type = 'overpayment' AND p.status = 'completed') AS overpaymentSurplus, "
        '(SELECT MAX(st.created_at) FROM savings_transactions st '
        ' WHERE st.savings_account_id = sa.id) AS lastActivityDate '
        'FROM savings_accounts sa '
        'INNER JOIN customers c ON sa.customer_id = c.id '
        'LEFT JOIN customer_groups cg ON c.group_id = cg.id '
        "WHERE c.status != 'archived' "
        'ORDER BY c.full_name COLLATE NOCASE ASC',
      );
      final result = rows
          .map((row) => SavingsReportRow(
                customerId: row['customerId'] as String? ?? '',
                customerName: row['customerName'] as String? ?? '',
                phone: row['phone'] as String? ?? '',
                groupName: row['groupName'] as String?,
                balance: _toDouble(row, 'balance'),
                totalDeposits: _toDouble(row, 'totalDeposits'),
                totalWithdrawals: _toDouble(row, 'totalWithdrawals'),
                overpaymentSurplus: _toDouble(row, 'overpaymentSurplus'),
                lastActivityDate: row['lastActivityDate'] as String?,
              ))
          .toList();
      return Result.success(result);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load savings report.', cause: e));
    }
  }

  /// Profit Report: one line per loan (cancelled loans excluded — they never
  /// disbursed or earned). Collected figures follow the money rule.
  Future<Result<List<ProfitReportRow>>> getProfitReport({
    DateTime? startDate,
    DateTime? endDate,
    String? loanType,
  }) async {
    try {
      final db = await _database;
      final startStr = startDate != null
          ? AppDateUtils.formatForStorage(startDate)
          : null;
      final endStr =
          endDate != null ? AppDateUtils.formatForStorage(endDate) : null;
      final where = StringBuffer("l.status != 'cancelled'");
      final args = <String>[];
      if (startStr != null && endStr != null) {
        where.write(' AND l.loan_date BETWEEN ? AND ?');
        args.addAll([startStr, endStr]);
      }
      if (loanType != null) {
        where.write(' AND l.loan_type = ?');
        args.add(loanType);
      }
      final rows = await db.rawQuery(
        'SELECT '
        'l.id AS loanId, '
        'l.customer_id AS customerId, '
        'c.full_name AS customerName, '
        'l.loan_type AS loanType, '
        'l.loan_date AS loanDate, '
        'l.amount AS principal, '
        'l.interest_rate AS interestRate, '
        'l.insurance_fee AS insuranceFee, '
        'l.commission AS commission, '
        'l.processing_fee AS processingFee, '
        'l.admin_fee AS adminFee, '
        'l.other_charges AS otherCharges, '
        'l.total_repayment AS expectedRepayment, '
        'l.outstanding_balance AS outstandingBalance, '
        'l.status AS status, '
        '(SELECT COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0) '
        ' FROM payments p '
        ' LEFT JOIN savings_transactions st '
        '   ON st.reference_loan_payment_id = p.id AND st.type = \'overpayment\' '
        " WHERE p.loan_id = l.id AND p.status = 'completed') AS totalCollected "
        'FROM loans l '
        'INNER JOIN customers c ON l.customer_id = c.id '
        'WHERE $where '
        'ORDER BY l.loan_date DESC',
        args,
      );
      final result = rows
          .map((row) {
            final amount = _toDouble(row, 'principal');
            final rate = _toDouble(row, 'interestRate');
            final insurance = _toDouble(row, 'insuranceFee');
            final commission = _toDouble(row, 'commission');
            return ProfitReportRow(
              loanId: row['loanId'] as String? ?? '',
              customerId: row['customerId'] as String? ?? '',
              customerName: row['customerName'] as String? ?? '',
              loanType: row['loanType'] as String? ?? '',
              loanDate: row['loanDate'] as String? ?? '',
              principal: amount,
              interest: amount * rate / 100,
              fees: amount * insurance / 100 +
                  amount * commission / 100 +
                  _toDouble(row, 'processingFee') +
                  _toDouble(row, 'adminFee') +
                  _toDouble(row, 'otherCharges'),
              expectedRepayment: _toDouble(row, 'expectedRepayment'),
              totalCollected: _toDouble(row, 'totalCollected'),
              outstandingBalance: _toDouble(row, 'outstandingBalance'),
              status: row['status'] as String? ?? '',
            );
          })
          .toList();
      return Result.success(result);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load profit report.', cause: e));
    }
  }

  /// Dashboard trends bucketed by the active report period (daily for short
  /// ranges, weekly for medium, monthly for long). All payment-derived series
  /// follow the money rule; disbursed/loan counts exclude cancelled loans.
  Future<Result<DashboardTrends>> getDashboardTrends({
    DateTime? startDate,
    DateTime? endDate,
    String? loanType,
  }) async {
    try {
      final db = await _database;
      final start = startDate ?? DateTime(DateTime.now().year, DateTime.now().month, 1);
      final end = endDate ?? DateTime(DateTime.now().year, DateTime.now().month + 1, 0);
      final days = end.difference(start).inDays + 1;

      final buckets = <(DateTime, DateTime, String)>[];
      if (days <= 31) {
        for (var d = 0; d < days; d++) {
          final day = start.add(Duration(days: d));
          buckets.add((day, day, _shortDateLabel(day)));
        }
      } else if (days <= 180) {
        var cursor = start;
        while (cursor.isBefore(end) || _sameDay(cursor, end)) {
          var bucketEnd = cursor.add(const Duration(days: 6));
          if (bucketEnd.isAfter(end)) bucketEnd = end;
          buckets.add((cursor, bucketEnd, _shortDateLabel(cursor)));
          cursor = bucketEnd.add(const Duration(days: 1));
        }
      } else {
        var cursor = DateTime(start.year, start.month, 1);
        final lastMonth = DateTime(end.year, end.month, 1);
        while (!cursor.isAfter(lastMonth)) {
          final monthEnd = DateTime(cursor.year, cursor.month + 1, 0);
          buckets.add((cursor, monthEnd, _monthLabel(cursor)));
          cursor = DateTime(cursor.year, cursor.month + 1, 1);
        }
      }

      final ltClause = loanType != null ? ' AND l.loan_type = ?' : '';
      final collections = <DashboardTrendPoint>[];
      final disbursed = <DashboardTrendPoint>[];
      final savingsIn = <DashboardTrendPoint>[];
      final savingsOut = <DashboardTrendPoint>[];
      final customers = <DashboardTrendPoint>[];
      final loans = <DashboardTrendPoint>[];
      // Build every bucket query up front and run them in ONE concurrent batch
      // (order preserved by index). Previously each bucket awaited its 6
      // queries serially — for a 31-day daily report that was 186 sequential
      // round trips through the DB queue.
      final queries = <Future<List<Map<String, Object?>>>>[];
      final queryLabels = <String>[];
      for (final (bucketStart, bucketEnd, label) in buckets) {
        final startStr = AppDateUtils.formatForStorage(bucketStart);
        final endStr = AppDateUtils.formatForStorage(bucketEnd);
        queryLabels.add(label);
        final dateArgs = [startStr, endStr];
        final ltArgs = loanType != null ? [...dateArgs, loanType] : dateArgs;
        queries.addAll([
          db.rawQuery(
            'SELECT COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0) AS total '
            'FROM payments p '
            'JOIN loans l ON p.loan_id = l.id '
            'LEFT JOIN savings_transactions st '
            '  ON st.reference_loan_payment_id = p.id AND st.type = \'overpayment\' '
            "WHERE p.status = 'completed' AND p.payment_date BETWEEN ? AND ?$ltClause",
            ltArgs,
          ),
          db.rawQuery(
            'SELECT COALESCE(SUM(l.amount), 0) AS total FROM loans l '
            "WHERE l.status IN ('active', 'completed', 'defaulted') AND l.loan_date BETWEEN ? AND ?$ltClause",
            ltArgs,
          ),
          db.rawQuery(
            'SELECT COALESCE(SUM(st.amount), 0) AS total FROM savings_transactions st '
            'LEFT JOIN payments p ON st.reference_loan_payment_id = p.id '
            "WHERE st.type IN ('deposit', 'overpayment') AND (st.reference_loan_payment_id IS NULL OR p.status = 'completed') "
            'AND substr(st.created_at, 1, 10) BETWEEN ? AND ?',
            dateArgs,
          ),
          db.rawQuery(
            'SELECT COALESCE(SUM(st.amount), 0) AS total FROM savings_transactions st '
            "WHERE st.type = 'withdrawal' AND substr(st.created_at, 1, 10) BETWEEN ? AND ?",
            dateArgs,
          ),
          db.rawQuery(
            'SELECT COUNT(*) AS total FROM customers c '
            "WHERE c.status != 'archived' AND DATE(c.date_registered) BETWEEN ? AND ?",
            dateArgs,
          ),
          db.rawQuery(
            'SELECT COUNT(*) AS total FROM loans l '
            "WHERE l.status != 'cancelled' AND l.loan_date BETWEEN ? AND ?$ltClause",
            ltArgs,
          ),
        ]);
      }
      final results = await Future.wait(queries);

      for (var i = 0; i < buckets.length; i++) {
        final label = queryLabels[i];
        final base = i * 6;
        collections.add(DashboardTrendPoint(
            label: label, value: _toDouble(results[base].first, 'total')));
        disbursed.add(DashboardTrendPoint(
            label: label, value: _toDouble(results[base + 1].first, 'total')));
        savingsIn.add(DashboardTrendPoint(
            label: label, value: _toDouble(results[base + 2].first, 'total')));
        savingsOut.add(DashboardTrendPoint(
            label: label, value: _toDouble(results[base + 3].first, 'total')));
        customers.add(DashboardTrendPoint(
            label: label, value: _toInt(results[base + 4].first, 'total').toDouble()));
        loans.add(DashboardTrendPoint(
            label: label, value: _toInt(results[base + 5].first, 'total').toDouble()));
      }

      return Result.success(DashboardTrends(
        collected: collections,
        disbursed: disbursed,
        savingsIn: savingsIn,
        savingsOut: savingsOut,
        customers: customers,
        loans: loans,
      ));
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load dashboard trends.', cause: e));
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _shortDateLabel(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  static String _monthLabel(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }
}


