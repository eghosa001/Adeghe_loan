import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/di/providers.dart';
import 'package:loantrack/features/holidays/data/models/holiday_entity.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/domain/loan_schedule_calculator.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class LoanScheduleVersionNotifier extends StateNotifier<int> {
  LoanScheduleVersionNotifier() : super(0);
  void bump() => state++;
}

class LoanScheduleService {
  LoanScheduleService(this._dbService, this._versionNotifier);
  final DatabaseService _dbService;
  final LoanScheduleVersionNotifier _versionNotifier;
  Future<Database> get _db async => _dbService.database;

  Future<void> rebuildSchedule(String loanId) async {
    final db = await _db;
    final loanRows = await db.query('loans', where: 'id = ?', whereArgs: [loanId], limit: 1);
    if (loanRows.isEmpty) return;
    await _rebuild(db, Loan.fromMap(loanRows.first));
    _versionNotifier.bump();
  }

  Future<void> rebuildAllSchedules() async {
    final db = await _db;
    final loanRows = await db.query('loans');
    if (loanRows.isEmpty) { _versionNotifier.bump(); return; }
    final holidays = (await db.query('holidays'))
        .map((row) => Holiday.fromMap(row)).toList(growable: false);
    final paymentRows = await db.rawQuery('''
      SELECT p.loan_id,
             COALESCE(SUM(p.amount - COALESCE((SELECT st.amount
               FROM savings_transactions st
               WHERE st.reference_loan_payment_id = p.id
                 AND st.type = 'overpayment' LIMIT 1), 0.0)), 0.0) AS applied
      FROM payments p WHERE p.status = 'completed' GROUP BY p.loan_id
    ''');
    final appliedByLoan = <String, double>{};
    for (final row in paymentRows) {
      final id = row['loan_id'] as String?;
      if (id != null) appliedByLoan[id] = (row['applied'] as num?)?.toDouble() ?? 0.0;
    }
    for (final row in loanRows) {
      await _rebuild(db, Loan.fromMap(row), holidays: holidays,
          totalAppliedToLoan: appliedByLoan[row['id']] ?? 0.0);
    }
    await _rebuildSavingsBalances(db);
    _versionNotifier.bump();
  }

  Future<void> _rebuild(Database db, Loan loan, {
    List<Holiday>? holidays,
    double? totalAppliedToLoan,
  }) async {
    final effectiveHolidays = holidays ?? (await db.query('holidays'))
        .map((row) => Holiday.fromMap(row)).toList(growable: false);
    final effectiveApplied = totalAppliedToLoan ?? await _loadApplied(db, loan.id);
    if (!effectiveApplied.isFinite || effectiveApplied < 0) {
      throw StateError('Cannot rebuild loan ${loan.id}: applied payment total is invalid.');
    }

    final remaining = (loan.totalRepayment - effectiveApplied)
        .clamp(0.0, loan.totalRepayment).toDouble();

    // Loan balance/status and its derived repayment schedule are one logical
    // state. Updating the loan first and the schedule in a separate transaction
    // could leave them disagreeing after an interruption. Commit both together.
    await db.transaction((txn) async {
      if (loan.status != LoanStatus.cancelled && loan.status != LoanStatus.pending) {
        await txn.update('loans', {
          'outstanding_balance': remaining,
          'status': remaining <= 0.005 ? LoanStatus.completed.name : LoanStatus.active.name,
        }, where: 'id = ?', whereArgs: [loan.id]);
      }

      final result = LoanScheduleCalculator.build(
        loan: loan, holidays: effectiveHolidays, totalAppliedToLoan: effectiveApplied,
      );
      await txn.delete('repayment_schedule', where: 'loan_id = ?', whereArgs: [loan.id]);
      final batch = txn.batch();
      for (final installment in result.installments) {
        batch.insert('repayment_schedule', installment.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<double> _loadApplied(Database db, String loanId) async {
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(p.amount - COALESCE((SELECT st.amount
        FROM savings_transactions st
        WHERE st.reference_loan_payment_id = p.id
          AND st.type = 'overpayment' LIMIT 1), 0.0)), 0.0) AS applied
      FROM payments p WHERE p.loan_id = ? AND p.status = 'completed'
    ''', [loanId]);
    return (rows.first['applied'] as num?)?.toDouble() ?? 0.0;
  }

  Future<void> _rebuildSavingsBalances(Database db) async {
    final rows = await db.rawQuery('''
      SELECT sa.id, COALESCE(SUM(CASE
        WHEN st.type IN ('deposit', 'overpayment') THEN st.amount
        WHEN st.type = 'withdrawal' THEN -st.amount
        ELSE 0 END), 0.0) AS balance
      FROM savings_accounts sa
      LEFT JOIN savings_transactions st ON st.savings_account_id = sa.id
      GROUP BY sa.id
    ''');
    for (final row in rows) {
      final id = row['id'] as String;
      final balance = ((row['balance'] as num?)?.toDouble() ?? 0.0)
          .clamp(0.0, double.infinity).toDouble();
      await db.update('savings_accounts', {'balance': balance}, where: 'id = ?', whereArgs: [id]);
    }
  }
}

final loanScheduleVersionProvider =
    StateNotifierProvider<LoanScheduleVersionNotifier, int>((ref) => LoanScheduleVersionNotifier());

final loanScheduleServiceProvider = FutureProvider<LoanScheduleService>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return LoanScheduleService(dbService, ref.read(loanScheduleVersionProvider.notifier));
});
