import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/di/providers.dart';
import 'models/customer_entity.dart';

class DuplicateCustomerException implements Exception {
  const DuplicateCustomerException(this.field);
  final String field;

  @override
  String toString() => 'A customer already uses this $field.';
}

class CustomerRepository {
  CustomerRepository(this._ref);
  final Ref _ref;

  Future<Database> get _database async {
    final service = await _ref.read(databaseServiceProvider.future);
    return service.database;
  }

  Future<List<Customer>> search(String query, {String? groupId}) async {
    final db = await _database;
    final term = query.trim();

    final conditions = <String>[];
    final args = <Object?>[];

    if (term.isNotEmpty) {
      conditions.add(
          '''(c.id LIKE ? OR c.full_name LIKE ? OR c.phone LIKE ? OR
             COALESCE(c.bvn, '') LIKE ? OR COALESCE(c.nin, '') LIKE ? OR
             COALESCE(c.residential_address, '') LIKE ?)''');
      args.addAll(List.filled(6, '%$term%'));
    }

    if (groupId != null && groupId.isNotEmpty) {
      conditions.add('c.group_id = ?');
      args.add(groupId);
    }

    final where = conditions.isEmpty ? '1=1' : conditions.join(' AND ');

    final rows = await db.rawQuery('''
      SELECT c.*,
        COALESCE(
          (SELECT SUM(l.outstanding_balance)
           FROM loans l
           WHERE l.customer_id = c.id AND l.status = 'active'),
          0.0
        ) AS total_owed
      FROM customers c
      WHERE $where
      ORDER BY c.full_name COLLATE NOCASE ASC
    ''', args);
    return rows.map(Customer.fromMap).toList(growable: false);
  }

  Future<Customer?> getById(String id) async {
    final db = await _database;
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  Future<void> save(Customer customer) async {
    final db = await _database;
    await _validateUnique(db, customer);

    final isNew = await db
        .query('customers', columns: ['id'], where: 'id = ?', whereArgs: [customer.id])
        .then((rows) => rows.isEmpty);

    await db.transaction((txn) async {
      await txn.insert(
        'customers',
        customer.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      // Auto-create a savings account for new customers
      if (isNew) {
        await txn.insert(
          'savings_accounts',
          {
            'id': const Uuid().v4(),
            'customer_id': customer.id,
            'balance': 0.0,
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<void> delete(String id) async {
    final db = await _database;
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> changeStatus(String id, CustomerStatus status) async {
    final db = await _database;
    await db.update('customers', {'status': status.value},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _validateUnique(Database db, Customer customer) async {
    final checks = <String, String?>{
      'phone number': customer.phone,
      'BVN': customer.bvn,
      'NIN': customer.nin,
    };
    for (final entry in checks.entries) {
      final value = entry.value?.trim();
      if (value == null || value.isEmpty) continue;
      final column = switch (entry.key) {
        'phone number' => 'phone',
        'BVN' => 'bvn',
        _ => 'nin',
      };
      final duplicate = await db.query(
        'customers',
        columns: const ['id'],
        where: '$column = ? AND id != ?',
        whereArgs: [value, customer.id],
        limit: 1,
      );
      if (duplicate.isNotEmpty) throw DuplicateCustomerException(entry.key);
    }
  }
}
