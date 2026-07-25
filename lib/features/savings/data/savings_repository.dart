import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_service.dart';
import 'models/savings_account_entity.dart';

class SavingsRepository {
  SavingsRepository(this._dbService);
  final DatabaseService _dbService;

  Future<Database> get _db async => _dbService.database;

  /// Returns (or creates) the savings account for a customer.
  Future<SavingsAccount> getOrCreate(String customerId) async {
    final db = await _db;
    final rows = await db.query(
      'savings_accounts',
      where: 'customer_id = ?',
      whereArgs: [customerId],
    );
    if (rows.isNotEmpty) return SavingsAccount.fromMap(rows.first);
    final account = SavingsAccount(
      id: const Uuid().v4(),
      customerId: customerId,
      balance: 0.0,
      createdAt: DateTime.now().toIso8601String(),
    );
    await db.insert('savings_accounts', account.toMap());
    return account;
  }

  Future<SavingsAccount?> getByCustomer(String customerId) async {
    final db = await _db;
    final rows = await db.query(
      'savings_accounts',
      where: 'customer_id = ?',
      whereArgs: [customerId],
    );
    return rows.isEmpty ? null : SavingsAccount.fromMap(rows.first);
  }

  Future<List<SavingsTransaction>> getTransactions(String customerId) async {
    final db = await _db;
    final account = await getByCustomer(customerId);
    if (account == null) return [];
    final rows = await db.query(
      'savings_transactions',
      where: 'savings_account_id = ?',
      whereArgs: [account.id],
      orderBy: 'created_at DESC',
    );
    return rows.map(SavingsTransaction.fromMap).toList(growable: false);
  }

  /// Credit the savings account with [amount]. Used for deposits and
  /// overpayment credits. Pass [referenceLoanPaymentId] when crediting
  /// from a loan overpayment.
  Future<SavingsTransaction> credit({
    required String customerId,
    required double amount,
    required SavingsTransactionType type,
    required String note,
    String? referenceLoanPaymentId,
    Transaction? txn,
  }) async {
    final db = txn ?? (await _db);
    final rows = await (txn != null
        ? txn.query('savings_accounts',
            where: 'customer_id = ?', whereArgs: [customerId])
        : (await _db).query('savings_accounts',
            where: 'customer_id = ?', whereArgs: [customerId]));

    final String accountId;
    if (rows.isEmpty) {
      accountId = const Uuid().v4();
      await db.insert('savings_accounts', {
        'id': accountId,
        'customer_id': customerId,
        'balance': 0.0,
        'created_at': DateTime.now().toIso8601String(),
      });
    } else {
      accountId = rows.first['id'] as String;
    }

    await db.rawUpdate(
      'UPDATE savings_accounts SET balance = balance + ? WHERE id = ?',
      [amount, accountId],
    );

    final txnRecord = SavingsTransaction(
      id: const Uuid().v4(),
      savingsAccountId: accountId,
      type: type,
      amount: amount,
      note: note,
      createdAt: DateTime.now().toIso8601String(),
      referenceLoanPaymentId: referenceLoanPaymentId,
    );
    await db.insert('savings_transactions', txnRecord.toMap());
    return txnRecord;
  }

  Future<SavingsTransaction> withdraw({
    required String customerId,
    required double amount,
    required String note,
  }) async {
    final db = await _db;
    final account = await getByCustomer(customerId);
    if (account == null || account.balance < amount) {
      throw Exception('Insufficient savings balance.');
    }
    await db.rawUpdate(
      'UPDATE savings_accounts SET balance = balance - ? WHERE id = ?',
      [amount, account.id],
    );
    final txnRecord = SavingsTransaction(
      id: const Uuid().v4(),
      savingsAccountId: account.id,
      type: SavingsTransactionType.withdrawal,
      amount: amount,
      note: note,
      createdAt: DateTime.now().toIso8601String(),
    );
    await db.insert('savings_transactions', txnRecord.toMap());
    return txnRecord;
  }

  /// Total savings balance across ALL customers (for dashboard).
  Future<double> totalSavingsBalance() async {
    final db = await _db;
    final result = await db
        .rawQuery('SELECT COALESCE(SUM(balance), 0.0) AS total FROM savings_accounts');
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }
}
