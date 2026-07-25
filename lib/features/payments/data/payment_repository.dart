import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_service.dart';
import 'models/payment_entity.dart';
import '../../../features/savings/data/models/savings_account_entity.dart';

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
  /// of all non-reversed payments for [loanId]. Used after a reversal.
  Future<void> _recalculateScheduleFromPayments(
      Transaction txn, String loanId) async {
    final paidResult = await txn.rawQuery(
      "SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments "
      "WHERE loan_id = ? AND status = 'completed'",
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
      final newBalance = (outstanding - amount).clamp(0.0, double.infinity);
      final loanStatus = newBalance == 0.0 ? 'completed' : 'active';

      await txn.update(
        'loans',
        {'outstanding_balance': newBalance, 'status': loanStatus},
        where: 'id = ?',
        whereArgs: [loanId],
      );

      // Keep repayment_schedule in sync (only up to the outstanding amount).
      final appliedAmount = amount.clamp(0.0, outstanding);
      await _applyPaymentToSchedule(txn, loanId, appliedAmount);

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

      // If the customer paid more than what was owed, credit the surplus
      // to their savings account within the same transaction.
      final surplus = amount - outstanding;
      if (surplus > 0.001) {
        await _creditSavingsOverpayment(
            txn, customerId, surplus, payment.id);
      }

      return payment;
    });
  }

  /// Credits [surplus] to the customer's savings account as an overpayment.
  /// Auto-creates the savings account if it does not exist yet.
  Future<void> _creditSavingsOverpayment(
    Transaction txn,
    String customerId,
    double surplus,
    String paymentId,
  ) async {
    final rows = await txn.query('savings_accounts',
        where: 'customer_id = ?', whereArgs: [customerId]);

    final String accountId;
    if (rows.isEmpty) {
      accountId = const Uuid().v4();
      await txn.insert('savings_accounts', {
        'id': accountId,
        'customer_id': customerId,
        'balance': surplus,
        'created_at': DateTime.now().toIso8601String(),
      });
    } else {
      accountId = rows.first['id'] as String;
      await txn.rawUpdate(
        'UPDATE savings_accounts SET balance = balance + ? WHERE id = ?',
        [surplus, accountId],
      );
    }

    await txn.insert('savings_transactions', {
      'id': const Uuid().v4(),
      'savings_account_id': accountId,
      'type': SavingsTransactionType.overpayment.value,
      'amount': surplus,
      'note': 'Overpayment credit from loan repayment',
      'created_at': DateTime.now().toIso8601String(),
      'reference_loan_payment_id': paymentId,
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
      final status = payment['status'] as String;

      if (status == PaymentStatus.reversed.name) {
        throw Exception('Payment already reversed.');
      }

      await txn.update(
        'payments',
        {'status': PaymentStatus.reversed.name},
        where: 'id = ?',
        whereArgs: [paymentId],
      );

      await txn.rawUpdate(
        'UPDATE loans SET outstanding_balance = outstanding_balance + ?, '
        'status = ? WHERE id = ?',
        [amount, 'active', loanId],
      );

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
