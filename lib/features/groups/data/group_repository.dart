import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_service.dart';
import '../../../core/database/holiday_sql.dart';
import '../../../features/customers/data/models/customer_entity.dart';
import 'models/customer_group_entity.dart';

class GroupRepository {
  GroupRepository(this._dbService);
  final DatabaseService _dbService;

  Future<Database> get _database async => _dbService.database;

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

  /// Deletes the group, unassigning its members first. Returns the ids of the
  /// members that were unassigned so an undo action can restore full
  /// membership to a recreated group.
  Future<List<String>> delete(String id) async {
    final db = await _database;
    final members = await db.query(
      'customers',
      columns: ['id'],
      where: 'group_id = ?',
      whereArgs: [id],
    );
    // Unassign customers from this group before deleting
    await db.update(
      'customers',
      {'group_id': null},
      where: 'group_id = ?',
      whereArgs: [id],
    );
    await db.delete('customer_groups', where: 'id = ?', whereArgs: [id]);
    return members.map((m) => m['id'] as String).toList(growable: false);
  }

  Future<List<Customer>> getMembers(String groupId) async {
    final db = await _database;
    final rows = await db.query(
      'customers',
      where: "group_id = ? AND status != 'archived'",
      whereArgs: [groupId],
      orderBy: 'full_name COLLATE NOCASE ASC',
    );
    return rows.map(Customer.fromMap).toList(growable: false);
  }

  Future<void> removeMember(String customerId) async {
    final db = await _database;
    await db.update(
      'customers',
      {'group_id': null},
      where: 'id = ?',
      whereArgs: [customerId],
    );
  }

  Future<void> moveMembers(List<String> customerIds, String targetGroupId) async {
    final db = await _database;
    await db.transaction((txn) async {
      for (final id in customerIds) {
        await txn.update(
          'customers',
          {'group_id': targetGroupId},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  Future<Map<String, dynamic>> getStats(String groupId) async {
    final db = await _database;
    final results = await Future.wait([
      db.rawQuery("SELECT COUNT(*) AS count FROM customers WHERE group_id = ? AND status != 'archived'", [groupId]),
      db.rawQuery("SELECT COUNT(*) AS count FROM loans l INNER JOIN customers c ON l.customer_id = c.id WHERE c.group_id = ? AND l.status = 'active' AND c.status != 'archived'", [groupId]),
      db.rawQuery("SELECT COALESCE(SUM(l.outstanding_balance), 0.0) AS total FROM loans l INNER JOIN customers c ON l.customer_id = c.id WHERE c.group_id = ? AND l.status = 'active' AND c.status != 'archived'", [groupId]),
      db.rawQuery("SELECT COALESCE(SUM(sa.balance), 0.0) AS total FROM savings_accounts sa INNER JOIN customers c ON sa.customer_id = c.id WHERE c.group_id = ? AND c.status != 'archived'", [groupId]),
    ]);
    return {
      'memberCount': (results[0].first['count'] as int?) ?? 0,
      'activeLoans': (results[1].first['count'] as int?) ?? 0,
      'totalOutstanding': (results[2].first['total'] as num?)?.toDouble() ?? 0.0,
      'totalSavings': (results[3].first['total'] as num?)?.toDouble() ?? 0.0,
    };
  }

  Future<Map<String, double>> getCollectionSummary(String groupId, DateTime date) async {
    final db = await _database;
    final dateStr = date.toIso8601String().split('T').first;
    final results = await Future.wait([
      db.rawQuery('''
        SELECT
          COALESCE(SUM((
            SELECT COALESCE(SUM(COALESCE(l.custom_collection_amount, rs.amount)), 0.0)
            FROM repayment_schedule rs
            WHERE rs.loan_id = l.id AND DATE(rs.due_date) = ?
              AND $notOnEnabledHolidaySql
          )), 0.0) AS due,
          COALESCE(SUM((
            SELECT COALESCE(SUM(p.amount - COALESCE(st.amount, 0.0)), 0.0)
            FROM payments p
            LEFT JOIN savings_transactions st
              ON st.reference_loan_payment_id = p.id AND st.type = 'overpayment'
            WHERE p.loan_id = l.id AND p.status = 'completed'
              AND DATE(p.payment_date) = ?
          )), 0.0) AS paid
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        WHERE l.status = 'active' AND c.group_id = ?
          AND (
            EXISTS (
              SELECT 1 FROM repayment_schedule rs
              WHERE rs.loan_id = l.id AND DATE(rs.due_date) = ?
                AND $notOnEnabledHolidaySql
            )
            OR EXISTS (
              SELECT 1 FROM payments px
              WHERE px.loan_id = l.id AND px.status = 'completed'
                AND DATE(px.payment_date) = ?
            )
          )
      ''', [dateStr, dateStr, groupId, dateStr, dateStr]),
    ]);
    final due = (results[0].first['due'] as num?)?.toDouble() ?? 0.0;
    final paid = (results[0].first['paid'] as num?)?.toDouble() ?? 0.0;
    final remaining = (due - paid).clamp(0.0, double.infinity).toDouble();
    return {'due': due, 'paid': paid, 'remaining': remaining};
  }
}
