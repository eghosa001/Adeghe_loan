import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

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
      conditions.add('''(id LIKE ? OR full_name LIKE ? OR phone LIKE ? OR
           COALESCE(bvn, '') LIKE ? OR COALESCE(nin, '') LIKE ? OR
           COALESCE(residential_address, '') LIKE ?)''');
      args.addAll(List.filled(6, '%$term%'));
    }
    if (groupId != null) {
      conditions.add('group_id = ?');
      args.add(groupId);
    }

    final where = conditions.isEmpty ? null : conditions.join(' AND ');
    final rows = await db.query(
      'customers',
      where: where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'full_name COLLATE NOCASE ASC',
    );
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
    await db.insert(
      'customers',
      customer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
