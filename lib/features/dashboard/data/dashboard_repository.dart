import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_service.dart';
import '../../../core/error/failure.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/payments/data/models/payment_entity.dart';
import 'models/dashboard_data.dart';

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

  Future<Result<DashboardData>> getDashboardData() async {
    try {
      final db = await _database;

      // Local device dates (never UTC `date('now')`) so day windows match the
      // locally-stored `payment_date` strings.
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todayStr = today.toIso8601String().split('T').first;
      final weekStartStr = today
          .subtract(const Duration(days: 6))
          .toIso8601String()
          .split('T')
          .first;

      // Run all independent read queries in parallel.
      final results = await Future.wait([
        db.rawQuery('SELECT COUNT(*) AS count FROM customers'),
        db.rawQuery("SELECT COUNT(*) AS count FROM loans WHERE status = 'active'"),
        db.rawQuery("SELECT COUNT(*) AS count FROM loans WHERE status = 'active' AND loan_type = 'daily'"),
        db.rawQuery("SELECT COUNT(*) AS count FROM loans WHERE status = 'active' AND loan_type = 'weekly'"),
        db.rawQuery("SELECT COALESCE(SUM(amount), 0.0) AS total FROM loans WHERE status IN ('active', 'completed', 'defaulted') AND loan_type = 'daily'"),
        db.rawQuery("SELECT COALESCE(SUM(amount), 0.0) AS total FROM loans WHERE status IN ('active', 'completed', 'defaulted') AND loan_type = 'weekly'"),
        db.rawQuery(
          "SELECT COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0.0) AS total "
          "FROM payments p "
          "LEFT JOIN savings_transactions st "
          "  ON st.reference_loan_payment_id = p.id "
          " AND st.type = 'overpayment' "
          "WHERE p.status = 'completed'"),
        db.rawQuery(
          "SELECT COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0.0) AS total "
          "FROM payments p "
          "LEFT JOIN savings_transactions st "
          "  ON st.reference_loan_payment_id = p.id "
          " AND st.type = 'overpayment' "
          "WHERE p.status = 'completed' AND DATE(p.payment_date) = ?",
          [todayStr],
        ),
        db.rawQuery(
          "SELECT COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0.0) AS total "
          "FROM payments p "
          "LEFT JOIN savings_transactions st "
          "  ON st.reference_loan_payment_id = p.id "
          " AND st.type = 'overpayment' "
          "WHERE p.status = 'completed' AND DATE(p.payment_date) >= ?",
          [weekStartStr],
        ),
        db.rawQuery("SELECT COALESCE(SUM(outstanding_balance), 0.0) AS total FROM loans WHERE status = 'active' AND loan_type = 'daily'"),
        db.rawQuery("SELECT COALESCE(SUM(outstanding_balance), 0.0) AS total FROM loans WHERE status = 'active' AND loan_type = 'weekly'"),
        db.query(AppConstants.tableLoans, orderBy: 'loan_date DESC', limit: AppConstants.recentItemsLimit),
        db.query(AppConstants.tablePayments,
          where: "status = 'completed'",
          orderBy: 'payment_date DESC',
          limit: AppConstants.recentItemsLimit),
        db.rawQuery('SELECT COALESCE(SUM(balance), 0.0) AS total FROM savings_accounts'),
        db.rawQuery('SELECT COUNT(*) AS count FROM customer_groups'),
        db.rawQuery(
          'SELECT st.id, sa.customer_id AS customerId, c.full_name AS customerName, '
          'st.type, st.amount, st.created_at AS createdAt '
          'FROM savings_transactions st '
          'INNER JOIN savings_accounts sa ON st.savings_account_id = sa.id '
          'INNER JOIN customers c ON sa.customer_id = c.id '
          'ORDER BY st.created_at DESC LIMIT ?',
          [AppConstants.recentItemsLimit],
        ),
      ]);

      final totalCustomers = _toInt(results[0].first, 'count');
      final activeLoans = _toInt(results[1].first, 'count');
      final dailyActiveLoans = _toInt(results[2].first, 'count');
      final weeklyActiveLoans = _toInt(results[3].first, 'count');
      final dailyDisbursed = _toDouble(results[4].first, 'total');
      final weeklyDisbursed = _toDouble(results[5].first, 'total');
      final totalDisbursed = dailyDisbursed + weeklyDisbursed;
      final totalCollected = _toDouble(results[6].first, 'total');
      final dailyCollected = _toDouble(results[7].first, 'total');
      final weeklyCollected = _toDouble(results[8].first, 'total');
      final dailyOutstandingBalance = _toDouble(results[9].first, 'total');
      final weeklyOutstandingBalance = _toDouble(results[10].first, 'total');
      final outstandingBalance = dailyOutstandingBalance + weeklyOutstandingBalance;
      final recentLoans = (results[11] as List<Map<String, dynamic>>)
          .map(Loan.fromMap)
          .toList(growable: false);
      final recentPayments = (results[12] as List<Map<String, dynamic>>)
          .map(Payment.fromMap)
          .toList(growable: false);
      final totalSavingsBalance = _toDouble(results[13].first, 'total');
      final totalGroups = _toInt(results[14].first, 'count');
      final recentSavingsTransactions = (results[15] as List<Map<String, dynamic>>)
          .map(DashboardSavingsTransaction.fromMap)
          .toList(growable: false);

      return Result.success(DashboardData(
        totalCustomers: totalCustomers,
        activeLoans: activeLoans,
        dailyActiveLoans: dailyActiveLoans,
        weeklyActiveLoans: weeklyActiveLoans,
        totalDisbursed: totalDisbursed,
        dailyDisbursed: dailyDisbursed,
        weeklyDisbursed: weeklyDisbursed,
        totalCollected: totalCollected,
        dailyCollected: dailyCollected,
        weeklyCollected: weeklyCollected,
        outstandingBalance: outstandingBalance,
        dailyOutstandingBalance: dailyOutstandingBalance,
        weeklyOutstandingBalance: weeklyOutstandingBalance,
        totalSavingsBalance: totalSavingsBalance,
        recentLoans: recentLoans,
        recentPayments: recentPayments,
        totalGroups: totalGroups,
        recentSavingsTransactions: recentSavingsTransactions,
      ));
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load dashboard data.', cause: e));
    }
  }
}
