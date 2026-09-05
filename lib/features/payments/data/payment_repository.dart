import 'dart:math' show min, max;

import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_service.dart';
import '../../../core/utils/currency_utils.dart';
import '../../loans/data/loan_schedule_service.dart';
import 'models/payment_entity.dart';
import 'payment_logic.dart';

class PaymentRepository {
  PaymentRepository(this._dbService, {this._scheduleService});
  final DatabaseService _dbService;
  final LoanScheduleService? _scheduleService;

  Future<Database> get _db async => _dbService.database;

  Future<String> _generateReceiptNumber(DatabaseExecutor db) async {
    final date = DateTime.now().toIso8601String().split('T').first.replaceAll('-', '');
    return 'REC-$date-${const Uuid().v4().substring(0, 8)}';
  }

  Future<void> _applyPaymentToSchedule(Transaction txn, String loanId, double amount) async {
    final pendingSchedules = await txn.rawQuery("SELECT id, amount, paid_amount FROM repayment_schedule WHERE loan_id = ? AND status != 'paid' ORDER BY due_date ASC", [loanId]);
    double remaining = amount;
    final batch = txn.batch();
    for (final schedule in pendingSchedules) {
      if (remaining <= 0) break;
      final scheduleId = schedule['id'] as String;
      final scheduleAmount = (schedule['amount'] as num).toDouble();
      final alreadyPaid = (schedule['paid_amount'] as num).toDouble();
      final stillOwed = scheduleAmount - alreadyPaid;
      if (stillOwed <= 0) continue;
      if (remaining >= stillOwed) {
        batch.update('repayment_schedule', {'status': 'paid', 'paid_amount': scheduleAmount}, where: 'id = ?', whereArgs: [scheduleId]);
        remaining -= stillOwed;
      } else {
        batch.update('repayment_schedule', {'status': 'partial', 'paid_amount': alreadyPaid + remaining}, where: 'id = ?', whereArgs: [scheduleId]);
        remaining = 0;
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> _recalculateScheduleFromPayments(Transaction txn, String loanId) async {
    final paidResult = await txn.rawQuery('''
      SELECT COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0.0) AS total
      FROM payments p
      LEFT JOIN savings_transactions st
        ON st.reference_loan_payment_id = p.id AND st.type = 'overpayment'
      WHERE p.loan_id = ? AND p.status = 'completed'
    ''', [loanId]);
    double totalPaid = (paidResult.first['total'] as num?)?.toDouble() ?? 0.0;
    final schedules = await txn.rawQuery("SELECT id, amount FROM repayment_schedule WHERE loan_id = ? ORDER BY due_date ASC", [loanId]);
    final batch = txn.batch();
    for (final schedule in schedules) {
      final scheduleId = schedule['id'] as String;
      final scheduleAmount = (schedule['amount'] as num).toDouble();
      if (totalPaid >= scheduleAmount) {
        batch.update('repayment_schedule', {'status': 'paid', 'paid_amount': scheduleAmount}, where: 'id = ?', whereArgs: [scheduleId]);
        totalPaid -= scheduleAmount;
      } else if (totalPaid > 0) {
        batch.update('repayment_schedule', {'status': 'partial', 'paid_amount': totalPaid}, where: 'id = ?', whereArgs: [scheduleId]);
        totalPaid = 0;
      } else {
        batch.update('repayment_schedule', {'status': 'pending', 'paid_amount': 0}, where: 'id = ?', whereArgs: [scheduleId]);
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> _creditOverpaymentToSavings(Transaction txn, String customerId, String paymentId, double surplus, String loanId) async {
    if (surplus <= 0) return;
    final accountRows = await txn.query('savings_accounts', columns: ['id', 'balance'], where: 'customer_id = ?', whereArgs: [customerId], limit: 1);
    late String accountId;
    late double currentBalance;
    if (accountRows.isEmpty) {
      accountId = const Uuid().v4();
      currentBalance = 0;
      await txn.insert('savings_accounts', {'id': accountId, 'customer_id': customerId, 'balance': 0.0, 'created_at': DateTime.now().toIso8601String()});
    } else {
      accountId = accountRows.first['id'] as String;
      currentBalance = (accountRows.first['balance'] as num?)?.toDouble() ?? 0.0;
      if (!currentBalance.isFinite || currentBalance < 0) throw StateError('Customer savings balance is invalid.');
    }
    final normalizedSurplus = CurrencyUtils.fromMinorUnits(CurrencyUtils.toMinorUnits(surplus));
    final newBalance = CurrencyUtils.roundToCents(currentBalance + normalizedSurplus);
    await txn.update('savings_accounts', {'balance': newBalance}, where: 'id = ?', whereArgs: [accountId]);
    await txn.insert('savings_transactions', {'id': const Uuid().v4(), 'savings_account_id': accountId, 'type': 'overpayment', 'amount': normalizedSurplus, 'reference_loan_payment_id': paymentId, 'note': 'Automatic Savings Deposit — Loan: $loanId', 'created_at': DateTime.now().toIso8601String()});
  }

  Future<Payment> createPayment({required String loanId, required String customerId, required double amount, required PaymentMethod method, String? referenceNumber, required String collector, String? remarks, double? installmentDue, String? clientRequestId}) async {
    if (!amount.isFinite || amount <= 0) throw Exception('Invalid payment amount. Please enter a valid amount.');
    final db = await _db;
    final payment = await db.transaction((txn) async {
      if (clientRequestId != null && clientRequestId.trim().isNotEmpty) {
        final existing = await txn.query('payments', where: 'client_request_id = ?', whereArgs: [clientRequestId.trim()], limit: 1);
        if (existing.isNotEmpty) return Payment.fromMap(existing.first);
      }
      final loanRows = await txn.query('loans', where: 'id = ?', whereArgs: [loanId]);
      if (loanRows.isEmpty) throw Exception('Loan not found');
      final loan = loanRows.first;
      final loanCustomerId = loan['customer_id'] as String?;
      if (loanCustomerId == null || loanCustomerId != customerId) throw Exception('Loan does not belong to the specified customer.');
      final loanStatusBefore = loan['status'] as String? ?? 'active';
      if (loanStatusBefore == 'completed' || loanStatusBefore == 'cancelled') throw Exception('Loan is already closed and cannot accept payments.');
      final outstanding = (loan['outstanding_balance'] as num).toDouble();
      final priorLoanStatus = loan['status'] as String;
      final split = computePaymentSplit(paymentAmount: amount, outstandingBalance: outstanding, installmentDue: installmentDue);
      final loanStatus = split.newLoanBalance <= 0.005 ? 'completed' : 'active';
      final updated = await txn.rawUpdate('UPDATE loans SET outstanding_balance = ?, status = ? WHERE id = ? AND outstanding_balance = ?', [split.newLoanBalance, loanStatus, loanId, outstanding]);
      if (updated != 1) throw Exception('Loan balance changed since this payment was prepared; please retry.');
      await _applyPaymentToSchedule(txn, loanId, split.appliedToLoan);
      final receiptNumber = await _generateReceiptNumber(txn);
      final payment = Payment(id: const Uuid().v4(), loanId: loanId, customerId: customerId, amount: amount, method: method, referenceNumber: referenceNumber, receiptNumber: receiptNumber, paymentDate: DateTime.now(), collector: collector, type: split.overpaymentSurplus > 0 ? PaymentType.overpayment : (split.newLoanBalance <= 0.005 ? PaymentType.full : PaymentType.partial), status: PaymentStatus.completed, remarks: remarks, priorLoanStatus: priorLoanStatus, clientRequestId: clientRequestId, createdAt: DateTime.now());
      await txn.insert('payments', payment.toMap());
      if (split.overpaymentSurplus > 0) await _creditOverpaymentToSavings(txn, customerId, payment.id, split.overpaymentSurplus, loanId);
      return payment;
    });
    try { await _scheduleService?.rebuildSchedule(loanId); } catch (_) {}
    return payment;
  }

  Future<void> updatePaymentNotes(String paymentId, String? remarks) async {
    final db = await _db;
    await db.update('payments', {'remarks': remarks}, where: 'id = ?', whereArgs: [paymentId]);
  }

  Future<void> reversePayment(String paymentId) async {
    final db = await _db;
    late String capturedLoanId;
    await db.transaction((txn) async {
      final rows = await txn.query('payments', where: 'id = ?', whereArgs: [paymentId]);
      if (rows.isEmpty) throw Exception('Payment not found.');
      final payment = rows.first;
      final amount = (payment['amount'] as num?)?.toDouble();
      capturedLoanId = payment['loan_id'] as String;
      final customerId = payment['customer_id'] as String;
      final status = payment['status'] as String;
      if (amount == null || !amount.isFinite || amount <= 0) throw StateError('Payment contains an invalid amount.');
      if (status != PaymentStatus.completed.name) {
        if (status == PaymentStatus.reversed.name) throw Exception('Payment already reversed.');
        throw Exception('Only completed payments can be reversed.');
      }
      final loanRows = await txn.query('loans', columns: ['customer_id'], where: 'id = ?', whereArgs: [capturedLoanId], limit: 1);
      if (loanRows.isEmpty || loanRows.first['customer_id'] != customerId) throw StateError('Payment is linked to an invalid loan/customer relationship.');
      final savingsCreditRows = await txn.query('savings_transactions', where: 'reference_loan_payment_id = ? AND type = ?', whereArgs: [paymentId, 'overpayment'], limit: 1);
      final overpaymentSurplus = savingsCreditRows.isEmpty ? 0.0 : (savingsCreditRows.first['amount'] as num?)?.toDouble() ?? 0.0;
      if (!overpaymentSurplus.isFinite || overpaymentSurplus < 0 || overpaymentSurplus > amount) throw StateError('Payment has an invalid savings overpayment record.');
      final savingsWithdrawalRows = await txn.query('savings_transactions', where: 'reference_loan_payment_id = ? AND type = ?', whereArgs: [paymentId, 'withdrawal'], limit: 1);
      final savingsToRefund = savingsWithdrawalRows.isEmpty ? 0.0 : (savingsWithdrawalRows.first['amount'] as num?)?.toDouble() ?? 0.0;
      if (!savingsToRefund.isFinite || savingsToRefund < 0) throw StateError('Payment has an invalid savings-clearing record.');
      String? savingsAccountId;
      double? savingsNewBalance;
      if (overpaymentSurplus > 0) {
        final accountRows = await txn.query('savings_accounts', columns: ['id', 'balance'], where: 'customer_id = ?', whereArgs: [customerId], limit: 1);
        if (accountRows.isEmpty) throw StateError('Cannot reverse this payment: the required savings account is missing.');
        final accountId = accountRows.first['id'] as String;
        final currentBalance = (accountRows.first['balance'] as num?)?.toDouble() ?? 0.0;
        final reversal = computeSavingsReversal(balance: currentBalance, overpaymentSurplus: overpaymentSurplus);
        savingsAccountId = accountId;
        savingsNewBalance = reversal.$1;
      }
      final appliedToLoan = computeReversalLoanDelta(paymentAmount: amount, overpaymentSurplus: overpaymentSurplus);
      final paymentUpdated = await txn.update('payments', {'status': PaymentStatus.reversed.name}, where: 'id = ? AND status = ?', whereArgs: [paymentId, PaymentStatus.completed.name]);
      if (paymentUpdated != 1) throw Exception('Payment status changed before reversal could be completed; please retry.');
      final storedPriorStatus = payment['prior_loan_status'] as String?;
      final previousStatus = storedPriorStatus ?? 'active';
      final loanUpdated = await txn.rawUpdate('UPDATE loans SET outstanding_balance = outstanding_balance + ?, status = ? WHERE id = ?', [appliedToLoan, previousStatus, capturedLoanId]);
      if (loanUpdated != 1) throw Exception('Loan disappeared before payment reversal could be completed.');
      if (savingsAccountId != null && savingsNewBalance != null) {
        await txn.update('savings_accounts', {'balance': savingsNewBalance}, where: 'id = ?', whereArgs: [savingsAccountId]);
        await txn.insert('savings_transactions', {'id': const Uuid().v4(), 'savings_account_id': savingsAccountId, 'type': 'withdrawal', 'amount': overpaymentSurplus, 'reference_loan_payment_id': paymentId, 'note': 'Overpayment reversal — Loan: $capturedLoanId', 'created_at': DateTime.now().toIso8601String()});
      }
      if (savingsToRefund > 0) {
        final accountRows = await txn.query('savings_accounts', columns: ['id', 'balance'], where: 'customer_id = ?', whereArgs: [customerId], limit: 1);
        if (accountRows.isEmpty) throw StateError('Cannot refund savings-cleared payment: savings account is missing.');
        final accountId = accountRows.first['id'] as String;
        final currentBalance = (accountRows.first['balance'] as num?)?.toDouble() ?? 0.0;
        if (!currentBalance.isFinite || currentBalance < 0) throw StateError('Customer savings balance is invalid.');
        await txn.update('savings_accounts', {'balance': CurrencyUtils.roundToCents(currentBalance + savingsToRefund)}, where: 'id = ?', whereArgs: [accountId]);
        await txn.insert('savings_transactions', {'id': const Uuid().v4(), 'savings_account_id': accountId, 'type': 'deposit', 'amount': CurrencyUtils.roundToCents(savingsToRefund), 'reference_loan_payment_id': paymentId, 'note': 'Savings-cleared payment reversal — Loan: $capturedLoanId', 'created_at': DateTime.now().toIso8601String()});
      }
      await _recalculateScheduleFromPayments(txn, capturedLoanId);
      return capturedLoanId;
    });
    try { await _scheduleService?.rebuildSchedule(capturedLoanId); } catch (_) {}
  }

  Future<List<Payment>> getPaymentsForLoan(String loanId) async {
    final db = await _db;
    final rows = await db.query('payments', where: 'loan_id = ?', whereArgs: [loanId], orderBy: 'payment_date DESC, created_at DESC');
    return rows.map((e) => Payment.fromMap(e)).toList(growable: false);
  }

  Future<void> clearLoanWithSavings({required String loanId, required String customerId}) async {
    final db = await _db;
    await db.transaction((txn) async {
      final loanRows = await txn.query('loans', where: 'id = ?', whereArgs: [loanId]);
      if (loanRows.isEmpty) throw Exception('Loan not found.');
      final loan = loanRows.first;
      final loanCustomerId = loan['customer_id'] as String?;
      if (loanCustomerId == null || loanCustomerId != customerId) throw Exception('Loan does not belong to the specified customer.');
      final outstanding = (loan['outstanding_balance'] as num).toDouble();
      if (!outstanding.isFinite || outstanding <= 0) throw Exception('Loan has no valid outstanding balance.');
      final status = loan['status'] as String;
      if (status != 'active') throw Exception('Loan is not active.');
      final accountRows = await txn.query('savings_accounts', columns: ['id', 'balance'], where: 'customer_id = ?', whereArgs: [customerId], limit: 1);
      if (accountRows.isEmpty) throw Exception('Customer has no savings account.');
      final accountId = accountRows.first['id'] as String;
      final savingsBalance = (accountRows.first['balance'] as num?)?.toDouble() ?? 0.0;
      if (!savingsBalance.isFinite || savingsBalance < 0) throw Exception('Customer savings balance is invalid.');
      if (CurrencyUtils.toMinorUnits(savingsBalance) < CurrencyUtils.toMinorUnits(outstanding)) throw Exception('Insufficient savings. Available: ${savingsBalance.toStringAsFixed(2)}, Needed: ${outstanding.toStringAsFixed(2)}');
      final newSavingsBalance = CurrencyUtils.fromMinorUnits(CurrencyUtils.toMinorUnits(savingsBalance) - CurrencyUtils.toMinorUnits(outstanding));
      await txn.update('savings_accounts', {'balance': newSavingsBalance}, where: 'id = ?', whereArgs: [accountId]);
      final receiptNumber = await _generateReceiptNumber(txn);
      final paymentId = const Uuid().v4();
      final payment = Payment(id: paymentId, loanId: loanId, customerId: customerId, amount: CurrencyUtils.fromMinorUnits(CurrencyUtils.toMinorUnits(outstanding)), method: PaymentMethod.savings, referenceNumber: null, receiptNumber: receiptNumber, paymentDate: DateTime.now(), collector: 'System — Savings', type: PaymentType.full, status: PaymentStatus.completed, priorLoanStatus: 'active', createdAt: DateTime.now());
      await txn.insert('payments', payment.toMap());
      await txn.insert('savings_transactions', {'id': const Uuid().v4(), 'savings_account_id': accountId, 'type': 'withdrawal', 'amount': payment.amount, 'reference_loan_payment_id': paymentId, 'note': 'Loan cleared with savings — Loan: $loanId', 'created_at': DateTime.now().toIso8601String()});
      await txn.rawUpdate("UPDATE repayment_schedule SET status = 'paid', paid_amount = amount WHERE loan_id = ? AND status != 'paid'", [loanId]);
      final loanUpdated = await txn.update('loans', {'outstanding_balance': 0.0, 'status': 'completed'}, where: 'id = ? AND status = ?', whereArgs: [loanId, 'active']);
      if (loanUpdated != 1) throw Exception('Loan status changed before savings clearance could be completed.');
    });
    try { await _scheduleService?.rebuildSchedule(loanId); } catch (_) {}
  }
}
