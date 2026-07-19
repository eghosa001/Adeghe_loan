import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/di/providers.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/error/failure.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/data/models/repayment_installment_entity.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class LoanRepository {
  LoanRepository(this._dbService);
  final DatabaseService _dbService;

  Future<Database> get _database async {
    return _dbService.database;
  }

  Future<Result<void>> saveLoanAndSchedule(
      Loan loan, List<RepaymentInstallment> schedule) async {
    try {
      final db = await _database;
      await db.transaction((txn) async {
        await txn.insert(
          'loans',
          loan.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        for (final installment in schedule) {
          await txn.insert(
            'repayment_schedule',
            installment.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      return const Result.success(null);
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to save loan.', cause: e));
    }
  }

  Future<Result<Loan>> getLoanById(String loanId) async {
    try {
      final db = await _database;
      final maps = await db.query('loans', where: 'id = ?', whereArgs: [loanId]);
      if (maps.isEmpty) {
        return Result.failure(NotFoundFailure('Loan with ID $loanId not found.'));
      }
      return Result.success(Loan.fromMap(maps.first));
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to load loan.', cause: e));
    }
  }

  Future<Result<List<RepaymentInstallment>>> getScheduleForLoan(
      String loanId) async {
    try {
      final db = await _database;
      final maps = await db.query(
        'repayment_schedule',
        where: 'loan_id = ?',
        whereArgs: [loanId],
        orderBy: 'installment_number ASC',
      );
      final schedule =
          maps.map((map) => RepaymentInstallment.fromMap(map)).toList();
      return Result.success(schedule);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load repayment schedule.', cause: e));
    }
  }
}

final loanRepositoryProvider = FutureProvider<LoanRepository>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return LoanRepository(dbService);
});
