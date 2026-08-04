import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_service.dart';
import '../../../core/utils/currency_utils.dart';
import 'models/savings_account_entity.dart';
import 'models/savings_transaction_entity.dart';

class SavingsRepository {
  SavingsRepository(this._dbService);
  final DatabaseService _dbService;

  Future<Database> get _database async => _dbService.database;

  /// Returns the savings account for a customer, or null if none exists.
  Future<SavingsAccount?> getAccount(String customerId) async {
    final db = await _database;
    final rows = await db.query(
      'savings_accounts',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    return rows.isEmpty ? null : SavingsAccount.fromMap(rows.first);
  }

  /// Creates a savings account for a new customer (called during customer creation).
  Future<SavingsAccount> createAccount(String customerId) async {
    final db = await _database;
    final account = SavingsAccount(
      id: const Uuid().v4(),
      customerId: customerId,
      balance: 0,
      createdAt: DateTime.now().toIso8601String(),
    );
    await db.insert('savings_accounts', account.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return account;
  }

  /// Returns the savings balance for a customer (0.0 if no account yet).
  Future<double> getSavingsBalance(String customerId) async {
    final db = await _database;
    final rows = await db.query(
      'savings_accounts',
      columns: ['balance'],
      where: 'customer_id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (rows.isEmpty) return 0.0;
    return (rows.first['balance'] as num?)?.toDouble() ?? 0.0;
  }

  /// Returns all transactions for a customer's savings account, newest first.
  Future<List<SavingsTransaction>> getTransactions(String customerId) async {
    final db = await _database;
    final accountRows = await db.query(
      'savings_accounts',
      columns: ['id'],
      where: 'customer_id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (accountRows.isEmpty) return [];
    final accountId = accountRows.first['id'] as String;
    final rows = await db.query(
      'savings_transactions',
      where: 'savings_account_id = ?',
      whereArgs: [accountId],
      orderBy: 'created_at DESC',
    );
    return rows.map(SavingsTransaction.fromMap).toList(growable: false);
  }

  /// Records a deposit or withdrawal for a customer. Throws if insufficient
  /// balance for a withdrawal.
  Future<SavingsTransaction> recordTransaction({
    required String customerId,
    required SavingsTransactionType type,
    required double amount,
    String? note,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw Exception('Amount must be a valid number greater than zero.');
    }
    final db = await _database;
    return await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      // Find or create account
      var accountRows = await txn.query(
        'savings_accounts',
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
          'balance': 0,
          'created_at': now,
        });
      } else {
        accountId = accountRows.first['id'] as String;
        currentBalance =
            (accountRows.first['balance'] as num?)?.toDouble() ?? 0.0;
      }

      if (type == SavingsTransactionType.withdrawal &&
          amount > currentBalance) {
        throw Exception(
            'Insufficient savings balance. Available: ${currentBalance.toStringAsFixed(2)}');
      }

      final newBalance = CurrencyUtils.roundToCents(
        type == SavingsTransactionType.withdrawal
            ? currentBalance - amount
            : currentBalance + amount,
      );

      await txn.update(
        'savings_accounts',
        {'balance': newBalance},
        where: 'id = ?',
        whereArgs: [accountId],
      );

      final tx = SavingsTransaction(
        id: const Uuid().v4(),
        savingsAccountId: accountId,
        type: type,
        amount: amount,
        note: note,
        createdAt: now,
      );
      await txn.insert('savings_transactions', tx.toMap());
      return tx;
    });
  }

  /// Returns all savings accounts, newest first.
  Future<List<SavingsAccount>> getAllAccounts() async {
    final db = await _database;
    final rows = await db.query('savings_accounts', orderBy: 'created_at DESC');
    return rows.map(SavingsAccount.fromMap).toList(growable: false);
  }

  /// Returns all savings accounts joined with customer names, newest first.
  Future<List<Map<String, dynamic>>> getAllAccountsWithCustomerNames() async {
    final db = await _database;
    return await db.rawQuery('''
      SELECT
        sa.id AS id,
        sa.customer_id AS customerId,
        sa.balance AS balance,
        sa.created_at AS createdAt,
        c.full_name AS customerName,
        c.phone AS phone
      FROM savings_accounts sa
      INNER JOIN customers c ON sa.customer_id = c.id
      ORDER BY sa.created_at DESC
    ''');
  }

  /// Returns the total savings balance across all customers.
  Future<double> getTotalSavingsBalance() async {
    final db = await _database;
    final result = await db.rawQuery(
        'SELECT COALESCE(SUM(balance), 0.0) AS total FROM savings_accounts');
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }
}
