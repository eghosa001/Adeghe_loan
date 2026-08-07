import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/features/loans/data/loan_schedule_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, inMemoryDatabasePath, sqfliteFfiInit;
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

/// Verifies the schedule cache converges when a payment write races a rebuild —
/// the real-world shape of a payment recorded while a cloud pull is running
/// `rebuildAllSchedules()` (providers.dart `onPullComplete`). The schedule is a
/// derived cache: concurrent writers may interleave, but a subsequent rebuild is
/// a pure function of the final source rows, so the cache must converge exactly
/// on the money rule (completed payments minus overpayment surplus) with no
/// partial/duplicate rows left behind.
class _FakeDatabaseService extends DatabaseService {
  _FakeDatabaseService(this._db) : super(SecureStorageService());

  final Database _db;

  @override
  Future<Database> get database async => _db;
}

void main() {
  sqfliteFfiInit();

  Future<Database> openDb() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
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

  test('a payment racing a schedule rebuild still converges to the money rule',
      () async {
    final db = await openDb();
    addTearDown(db.close);

    await db.insert('loans', {
      'id': 'L1',
      'customer_id': 'C1',
      'loan_type': 'daily',
      'status': 'active',
      'amount': 5000.0,
      'interest_rate': 10.0,
      'duration_days': 5,
      'start_date': '2026-08-03',
      'total_repayment': 5000.0,
      'outstanding_balance': 5000.0,
    });

    final service = LoanScheduleService(
        _FakeDatabaseService(db), LoanScheduleVersionNotifier());

    // Interleave rebuilds with payment writes, as a payment recorded mid-pull
    // would. Each write races the others and the rebuilds.
    final writes = <Future<void>>[];
    for (var i = 1; i <= 3; i++) {
      writes.add(db.insert('payments', {
        'id': 'P$i',
        'loan_id': 'L1',
        'status': 'completed',
        'amount': 1000.0,
      }));
    }
    // P4 is a 2500 payment: 2000 to the loan + 500 overpayment surplus.
    writes.add(db.insert('payments', {
      'id': 'P4',
      'loan_id': 'L1',
      'status': 'completed',
      'amount': 2500.0,
    }));
    writes.add(db.insert('savings_transactions', {
      'id': 'ST4',
      'reference_loan_payment_id': 'P4',
      'type': 'overpayment',
      'amount': 500.0,
    }));
    final rebuilds = <Future<void>>[
      for (var i = 0; i < 5; i++) service.rebuildAllSchedules(),
    ];

    await Future.wait([...writes, ...rebuilds]);

    // A final rebuild (what another device would do) converges exactly on the
    // source of truth: 1000+1000+1000+2000 = 5000 applied, all five paid.
    await service.rebuildAllSchedules();
    final rows = await db.query('repayment_schedule',
        where: 'loan_id = ?',
        whereArgs: ['L1'],
        orderBy: 'installment_number ASC');

    expect(rows, hasLength(5)); // Exactly one row per installment, no dupes.
    var applied = 0.0;
    for (final row in rows) {
      expect(row['id'], startsWith('L1-'));
      expect(row['status'], 'paid');
      expect(row['paid_amount'], row['amount']);
      applied += (row['paid_amount'] as num).toDouble();
    }
    expect(applied, 5000.0);
  });
}
