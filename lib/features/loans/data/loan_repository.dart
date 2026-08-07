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
      // Best-effort derived rebuild: recomputes paid amounts/statuses from the
      // completed payments + overpayment surplus so the stored schedule is
      // exactly what another device would derive from the same source data.
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

  /// Rejects NaN/±Infinity/negative financial values at the repository
  /// boundary. A non-finite value written through `toMap()` would be stored
  /// as NULL (finding N9), and `Loan.fromMap`'s strict `(x as num)` casts
  /// would then crash every screen that reads the loan.
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
    // Duration cap at the repository boundary (defence-in-depth behind the
    // form): a huge duration would allocate an unbounded schedule via
    // List.generate (finding N2).
    if (loan.duration <= 0 || loan.duration > AppConstants.maxLoanDuration) {
      return ValidationFailure(
          'Loan duration must be between 1 and ${AppConstants.maxLoanDuration}.');
    }
    final custom = loan.customCollectionAmount;
    if (custom != null && (!custom.isFinite || custom <= 0)) {
      return const ValidationFailure(
          'Custom collection amount must be a valid amount.');
    }
    for (final installment in schedule) {
      if (!installment.amount.isFinite || installment.amount <= 0 ||
          !installment.paidAmount.isFinite || installment.paidAmount < 0) {
        return const ValidationFailure(
            'Repayment schedule contains an invalid amount.');
      }
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
    final validation = _validateLoanFinances(loan, schedule);
    if (validation != null) return Result.failure(validation);
    if (!paidSoFar.isFinite || paidSoFar < 0) {
      return Result.failure(const ValidationFailure(
          'Paid-so-far amount must be a valid non-negative number.'));
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
      // Best-effort derived rebuild so the stored schedule matches the derived
      // one on a fresh device (see saveLoanAndSchedule).
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
      // Cancelling a loan with collected money would zero the outstanding
      // balance while the completed payments still count toward "Total
      // Collected" (and the loan drops out of "Disbursed") — the dashboard
      // totals would stop reconciling. Refuse and ask for the payments to be
      // reversed first.
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

  Future<Result<int>> countAllLoans({
    String? query,
    String? statusFilter,
    String? loanType,
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
}

final loanRepositoryProvider = FutureProvider<LoanRepository>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  final scheduleService = await ref.watch(loanScheduleServiceProvider.future);
  return LoanRepository(dbService, scheduleService: scheduleService);
});
