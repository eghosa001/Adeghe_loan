import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/di/providers.dart';
import 'package:loantrack/features/holidays/data/models/holiday_entity.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/domain/loan_schedule_calculator.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Bumps whenever any repayment schedule is rebuilt. Providers that read the
/// derived `repayment_schedule` table watch this so a background rebuild
/// (e.g. after a cloud pull or a holiday change) refreshes open screens
/// without waiting for a manual invalidate.
class LoanScheduleVersionNotifier extends StateNotifier<int> {
  LoanScheduleVersionNotifier() : super(0);

  void bump() => state++;
}

/// Keeps the local `repayment_schedule` table in sync with its **source data**
/// (loans + holidays + completed payments).
///
/// The schedule is a derived cache, not a source of truth:
///  * `rebuildSchedule`/`rebuildAllSchedules` recompute every row for a loan
///    from scratch via [LoanScheduleCalculator] and replace them atomically,
///  * due dates and installment ids are deterministic, so the rebuilt table is
///    identical to the one another device computes from the same synced data,
///  * the rows are never replicated to the cloud (see `_tables` in
///    `cloud_sync_service.dart`), and
///  * each successful rebuild bumps [LoanScheduleVersionNotifier] so
///    schedule-reading providers re-read the fresh rows.
///
/// Callers: payment/loan repositories after a write that changes the schedule
/// (payment recorded/reversed, savings clear, loan saved/edited), the holiday
/// management screen after any holiday change, and the cloud sync service
/// after a pull.
class LoanScheduleService {
  LoanScheduleService(this._dbService, this._versionNotifier);

  final DatabaseService _dbService;
  final LoanScheduleVersionNotifier _versionNotifier;

  Future<Database> get _db async => _dbService.database;

  /// Rebuilds the derived schedule for [loanId] from its source data. No-op if
  /// the loan no longer exists (e.g. removed by a remote delete).
  Future<void> rebuildSchedule(String loanId) async {
    final db = await _db;
    final loanRows = await db.query(
      'loans',
      where: 'id = ?',
      whereArgs: [loanId],
      limit: 1,
    );
    if (loanRows.isEmpty) return;
    await _rebuild(db, Loan.fromMap(loanRows.first));
    _versionNotifier.bump();
  }

  /// Rebuilds the derived schedule for every loan in the database. Used after a
  /// holiday change or a cloud pull that may have touched any loan/payment.
  Future<void> rebuildAllSchedules() async {
    final db = await _db;
    final loanRows = await db.query('loans');
    for (final row in loanRows) {
      await _rebuild(db, Loan.fromMap(row));
    }
    _versionNotifier.bump();
  }

  Future<void> _rebuild(Database db, Loan loan) async {
    // Source 1: holidays (weekends are always excluded by the generator).
    final holidays = (await db.query('holidays'))
        .map((row) => Holiday.fromMap(row))
        .toList(growable: false);

    // Source 2: completed payments, with each payment's overpayment surplus
    // (the money rule: `SUM(amount) − COALESCE(st.amount, 0)` for
    // `type = 'overpayment'`). The surplus was credited to savings and never
    // touched the loan balance, so it must not count toward the schedule.
    final paymentRows = await db.rawQuery('''
      SELECT p.amount, COALESCE((
        SELECT st.amount FROM savings_transactions st
        WHERE st.reference_loan_payment_id = p.id AND st.type = 'overpayment'
        LIMIT 1
      ), 0.0) AS surplus
      FROM payments p
      WHERE p.loan_id = ? AND p.status = 'completed'
    ''', [loan.id]);
    var totalApplied = 0.0;
    for (final row in paymentRows) {
      final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
      final surplus = (row['surplus'] as num?)?.toDouble() ?? 0.0;
      totalApplied += amount - surplus;
    }

    final result = LoanScheduleCalculator.build(
      loan: loan,
      holidays: holidays,
      totalAppliedToLoan: totalApplied,
    );

    // Atomic replace: delete every row for the loan, then insert the derived
    // rows. The derived table is a cache, so a partial write is never visible.
    await db.transaction((txn) async {
      await txn.delete('repayment_schedule',
          where: 'loan_id = ?', whereArgs: [loan.id]);
      final batch = txn.batch();
      for (final installment in result.installments) {
        batch.insert('repayment_schedule', installment.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }
}

/// Watch this from any provider that reads the derived `repayment_schedule`
/// table so a rebuild (payment recorded, holiday changed, cloud pull) refreshes
/// it automatically.
final loanScheduleVersionProvider =
    StateNotifierProvider<LoanScheduleVersionNotifier, int>((ref) {
  return LoanScheduleVersionNotifier();
});

final loanScheduleServiceProvider = FutureProvider<LoanScheduleService>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return LoanScheduleService(
      dbService, ref.read(loanScheduleVersionProvider.notifier));
});
