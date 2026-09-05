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
    final balance = (rows.first['balance'] as num?)?.toDouble();
    if (balance == null || !balance.isFinite || balance < 0) {
      throw StateError('Customer savings balance is invalid.');
    }
    return CurrencyUtils.roundToCents(balance);
  }

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

  Future<SavingsTransaction> recordTransaction({
    required String customerId,
    required SavingsTransactionType type,
    required double amount,
    String? note,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw Exception('Amount must be a valid number greater than zero.');
    }
    final amountCents = CurrencyUtils.toMinorUnits(amount);
    if (amountCents <= 0) {
      throw Exception('Amount must be at least 0.01.');
    }
    final normalizedAmount = CurrencyUtils.fromMinorUnits(amountCents);
    final db = await _database;
    return await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
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
          'balance': 0.0,
          'created_at': now,
        });
      } else {
        accountId = accountRows.first['id'] as String;
        final rawBalance = (accountRows.first['balance'] as num?)?.toDouble();
        if (rawBalance == null || !rawBalance.isFinite || rawBalance < 0) {
          throw StateError('Customer savings balance is invalid.');
        }
        currentBalance = CurrencyUtils.roundToCents(rawBalance);
      }

      if (type == SavingsTransactionType.withdrawal &&
          amountCents > CurrencyUtils.toMinorUnits(currentBalance)) {
        throw Exception(
            'Insufficient savings balance. Available: ${currentBalance.toStringAsFixed(2)}');
      }

      final currentCents = CurrencyUtils.toMinorUnits(currentBalance);
      final newBalanceCents = type == SavingsTransactionType.withdrawal
          ? currentCents - amountCents
          : currentCents + amountCents;
      if (newBalanceCents < 0) {
        throw StateError('Savings balance cannot become negative.');
      }
      final newBalance = CurrencyUtils.fromMinorUnits(newBalanceCents);

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
        amount: normalizedAmount,
        note: note,
        createdAt: now,
      );
      await txn.insert('savings_transactions', tx.toMap());
      return tx;
    });
  }

  Future<List<SavingsAccount>> getAllAccounts() async {
    final db = await _database;
    final rows = await db.query('savings_accounts', orderBy: 'created_at DESC');
    return rows.map(SavingsAccount.fromMap).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getAllAccountsWithCustomerNames(
      {String query = ''}) async {
    final db = await _database;
    final where = query.isEmpty
        ? ''
        : ' AND (c.full_name LIKE ? OR c.phone LIKE ?)';
    final args = query.isEmpty ? [] : ['%$query%', '%$query%'];
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
      WHERE 1=1 $where
      ORDER BY sa.created_at DESC
    ''', args);
  }
}
