import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/database/database_service.dart';
import '../../../core/error/failure.dart';
import '../../../core/utils/date_utils.dart';
import 'models/report_summary.dart';

class ReportRepository {
  ReportRepository(this._dbService);
  final DatabaseService _dbService;

  Future<Database> get _database async {
    return _dbService.database;
  }

  Future<Result<ReportSummary>> getReportSummary(
      DateTime startDate, DateTime endDate) async {
    try {
      final db = await _database;
      final startStr = AppDateUtils.formatForStorage(startDate);
      final endStr = AppDateUtils.formatForStorage(endDate);

      final disbursedResult = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0.0) AS total FROM loans '
        'WHERE loan_date BETWEEN ? AND ?',
        [startStr, endStr],
      );
      final totalDisbursed =
          (disbursedResult.first['total'] as num?)?.toDouble() ?? 0.0;

      final collectedResult = await db.rawQuery(
        "SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments "
        "WHERE payment_date BETWEEN ? AND ? AND status = 'completed'",
        [startStr, endStr],
      );
      final totalCollected =
          (collectedResult.first['total'] as num?)?.toDouble() ?? 0.0;

      final activeResult = await db.rawQuery(
        "SELECT COUNT(*) AS count FROM loans WHERE status = 'active'",
      );
      final activeLoans = (activeResult.first['count'] as int?) ?? 0;

      final completedResult = await db.rawQuery(
        "SELECT COUNT(*) AS count FROM loans WHERE status = 'completed'",
      );
      final completedLoans = (completedResult.first['count'] as int?) ?? 0;

      final defaultedResult = await db.rawQuery(
        "SELECT COUNT(*) AS count FROM loans WHERE status = 'defaulted'",
      );
      final defaultedLoans = (defaultedResult.first['count'] as int?) ?? 0;

      return Result.success(ReportSummary(
        totalDisbursed: totalDisbursed,
        totalCollected: totalCollected,
        netProfit: totalCollected - totalDisbursed,
        activeLoans: activeLoans,
        completedLoans: completedLoans,
        defaultedLoans: defaultedLoans,
      ));
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to generate report summary.', cause: e));
    }
  }
}
