import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/di/providers.dart';
import 'package:loantrack/features/holidays/data/holiday_repository.dart';
import 'package:loantrack/features/holidays/data/models/holiday_entity.dart';

final holidayRepositoryProvider = FutureProvider<HolidayRepository>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return HolidayRepositoryImpl(dbService);
});

final holidayListProvider = FutureProvider<List<Holiday>>((ref) async {
  final repo = await ref.watch(holidayRepositoryProvider.future);
  final result = await repo.getHolidays();
  return result.when(
    success: (holidays) => holidays,
    failure: (failure) => throw failure,
  );
});
