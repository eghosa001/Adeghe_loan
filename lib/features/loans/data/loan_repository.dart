import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/constants/app_constants.dart';
import 'package:loantrack/core/di/providers.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/error/failure.dart';
import 'package:loantrack/features/customers/data/models/customer_entity.dart';
import 'package:loantrack/features/loans/data/loan_schedule_service.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/data/models/repayment_installment_entity.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class LoanRepository {
  LoanRepository(this._dbService, {this._scheduleService});
  final DatabaseService _dbService;
  final LoanScheduleService? _scheduleService;

  Future<Database> get _database async {
    return _dbService.database;
  }

  Future<Result<void>> saveLoanAndSchedule(
      Loan loan, List<RepaymentInstallment> schedule) async {
    final validation = _validateLoanFinances(loan, schedule);
    if (validation != null) return Result.failure(validation);
    try {
      final db = await _database;
      final result = await db.transaction((txn) async {
        // A loan must never be created for an archived (soft-deleted) customer.
        final customerRows = await txn.query(
          'customers',
          columns: const ['id', 'status'],
          where: 'id = ?',
          whereArgs: [loan.customerId],
          limit: 1,
        );
        if (customerRows.isEmpty ||
            customerRows.first['status'] == CustomerStatus.archived.value) {
          return const Result<void>.failure(ValidationFailure(
              'Cannot create a loan for an archived customer.'));
        }
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
        return const Result.success(null);
      });
      try {
        await _scheduleService?.rebuildSchedule(loan.id);
      } catch (_) {
        // The schedule written inside the transaction is already valid; the
        // rebuild is a normalization pass.
      }
      return result;
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to save loan.', cause: e));
    }
  }

  /// Validates the complete financial shape before it is persisted. In
  /// particular, a caller must not be able to save a schedule whose total or
  /// installment count disagrees with the loan terms.
  Failure? _validateLoanFinances(
      Loan loan, List<RepaymentInstallment> schedule) {
    final nonNegative = <double>[
      loan.amount,
      loan.interestRate,
      loan.insuranceFee,
      loan.commission,
      loan.processingFee,
      loan.administrativeFee,
      loan.otherCharges,
      loan.outstandingBalance,
    ];
    for (final value in nonNegative) {
      if (!value.isFinite || value < 0) {
        return const ValidationFailure(
            'Loan contains an invalid (non-finite or negative) amount.');
      }
    }
    if (!loan.totalRepayment.isFinite || loan.totalRepayment <= 0) {
      return const ValidationFailure(
          'Loan total repayment must be a valid amount.');
    }
    if (!loan.installmentAmount.isFinite || loan.installmentAmount < 0) {
      return const ValidationFailure('Loan installment amount is invalid.');
    }
    if (loan.duration <= 0 || loan.duration > AppConstants.maxLoanDuration) {
      return ValidationFailure(
          'Loan duration must be between 1 and ${AppConstants.maxLoanDuration}.');
    }
    if (schedule.length != loan.duration) {
      return const ValidationFailure(
          'Repayment schedule does not match the loan duration.');
    }

    final custom = loan.customCollectionAmount;
    if (custom != null && (!custom.isFinite || custom <= 0)) {
      return const ValidationFailure(
          'Custom collection amount must be a valid amount.');
    }

    var scheduleTotal = 0.0;
    for (final installment in schedule) {
      if (!installment.amount.isFinite || installment.amount <= 0 ||
          !installment.paidAmount.isFinite || installment.paidAmount < 0 ||
          installment.paidAmount > installment.amount + 0.005) {
        return const ValidationFailure(
            'Repayment schedule contains an invalid amount.');
      }
      scheduleTotal += installment.amount;
    }
    if (!scheduleTotal.isFinite ||
        (scheduleTotal - loan.totalRepayment).abs() > 0.005) {
      return const ValidationFailure(
          'Repayment schedule total does not match the loan total repayment.');
    }
    return null;
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

  Future<Result<void>> updateLoanAndSchedule(
    Loan loan,
    List<RepaymentInstallment> schedule, {
    double paidSoFar = 0.0,
  }) async {
    final validation = _validateLoanFinances(loan, schedule);
    if (validation != null) return Result.failure(validation);
    if (!paidSoFar.isFinite || paidSoFar < 0) {
      return Result.failure(const ValidationFailure(
          'Paid-so-far amount must be a valid non-negative number.'));
    }
    if (paidSoFar > loan.totalRepayment + 0.005) {
      return Result.failure(const ValidationFailure(
          'Paid-so-far amount cannot exceed the new loan total repayment.'));
    }

    // The outstanding balance is derived from the immutable payment history
    // supplied by the caller, not trusted from a separately editable field.
    final expectedOutstanding =
        (loan.totalRepayment - paidSoFar).clamp(0.0, loan.totalRepayment).toDouble();
    if ((loan.outstandingBalance - expectedOutstanding).abs() > 0.005) {
      return Result.failure(const ValidationFailure(
          'Loan outstanding balance does not match the paid-so-far amount.'));
    }

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
      try {
        await _scheduleService?.rebuildSchedule(loan.id);
      } catch (_) {
        // The schedule written inside the transaction is already valid.
      }
      return const Result.success(null);
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to update loan.', cause: e));
    }
  }

  Future<Result<void>> cancelLoan(String loanId) async {
    try {
      final db = await _database;
      final rows = await db
          .query('loans', columns: ['status'], where: 'id = ?', whereArgs: [loanId]);
      if (rows.isEmpty) {
        return Result.failure(NotFoundFailure('Loan not found.'));
      }
      final status = rows.first['status'] as String? ?? 'active';
      if (status == 'completed' || status == 'cancelled') {
        return Result.failure(
            ValidationFailure('Loan is already closed.'));
      }
      final paid = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM payments '
        "WHERE loan_id = ? AND status = 'completed'",
        [loanId],
      );
      final paidCount = (paid.first['count'] as int?) ?? 0;
      if (paidCount > 0) {
        return Result.failure(ValidationFailure(
            'Cannot cancel a loan that has completed payments. '
            'Reverse the payments first, then cancel the loan.'));
      }
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
    String? loanType,
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
      if (loanType != null && loanType.isNotEmpty) {
        conditions.add('l.loan_type = ?');
        args.add(loanType);
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
  final scheduleService = await ref.watch(loanScheduleServiceProvider.future);
  return LoanRepository(dbService, scheduleService: scheduleService);
});