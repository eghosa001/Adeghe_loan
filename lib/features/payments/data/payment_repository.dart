import 'dart:math' show min, max;

import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_service.dart';
import 'models/payment_entity.dart';
import 'payment_logic.dart';

class PaymentRepository {
  PaymentRepository(this._dbService);
  final DatabaseService _dbService;

  Future<Database> get _db async => _dbService.database;

  Future<String> _generateReceiptNumber(DatabaseExecutor db) async {
    final date = DateTime.now()
        .toIso8601String()
        .split('T')
        .first
        .replaceAll('-', '');
    return 'REC-$date-${const Uuid().v4().substring(0, 8)}';
  }

  /// Applies [amount] to pending/partial repayment_schedule entries for [loanId]
  /// in due-date order, marking each as 'paid' or 'partial' accordingly.
  Future<void> _applyPaymentToSchedule(
      Transaction txn, String loanId, double amount) async {
    final pendingSchedules = await txn.rawQuery(
      "SELECT id, amount, paid_amount FROM repayment_schedule "
      "WHERE loan_id = ? AND status != 'paid' ORDER BY due_date ASC",
      [loanId],
    );

    double remaining = amount;
    final batch = txn.batch();
    for (final schedule in pendingSchedules) {
      if (remaining <= 0) break;
      final scheduleId = schedule['id'] as String;
      final scheduleAmount = (schedule['amount'] as num).toDouble();
      final alreadyPaid = (schedule['paid_amount'] as num).toDouble();
      final stillOwed = scheduleAmount - alreadyPaid;

      if (remaining >= stillOwed) {
        batch.update(
          'repayment_schedule',
          {'status': 'paid', 'paid_amount': scheduleAmount},
          where: 'id = ?',
          whereArgs: [scheduleId],
        );
        remaining -= stillOwed;
      } else {
        batch.update(
          'repayment_schedule',
          {'status': 'partial', 'paid_amount': alreadyPaid + remaining},
          where: 'id = ?',
          whereArgs: [scheduleId],
        );
        remaining = 0;
      }
    }
    await batch.commit(noResult: true);
  }

  /// Recalculates repayment_schedule statuses from scratch using the total
  /// amount actually applied to the loan for each completed payment.
  Future<void> _recalculateScheduleFromPayments(
      Transaction txn, String loanId) async {
    final paidResult = await txn.rawQuery(
      '''
      SELECT COALESCE(SUM(
        p.amount - COALESCE(st.amount, 0.0)
      ), 0.0) AS total
      FROM payments p
      LEFT JOIN savings_transactions st
        ON st.reference_loan_payment_id = p.id
       AND st.type = 'overpayment'
      WHERE p.loan_id = ? AND p.status = 'completed'
      ''',
      [loanId],
    );
    double totalPaid =
        (paidResult.first['total'] as num?)?.toDouble() ?? 0.0;

    final schedules = await txn.rawQuery(
      "SELECT id, amount FROM repayment_schedule "
      "WHERE loan_id = ? ORDER BY due_date ASC",
      [loanId],
    );

    final batch = txn.batch();
    for (final schedule in schedules) {
      final scheduleId = schedule['id'] as String;
      final scheduleAmount = (schedule['amount'] as num).toDouble();

      if (totalPaid >= scheduleAmount) {
        batch.update(
          'repayment_schedule',
          {'status': 'paid', 'paid_amount': scheduleAmount},
          where: 'id = ?',
          whereArgs: [scheduleId],
        );
        totalPaid -= scheduleAmount;
      } else if (totalPaid > 0) {
        batch.update(
          'repayment_schedule',
          {'status': 'partial', 'paid_amount': totalPaid},
          where: 'id = ?',
          whereArgs: [scheduleId],
        );
        totalPaid = 0;
      } else {
        batch.update(
          'repayment_schedule',
          {'status': 'pending', 'paid_amount': 0},
          where: 'id = ?',
          whereArgs: [scheduleId],
        );
      }
    }
    await batch.commit(noResult: true);
  }

  /// Credits a surplus amount to the customer's savings account and records
  /// the transaction. Called inside an active [txn].
  Future<void> _creditOverpaymentToSavings(
    Transaction txn,
    String customerId,
    String paymentId,
    double surplus,
    String loanId,
  ) async {
    if (surplus <= 0) return;

    var accountRows = await txn.query(
      'savings_accounts',
      columns: ['id', 'balance'],
      where: 'customer_id = ?',
      whereArgs: [customerId],
      limit: 1,
    );

    late String accountId;
    late double currentBalance;

    if (accountRows.isEmpty) {
      accountId = const Uuid().v4();
      currentBalance = 0;
      await txn.insert('savings_accounts', {
        'id': accountId,
        'customer_id': customerId,
        'balance': 0.0,
        'created_at': DateTime.now().toIso8601String(),
      });
    } else {
      accountId = accountRows.first['id'] as String;
      currentBalance =
          (accountRows.first['balance'] as num?)?.toDouble() ?? 0.0;
    }

    await txn.update(
      'savings_accounts',
      {'balance': currentBalance + surplus},
      where: 'id = ?',
      whereArgs: [accountId],
    );

    await txn.insert('savings_transactions', {
      'id': const Uuid().v4(),
      'savings_account_id': accountId,
      'type': 'overpayment',
      'amount': surplus,
      'reference_loan_payment_id': paymentId,
      'note': 'Automatic Savings Deposit — Loan: $loanId',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Payment> createPayment({
    required String loanId,
    required String customerId,
    required double amount,
    required PaymentMethod method,
    String? referenceNumber,
    required String collector,
    String? remarks,
    double? installmentDue,
    String? clientRequestId,
  }) async {
    // Guard at the repository boundary: NaN/±Infinity (e.g. "1e309") would
    // otherwise flow into the schedule math and be stored as NULL, crashing
    // every payment-list read via `Payment.fromMap (amount as num)`.
    if (!amount.isFinite || amount <= 0) {
      throw Exception('Invalid payment amount. Please enter a valid amount.');
    }
    final db = await _db;
    return await db.transaction((txn) async {
      // Idempotency: if the caller supplied a client-side request key that was
      // already recorded, return the existing payment instead of applying the
      // payment a second time. This stops a double-tap or a retry of the same
      // logical payment from creating a duplicate.
      if (clientRequestId != null && clientRequestId.trim().isNotEmpty) {
        final existing = await txn.query(
          'payments',
          where: 'client_request_id = ?',
          whereArgs: [clientRequestId.trim()],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          return Payment.fromMap(existing.first);
        }
      }

      final loanRows =
          await txn.query('loans', where: 'id = ?', whereArgs: [loanId]);
      if (loanRows.isEmpty) throw Exception('Loan not found');

      final loan = loanRows.first;
      // Money can only be applied to an open (active/defaulted) loan. Rejecting
      // completed/cancelled loans at the repository boundary (not just in the
      // UI) prevents a deep-link or direct call from recording a payment on a
      // closed loan, which would otherwise credit the whole amount to savings
      // with no loan offset.
      final loanStatusBefore = loan['status'] as String? ?? 'active';
      if (loanStatusBefore == 'completed' ||
          loanStatusBefore == 'cancelled') {
        throw Exception('Loan is already closed and cannot accept payments.');
      }

      final outstanding = (loan['outstanding_balance'] as num).toDouble();
      final priorLoanStatus = loan['status'] as String;

      // The loan receives the payment up to the current installment due;
      // any excess over the installment is credited to savings. When no
      // installment context is supplied the payment caps at the outstanding
      // balance so full settlements apply entirely to the loan.
      final split = computePaymentSplit(
        paymentAmount: amount,
        outstandingBalance: outstanding,
        installmentDue: installmentDue,
      );
      final loanStatus = split.newLoanBalance <= 0.005 ? 'completed' : 'active';

      // Optimistic compare-and-swap: only apply this payment if the outstanding
      // balance is still exactly what we computed against. If another write
      // already moved it (a concurrent/duplicate repayment), the update affects
      // 0 rows and we abort rather than double-apply against a stale balance.
      final updated = await txn.rawUpdate(
        'UPDATE loans SET outstanding_balance = ?, status = ? '
        'WHERE id = ? AND outstanding_balance = ?',
        [split.newLoanBalance, loanStatus, loanId, outstanding],
      );
      if (updated != 1) {
        throw Exception(
            'Loan balance changed since this payment was prepared; '
            'please retry.');
      }

      await _applyPaymentToSchedule(txn, loanId, split.appliedToLoan);

      final receiptNumber = await _generateReceiptNumber(txn);
      final payment = Payment(
        id: const Uuid().v4(),
        loanId: loanId,
        customerId: customerId,
        amount: amount,
        method: method,
        referenceNumber: referenceNumber,
        receiptNumber: receiptNumber,
        paymentDate: DateTime.now(),
        collector: collector,
        type: split.overpaymentSurplus > 0 ? PaymentType.overpayment :
              (split.newLoanBalance <= 0.005 ? PaymentType.full : PaymentType.partial),
        status: PaymentStatus.completed,
        remarks: remarks,
        priorLoanStatus: priorLoanStatus,
        clientRequestId: clientRequestId,
      );
      await txn.insert('payments', payment.toMap());

      if (split.overpaymentSurplus > 0) {
        await _creditOverpaymentToSavings(
            txn, customerId, payment.id, split.overpaymentSurplus, loanId);
      }

      return payment;
    });
  }

  Future<void> updatePaymentNotes(String paymentId, String? remarks) async {
    final db = await _db;
    await db.update(
      'payments',
      {'remarks': remarks},
      where: 'id = ?',
      whereArgs: [paymentId],
    );
  }

  Future<void> reversePayment(String paymentId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn
          .query('payments', where: 'id = ?', whereArgs: [paymentId]);
      if (rows.isEmpty) throw Exception('Payment not found.');

      final payment = rows.first;
      final amount = (payment['amount'] as num).toDouble();
      final loanId = payment['loan_id'] as String;
      final customerId = payment['customer_id'] as String;
      final status = payment['status'] as String;

      if (status == PaymentStatus.reversed.name) {
        throw Exception('Payment already reversed.');
      }

      final savingsCreditRows = await txn.query(
        'savings_transactions',
        where: 'reference_loan_payment_id = ? AND type = ?',
        whereArgs: [paymentId, 'overpayment'],
        limit: 1,
      );
      final overpaymentSurplus = savingsCreditRows.isEmpty
          ? 0.0
          : (savingsCreditRows.first['amount'] as num).toDouble();

      // A loan cleared with savings withdrew from the savings account; the
      // reversal must refund that withdrawal back into savings.
      final savingsWithdrawalRows = await txn.query(
        'savings_transactions',
        where: 'reference_loan_payment_id = ? AND type = ?',
        whereArgs: [paymentId, 'withdrawal'],
        limit: 1,
      );
      final savingsToRefund = savingsWithdrawalRows.isEmpty
          ? 0.0
          : (savingsWithdrawalRows.first['amount'] as num).toDouble();

      final appliedToLoan = max(0.0, amount - overpaymentSurplus);

      await txn.update(
        'payments',
        {'status': PaymentStatus.reversed.name},
        where: 'id = ?',
        whereArgs: [paymentId],
      );

      final loanRows = await txn.query('loans', columns: ['status'], where: 'id = ?', whereArgs: [loanId]);
      final storedPriorStatus = payment['prior_loan_status'] as String?;
      // Restore the exact pre-payment status (e.g. 'defaulted') recorded when
      // the payment was created; fall back to 'active' if not present.
      final previousStatus = storedPriorStatus ?? (loanRows.isNotEmpty ? loanRows.first['status'] as String : 'active');
      await txn.rawUpdate(
        'UPDATE loans SET outstanding_balance = outstanding_balance + ?, '
        'status = ? WHERE id = ?',
        [appliedToLoan, previousStatus, loanId],
      );

      if (overpaymentSurplus > 0) {
        final accountRows = await txn.query(
          'savings_accounts',
          columns: ['id', 'balance'],
          where: 'customer_id = ?',
          whereArgs: [customerId],
          limit: 1,
        );
        if (accountRows.isNotEmpty) {
          final accountId = accountRows.first['id'] as String;
          final currentBalance =
              (accountRows.first['balance'] as num?)?.toDouble() ?? 0.0;
          final toDeduct = min(overpaymentSurplus, currentBalance);
          final newBalance = currentBalance - toDeduct;

          await txn.update(
            'savings_accounts',
            {'balance': newBalance},
            where: 'id = ?',
            whereArgs: [accountId],
          );

          await txn.insert('savings_transactions', {
            'id': const Uuid().v4(),
            'savings_account_id': accountId,
            'type': 'withdrawal',
            'amount': toDeduct,
            'reference_loan_payment_id': paymentId,
            'note': 'Overpayment reversal — Loan: $loanId',
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      }

      if (savingsToRefund > 0) {
        final accountRows = await txn.query(
          'savings_accounts',
          columns: ['id', 'balance'],
          where: 'customer_id = ?',
          whereArgs: [customerId],
          limit: 1,
        );
        if (accountRows.isNotEmpty) {
          final accountId = accountRows.first['id'] as String;
          final currentBalance =
              (accountRows.first['balance'] as num?)?.toDouble() ?? 0.0;
          final newBalance = currentBalance + savingsToRefund;

          await txn.update(
            'savings_accounts',
            {'balance': newBalance},
            where: 'id = ?',
            whereArgs: [accountId],
          );

          await txn.insert('savings_transactions', {
            'id': const Uuid().v4(),
            'savings_account_id': accountId,
            'type': 'deposit',
            'amount': savingsToRefund,
            'reference_loan_payment_id': paymentId,
            'note': 'Savings-cleared payment reversal — Loan: $loanId',
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      }

      await _recalculateScheduleFromPayments(txn, loanId);
    });
  }

  Future<List<Payment>> getPaymentsForLoan(String loanId) async {
    final db = await _db;
    final rows = await db.query(
      'payments',
      where: 'loan_id = ?',
      whereArgs: [loanId],
      orderBy: 'payment_date DESC',
    );
    return rows.map((e) => Payment.fromMap(e)).toList(growable: false);
  }

  /// Clears an active loan using the customer's savings balance.
  Future<void> clearLoanWithSavings({
    required String loanId,
    required String customerId,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final loanRows =
          await txn.query('loans', where: 'id = ?', whereArgs: [loanId]);
      if (loanRows.isEmpty) throw Exception('Loan not found.');
      final loan = loanRows.first;
      final outstanding = (loan['outstanding_balance'] as num).toDouble();
      if (!outstanding.isFinite || outstanding <= 0) {
        throw Exception('Loan has no valid outstanding balance.');
      }
      final status = loan['status'] as String;
      if (status != 'active') throw Exception('Loan is not active.');

      final accountRows = await txn.query(
        'savings_accounts',
        columns: ['id', 'balance'],
        where: 'customer_id = ?',
        whereArgs: [customerId],
        limit: 1,
      );
      if (accountRows.isEmpty) {
        throw Exception('Customer has no savings account.');
      }
      final accountId = accountRows.first['id'] as String;
      final savingsBalance =
          (accountRows.first['balance'] as num?)?.toDouble() ?? 0.0;
      if (!savingsBalance.isFinite || savingsBalance < 0) {
        throw Exception('Customer savings balance is invalid.');
      }
      if (savingsBalance < outstanding) {
        throw Exception(
            'Insufficient savings. Available: ${savingsBalance.toStringAsFixed(2)}, '
            'Needed: ${outstanding.toStringAsFixed(2)}');
      }

      await txn.update(
        'savings_accounts',
        {'balance': savingsBalance - outstanding},
        where: 'id = ?',
        whereArgs: [accountId],
      );

      final receiptNumber = await _generateReceiptNumber(txn);
      final payment = Payment(
        id: const Uuid().v4(),
        loanId: loanId,
        customerId: customerId,
        amount: outstanding,
        method: PaymentMethod.savings,
        referenceNumber: null,
        receiptNumber: receiptNumber,
        paymentDate: DateTime.now(),
        collector: 'System — Savings',
        type: PaymentType.full,
        status: PaymentStatus.completed,
        // The loan was active (checked above); record that so a reversal can
        // restore 'active' instead of leaving it stuck on 'completed' with a
        // positive outstanding balance.
        priorLoanStatus: 'active',
      );
      await txn.insert('payments', payment.toMap());

      // Link the savings withdrawal to the payment so reversing the payment
      // can refund the exact amount back into savings.
      await txn.insert('savings_transactions', {
        'id': const Uuid().v4(),
        'savings_account_id': accountId,
        'type': 'withdrawal',
        'amount': outstanding,
        'reference_loan_payment_id': payment.id,
        'note': 'Loan cleared with savings — Loan: $loanId',
        'created_at': DateTime.now().toIso8601String(),
      });

      await txn.rawUpdate(
        "UPDATE repayment_schedule SET status = 'paid', paid_amount = amount "
        "WHERE loan_id = ? AND status != 'paid'",
        [loanId],
      );

      await txn.update(
        'loans',
        {'outstanding_balance': 0.0, 'status': 'completed'},
        where: 'id = ?',
        whereArgs: [loanId],
      );
    });
  }
}
