import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show OpenDatabaseOptions, databaseFactoryFfi, inMemoryDatabasePath, sqfliteFfiInit;
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

/// Validates the v21 customers table-recreate migration:
///  * the column-level `phone UNIQUE` constraint is dropped and replaced by a
///    PARTIAL unique index (`WHERE status != 'archived'`)
///  * re-registering a customer whose phone matches an ARCHIVED customer no
///    longer hits `UNIQUE constraint failed` (the bug: the repository check
///    deliberately excludes archived rows, but the table constraint still
///    blocked the INSERT with a generic "Unable to save customer")
///  * a duplicate of a NON-archived customer is still rejected
///  * no customer column is lost in the recreate
void main() {
  sqfliteFfiInit();

  Future<Database> openV20Database() async {
    final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath, options: OpenDatabaseOptions(version: 20));
    await db.execute(
        'CREATE TABLE customer_groups (id TEXT PRIMARY KEY, name TEXT NOT NULL)');
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        passport_path TEXT,
        full_name TEXT NOT NULL,
        gender TEXT,
        dob TEXT,
        phone TEXT UNIQUE NOT NULL,
        alt_phone TEXT,
        email TEXT,
        residential_address TEXT,
        business_address TEXT,
        occupation TEXT,
        employer TEXT,
        marital_status TEXT,
        nationality TEXT,
        state TEXT,
        lga TEXT,
        next_of_kin TEXT,
        next_of_kin_relation TEXT,
        next_of_kin_phone TEXT,
        guarantor_1_name TEXT,
        guarantor_1_phone TEXT,
        guarantor_1_address TEXT,
        guarantor_2_name TEXT,
        guarantor_2_phone TEXT,
        guarantor_2_address TEXT,
        guarantor_passport_path TEXT,
        nin TEXT,
        bvn TEXT,
        id_type TEXT,
        id_number TEXT,
        signature_path TEXT,
        date_registered TEXT NOT NULL,
        notes TEXT,
        status TEXT NOT NULL,
        credit_score REAL DEFAULT 0.0,
        group_id TEXT,
        updated_at TEXT
      )
    ''');
    // The v17 bookkeeping tables the recreated change-tracking triggers
    // reference (on a real upgrade v17 runs before v21, so they exist).
    await db.execute(
        'CREATE TABLE sync_flags (key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('''
      CREATE TABLE sync_tombstones (
        deleted_table TEXT NOT NULL,
        deleted_row_id TEXT NOT NULL,
        deleted_at TEXT NOT NULL,
        PRIMARY KEY (deleted_table, deleted_row_id)
      )
    ''');
    return db;
  }

  Future<Set<String>> tableColumns(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name'] as String).toSet();
  }

  test('v21 allows re-registering a phone used by an archived customer', () async {
    final db = await openV20Database();
    addTearDown(db.close);

    await db.insert('customers', {
      'id': 'A', 'full_name': 'Active Ada', 'phone': '0801',
      'date_registered': '2026-01-01', 'status': 'active',
    });
    await db.insert('customers', {
      'id': 'B', 'full_name': 'Archived Bob', 'phone': '0802',
      'date_registered': '2026-01-01', 'status': 'archived',
    });

    await DatabaseMigrations.run(db, 20, 21);

    // Duplicate of the ARCHIVED customer's phone must now be accepted.
    await db.insert('customers', {
      'id': 'C', 'full_name': 'Bob Again', 'phone': '0802',
      'date_registered': '2026-02-01', 'status': 'active',
    });

    // Duplicate of a NON-archived customer's phone must still be rejected.
    await expectLater(
      db.insert('customers', {
        'id': 'D', 'full_name': 'Ada Twice', 'phone': '0801',
        'date_registered': '2026-02-01', 'status': 'active',
      }),
      throwsA(isA<dynamic>()),
    );
  });

  test('v21 preserves every customer column and installs the partial index',
      () async {
    final db = await openV20Database();
    addTearDown(db.close);
    await db.insert('customers', {
      'id': 'A', 'full_name': 'Ada', 'phone': '0801',
      'date_registered': '2026-01-01', 'status': 'active', 'credit_score': 5.0,
    });

    await DatabaseMigrations.run(db, 20, 21);

    final columns = await tableColumns(db, 'customers');
    const expected = {
      'id', 'passport_path', 'full_name', 'gender', 'dob', 'phone', 'alt_phone',
      'email', 'residential_address', 'business_address', 'occupation',
      'employer', 'marital_status', 'nationality', 'state', 'lga',
      'next_of_kin', 'next_of_kin_relation', 'next_of_kin_phone',
      'guarantor_1_name', 'guarantor_1_phone', 'guarantor_1_address',
      'guarantor_2_name', 'guarantor_2_phone', 'guarantor_2_address',
      'guarantor_passport_path', 'nin', 'bvn', 'id_type', 'id_number',
      'signature_path', 'date_registered', 'notes', 'status', 'credit_score',
      'group_id', 'updated_at',
    };
    expect(columns, expected);

    final indexRows = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'idx_customers_phone_unique'");
    expect(indexRows, hasLength(1));
    final indexSql = indexRows.first['sql'] as String;
    expect(indexSql.toLowerCase(), contains("where status != 'archived'"));
  });

  test('v21 recreates the customer change-tracking triggers lost by DROP TABLE',
      () async {
    final db = await openV20Database();
    addTearDown(db.close);

    await DatabaseMigrations.run(db, 20, 21);

    // The DROP TABLE customers in v21 used to destroy trg_customers_ins/upd/del.
    for (final name in const ['ins', 'upd', 'del']) {
      final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name = 'trg_customers_$name'");
      expect(rows, hasLength(1), reason: 'trg_customers_$name missing after v21');
    }

    // Behavior: an insert still stamps `updated_at` and a delete still records
    // a tombstone, so customer sync keeps working on upgraded devices.
    await db.insert('customers', {
      'id': 'A', 'full_name': 'Ada', 'phone': '0801',
      'date_registered': '2026-01-01', 'status': 'active',
    });
    final stamped = await db.query('customers',
        columns: ['updated_at'], where: 'id = ?', whereArgs: ['A']);
    expect((stamped.first['updated_at'] as String?)?.isNotEmpty, isTrue);

    await db.delete('customers', where: 'id = ?', whereArgs: ['A']);
    final tombstones = await db.query('sync_tombstones');
    expect(tombstones, hasLength(1));
    expect(tombstones.first['deleted_table'], 'customers');
    expect(tombstones.first['deleted_row_id'], 'A');
  });
}
