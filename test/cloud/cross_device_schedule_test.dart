import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/di/providers.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/features/loans/data/loan_schedule_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show
        OpenDatabaseOptions,
        databaseFactoryFfi,
        inMemoryDatabasePath,
        sqfliteFfiInit;
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

/// Verifies the cross-device contract of the derived `repayment_schedule`
/// cache: two devices holding byte-identical synced source data must derive
/// byte-identical schedules (deterministic ids, due dates, statuses), the
/// payment INSERTION ORDER must not change the derivation, and the production
/// `onPullComplete` wiring (`providers.dart`) must rebuild schedules after a
/// pull writes new payments.
class _FakeDatabaseService extends DatabaseService {
  _FakeDatabaseService(this._db) : super(SecureStorageService());

  final Database _db;

  @override
  Future<Database> get database async => _db;
}

void main() {
  sqfliteFfiInit();

  Future<Database> openDb() async {
    // `singleInstance: false` gives each open its own connection, so the
    // second `:memory:` database is truly independent (otherwise sqflite
    // returns the same connection and the duplicate CREATE fails).
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('''
      CREATE TABLE loans (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        loan_type TEXT NOT NULL,
        status TEXT NOT NULL,
        amount REAL NOT NULL,
        interest_rate REAL NOT NULL,
        duration_days INTEGER,
        duration_weeks INTEGER,
        start_date TEXT NOT NULL,
        total_repayment REAL NOT NULL,
        outstanding_balance REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE repayment_schedule (
        id TEXT PRIMARY KEY,
        loan_id TEXT NOT NULL,
        installment_number INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        amount REAL NOT NULL,
        status TEXT NOT NULL,
        paid_amount REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE holidays (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        date TEXT NOT NULL,
        is_recurring INTEGER NOT NULL,
        is_enabled INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        loan_id TEXT NOT NULL,
        status TEXT NOT NULL,
        amount REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE savings_transactions (
        id TEXT PRIMARY KEY,
        reference_loan_payment_id TEXT,
        type TEXT NOT NULL,
        amount REAL NOT NULL
      )
    ''');
    return db;
  }

  Future<void> insertLoan(Database db) async {
    await db.insert('loans', {
      'id': 'L1',
      'customer_id': 'C1',
      'loan_type': 'weekly',
      'status': 'active',
      'amount': 4000.0,
      'interest_rate': 10.0,
      'duration_weeks': 4,
      'start_date': '2026-08-03',
      'total_repayment': 4000.0,
      'outstanding_balance': 4000.0,
    });
  }

  Future<void> seedPayments(Database db, {bool reverseOrder = false}) async {
    final payments = [
      {
        'id': 'P1',
        'loan_id': 'L1',
        'status': 'completed',
        'amount': 1000.0,
      },
      {
        'id': 'P2',
        'loan_id': 'L1',
        'status': 'completed',
        'amount': 1500.0,
      },
      {
        'id': 'P3',
        'loan_id': 'L1',
        'status': 'completed',
        'amount': 750.0,
      },
    ];
    final ordered = reverseOrder ? payments.reversed.toList() : payments;
    for (final payment in ordered) {
      await db.insert('payments', payment);
    }
    // P2's 500 overpayment surplus went to savings and never touched the loan.
    await db.insert('savings_transactions', {
      'id': 'ST1',
      'reference_loan_payment_id': 'P2',
      'type': 'overpayment',
      'amount': 500.0,
    });
  }

  Future<void> seedHoliday(Database db) async {
    await db.insert('holidays', {
      'id': 'H1',
      'name': 'Sallah',
      'date': '2026-08-17',
      'is_recurring': 0,
      'is_enabled': 1,
    });
  }

  Future<List<Map<String, Object?>>> scheduleRows(Database db) async {
    return db.query('repayment_schedule',
        where: 'loan_id = ?',
        whereArgs: ['L1'],
        orderBy: 'installment_number ASC');
  }

  List<List<Object?>> scheduleProjection(List<Map<String, Object?>> rows) {
    return rows
        .map((r) => [
              r['id'],
              r['installment_number'],
              r['due_date'],
              r['status'],
              r['paid_amount'],
            ])
        .toList();
  }

  test('two devices with identical source data derive identical schedules',
      () async {
    final dbA = await openDb();
    final dbB = await openDb();
    addTearDown(dbA.close);
    addTearDown(dbB.close);

    for (final db in [dbA, dbB]) {
      await insertLoan(db);
      await seedHoliday(db);
      await seedPayments(db);
    }

    final serviceA =
        LoanScheduleService(_FakeDatabaseService(dbA), LoanScheduleVersionNotifier());
    final serviceB =
        LoanScheduleService(_FakeDatabaseService(dbB), LoanScheduleVersionNotifier());
    await serviceA.rebuildAllSchedules();
    await serviceB.rebuildAllSchedules();

    final rowsA = await scheduleRows(dbA);
    final rowsB = await scheduleRows(dbB);
    expect(scheduleProjection(rowsB), scheduleProjection(rowsA));
    expect(rowsA, hasLength(4));
  });

  test('payment insertion order never changes the derived schedule', () async {
    final dbA = await openDb();
    final dbB = await openDb();
    addTearDown(dbA.close);
    addTearDown(dbB.close);

    await insertLoan(dbA);
    await seedHoliday(dbA);
    await seedPayments(dbA); // P1, P2, P3

    await insertLoan(dbB);
    await seedHoliday(dbB);
    await seedPayments(dbB, reverseOrder: true); // P3, P2, P1

    final serviceA =
        LoanScheduleService(_FakeDatabaseService(dbA), LoanScheduleVersionNotifier());
    final serviceB =
        LoanScheduleService(_FakeDatabaseService(dbB), LoanScheduleVersionNotifier());
    await serviceA.rebuildAllSchedules();
    await serviceB.rebuildAllSchedules();

    expect(scheduleProjection(await scheduleRows(dbB)),
        scheduleProjection(await scheduleRows(dbA)));

    // Sanity: the surplus was excluded and the money allocated oldest-first —
    // 2750 applied: 1000 + 1000 + 750(partial), last installment pending.
    final rowsA = await scheduleRows(dbA);
    expect(rowsA[0]['status'], 'paid');
    expect(rowsA[0]['paid_amount'], 1000.0);
    expect(rowsA[1]['status'], 'paid');
    expect(rowsA[1]['paid_amount'], 1000.0);
    expect(rowsA[2]['status'], 'partial');
    expect(rowsA[2]['paid_amount'], 750.0);
    expect(rowsA[3]['status'], 'pending');
  });

  test('the onPullComplete wiring rebuilds schedules after a pull', () async {
    final db = await openDb();
    addTearDown(db.close);
    await insertLoan(db);

    final fake = _FakeDatabaseService(db);
    final container = ProviderContainer(overrides: [
      databaseServiceProvider.overrideWith((ref) async => fake),
    ]);
    addTearDown(container.dispose);

    // Pull writes a payment into the loan (as a remote row would).
    await db.insert('payments', {
      'id': 'P1',
      'loan_id': 'L1',
      'status': 'completed',
      'amount': 1000.0,
    });

    final sync = await container.read(cloudSyncServiceProvider.future);
    expect(container.read(loanScheduleVersionProvider), 0);

    await sync.onPullComplete?.call();

    expect(container.read(loanScheduleVersionProvider), 1);
    final rows = await scheduleRows(db);
    expect(rows, hasLength(4));
    expect(rows[0]['status'], 'paid');
    expect(rows[0]['paid_amount'], 1000.0);
    expect(rows[1]['status'], 'pending');
  });
}
