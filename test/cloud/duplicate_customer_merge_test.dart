import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/cloud/cloud_sync_service.dart';
import 'package:loantrack/core/database/migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show OpenDatabaseOptions, databaseFactoryFfi, inMemoryDatabasePath, sqfliteFfiInit;
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

/// Guards the duplicate-customer merge that runs at the start of every cloud
/// push (`_resolveDuplicateCustomers` in `cloud_sync_service.dart`):
///  * the survivor rule is deterministic across devices (earliest
///    `date_registered`, ties by `id`) so two syncing devices never pick
///    different survivors and fight
///  * every child row (loans/payments/documents/savings) is re-pointed at the
///    survivor before the duplicate is deleted, and each re-point is stamped so
///    it is pushed
///  * the duplicate's removal is recorded as a sync tombstone so the cloud and
///    the other device converge to the survivor
///  * the 1:1 savings account (`UNIQUE customer_id`) is folded, not re-pointed
///  * profile fields fill NULLs only (existing data is never overwritten), and
///    `nin`/`bvn` are copied only when no other non-archived customer holds the
///    same value (v21 partial unique indexes)
void main() {
  sqfliteFfiInit();

  /// Minimal copy of the real schema for the tables the merge touches, plus the
  /// v17 sync bookkeeping + triggers (needed so re-points get stamped and
  /// deletes get tombstoned). `createSyncSchema` creates triggers for every
  /// table in `migrations.dart` `_syncTables`, so all of them must exist.
  Future<Database> openFixture() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1),
    );
    await db.execute('PRAGMA foreign_keys = ON');    await db.execute(
        'CREATE TABLE business_profile (id TEXT PRIMARY KEY, updated_at TEXT)');
    await db.execute(
        'CREATE TABLE customer_groups (id TEXT PRIMARY KEY, name TEXT NOT NULL, updated_at TEXT)');
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        full_name TEXT NOT NULL,
        phone TEXT NOT NULL,
        group_id TEXT,
        nin TEXT,
        bvn TEXT,
        email TEXT,
        gender TEXT,
        notes TEXT,
        credit_score REAL DEFAULT 0.0,
        date_registered TEXT NOT NULL,
        status TEXT NOT NULL,
        updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE loans (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        loan_type TEXT NOT NULL,
        status TEXT NOT NULL,
        updated_at TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        loan_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        updated_at TEXT,
        FOREIGN KEY (loan_id) REFERENCES loans (id) ON DELETE CASCADE,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE documents (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        file_path TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        updated_at TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE savings_accounts (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL UNIQUE,
        balance REAL NOT NULL DEFAULT 0.0,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE savings_transactions (
        id TEXT PRIMARY KEY,
        savings_account_id TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        FOREIGN KEY (savings_account_id) REFERENCES savings_accounts (id)
          ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE TABLE holidays (id TEXT PRIMARY KEY, updated_at TEXT)');
    await db.execute('CREATE TABLE audit_logs (id TEXT PRIMARY KEY, updated_at TEXT)');
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, updated_at TEXT)');
    await DatabaseMigrations.createSyncSchema(db);
    return db;
  }

  Future<void> insertCustomer(
    Database db, {
    required String id,
    required String name,
    required String phone,
    required String registered,
    String status = 'active',
    String? groupId,
    String? nin,
    String? email,
  }) async {
    await db.insert('customers', {
      'id': id,
      'full_name': name,
      'phone': phone,
      'group_id': groupId,
      'nin': nin,
      'email': email,
      'date_registered': registered,
      'status': status,
    });
  }

  Future<Map<String, Object?>> query(Database db, String table, String id) async {
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id]);
    return rows.single;
  }

  group('survivor selection', () {
    test('earliest date_registered wins; ties broken by id', () {
      final group = <Map<String, Object?>>[
        {'id': 'B', 'date_registered': '2026-02-01'},
        {'id': 'C', 'date_registered': '2026-03-01'},
        {'id': 'A', 'date_registered': '2026-01-01'},
      ];
      sortDuplicateCustomersByCanonicalOrder(group);
      expect(group.first['id'], 'A');
    });

    test('identical registrations resolve to the smallest id (deterministic)',
        () {
      final group = <Map<String, Object?>>[
        {'id': 'Z', 'date_registered': '2026-01-01'},
        {'id': 'A', 'date_registered': '2026-01-01'},
        {'id': 'M', 'date_registered': '2026-01-01'},
      ];
      sortDuplicateCustomersByCanonicalOrder(group);
      expect(group.first['id'], 'A');
    });
  });

  group('mergeDuplicateCustomerInto', () {
    test('re-points children, deletes the duplicate, tombstones it', () async {
      final db = await openFixture();
      addTearDown(db.close);

      await insertCustomer(db,
          id: 'A', name: 'ADA', phone: '0801', registered: '2026-01-01');
      await insertCustomer(db,
          id: 'B', name: 'ADA', phone: '0801', registered: '2026-02-01');

      await db.insert('loans',
          {'id': 'L1', 'customer_id': 'B', 'loan_type': 'daily', 'status': 'active'});
      await db.insert('payments', {
        'id': 'P1', 'loan_id': 'L1', 'customer_id': 'B',
      });
      await db.insert('documents', {
        'id': 'D1', 'customer_id': 'B', 'file_path': '/x.enc', 'mime_type': 'application/pdf',
      });

      final b = await query(db, 'customers', 'B');
      final a = await query(db, 'customers', 'A');
      await mergeDuplicateCustomerInto(db, b, a);

      expect((await query(db, 'loans', 'L1'))['customer_id'], 'A');
      expect((await query(db, 'payments', 'P1'))['customer_id'], 'A');
      expect((await query(db, 'documents', 'D1'))['customer_id'], 'A');

      // Re-points are stamped so they are captured by the push snapshot.
      expect((await query(db, 'loans', 'L1'))['updated_at'] as String?, isNotEmpty);

      // The duplicate is gone and its removal is tombstoned for replication.
      expect(await db.query('customers', where: 'id = ?', whereArgs: ['B']),
          isEmpty);
      final tombstones = await db.query('sync_tombstones',
          where: 'deleted_table = ? AND deleted_row_id = ?',
          whereArgs: ['customers', 'B']);
      expect(tombstones, hasLength(1));
    });

    test('folds the duplicate savings balance when both hold an account',
        () async {
      final db = await openFixture();
      addTearDown(db.close);

      await insertCustomer(db,
          id: 'A', name: 'ADA', phone: '0801', registered: '2026-01-01');
      await insertCustomer(db,
          id: 'B', name: 'ADA', phone: '0801', registered: '2026-02-01');

      await db.insert('savings_accounts', {
        'id': 'SA_A', 'customer_id': 'A', 'balance': 500.0, 'created_at': '2026-01-01',
      });
      await db.insert('savings_accounts', {
        'id': 'SA_B', 'customer_id': 'B', 'balance': 250.0, 'created_at': '2026-02-01',
      });
      await db.insert('savings_transactions', {
        'id': 'T1', 'savings_account_id': 'SA_B', 'type': 'deposit',
        'amount': 250.0, 'created_at': '2026-02-01',
      });

      final b = await query(db, 'customers', 'B');
      final a = await query(db, 'customers', 'A');
      await mergeDuplicateCustomerInto(db, b, a);

      final survivorAccount = await query(db, 'savings_accounts', 'SA_A');
      expect(survivorAccount['balance'], 750.0);
      expect((await query(db, 'savings_transactions', 'T1'))['savings_account_id'],
          'SA_A');
      expect(await db.query('savings_accounts', where: 'id = ?', whereArgs: ['SA_B']),
          isEmpty);

      // Both deletions are tombstoned so the cloud drops the extra account.
      final tombstones = await db.query('sync_tombstones',
          where: 'deleted_row_id = ?', whereArgs: ['SA_B']);
      expect(tombstones, hasLength(1));
    });

    test('re-points the duplicate account when the survivor has none', () async {
      final db = await openFixture();
      addTearDown(db.close);

      await insertCustomer(db,
          id: 'A', name: 'ADA', phone: '0801', registered: '2026-01-01');
      await insertCustomer(db,
          id: 'B', name: 'ADA', phone: '0801', registered: '2026-02-01');
      await db.insert('savings_accounts', {
        'id': 'SA_B', 'customer_id': 'B', 'balance': 250.0, 'created_at': '2026-02-01',
      });

      final b = await query(db, 'customers', 'B');
      final a = await query(db, 'customers', 'A');
      await mergeDuplicateCustomerInto(db, b, a);

      final account = await query(db, 'savings_accounts', 'SA_B');
      expect(account['customer_id'], 'A');
      expect(account['balance'], 250.0);
    });

    test('fills NULL profile fields and group; never overwrites existing data',
        () async {
      final db = await openFixture();
      addTearDown(db.close);

      await db.insert('customer_groups', {'id': 'G1', 'name': 'MARKET'});
      await db.insert('customer_groups', {'id': 'G2', 'name': 'FISHERS'});
      await insertCustomer(db,
          id: 'A',
          name: 'ADA',
          phone: '0801',
          registered: '2026-01-01',
          groupId: 'G1',
          email: 'a@x.com');
      await insertCustomer(db,
          id: 'B',
          name: 'ADA',
          phone: '0801',
          registered: '2026-02-01',
          groupId: 'G2',
          email: 'b@y.com');

      final b = await query(db, 'customers', 'B');
      final a = await query(db, 'customers', 'A');
      await mergeDuplicateCustomerInto(db, b, a);

      final survivor = await query(db, 'customers', 'A');
      expect(survivor['group_id'], 'G1'); // never overwritten
      expect(survivor['email'], 'a@x.com'); // never overwritten
      expect(survivor['notes'], isNull); // B had nothing worth copying
    });

    test('copies nin/bvn only when no other non-archived customer holds them',
        () async {
      final db = await openFixture();
      addTearDown(db.close);

      await insertCustomer(db,
          id: 'A', name: 'ADA', phone: '0801', registered: '2026-01-01');
      await insertCustomer(db,
          id: 'B', name: 'ADA', phone: '0801', registered: '2026-02-01', nin: '11111111111');
      // C holds the same NIN under a different phone — the copy must be skipped
      // or the v21 partial unique index rejects it.
      await insertCustomer(db,
          id: 'C', name: 'CHI', phone: '0802', registered: '2026-01-01', nin: '11111111111');

      final b = await query(db, 'customers', 'B');
      final a = await query(db, 'customers', 'A');
      await mergeDuplicateCustomerInto(db, b, a);

      expect((await query(db, 'customers', 'A'))['nin'], isNull);
    });

    test('copies nin when the survivor has none and no clash exists', () async {
      final db = await openFixture();
      addTearDown(db.close);

      await insertCustomer(db,
          id: 'A', name: 'ADA', phone: '0801', registered: '2026-01-01');
      await insertCustomer(db,
          id: 'B', name: 'ADA', phone: '0801', registered: '2026-02-01', nin: '22222222222');

      final b = await query(db, 'customers', 'B');
      final a = await query(db, 'customers', 'A');
      await mergeDuplicateCustomerInto(db, b, a);

      expect((await query(db, 'customers', 'A'))['nin'], '22222222222');
    });

    test('is a no-op when duplicate and survivor are the same record', () async {
      final db = await openFixture();
      addTearDown(db.close);

      await insertCustomer(db,
          id: 'A', name: 'ADA', phone: '0801', registered: '2026-01-01');
      final a = await query(db, 'customers', 'A');
      await mergeDuplicateCustomerInto(db, a, a);

      expect(await db.query('customers', where: 'id = ?', whereArgs: ['A']),
          hasLength(1));
      expect(await db.query('sync_tombstones'), isEmpty);
    });
  });
}
