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

      final customerCountResult = await db
          .rawQuery('SELECT COUNT(*) AS count FROM customers');
      final totalCustomers =
          (customerCountResult.first['count'] as int?) ?? 0;

      final activeLoansResult = await db.rawQuery(
          "SELECT COUNT(*) AS count FROM loans WHERE status = 'active'");
      final activeLoans =
          (activeLoansResult.first['count'] as int?) ?? 0;

      final disbursedResult = await db
          .rawQuery('SELECT COALESCE(SUM(amount), 0.0) AS total FROM loans');
      final totalDisbursed =
          (disbursedResult.first['total'] as num?)?.toDouble() ?? 0.0;

      final collectedResult = await db.rawQuery(
          "SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments WHERE status = 'completed'");
      final totalCollected =
          (collectedResult.first['total'] as num?)?.toDouble() ?? 0.0;

      final outstandingResult = await db.rawQuery(
          "SELECT COALESCE(SUM(outstanding_balance), 0.0) AS total FROM loans WHERE status = 'active'");
      final outstandingBalance =
          (outstandingResult.first['total'] as num?)?.toDouble() ?? 0.0;

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

      return Result.success(DashboardData(
        totalCustomers: totalCustomers,
        activeLoans: activeLoans,
        totalDisbursed: totalDisbursed,
        totalCollected: totalCollected,
        outstandingBalance: outstandingBalance,
        recentLoans: recentLoans,
        recentPayments: recentPayments,
      ));
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load dashboard data.', cause: e));
    }
  }
}
