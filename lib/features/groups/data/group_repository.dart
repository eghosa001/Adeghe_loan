import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/di/providers.dart';
import 'models/customer_group_entity.dart';

class GroupRepository {
  GroupRepository(this._ref);
  final Ref _ref;

  Future<List<CustomerGroup>> getAll() async {
    final service = await _ref.read(databaseServiceProvider.future);
    final db = await service.database;
    final rows = await db.query('customer_groups', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(CustomerGroup.fromMap).toList(growable: false);
  }

  Future<CustomerGroup?> getById(String id) async {
    final service = await _ref.read(databaseServiceProvider.future);
    final db = await service.database;
    final rows = await db.query('customer_groups', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : CustomerGroup.fromMap(rows.first);
  }

  Future<CustomerGroup> create(String name, {String? description}) async {
    final service = await _ref.read(databaseServiceProvider.future);
    final db = await service.database;
    final group = CustomerGroup(
      id: const Uuid().v4(),
      name: name.trim(),
      description: description?.trim().isEmpty == true ? null : description?.trim(),
      createdAt: DateTime.now().toIso8601String(),
    );
    await db.insert('customer_groups', group.toMap());
    return group;
  }

  Future<void> update(String id, {required String name, String? description}) async {
    final service = await _ref.read(databaseServiceProvider.future);
    final db = await service.database;
    await db.update(
      'customer_groups',
      {
        'name': name.trim(),
        'description': description?.trim().isEmpty == true ? null : description?.trim(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final service = await _ref.read(databaseServiceProvider.future);
    final db = await service.database;
    // Unassign customers from this group before deleting
    await db.update('customers', {'group_id': null}, where: 'group_id = ?', whereArgs: [id]);
    await db.delete('customer_groups', where: 'id = ?', whereArgs: [id]);
  }
}
