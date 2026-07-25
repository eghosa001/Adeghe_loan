import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/di/providers.dart';
import 'models/customer_group_entity.dart';

class GroupRepository {
  GroupRepository(this._ref);
  final Ref _ref;

  Future<Database> get _database async {
    final service = await _ref.read(databaseServiceProvider.future);
    return service.database;
  }

  Future<List<CustomerGroup>> getAll() async {
    final db = await _database;
    final rows = await db.query(
      'customer_groups',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(CustomerGroup.fromMap).toList(growable: false);
  }

  Future<CustomerGroup> create({
    required String name,
    String? description,
  }) async {
    final db = await _database;
    final group = CustomerGroup(
      id: const Uuid().v4(),
      name: name.trim(),
      description: description?.trim().isEmpty == true ? null : description?.trim(),
      createdAt: DateTime.now().toIso8601String(),
    );
    await db.insert('customer_groups', group.toMap());
    return group;
  }

  Future<void> update(CustomerGroup group) async {
    final db = await _database;
    await db.update(
      'customer_groups',
      {'name': group.name, 'description': group.description},
      where: 'id = ?',
      whereArgs: [group.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _database;
    // Unassign customers from this group before deleting
    await db.update(
      'customers',
      {'group_id': null},
      where: 'group_id = ?',
      whereArgs: [id],
    );
    await db.delete('customer_groups', where: 'id = ?', whereArgs: [id]);
  }
}
