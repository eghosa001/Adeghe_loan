import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Guards the M14 fix: the DB connection is memoized so concurrent callers can
/// never double-open the same SQLite file, and a backup/restore's exclusive
/// close -> swap -> reopen cycle gates any concurrent [DatabaseService.database]
/// access so no one opens a half-swapped file.
void main() {
  sqfliteFfiInit();

  DatabaseService serviceWithOpen(
      Future<Database> Function() open, void Function(int) onOpens) {
    var opens = 0;
    Future<Database> countingOpen() async {
      opens++;
      onOpens(opens);
      final db = await open();
      await db.execute('CREATE TABLE IF NOT EXISTS t (id INTEGER)');
      return db;
    }

    return DatabaseService.withOpenOverride(SecureStorageService(), countingOpen);
  }

  test('concurrent database callers share one open (no double-open)', () async {
    var opens = 0;
    final service = serviceWithOpen(
        () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
        (n) => opens = n);
    addTearDown(service.close);

    final results =
        await Future.wait([service.database, service.database, service.database]);

    expect(opens, 1,
        reason: 'three concurrent callers must share a single in-flight open');
    expect(results[0], same(results[1]));
    expect(results[1], same(results[2]));
    expect(await service.database, same(results[0]),
        reason: 'memo persists for later callers too');
  });

  test('withExclusiveAccess gates concurrent access and reopens exactly once',
      () async {
    var opens = 0;
    final service = serviceWithOpen(
        () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
        (n) => opens = n);
    addTearDown(service.close);

    await service.database;
    expect(opens, 1);

    // Start an exclusive block that closes the DB and holds it closed.
    final entered = Completer<void>();
    final release = Completer<void>();
    final exclusive = service.withExclusiveAccess(() async {
      entered.complete();
      await release.future;
      return 'done';
    });

    await entered.future;

    // While the DB is closed, a concurrent caller must wait, not open a
    // second connection to the live file.
    final waiting = service.database;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(opens, 1,
        reason: 'database must not reopen while exclusive access holds it');

    release.complete();
    expect(await exclusive, 'done');

    final second = await waiting;
    expect(second, isNotNull);
    expect(opens, 2,
        reason: 'the database reopens exactly once after the exclusive block');
    expect(await service.database, same(second),
        reason: 'the waiting caller and later callers share the reopened DB');
  });

  test('close invalidates the memo so the next access reopens', () async {
    var opens = 0;
    final service = serviceWithOpen(
        () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
        (n) => opens = n);
    addTearDown(service.close);

    final first = await service.database;
    await service.close();
    final second = await service.database;

    expect(opens, 2);
    expect(second, isNot(same(first)));
  });

  test('a failed open does not poison the memo forever', () async {
    var fail = true;
    final service = DatabaseService.withOpenOverride(
      SecureStorageService(),
      () async {
        if (fail) throw Exception('open failed');
        return databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      },
    );
    addTearDown(service.close);

    await expectLater(service.database, throwsException);

    fail = false;
    final db = await service.database;
    expect(db, isNotNull,
        reason: 'a later call must retry after the first open failed');
  });
}
