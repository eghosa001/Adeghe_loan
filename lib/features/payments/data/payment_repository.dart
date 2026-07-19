import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_service.dart';
import 'models/payment_entity.dart';

class PaymentRepository {
  PaymentRepository(this._dbService);
  final DatabaseService _dbService;

  Future<Database> get _db async => _dbService.database;

  Future<String> _generateReceiptNumber() async {
    final db = await _db;
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM payments');
    final count = Sqflite.firstIntValue(countResult) ?? 0;
    final date = DateTime.now().toIso8601String().split('T').first.replaceAll('-', '');
    return 'REC-$date-${(count + 1).toString().padLeft(5, '0')}';
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
      final loanRows = await txn.query('loans', where: 'id = ?', whereArgs: [loanId]);
      if (loanRows.isEmpty) {
        throw Exception('Loan not found');
      }
      final loan = loanRows.first;
      final outstanding = (loan['outstanding_balance'] as num).toDouble();
      final paymentType = amount >= outstanding
          ? PaymentType.full
          : PaymentType.partial;
      final newBalance = (outstanding - amount).clamp(0.0, double.infinity);
      final status = newBalance == 0.0 ? 'completed' : 'active';
      await txn.update(
        'loans',
        {'outstanding_balance': newBalance, 'status': status},
        where: 'id = ?',
        whereArgs: [loanId],
      );
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
      return payment;
    });
  }

  Future<void> reversePayment(String paymentId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query('payments', where: 'id = ?', whereArgs: [paymentId]);
      if (rows.isEmpty) throw Exception('Payment not found.');
      final payment = rows.first;
      final amount = (payment['amount'] as num).toDouble();
      final loanId = payment['loan_id'] as String;
      final status = payment['status'] as String;
      if (status == PaymentStatus.reversed.name) {
        throw Exception('Payment already reversed.');
      }
      await txn.update('payments', {'status': PaymentStatus.reversed.name}, where: 'id = ?', whereArgs: [paymentId]);
      await txn.rawUpdate(
        'UPDATE loans SET outstanding_balance = outstanding_balance + ?, status = ? WHERE id = ?',
        [amount, 'active', loanId],
      );
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
