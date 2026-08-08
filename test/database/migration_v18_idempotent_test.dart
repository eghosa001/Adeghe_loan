import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Guards the v18 idempotency fix: an early build shipped the fresh-install
/// DDL with `payments.client_request_id` already present while the schema
/// version was still 17, so databases created by that build reached v18 with
/// the column already in place and the bare `ALTER TABLE ... ADD COLUMN` threw
/// "duplicate column name", rolling the upgrade back on every launch. v18 must
/// now detect an existing column and skip the ALTER instead of crashing.
void main() {
  sqfliteFfiInit();

  /// Creates a version-17 database with the v18-era `payments` table, closes
  /// it, then reopens it as version 18 through the same `onUpgrade` path the
  /// app uses — sqflite bumps `user_version` only when the migration completes.
  Future<Database> migrateWithUpgrade({required bool columnPresent}) async {
    final dir = await Directory.systemTemp.createTemp('v18_idempotent');
    final path = '${dir.path}${Platform.pathSeparator}test.db';

    final initial = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(version: 17));
    await initial.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        loan_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_date TEXT NOT NULL,
        receipt_no TEXT UNIQUE NOT NULL,
        status TEXT NOT NULL DEFAULT 'completed',
        ${columnPresent ? 'client_request_id TEXT,' : ''}
        updated_at TEXT
      )
    ''');
    await initial.close();

    final upgraded = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
      version: 18,
      onUpgrade: (db, oldVersion, newVersion) async {
        await DatabaseMigrations.run(db, oldVersion, newVersion);
      },
    ));
    addTearDown(() async {
      await upgraded.close();
      await dir.delete(recursive: true);
    });
    return upgraded;
  }

  Future<bool> hasClientRequestId(Database db) async {
    final rows = await db.rawQuery('PRAGMA table_info(payments)');
    return rows.any((c) => c['name'] == 'client_request_id');
  }

  test('v18 upgrade completes when client_request_id already exists', () async {
    final db = await migrateWithUpgrade(columnPresent: true);

    // The exact failure path from the field: the column exists but the stored
    // schema version was 17, so v18 is the next pending migration. It must
    // skip the ALTER and let the upgrade (and version bump) finish.
    expect(await db.getVersion(), 18);
    expect(await hasClientRequestId(db), isTrue);
  });

  test('v18 still adds client_request_id when it is missing', () async {
    final db = await migrateWithUpgrade(columnPresent: false);

    expect(await db.getVersion(), 18);
    expect(await hasClientRequestId(db), isTrue);
  });
}
