import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/database/database_service.dart';
import '../../../core/error/failure.dart';
import '../../../core/utils/date_utils.dart';
import 'models/report_summary.dart';
import 'models/analytics_models.dart';

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
      final endDateTime = '$endStr 23:59:59';

      // When a specific loan type is requested, only that type is queried and
      // the other bucket is returned empty so combined totals are not skewed.
      final dailySummary = (loanType == null || loanType == 'daily')
          ? await _getLoanTypeSummary(db, 'daily', startStr, endStr, endDateTime)
          : LoanTypeReportSummary.empty();
      final weeklySummary = (loanType == null || loanType == 'weekly')
          ? await _getLoanTypeSummary(db, 'weekly', startStr, endStr, endDateTime)
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
    String endStr,
    String endDateTime,
  ) async {
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
      db.rawQuery(
        'SELECT COUNT(DISTINCT l.id) AS count FROM loans l '
        "WHERE l.status IN ('active', 'defaulted') AND l.loan_date <= ? "
        'AND EXISTS (SELECT 1 FROM repayment_schedule rs WHERE rs.loan_id = l.id AND rs.status != ? AND DATE(rs.due_date) < ?)'
        '$ltClause',
        ltParam != null
            ? [endStr, 'paid', todayStr, ltParam]
            : [endStr, 'paid', todayStr],
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
            ? [startStr, endDateTime, ltParam]
            : [startStr, endDateTime],
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
        'AND DATE(st.created_at) BETWEEN ? AND ?$ltClause',
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

    // Batch 2: Heavy queries (client reports + overdue entries)
    final heavy = await Future.wait([
      // 12: Client reports
      db.rawQuery(
        'SELECT '
        'c.id AS customerId, '
        'c.full_name AS customerName, '
        'c.phone AS phone, '
        'l.id AS loanId, '
        'l.loan_type AS loanType, '
        'l.amount AS amountBorrowed, '
        'l.outstanding_balance AS outstandingBalance, '
        'l.status AS loanStatus, '
        'cg.name AS groupName, '
        "COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0.0) AS totalPaid "
        'FROM loans l '
        'INNER JOIN customers c ON l.customer_id = c.id '
        'LEFT JOIN customer_groups cg ON c.group_id = cg.id '
        'LEFT JOIN payments p ON p.loan_id = l.id '
        "AND p.status = 'completed' "
        'LEFT JOIN savings_transactions st '
        'ON st.reference_loan_payment_id = p.id AND st.type = \'overpayment\' '
        "WHERE l.status IN ('active', 'defaulted') AND l.loan_date <= ?$ltClause "
        'GROUP BY l.id '
        'ORDER BY l.outstanding_balance DESC',
        ltParam != null
            ? [endStr, ltParam]
            : [endStr],
      ),
      // 13: Overdue entries
      db.rawQuery(
        'SELECT '
        'c.id AS customerId, '
        'c.full_name AS customerName, '
        'c.phone AS phone, '
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
        'ORDER BY rs.due_date ASC',
        ltParam != null ? [todayStr, ltParam] : [todayStr],
      ),
    ]);

    final nowDate = DateTime.now();

    final clientReports = (heavy[0] as List<Map<String, dynamic>>)
        .map((row) => ClientReport(
              customerId: row['customerId'] as String? ?? '',
              customerName: row['customerName'] as String? ?? '',
              phone: row['phone'] as String? ?? '',
              loanId: row['loanId'] as String? ?? '',
              loanType: row['loanType'] as String? ?? '',
              amountBorrowed:
                  (row['amountBorrowed'] as num?)?.toDouble() ?? 0.0,
              outstandingBalance:
                  (row['outstandingBalance'] as num?)?.toDouble() ?? 0.0,
              totalPaid: (row['totalPaid'] as num?)?.toDouble() ?? 0.0,
              loanStatus: row['loanStatus'] as String? ?? '',
              groupName: row['groupName'] as String?,
            ))
        .toList();

    final overdueEntries = (heavy[1] as List<Map<String, dynamic>>)
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
      );
    }).toList();

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

  Future<Result<PortfolioBreakdown>> getPortfolioBreakdown() async {
    try {
      final db = await _database;
      final results = await Future.wait([
        db.rawQuery("SELECT COUNT(*) AS count, COALESCE(SUM(outstanding_balance), 0) AS amount FROM loans WHERE status = 'active'"),
        db.rawQuery("SELECT COUNT(*) AS count, COALESCE(SUM(amount), 0) AS amount FROM loans WHERE status = 'completed'"),
        db.rawQuery("SELECT COUNT(*) AS count, COALESCE(SUM(outstanding_balance), 0) AS amount FROM loans WHERE status = 'defaulted'"),
      ]);
      return Result.success(PortfolioBreakdown(
        activeCount: _toInt(results[0].first, 'count'),
        completedCount: _toInt(results[1].first, 'count'),
        defaultedCount: _toInt(results[2].first, 'count'),
        activeAmount: _toDouble(results[0].first, 'amount'),
        completedAmount: _toDouble(results[1].first, 'amount'),
        defaultedAmount: _toDouble(results[2].first, 'amount'),
      ));
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to load portfolio breakdown.', cause: e));
    }
  }

  Future<Result<List<CollectionTrend>>> getCollectionTrends(int months) async {
    try {
      final db = await _database;
      final now = DateTime.now();
      final trends = <CollectionTrend>[];
      for (int i = months - 1; i >= 0; i--) {
        final month = DateTime(now.year, now.month - i, 1);
        final monthStart = AppDateUtils.formatForStorage(month);
        final monthEnd = AppDateUtils.formatForStorage(DateTime(month.year, month.month + 1, 0));
        final monthLabel = '${month.year}-${month.month.toString().padLeft(2, '0')}';
        final row = await db.rawQuery(
          "SELECT "
          "(SELECT COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0) "
          "FROM payments p "
          "LEFT JOIN savings_transactions st "
          "  ON st.reference_loan_payment_id = p.id "
          " AND st.type = 'overpayment' "
          "WHERE p.status = 'completed' AND p.payment_date BETWEEN ? AND ?) AS collected, "
          "COALESCE(SUM(rs.amount - COALESCE(rs.paid_amount, 0)), 0) AS expected "
          "FROM repayment_schedule rs "
          "WHERE rs.due_date BETWEEN ? AND ? AND rs.status != 'paid'",
          [monthStart, '$monthEnd 23:59:59', monthStart, monthEnd],
        );
        final collected = _toDouble(row.first, 'collected');
        final expected = _toDouble(row.first, 'expected');
        final efficiency = expected > 0 ? ((collected / expected) * 100).clamp(0.0, 100.0) : 0.0;
        trends.add(CollectionTrend(label: monthLabel, expected: expected, collected: collected, efficiency: efficiency));
      }
      return Result.success(trends);
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to load collection trends.', cause: e));
    }
  }

  Future<Result<List<MonthlyTrendPoint>>> getRepaymentTrends(int months) async {
    try {
      final db = await _database;
      final now = DateTime.now();
      final trends = <MonthlyTrendPoint>[];
      for (int i = months - 1; i >= 0; i--) {
        final month = DateTime(now.year, now.month - i, 1);
        final monthStart = AppDateUtils.formatForStorage(month);
        final monthEnd = AppDateUtils.formatForStorage(DateTime(month.year, month.month + 1, 0));
        final monthLabel = '${month.year}-${month.month.toString().padLeft(2, '0')}';
        final row = await db.rawQuery(
          "SELECT COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0) AS total "
          "FROM payments p "
          "LEFT JOIN savings_transactions st "
          "  ON st.reference_loan_payment_id = p.id "
          " AND st.type = 'overpayment' "
          "WHERE p.status = 'completed' AND p.payment_date BETWEEN ? AND ?",
          [monthStart, '$monthEnd 23:59:59'],
        );
        trends.add(MonthlyTrendPoint(label: monthLabel, value: _toDouble(row.first, 'total')));
      }
      return Result.success(trends);
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to load repayment trends.', cause: e));
    }
  }

  Future<Result<GrowthStats>> getGrowthStats(int months) async {
    try {
      final db = await _database;
      final now = DateTime.now();
      final thisMonthStart = AppDateUtils.formatForStorage(DateTime(now.year, now.month, 1));

      final totals = await Future.wait([
        db.rawQuery('SELECT COUNT(*) AS count FROM customers'),
        db.rawQuery("SELECT COUNT(*) AS count FROM customers WHERE status = 'active'"),
        db.rawQuery("SELECT COUNT(*) AS count FROM customers WHERE status != 'active'"),
        db.rawQuery('SELECT COUNT(DISTINCT customer_id) AS count FROM loans WHERE status IN (\'active\', \'completed\')'),
        db.rawQuery('SELECT COUNT(*) AS count FROM customers WHERE DATE(date_registered) >= ?', [thisMonthStart]),
      ]);
      final totalCustomers = _toInt(totals[0].first, 'count');
      final activeCustomers = _toInt(totals[1].first, 'count');
      final inactiveCustomers = _toInt(totals[2].first, 'count');
      final repeatBorrowers = _toInt(totals[3].first, 'count');
      final newCustomersThisMonth = _toInt(totals[4].first, 'count');

      final customerGrowth = <MonthlyTrendPoint>[];
      final loanGrowth = <MonthlyTrendPoint>[];
      for (int i = months - 1; i >= 0; i--) {
        final month = DateTime(now.year, now.month - i, 1);
        final monthStart = AppDateUtils.formatForStorage(month);
        final monthEnd = AppDateUtils.formatForStorage(DateTime(month.year, month.month + 1, 0));
        final monthLabel = '${month.year}-${month.month.toString().padLeft(2, '0')}';
        final rows = await Future.wait([
          db.rawQuery('SELECT COUNT(*) AS count FROM customers WHERE DATE(date_registered) BETWEEN ? AND ?', [monthStart, monthEnd]),
          db.rawQuery("SELECT COUNT(*) AS count, COALESCE(SUM(amount), 0) AS amount FROM loans WHERE loan_date BETWEEN ? AND ?", [monthStart, monthEnd]),
        ]);
        customerGrowth.add(MonthlyTrendPoint(label: monthLabel, value: _toInt(rows[0].first, 'count').toDouble()));
        final loanCount = _toInt(rows[1].first, 'count');
        loanGrowth.add(MonthlyTrendPoint(label: monthLabel, value: loanCount.toDouble()));
      }

      return Result.success(GrowthStats(
        totalCustomers: totalCustomers,
        activeCustomers: activeCustomers,
        inactiveCustomers: inactiveCustomers,
        repeatBorrowers: repeatBorrowers,
        newCustomersThisMonth: newCustomersThisMonth,
        customerGrowth: customerGrowth,
        loanGrowth: loanGrowth,
      ));
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to load growth stats.', cause: e));
    }
  }

  Future<Result<List<SavingsTrendPoint>>> getSavingsTrends(int months) async {
    try {
      final db = await _database;
      final now = DateTime.now();
      final trends = <SavingsTrendPoint>[];
      for (int i = months - 1; i >= 0; i--) {
        final month = DateTime(now.year, now.month - i, 1);
        final monthStart = AppDateUtils.formatForStorage(month);
        final monthEnd = AppDateUtils.formatForStorage(DateTime(month.year, month.month + 1, 0));
        final monthLabel = '${month.year}-${month.month.toString().padLeft(2, '0')}';
        final row = await db.rawQuery(
          "SELECT "
          "COALESCE(SUM(CASE WHEN type IN ('deposit', 'overpayment') THEN amount ELSE 0 END), 0) AS deposits, "
          "COALESCE(SUM(CASE WHEN type = 'withdrawal' THEN amount ELSE 0 END), 0) AS withdrawals "
          "FROM savings_transactions WHERE DATE(created_at) BETWEEN ? AND ?",
          [monthStart, monthEnd],
        );
        final deposits = _toDouble(row.first, 'deposits');
        final withdrawals = _toDouble(row.first, 'withdrawals');
        final balance = deposits - withdrawals;
        trends.add(SavingsTrendPoint(label: monthLabel, deposits: deposits, withdrawals: withdrawals, balance: balance));
      }
      return Result.success(trends);
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to load savings trends.', cause: e));
    }
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
        );
      }).toList();

      return Result.success(entries);
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to fetch overdue report.', cause: e));
    }
  }
}


