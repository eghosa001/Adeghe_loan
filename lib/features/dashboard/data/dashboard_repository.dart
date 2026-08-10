import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_service.dart';
import '../../../core/error/failure.dart';
import '../../../core/utils/date_utils.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/payments/data/models/payment_entity.dart';
import 'models/dashboard_data.dart';

/// Reporting period options for dashboard filtering
enum DashboardPeriod {
  today,
  yesterday,
  thisWeek,
  thisMonth,
  lastMonth,
  custom,
}

class DashboardRepository {
  DashboardRepository(this._dbService);
  final DatabaseService _dbService;

  Future<Database> get _database async {
    return _dbService.database;
  }

  /// Helper: extract a single numeric scalar from a query result row.
  static double _toDouble(Map<String, dynamic> row, String key) =>
      (row[key] as num?)?.toDouble() ?? 0.0;

  static int _toInt(Map<String, dynamic> row, String key) =>
      (row[key] as int?) ?? 0;

  /// Get date range for a given period
  Map<String, String> getPeriodDateRange(DashboardPeriod period, {DateTime? customStart, DateTime? customEnd}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    DateTime startDate;
    DateTime endDate = today;
    
    switch (period) {
      case DashboardPeriod.today:
        startDate = today;
        break;
      case DashboardPeriod.yesterday:
        startDate = today.subtract(const Duration(days: 1));
        endDate = startDate;
        break;
      case DashboardPeriod.thisWeek:
        // Week starts on Monday
        final weekday = today.weekday; // 1 = Monday, 7 = Sunday
        startDate = today.subtract(Duration(days: weekday - 1));
        break;
      case DashboardPeriod.thisMonth:
        startDate = DateTime(now.year, now.month, 1);
        break;
      case DashboardPeriod.lastMonth:
        startDate = DateTime(now.year, now.month - 1, 1);
        endDate = DateTime(now.year, now.month, 0);
        break;
      case DashboardPeriod.custom:
        startDate = customStart ?? today;
        endDate = customEnd ?? today;
        break;
    }
    
    return {
      'start': AppDateUtils.formatForStorage(startDate),
      'end': AppDateUtils.formatForStorage(endDate),
    };
  }

  Future<Result<DashboardData>> getDashboardData({
    DashboardPeriod period = DashboardPeriod.today,
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    try {
      final db = await _database;

      // Local device dates (never UTC `date('now')`) so day windows match the
      // locally-stored `payment_date` strings.
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todayStr = AppDateUtils.formatForStorage(today);
      final weekStartStr =
          AppDateUtils.formatForStorage(today.subtract(const Duration(days: 6)));
      final monthStart = DateTime(now.year, now.month, 1);
      final monthStartStr = AppDateUtils.formatForStorage(monthStart);
      
      // Get period date range for period-based metrics
      final periodRange = getPeriodDateRange(period, customStart: customStart, customEnd: customEnd);
      final periodStartStr = periodRange['start']!;
      final periodEndStr = periodRange['end']!;

      // Run all independent read queries in parallel.
      final results = await Future.wait([
        // 0: Total customers
        db.rawQuery("SELECT COUNT(*) AS count FROM customers WHERE status != 'archived'"),
        // 1: Active loans count
        db.rawQuery("SELECT COUNT(*) AS count FROM loans WHERE status = 'active'"),
        // 2: Completed loans count
        db.rawQuery("SELECT COUNT(*) AS count FROM loans WHERE status = 'completed'"),
        // 3: Daily active loans
        db.rawQuery("SELECT COUNT(*) AS count FROM loans WHERE status = 'active' AND loan_type = 'daily'"),
        // 4: Weekly active loans
        db.rawQuery("SELECT COUNT(*) AS count FROM loans WHERE status = 'active' AND loan_type = 'weekly'"),
        // 5: Daily disbursed
        db.rawQuery("SELECT COALESCE(SUM(amount), 0.0) AS total FROM loans WHERE status IN ('active', 'completed', 'defaulted') AND loan_type = 'daily'"),
        // 6: Weekly disbursed
        db.rawQuery("SELECT COALESCE(SUM(amount), 0.0) AS total FROM loans WHERE status IN ('active', 'completed', 'defaulted') AND loan_type = 'weekly'"),
        // 7: Total collected (excluding overpayments credited to savings)
        db.rawQuery(
          "SELECT COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0.0) AS total "
          "FROM payments p "
          "LEFT JOIN savings_transactions st "
          "  ON st.reference_loan_payment_id = p.id "
          " AND st.type = 'overpayment' "
          "WHERE p.status = 'completed'"),
        // 8: Daily collected
        db.rawQuery(
          "SELECT COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0.0) AS total "
          "FROM payments p "
          "LEFT JOIN savings_transactions st "
          "  ON st.reference_loan_payment_id = p.id "
          " AND st.type = 'overpayment' "
          "WHERE p.status = 'completed' AND DATE(p.payment_date) = ?",
          [todayStr],
        ),
        // 9: Weekly collected
        db.rawQuery(
          "SELECT COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0.0) AS total "
          "FROM payments p "
          "LEFT JOIN savings_transactions st "
          "  ON st.reference_loan_payment_id = p.id "
          " AND st.type = 'overpayment' "
          "WHERE p.status = 'completed' AND DATE(p.payment_date) >= ?",
          [weekStartStr],
        ),
        // 10: Daily outstanding balance
        db.rawQuery("SELECT COALESCE(SUM(outstanding_balance), 0.0) AS total FROM loans WHERE status = 'active' AND loan_type = 'daily'"),
        // 11: Weekly outstanding balance
        db.rawQuery("SELECT COALESCE(SUM(outstanding_balance), 0.0) AS total FROM loans WHERE status = 'active' AND loan_type = 'weekly'"),
        // 12: Recent loans
        db.query(AppConstants.tableLoans, orderBy: 'loan_date DESC', limit: AppConstants.recentItemsLimit),
        // 13: Recent payments
        db.query(AppConstants.tablePayments,
          where: "status = 'completed'",
          orderBy: 'payment_date DESC',
          limit: AppConstants.recentItemsLimit),
        // 14: Total savings balance
        db.rawQuery('SELECT COALESCE(SUM(balance), 0.0) AS total FROM savings_accounts'),
        // 15: Total groups
        db.rawQuery('SELECT COUNT(*) AS count FROM customer_groups'),
        // 16: Recent savings transactions
        db.rawQuery(
          'SELECT st.id, sa.customer_id AS customerId, c.full_name AS customerName, '
          'st.type, st.amount, st.created_at AS createdAt '
          'FROM savings_transactions st '
          'INNER JOIN savings_accounts sa ON st.savings_account_id = sa.id '
          'INNER JOIN customers c ON sa.customer_id = c.id '
          'ORDER BY st.created_at DESC LIMIT ?',
          [AppConstants.recentItemsLimit],
        ),
        // 17: Total expected (sum of unpaid portions of active loan schedules)
        db.rawQuery(
          "SELECT COALESCE(SUM(rs.amount - COALESCE(rs.paid_amount, 0)), 0.0) AS total "
          "FROM repayment_schedule rs "
          "JOIN loans l ON rs.loan_id = l.id "
          "WHERE rs.status != 'paid' AND l.status = 'active'"),
        // 18: Daily expected (installments due today)
        db.rawQuery(
          "SELECT COALESCE(SUM(rs.amount - COALESCE(rs.paid_amount, 0)), 0.0) AS total "
          "FROM repayment_schedule rs "
          "JOIN loans l ON rs.loan_id = l.id "
          "WHERE DATE(rs.due_date) = ? AND rs.status != 'paid' AND l.status = 'active'",
          [todayStr]),
        // 19: Weekly expected (installments due this week)
        db.rawQuery(
          "SELECT COALESCE(SUM(rs.amount - COALESCE(rs.paid_amount, 0)), 0.0) AS total "
          "FROM repayment_schedule rs "
          "JOIN loans l ON rs.loan_id = l.id "
          "WHERE DATE(rs.due_date) >= ? AND rs.status != 'paid' AND l.status = 'active'",
          [weekStartStr]),
        // 20: Total overdue amount (unpaid installments with due date < today)
        db.rawQuery(
          "SELECT COALESCE(SUM(rs.amount - COALESCE(rs.paid_amount, 0)), 0.0) AS total "
          "FROM repayment_schedule rs "
          "JOIN loans l ON rs.loan_id = l.id "
          "WHERE DATE(rs.due_date) < ? AND rs.status != 'paid' AND l.status IN ('active', 'defaulted')",
          [todayStr]),
        // 21: Overdue 1-7 days
        db.rawQuery(
          "SELECT COALESCE(SUM(rs.amount - COALESCE(rs.paid_amount, 0)), 0.0) AS total "
          "FROM repayment_schedule rs "
          "JOIN loans l ON rs.loan_id = l.id "
          "WHERE DATE(rs.due_date) >= ? AND DATE(rs.due_date) < ? AND rs.status != 'paid' AND l.status IN ('active', 'defaulted')",
          [AppDateUtils.formatForStorage(today.subtract(const Duration(days: 7))), todayStr]),
        // 22: Overdue 8-30 days
        db.rawQuery(
          "SELECT COALESCE(SUM(rs.amount - COALESCE(rs.paid_amount, 0)), 0.0) AS total "
          "FROM repayment_schedule rs "
          "JOIN loans l ON rs.loan_id = l.id "
          "WHERE DATE(rs.due_date) >= ? AND DATE(rs.due_date) < ? AND rs.status != 'paid' AND l.status IN ('active', 'defaulted')",
          [AppDateUtils.formatForStorage(today.subtract(const Duration(days: 30))), AppDateUtils.formatForStorage(today.subtract(const Duration(days: 7)))]),
        // 23: Overdue 31+ days
        db.rawQuery(
          "SELECT COALESCE(SUM(rs.amount - COALESCE(rs.paid_amount, 0)), 0.0) AS total "
          "FROM repayment_schedule rs "
          "JOIN loans l ON rs.loan_id = l.id "
          "WHERE DATE(rs.due_date) < ? AND rs.status != 'paid' AND l.status IN ('active', 'defaulted')",
          [AppDateUtils.formatForStorage(today.subtract(const Duration(days: 30)))]),
        // 24: Overdue loans count
        db.rawQuery(
          "SELECT COUNT(DISTINCT l.id) AS count FROM loans l "
          "WHERE l.status IN ('active', 'defaulted') AND EXISTS ("
          "  SELECT 1 FROM repayment_schedule rs WHERE rs.loan_id = l.id "
          "  AND rs.status != 'paid' AND DATE(rs.due_date) < ?)",
          [todayStr]),
        // 25: Overdue customers count
        db.rawQuery(
          "SELECT COUNT(DISTINCT l.customer_id) AS count FROM loans l "
          "WHERE l.status IN ('active', 'defaulted') AND EXISTS ("
          "  SELECT 1 FROM repayment_schedule rs WHERE rs.loan_id = l.id "
          "  AND rs.status != 'paid' AND DATE(rs.due_date) < ?)",
          [todayStr]),
        // 26: PAR 1+ (portfolio at risk 1+ days)
        db.rawQuery(
          "SELECT COALESCE(SUM(l.outstanding_balance), 0.0) AS total FROM loans l "
          "WHERE l.status IN ('active', 'defaulted') AND EXISTS ("
          "  SELECT 1 FROM repayment_schedule rs WHERE rs.loan_id = l.id "
          "  AND rs.status != 'paid' AND DATE(rs.due_date) < ?)",
          [todayStr]),
        // 27: PAR 7+ 
        db.rawQuery(
          "SELECT COALESCE(SUM(l.outstanding_balance), 0.0) AS total FROM loans l "
          "WHERE l.status IN ('active', 'defaulted') AND EXISTS ("
          "  SELECT 1 FROM repayment_schedule rs WHERE rs.loan_id = l.id "
          "  AND rs.status != 'paid' AND DATE(rs.due_date) < ?)",
          [AppDateUtils.formatForStorage(today.subtract(const Duration(days: 7)))]),
        // 28: PAR 30+
        db.rawQuery(
          "SELECT COALESCE(SUM(l.outstanding_balance), 0.0) AS total FROM loans l "
          "WHERE l.status IN ('active', 'defaulted') AND EXISTS ("
          "  SELECT 1 FROM repayment_schedule rs WHERE rs.loan_id = l.id "
          "  AND rs.status != 'paid' AND DATE(rs.due_date) < ?)",
          [AppDateUtils.formatForStorage(today.subtract(const Duration(days: 30)))]),
        // 31: Total interest earned (all time - not period-based)
        db.rawQuery(
          "SELECT COALESCE(SUM(amount * interest_rate / 100), 0.0) AS total FROM loans "
          "WHERE status IN ('active', 'completed', 'defaulted')"),
        // 32: Total fees earned (all time - not period-based)
        db.rawQuery(
          "SELECT COALESCE(SUM(amount * insurance_fee / 100 + amount * commission / 100 + processing_fee + admin_fee + other_charges), 0.0) AS total FROM loans "
          "WHERE status IN ('active', 'completed', 'defaulted')"),
        // 33: Total expenses (all time) - returns 0 if table doesn't exist yet
        // Note: Expenses table is not yet implemented in the schema
        db.rawQuery("SELECT 0.0 AS total"),
        // 34: Savings deposits this month
        db.rawQuery(
          "SELECT COALESCE(SUM(amount), 0.0) AS total FROM savings_transactions "
          "WHERE type = 'deposit' AND DATE(created_at) >= ?",
          [monthStartStr]),
        // 35: Savings withdrawals this month
        db.rawQuery(
          "SELECT COALESCE(SUM(amount), 0.0) AS total FROM savings_transactions "
          "WHERE type = 'withdrawal' AND DATE(created_at) >= ?",
          [monthStartStr]),
        // 36: New customers today
        db.rawQuery(
          "SELECT COUNT(*) AS count FROM customers WHERE DATE(created_at) = ?",
          [todayStr]),
        // 37: New customers this week
        db.rawQuery(
          "SELECT COUNT(*) AS count FROM customers WHERE DATE(created_at) >= ?",
          [weekStartStr]),
        // 38: New customers this month
        db.rawQuery(
          "SELECT COUNT(*) AS count FROM customers WHERE DATE(created_at) >= ?",
          [monthStartStr]),
        // 39: Today's collection - customers due today
        db.rawQuery(
          "SELECT COUNT(DISTINCT l.customer_id) AS count FROM loans l "
          "JOIN repayment_schedule rs ON rs.loan_id = l.id "
          "WHERE DATE(rs.due_date) = ? AND l.status = 'active'",
          [todayStr]),
        // 40: Today's collection - customers who paid today
        db.rawQuery(
          "SELECT COUNT(DISTINCT p.customer_id) AS count FROM payments p "
          "WHERE p.status = 'completed' AND DATE(p.payment_date) = ?",
          [todayStr]),
        // 41: Period disbursed (principal disbursed during selected period)
        db.rawQuery(
          "SELECT COALESCE(SUM(amount), 0.0) AS total FROM loans "
          "WHERE status IN ('active', 'completed', 'defaulted') "
          "AND DATE(loan_date) BETWEEN ? AND ?",
          [periodStartStr, periodEndStr]),
        // 42: Period collected (payments received during selected period)
        db.rawQuery(
          "SELECT COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0.0) AS total "
          "FROM payments p "
          "LEFT JOIN savings_transactions st "
          "  ON st.reference_loan_payment_id = p.id "
          " AND st.type = 'overpayment' "
          "WHERE p.status = 'completed' AND DATE(p.payment_date) BETWEEN ? AND ?",
          [periodStartStr, periodEndStr]),
        // 43: Overdue carried forward (overdue before today that affects today's collection)
        db.rawQuery(
          "SELECT COALESCE(SUM(rs.amount - COALESCE(rs.paid_amount, 0)), 0.0) AS total "
          "FROM repayment_schedule rs "
          "JOIN loans l ON rs.loan_id = l.id "
          "WHERE DATE(rs.due_date) < ? AND rs.status != 'paid' AND l.status IN ('active', 'defaulted')",
          [todayStr]),
      ]);

      final totalCustomers = _toInt(results[0].first, 'count');
      final activeLoans = _toInt(results[1].first, 'count');
      final completedLoans = _toInt(results[2].first, 'count');
      final dailyActiveLoans = _toInt(results[3].first, 'count');
      final weeklyActiveLoans = _toInt(results[4].first, 'count');
      final dailyDisbursed = _toDouble(results[5].first, 'total');
      final weeklyDisbursed = _toDouble(results[6].first, 'total');
      final totalDisbursed = dailyDisbursed + weeklyDisbursed;
      final totalCollected = _toDouble(results[7].first, 'total');
      final dailyCollected = _toDouble(results[8].first, 'total');
      final weeklyCollected = _toDouble(results[9].first, 'total');
      final dailyOutstandingBalance = _toDouble(results[10].first, 'total');
      final weeklyOutstandingBalance = _toDouble(results[11].first, 'total');
      final outstandingBalance = dailyOutstandingBalance + weeklyOutstandingBalance;
      final recentLoans = (results[12] as List<Map<String, dynamic>>)
          .map(Loan.fromMap)
          .toList(growable: false);
      final recentPayments = (results[13] as List<Map<String, dynamic>>)
          .map(Payment.fromMap)
          .toList(growable: false);
      final totalSavingsBalance = _toDouble(results[14].first, 'total');
      final totalGroups = _toInt(results[15].first, 'count');
      final recentSavingsTransactions = (results[16] as List<Map<String, dynamic>>)
          .map(DashboardSavingsTransaction.fromMap)
          .toList(growable: false);
      
      // Expected collections
      final totalExpected = _toDouble(results[17].first, 'total');
      final dailyExpected = _toDouble(results[18].first, 'total');
      final weeklyExpected = _toDouble(results[19].first, 'total');
      
      // Overdue amounts
      final totalOverdue = _toDouble(results[20].first, 'total');
      final overdue1to7Days = _toDouble(results[21].first, 'total');
      final overdue8to30Days = _toDouble(results[22].first, 'total');
      final overdue31PlusDays = _toDouble(results[23].first, 'total');
      
      // Overdue counts
      final overdueLoansCount = _toInt(results[24].first, 'count');
      final overdueCustomersCount = _toInt(results[25].first, 'count');
      
      // PAR calculations
      final par1PlusAmount = _toDouble(results[26].first, 'total');
      final par7PlusAmount = _toDouble(results[27].first, 'total');
      final par30PlusAmount = _toDouble(results[28].first, 'total');
      final totalOutstanding = outstandingBalance > 0 ? outstandingBalance : 1.0;
      final par1Plus = ((par1PlusAmount / totalOutstanding) * 100).clamp(0.0, 100.0);
      final par7Plus = ((par7PlusAmount / totalOutstanding) * 100).clamp(0.0, 100.0);
      final par30Plus = ((par30PlusAmount / totalOutstanding) * 100).clamp(0.0, 100.0);
      
      // Income
      final totalInterestEarned = _toDouble(results[29].first, 'total');
      final totalFeesEarned = _toDouble(results[30].first, 'total');
      final totalExpenses = _toDouble(results[31].first, 'total');
      
      // Savings activity
      final savingsDepositsThisMonth = _toDouble(results[32].first, 'total');
      final savingsWithdrawalsThisMonth = _toDouble(results[33].first, 'total');
      
      // New customers
      final newCustomersToday = _toInt(results[34].first, 'count');
      final newCustomersThisWeek = _toInt(results[35].first, 'count');
      final newCustomersThisMonth = _toInt(results[36].first, 'count');
      
      // Today's collection stats
      final todayDueCustomers = _toInt(results[37].first, 'count');
      final todayPaidCustomers = _toInt(results[38].first, 'count');
      final todayPendingCustomers = todayDueCustomers - todayPaidCustomers;
      final todayExpected = dailyExpected;
      final todayCollected = dailyCollected;
      
      // Period-based metrics (queries 41 and 42)
      final periodDisbursed = _toDouble(results[40].first, 'total');
      final periodCollected = _toDouble(results[41].first, 'total');

      return Result.success(DashboardData(
        totalCustomers: totalCustomers,
        activeLoans: activeLoans,
        completedLoans: completedLoans,
        dailyActiveLoans: dailyActiveLoans,
        weeklyActiveLoans: weeklyActiveLoans,
        totalDisbursed: totalDisbursed,
        periodDisbursed: periodDisbursed,
        dailyDisbursed: dailyDisbursed,
        weeklyDisbursed: weeklyDisbursed,
        totalCollected: totalCollected,
        periodCollected: periodCollected,
        dailyCollected: dailyCollected,
        weeklyCollected: weeklyCollected,
        outstandingBalance: outstandingBalance,
        dailyOutstandingBalance: dailyOutstandingBalance,
        weeklyOutstandingBalance: weeklyOutstandingBalance,
        totalExpected: totalExpected,
        dailyExpected: dailyExpected,
        weeklyExpected: weeklyExpected,
        totalOverdue: totalOverdue,
        overdue1to7Days: overdue1to7Days,
        overdue8to30Days: overdue8to30Days,
        overdue31PlusDays: overdue31PlusDays,
        overdueLoansCount: overdueLoansCount,
        overdueCustomersCount: overdueCustomersCount,
        par1Plus: par1Plus,
        par7Plus: par7Plus,
        par30Plus: par30Plus,
        totalInterestEarned: totalInterestEarned,
        totalFeesEarned: totalFeesEarned,
        totalExpenses: totalExpenses,
        totalSavingsBalance: totalSavingsBalance,
        savingsDepositsThisMonth: savingsDepositsThisMonth,
        savingsWithdrawalsThisMonth: savingsWithdrawalsThisMonth,
        newCustomersToday: newCustomersToday,
        newCustomersThisWeek: newCustomersThisWeek,
        newCustomersThisMonth: newCustomersThisMonth,
        todayExpected: todayExpected,
        todayCollected: todayCollected,
        todayDueCustomers: todayDueCustomers,
        todayPaidCustomers: todayPaidCustomers,
        todayPendingCustomers: todayPendingCustomers,
        totalGroups: totalGroups,
        recentLoans: recentLoans,
        recentPayments: recentPayments,
        recentSavingsTransactions: recentSavingsTransactions,
      ));
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load dashboard data.', cause: e));
    }
  }
}
