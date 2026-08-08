import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_service.dart';
import 'models/customer_entity.dart';

/// Sort options for the customer list.
enum CustomerSortOption { name, group, amountOwed }

/// Filter for customer status in lists.
enum CustomerStatusFilter { active, archived }

/// Sentinel value for the customer-list group filter meaning "customers that
/// are not assigned to any group". Group IDs are UUIDs so this cannot collide.
const String ungroupedGroupFilter = '__ungrouped__';

/// Appends a group membership condition (group or "no group") to [conditions]
/// and [args]. Null [groupId] adds nothing (all customers).
void _applyGroupFilter(
  String? groupId,
  List<String> conditions,
  List<Object?> args,
) {
  if (groupId == null || groupId.isEmpty) return;
  if (groupId == ungroupedGroupFilter) {
    conditions.add("(COALESCE(c.group_id, '') = '')");
  } else {
    conditions.add('c.group_id = ?');
    args.add(groupId);
  }
}

class DuplicateCustomerException implements Exception {
  const DuplicateCustomerException(this.field);
  final String field;

  @override
  String toString() => 'A customer already uses this $field.';
}

class CustomerRepository {
  CustomerRepository(this._dbService);
  final DatabaseService _dbService;

  Future<Database> get _database async => _dbService.database;

  Future<List<Customer>> search(String query, {String? groupId, CustomerStatusFilter statusFilter = CustomerStatusFilter.active}) async {
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

    _applyGroupFilter(groupId, conditions, args);

    // Status filter
    if (statusFilter == CustomerStatusFilter.active) {
      conditions.add("c.status != 'archived'");
    } else {
      conditions.add("c.status = 'archived'");
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

  /// Returns the total count of customers matching [query] and [groupId].
  Future<int> count(String query, {String? groupId, CustomerStatusFilter statusFilter = CustomerStatusFilter.active}) async {
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
    _applyGroupFilter(groupId, conditions, args);
    if (statusFilter == CustomerStatusFilter.active) {
      conditions.add("c.status != 'archived'");
    } else {
      conditions.add("c.status = 'archived'");
    }
    final where = conditions.isEmpty ? '1=1' : conditions.join(' AND ');
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM customers c WHERE $where',
      args,
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  /// Paginated search. Returns up to [limit] results starting at [offset].
  Future<List<Customer>> searchPaginated(
    String query, {
    String? groupId,
    int limit = AppConstants.defaultPageSize,
    int offset = 0,
    CustomerSortOption sortBy = CustomerSortOption.name,
    CustomerStatusFilter statusFilter = CustomerStatusFilter.active,
  }) async {
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

    _applyGroupFilter(groupId, conditions, args);
    if (statusFilter == CustomerStatusFilter.active) {
      conditions.add("c.status != 'archived'");
    } else {
      conditions.add("c.status = 'archived'");
    }

    final where = conditions.isEmpty ? '1=1' : conditions.join(' AND ');

    final orderBy = switch (sortBy) {
      CustomerSortOption.name => 'c.full_name COLLATE NOCASE ASC',
      CustomerSortOption.group =>
        "COALESCE(c.group_id, '') COLLATE NOCASE ASC, c.full_name COLLATE NOCASE ASC",
      CustomerSortOption.amountOwed =>
        'total_owed DESC, c.full_name COLLATE NOCASE ASC',
    };

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
      ORDER BY $orderBy
      LIMIT ? OFFSET ?
    ''', [...args, limit, offset]);
    return rows.map(Customer.fromMap).toList(growable: false);
  }

  Future<Customer?> getById(String id) async {
    final db = await _database;
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  Future<void> save(Customer customer) async {
    final db = await _database;
    // Names are the source of truth for every screen, report, collection
    // sheet, statement and document — store them in ALL CAPS (trimmed) so a
    // single write normalizes every read path that consumes them.
    final normalized = _uppercaseNames(customer);

    await db.transaction((txn) async {
      await _validateUnique(txn, normalized);

      final existing = await txn.query(
        'customers',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [normalized.id],
      );
      final isNew = existing.isEmpty;

      if (isNew) {
        await txn.insert('customers', normalized.toMap());
      } else {
        await txn.update(
          'customers',
          normalized.toMap(),
          where: 'id = ?',
          whereArgs: [normalized.id],
        );
      }

      // Auto-create a savings account for new customers
      if (isNew) {
        await txn.insert(
          'savings_accounts',
          {
            'id': const Uuid().v4(),
            'customer_id': normalized.id,
            'balance': 0.0,
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Customer _uppercaseNames(Customer c) => Customer(
        id: c.id,
        passportPath: c.passportPath,
        fullName: c.fullName.trim().toUpperCase(),
        gender: c.gender,
        dateOfBirth: c.dateOfBirth,
        phone: c.phone,
        altPhone: c.altPhone,
        email: c.email,
        residentialAddress: c.residentialAddress,
        businessAddress: c.businessAddress,
        occupation: c.occupation,
        employer: c.employer,
        maritalStatus: c.maritalStatus,
        nationality: c.nationality,
        state: c.state,
        lga: c.lga,
        nextOfKin: _capsNullable(c.nextOfKin),
        nextOfKinRelation: c.nextOfKinRelation,
        nextOfKinPhone: c.nextOfKinPhone,
        guarantor1Name: _capsNullable(c.guarantor1Name),
        guarantor1Phone: c.guarantor1Phone,
        guarantor1Address: c.guarantor1Address,
        guarantor2Name: _capsNullable(c.guarantor2Name),
        guarantor2Phone: c.guarantor2Phone,
        guarantor2Address: c.guarantor2Address,
        guarantorPassportPath: c.guarantorPassportPath,
        nin: c.nin,
        bvn: c.bvn,
        idType: c.idType,
        idNumber: c.idNumber,
        signaturePath: c.signaturePath,
        dateRegistered: c.dateRegistered,
        notes: c.notes,
        status: c.status,
        creditScore: c.creditScore,
        groupId: c.groupId,
      );

  static String? _capsNullable(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? trimmed : trimmed.toUpperCase();
  }

  /// Soft-deletes a customer by archiving them. No rows or files are removed —
  /// loans, payments, documents and savings history are all preserved (an
  /// archive operation must never wipe financial history via CASCADE).
  Future<void> delete(String id) async {
    final db = await _database;
    await db.update('customers', {'status': CustomerStatus.archived.value},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Permanently deletes an archived customer and ALL associated data.
  /// This CASCADE deletes loans, payments, documents, savings accounts,
  /// and savings transactions. Use with extreme caution.
  Future<void> hardDelete(String id) async {
    final db = await _database;
    // Verify the customer is archived before allowing hard delete
    final customer = await db.query(
      'customers',
      columns: const ['id', 'status'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (customer.isEmpty) {
      throw Exception('Customer not found');
    }
    if (customer.first['status'] != CustomerStatus.archived.value) {
      throw Exception('Only archived customers can be permanently deleted');
    }
    // The CASCADE DELETE on foreign keys will remove all related data:
    // loans -> payments, repayment_schedule
    // documents
    // savings_accounts -> savings_transactions
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> changeStatus(String id, CustomerStatus status) async {
    final db = await _database;
    await db.update('customers', {'status': status.value},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> changeGroup(String id, String? groupId) async {
    final db = await _database;
    await db.update('customers', {'group_id': groupId},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _validateUnique(DatabaseExecutor db, Customer customer) async {
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
        where: "$column = ? AND id != ? AND status != 'archived'",
        whereArgs: [value, customer.id],
        limit: 1,
      );
      if (duplicate.isNotEmpty) throw DuplicateCustomerException(entry.key);
    }
  }
}
