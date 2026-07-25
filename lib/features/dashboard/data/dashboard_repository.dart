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

  Future<Result<DashboardData>> getDashboardData() async {
    try {
      final db = await _database;

      // ── Customers ───────────────────────────────────────────────────────────
      final customerCountResult =
          await db.rawQuery('SELECT COUNT(*) AS count FROM customers');
      final totalCustomers =
          (customerCountResult.first['count'] as int?) ?? 0;

      // ── Active Loans ─────────────────────────────────────────────────────────
      final activeLoansResult = await db.rawQuery(
          "SELECT COUNT(*) AS count FROM loans WHERE status = 'active'");
      final activeLoans = (activeLoansResult.first['count'] as int?) ?? 0;

      // Loans created today
      final dailyActiveLoansResult = await db.rawQuery(
          "SELECT COUNT(*) AS count FROM loans "
          "WHERE status = 'active' AND DATE(loan_date) = DATE('now')");
      final dailyActiveLoans =
          (dailyActiveLoansResult.first['count'] as int?) ?? 0;

      // Loans created in the last 7 days
      final weeklyActiveLoansResult = await db.rawQuery(
          "SELECT COUNT(*) AS count FROM loans "
          "WHERE status = 'active' AND DATE(loan_date) >= DATE('now', '-6 days')");
      final weeklyActiveLoans =
          (weeklyActiveLoansResult.first['count'] as int?) ?? 0;

      // ── Disbursed ─────────────────────────────────────────────────────────────
      // Sum of all loans that were actually disbursed (active + completed + defaulted).
      final disbursedResult = await db.rawQuery(
          "SELECT COALESCE(SUM(amount), 0.0) AS total FROM loans "
          "WHERE status IN ('active', 'completed', 'defaulted')");
      final totalDisbursed =
          (disbursedResult.first['total'] as num?)?.toDouble() ?? 0.0;

      // ── Collected ─────────────────────────────────────────────────────────────
      final collectedResult = await db.rawQuery(
          "SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments "
          "WHERE status = 'completed'");
      final totalCollected =
          (collectedResult.first['total'] as num?)?.toDouble() ?? 0.0;

      final dailyCollectedResult = await db.rawQuery(
          "SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments "
          "WHERE status = 'completed' AND DATE(payment_date) = DATE('now')");
      final dailyCollected =
          (dailyCollectedResult.first['total'] as num?)?.toDouble() ?? 0.0;

      final weeklyCollectedResult = await db.rawQuery(
          "SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments "
          "WHERE status = 'completed' "
          "AND DATE(payment_date) >= DATE('now', '-6 days')");
      final weeklyCollected =
          (weeklyCollectedResult.first['total'] as num?)?.toDouble() ?? 0.0;

      // ── Outstanding ───────────────────────────────────────────────────────────
      // Total unpaid balance across all active loans.
      final outstandingResult = await db.rawQuery(
          "SELECT COALESCE(SUM(outstanding_balance), 0.0) AS total "
          "FROM loans WHERE status = 'active'");
      final outstandingBalance =
          (outstandingResult.first['total'] as num?)?.toDouble() ?? 0.0;

      // Installments due TODAY that have not been fully paid.
      final dailyOutstandingResult = await db.rawQuery('''
        SELECT COALESCE(SUM(rs.amount - rs.paid_amount), 0.0) AS total
        FROM repayment_schedule rs
        INNER JOIN loans l ON rs.loan_id = l.id
        WHERE DATE(rs.due_date) = DATE('now')
          AND l.status = 'active'
          AND rs.status != 'paid'
      ''');
      final dailyOutstandingBalance =
          (dailyOutstandingResult.first['total'] as num?)?.toDouble() ?? 0.0;

      // Installments due in the last 7 days that have not been fully paid.
      final weeklyOutstandingResult = await db.rawQuery('''
        SELECT COALESCE(SUM(rs.amount - rs.paid_amount), 0.0) AS total
        FROM repayment_schedule rs
        INNER JOIN loans l ON rs.loan_id = l.id
        WHERE DATE(rs.due_date) BETWEEN DATE('now', '-6 days') AND DATE('now')
          AND l.status = 'active'
          AND rs.status != 'paid'
      ''');
      final weeklyOutstandingBalance =
          (weeklyOutstandingResult.first['total'] as num?)?.toDouble() ?? 0.0;

      // ── Recent items ──────────────────────────────────────────────────────────
      final recentLoanRows = await db.query(
        AppConstants.tableLoans,
        orderBy: 'loan_date DESC',
        limit: AppConstants.recentItemsLimit,
      );
      final recentLoans =
          recentLoanRows.map(Loan.fromMap).toList(growable: false);

      final recentPaymentRows = await db.query(
        AppConstants.tablePayments,
        orderBy: 'payment_date DESC',
        limit: AppConstants.recentItemsLimit,
      );
      final recentPayments =
          recentPaymentRows.map(Payment.fromMap).toList(growable: false);

      // ── Savings ───────────────────────────────────────────────────────────────
      double totalSavingsBalance = 0.0;
      try {
        final savingsResult = await db.rawQuery(
            'SELECT COALESCE(SUM(balance), 0.0) AS total FROM savings_accounts');
        totalSavingsBalance =
            (savingsResult.first['total'] as num?)?.toDouble() ?? 0.0;
      } catch (_) {
        // Table may not exist on older installs before migration runs
      }

      return Result.success(DashboardData(
        totalCustomers: totalCustomers,
        activeLoans: activeLoans,
        dailyActiveLoans: dailyActiveLoans,
        weeklyActiveLoans: weeklyActiveLoans,
        totalDisbursed: totalDisbursed,
        totalCollected: totalCollected,
        dailyCollected: dailyCollected,
        weeklyCollected: weeklyCollected,
        outstandingBalance: outstandingBalance,
        dailyOutstandingBalance: dailyOutstandingBalance,
        weeklyOutstandingBalance: weeklyOutstandingBalance,
        recentLoans: recentLoans,
        recentPayments: recentPayments,
        totalSavingsBalance: totalSavingsBalance,
      ));
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load dashboard data.', cause: e));
    }
  }
}
