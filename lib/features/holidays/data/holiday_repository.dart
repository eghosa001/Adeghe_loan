import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/error/failure.dart';
import 'package:loantrack/core/utils/date_utils.dart';
import 'package:loantrack/features/holidays/data/models/holiday_entity.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

abstract class HolidayRepository {
  Future<Result<List<Holiday>>> getHolidays();
  Future<Result<void>> saveHoliday(Holiday holiday);
  Future<Result<void>> deleteHoliday(String holidayId);
}

class HolidayRepositoryImpl implements HolidayRepository {
  final DatabaseService _dbService;

  HolidayRepositoryImpl(this._dbService);

  @override
  Future<Result<void>> deleteHoliday(String holidayId) async {
    try {
      final db = await _dbService.database;
      await db.delete('holidays', where: 'id = ?', whereArgs: [holidayId]);
      return const Result.success(null);
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to delete holiday.', cause: e));
    }
  }

  @override
  Future<Result<List<Holiday>>> getHolidays() async {
    try {
      final db = await _dbService.database;
      final maps = await db.query('holidays', orderBy: 'date ASC');
      final holidays = maps.map((map) => Holiday.fromMap(map)).toList();
      return Result.success(holidays);
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to load holidays.', cause: e));
    }
  }

  @override
  Future<Result<void>> saveHoliday(Holiday holiday) async {
    try {
      final db = await _dbService.database;
      final dateStr = AppDateUtils.formatForStorage(holiday.date);
      final existing = await db.query(
        'holidays',
        where: 'date = ? AND is_recurring = ?',
        whereArgs: [dateStr, holiday.isRecurring ? 1 : 0],
      );
      for (final row in existing) {
        if (row['id'] as String != holiday.id) {
          return Result.failure(ValidationFailure(
              'A holiday already exists on ${AppDateUtils.formatDate(holiday.date)}.'));
        }
      }
      await db.insert(
        'holidays',
        holiday.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return const Result.success(null);
    } on DatabaseException catch (e) {
      return Result.failure(DatabaseFailure('Failed to save holiday.', cause: e));
    }
  }
}
