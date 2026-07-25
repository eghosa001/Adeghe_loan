import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_service.dart';
import 'models/payment_entity.dart';
import 'payment_logic.dart';

class PaymentRepository {
  PaymentRepository(this._dbService);
  final DatabaseService _dbService;

  Future<Database> get _db async => _dbService.database;

  Future<String> _generateReceiptNumber() async {
    final db = await _db;
    final countResult =
        await db.rawQuery('SELECT COUNT(*) as count FROM payments');
    final count = Sqflite.firstIntValue(countResult) ?? 0;
    final date = DateTime.now()
        .toIso8601String()
        .split('T')
        .first
        .replaceAll('-', '');
    return 'REC-$date-${(count + 1).toString().padLeft(5, '0')}';
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
    for (final schedule in pendingSchedules) {
      if (remaining <= 0) break;
      final scheduleId = schedule['id'] as String;
      final scheduleAmount = (schedule['amount'] as num).toDouble();
      final alreadyPaid = (schedule['paid_amount'] as num).toDouble();
      final stillOwed = scheduleAmount - alreadyPaid;

      if (remaining >= stillOwed) {
        await txn.update(
          'repayment_schedule',
          {'status': 'paid', 'paid_amount': scheduleAmount},
          where: 'id = ?',
          whereArgs: [scheduleId],
        );
        remaining -= stillOwed;
      } else {
        await txn.update(
          'repayment_schedule',
          {'status': 'partial', 'paid_amount': alreadyPaid + remaining},
          where: 'id = ?',
          whereArgs: [scheduleId],
        );
        remaining = 0;
      }
    }
  }

  /// Recalculates repayment_schedule statuses from scratch using the total
  /// amount actually applied to the loan for each completed payment.
  ///
  /// Overpayment payments split between loan principal and savings surplus.
  /// We must use only the loan-applied portion (payment.amount minus any
  /// associated overpayment savings credit), so that the schedule stays in
  /// sync with loans.outstanding_balance after reversals.
  Future<void> _recalculateScheduleFromPayments(
      Transaction txn, String loanId) async {
    // For each completed payment, the effective loan-applied amount is:
    //   payment.amount − COALESCE(savings overpayment credit for that payment, 0)
    // This correctly handles both normal payments and overpayments.
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

    for (final schedule in schedules) {
      final scheduleId = schedule['id'] as String;
      final scheduleAmount = (schedule['amount'] as num).toDouble();

      if (totalPaid >= scheduleAmount) {
        await txn.update(
          'repayment_schedule',
          {'status': 'paid', 'paid_amount': scheduleAmount},
          where: 'id = ?',
          whereArgs: [scheduleId],
        );
        totalPaid -= scheduleAmount;
      } else if (totalPaid > 0) {
        await txn.update(
          'repayment_schedule',
          {'status': 'partial', 'paid_amount': totalPaid},
          where: 'id = ?',
          whereArgs: [scheduleId],
        );
        totalPaid = 0;
      } else {
        await txn.update(
          'repayment_schedule',
          {'status': 'pending', 'paid_amount': 0},
          where: 'id = ?',
          whereArgs: [scheduleId],
        );
      }
    }
  }

  /// Credits a surplus amount to the customer's savings account and records
  /// the transaction. Called inside an active [txn].
  Future<void> _creditOverpaymentToSavings(
    Transaction txn,
    String customerId,
    String paymentId,
    double surplus,
  ) async {
    if (surplus <= 0) return;

    // Find or create savings account
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
      'note': 'Overpayment credit',
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
  }) async {
    final db = await _db;
    return await db.transaction((txn) async {
      final loanRows =
          await txn.query('loans', where: 'id = ?', whereArgs: [loanId]);
      if (loanRows.isEmpty) throw Exception('Loan not found');

      final loan = loanRows.first;
      final outstanding = (loan['outstanding_balance'] as num).toDouble();
      final paymentType =
          amount >= outstanding ? PaymentType.full : PaymentType.partial;

      // Compute how the payment splits between loan principal and savings surplus.
      final split = computePaymentSplit(
        paymentAmount: amount,
        outstandingBalance: outstanding,
      );
      final loanStatus = split.newLoanBalance == 0.0 ? 'completed' : 'active';

      await txn.update(
        'loans',
        {'outstanding_balance': split.newLoanBalance, 'status': loanStatus},
        where: 'id = ?',
        whereArgs: [loanId],
      );

      // Keep repayment_schedule in sync (only up to the outstanding amount).
      await _applyPaymentToSchedule(txn, loanId, split.appliedToLoan);

      final receiptNumber = await _generateReceiptNumber();
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
        type: paymentType,
        status: PaymentStatus.completed,
      );
      await txn.insert('payments', payment.toMap());

      // Credit any overpayment surplus to the customer's savings account
      if (split.overpaymentSurplus > 0) {
        await _creditOverpaymentToSavings(
            txn, customerId, payment.id, split.overpaymentSurplus);
      }

      return payment;
    });
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

      // Look up any overpayment savings credit that was created for this payment.
      final savingsCreditRows = await txn.query(
        'savings_transactions',
        where: 'reference_loan_payment_id = ? AND type = ?',
        whereArgs: [paymentId, 'overpayment'],
        limit: 1,
      );
      final overpaymentSurplus = savingsCreditRows.isEmpty
          ? 0.0
          : (savingsCreditRows.first['amount'] as num).toDouble();

      // Only the portion applied to the loan balance is restored to the loan.
      // The overpayment surplus went to savings, not to the loan, so we must
      // NOT add it back to outstanding_balance.
      final appliedToLoan = amount - overpaymentSurplus;

      await txn.update(
        'payments',
        {'status': PaymentStatus.reversed.name},
        where: 'id = ?',
        whereArgs: [paymentId],
      );

      await txn.rawUpdate(
        'UPDATE loans SET outstanding_balance = outstanding_balance + ?, '
        'status = ? WHERE id = ?',
        [appliedToLoan, 'active', loanId],
      );

      // Atomically unwind the overpayment savings credit.
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
          // Clamp to 0 so savings never goes negative (defensive guard).
          final amountToDeduct =
              overpaymentSurplus.clamp(0.0, currentBalance);
          final newBalance = currentBalance - amountToDeduct;

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
            'amount': amountToDeduct,
            'reference_loan_payment_id': paymentId,
            'note': 'Overpayment reversal',
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      }

      // Recalculate schedule from the remaining completed payments.
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
}
