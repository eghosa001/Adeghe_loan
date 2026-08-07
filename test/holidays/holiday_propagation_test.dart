import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/features/holidays/data/holiday_repository.dart';
import 'package:loantrack/features/holidays/data/models/holiday_entity.dart';
import 'package:loantrack/features/loans/data/loan_schedule_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, inMemoryDatabasePath, sqfliteFfiInit;
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

/// Exercises the full holiday-change propagation path used by the holiday
/// management screen — `HolidayRepository.saveHoliday` then
/// `LoanScheduleService.rebuildAllSchedules()` — against a real SQLite engine:
///  * an enabled holiday shifts due dates past the holiday
///  * toggling `is_enabled` off reverts the schedule (dates shift back)
///  * a recurring holiday only skips when its month/day matches
///  * a weekly holiday shifts only the affected installment; the next
///    installment resumes the anchor weekday
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

  Future<void> insertLoan(
    Database db, {
    required String id,
    required String type,
    required String startDate,
    int? durationDays,
    int? durationWeeks,
  }) async {
    await db.insert('loans', {
      'id': id,
      'customer_id': 'C1',
      'loan_type': type,
      'status': 'active',
      'amount': 3000.0,
      'interest_rate': 10.0,
      'duration_days': durationDays,
      'duration_weeks': durationWeeks,
      'start_date': startDate,
      'total_repayment': 3000.0,
      'outstanding_balance': 3000.0,
    });
  }

  Future<List<Map<String, Object?>>> dueDates(Database db, String loanId) async {
    final rows = await db.query('repayment_schedule',
        where: 'loan_id = ?',
        whereArgs: [loanId],
        orderBy: 'installment_number ASC');
    return rows;
  }

  test('enabled holiday shifts due dates; disabling reverts them', () async {
    final db = await openDb();
    addTearDown(db.close);

    await insertLoan(db,
        id: 'L1', type: 'daily', startDate: '2026-08-10', durationDays: 3);
    final repo = HolidayRepositoryImpl(_FakeDatabaseService(db));
    final service = LoanScheduleService(
        _FakeDatabaseService(db), LoanScheduleVersionNotifier());

    // Baseline: Mon 08-10, Tue 08-11, Wed 08-12.
    await service.rebuildAllSchedules();
    var dates = (await dueDates(db, 'L1')).map((r) => r['due_date']);
    expect(dates, ['2026-08-10', '2026-08-11', '2026-08-12']);

    // Add an enabled holiday on the Tuesday — the Tuesday installment shifts to
    // Wednesday, pushing Wednesday's to Thursday.
    final h1 = Holiday(
        id: 'H1', name: 'Public Holiday', date: DateTime(2026, 8, 11));
    final save = await repo.saveHoliday(h1);
    expect(save.isSuccess, isTrue);
    await service.rebuildAllSchedules();

    dates = (await dueDates(db, 'L1')).map((r) => r['due_date']);
    expect(dates, ['2026-08-10', '2026-08-12', '2026-08-13']);

    // Disable the holiday — the schedule reverts to the original dates.
    final disable = await repo.saveHoliday(h1.copyWith(isEnabled: false));
    expect(disable.isSuccess, isTrue);
    await service.rebuildAllSchedules();

    dates = (await dueDates(db, 'L1')).map((r) => r['due_date']);
    expect(dates, ['2026-08-10', '2026-08-11', '2026-08-12']);
  });

  test('a recurring holiday only skips when its month/day matches', () async {
    final db = await openDb();
    addTearDown(db.close);

    final repo = HolidayRepositoryImpl(_FakeDatabaseService(db));
    final service = LoanScheduleService(
        _FakeDatabaseService(db), LoanScheduleVersionNotifier());

    // Recurring holiday on 11 August.
    final recurring =
        Holiday(id: 'H1', name: 'Eid', date: DateTime(2026, 8, 11), isRecurring: true);
    await repo.saveHoliday(recurring);

    // A daily loan running across 11 August skips it.
    await insertLoan(db,
        id: 'L1', type: 'daily', startDate: '2026-08-10', durationDays: 3);
    // A daily loan in September shares the schedule space; its dates never
    // collide with the August holiday.
    await insertLoan(db,
        id: 'L2', type: 'daily', startDate: '2026-09-01', durationDays: 3);

    await service.rebuildAllSchedules();

    var dates = (await dueDates(db, 'L1')).map((r) => r['due_date']);
    expect(dates, ['2026-08-10', '2026-08-12', '2026-08-13']);

    dates = (await dueDates(db, 'L2')).map((r) => r['due_date']);
    expect(dates, ['2026-09-01', '2026-09-02', '2026-09-03']);
  });

  test('a weekly holiday shifts only the affected installment; the next '
      'resumes the anchor weekday', () async {
    final db = await openDb();
    addTearDown(db.close);

    await insertLoan(db,
        id: 'L1', type: 'weekly', startDate: '2026-08-10', durationWeeks: 3);
    final repo = HolidayRepositoryImpl(_FakeDatabaseService(db));
    final service = LoanScheduleService(
        _FakeDatabaseService(db), LoanScheduleVersionNotifier());

    await service.rebuildAllSchedules();
    var dates = (await dueDates(db, 'L1')).map((r) => r['due_date']);
    expect(dates, ['2026-08-10', '2026-08-17', '2026-08-24']);

    // Holiday on Monday 08-17: installment 2 shifts to Tuesday 08-18, but
    // installment 3 returns to the Monday anchor 08-24.
    await repo.saveHoliday(
        Holiday(id: 'H1', name: 'Sallah', date: DateTime(2026, 8, 17)));
    await service.rebuildAllSchedules();

    dates = (await dueDates(db, 'L1')).map((r) => r['due_date']);
    expect(dates, ['2026-08-10', '2026-08-18', '2026-08-24']);
  });
}
