import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/di/providers.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/error/failure.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:loantrack/features/holidays/data/models/holiday_entity.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/data/models/repayment_installment_entity.dart';
import 'package:loantrack/features/loans/domain/schedule_generator.dart';
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

        final batch = txn.batch();
        for (final installment in schedule) {
          batch.insert(
            'repayment_schedule',
            installment.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
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

  Future<Result<List<Loan>>> getActiveLoansForCustomer(String customerId) async {
    try {
      final db = await _database;
      final maps = await db.query(
        'loans',
        where: "customer_id = ? AND status = 'active'",
        whereArgs: [customerId],
        orderBy: 'loan_date DESC',
      );
      final loans = maps.map((map) => Loan.fromMap(map)).toList();
      return Result.success(loans);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load customer loans.', cause: e));
    }
  }

  /// All loans for a customer regardless of status (statements should include
  /// completed/cancelled history, not just active loans).
  Future<Result<List<Loan>>> getLoansForCustomer(String customerId) async {
    try {
      final db = await _database;
      final maps = await db.query(
        'loans',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'loan_date DESC',
      );
      final loans = maps.map((map) => Loan.fromMap(map)).toList();
      return Result.success(loans);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to load customer loans.', cause: e));
    }
  }

  /// Updates a loan and fully replaces its repayment schedule in one
  /// transaction. [paidSoFar] (the total the customer has already paid toward
  /// the previous total) is applied to the fresh schedule so already-settled
  /// installments stay marked paid/partial.
  Future<Result<void>> updateLoanAndSchedule(
    Loan loan,
    List<RepaymentInstallment> schedule, {
    double paidSoFar = 0.0,
  }) async {
    try {
      final db = await _database;
      await db.transaction((txn) async {
        await txn.update(
            'loans', loan.toMap(), where: 'id = ?', whereArgs: [loan.id]);
        await txn.delete('repayment_schedule',
            where: 'loan_id = ?', whereArgs: [loan.id]);

        var remaining = paidSoFar;
        final batch = txn.batch();
        for (final installment in schedule) {
          final map = installment.toMap();
          if (remaining >= installment.amount - 0.005) {
            map['status'] = 'paid';
            map['paid_amount'] = installment.amount;
            remaining -= installment.amount;
          } else if (remaining > 0.005) {
            map['status'] = 'partial';
            map['paid_amount'] = remaining;
            remaining = 0;
          } else {
            map['status'] = 'pending';
            map['paid_amount'] = 0.0;
          }
          batch.insert('repayment_schedule', map,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      });
      return const Result.success(null);
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to update loan.', cause: e));
    }
  }

  Future<Result<void>> cancelLoan(String loanId) async {
    try {
      final db = await _database;
      await db.update('loans', {'status': 'cancelled', 'outstanding_balance': 0},
          where: 'id = ?', whereArgs: [loanId]);
      return const Result.success(null);
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to cancel loan.', cause: e));
    }
  }

  Future<Result<List<Loan>>> getAllLoans({
    String? query,
    String? statusFilter,
    int? limit,
    int offset = 0,
  }) async {
    try {
      final db = await _database;
      final conditions = <String>['1=1'];
      final args = <Object?>[];

      if (query != null && query.isNotEmpty) {
        conditions.add('(l.id LIKE ? OR c.full_name LIKE ? OR c.phone LIKE ?)');
        args.addAll(List.filled(3, '%$query%'));
      }
      if (statusFilter != null && statusFilter.isNotEmpty) {
        conditions.add('l.status = ?');
        args.add(statusFilter);
      }

      final where = conditions.join(' AND ');
      final rows = await db.rawQuery('''
        SELECT l.*, c.full_name AS customer_name
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        WHERE $where
        ORDER BY l.loan_date DESC
        ${limit != null ? 'LIMIT ? OFFSET ?' : ''}
      ''', limit != null ? [...args, limit, offset] : args);

      final loans = rows.map((row) {
        final map = Map<String, dynamic>.from(row);
        return Loan.fromMap(map);
      }).toList();
      return Result.success(loans);
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to load loans.', cause: e));
    }
  }

  Future<Result<int>> countAllLoans({String? query, String? statusFilter}) async {
    try {
      final db = await _database;
      final conditions = <String>['1=1'];
      final args = <Object?>[];

      if (query != null && query.isNotEmpty) {
        conditions.add('(l.id LIKE ? OR c.full_name LIKE ? OR c.phone LIKE ?)');
        args.addAll(List.filled(3, '%$query%'));
      }
      if (statusFilter != null && statusFilter.isNotEmpty) {
        conditions.add('l.status = ?');
        args.add(statusFilter);
      }

      final where = conditions.join(' AND ');
      final result = await db.rawQuery('''
        SELECT COUNT(*) AS count FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        WHERE $where
      ''', args);
      return Result.success((result.first['count'] as int?) ?? 0);
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to count loans.', cause: e));
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

  /// Regenerates the repayment schedule of every active loan that has no
  /// recorded payments, so holiday changes are reflected in upcoming
  /// installments. Loans with payments are intentionally left untouched to
  /// avoid breaking the paid-installment linkage.
  Future<Result<int>> regenSchedulesForActiveLoans(
      List<Holiday> holidays) async {
    try {
      final db = await _database;
      final rows =
          await db.query('loans', where: "status = 'active'", whereArgs: []);
      var regenCount = 0;

      for (final row in rows) {
        final loan = Loan.fromMap(row);
        final paid = await db.query('payments',
            columns: ['id'],
            where: 'loan_id = ? AND status = ?',
            whereArgs: [loan.id, 'completed']);
        if (paid.isNotEmpty) continue;

        final customAmount = loan.customCollectionAmount;
        final isCustom = customAmount != null && customAmount > 0;
        final totalRepayment = isCustom
            ? CurrencyUtils.roundToCents(customAmount * loan.duration)
            : loan.totalRepayment;
        final amounts =
            CurrencyUtils.splitEvenly(totalRepayment, loan.duration);
        final schedule = ScheduleGenerator.generate(
          loanId: loan.id,
          loanType: loan.loanType,
          startDate: loan.repaymentStartDate,
          amounts: amounts,
          holidays: holidays,
        );
        if (schedule.isEmpty) continue;

        await db.transaction((txn) async {
          await txn.delete('repayment_schedule',
              where: 'loan_id = ?', whereArgs: [loan.id]);
          final batch = txn.batch();
          for (final installment in schedule) {
            batch.insert('repayment_schedule', installment.toMap(),
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
          await batch.commit(noResult: true);
        });
        regenCount++;
      }
      return Result.success(regenCount);
    } on DatabaseException catch (e) {
      return Result.failure(
          DatabaseFailure('Failed to regenerate schedules.', cause: e));
    }
  }
}

final loanRepositoryProvider = FutureProvider<LoanRepository>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return LoanRepository(dbService);
});
