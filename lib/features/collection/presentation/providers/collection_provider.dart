import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/collection_repository.dart';
import '../../data/models/collection_row.dart';
import '../../data/models/weekly_collection_row.dart';

final collectionRepositoryProvider = FutureProvider<CollectionRepository>(
    (ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return CollectionRepository(dbService);
});

final collectionDateFilterProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// When true, the collection screen uses a date range instead of a single date.
final collectionDateRangeModeProvider = StateProvider<bool>((ref) => false);

/// Start date for date range mode.
final collectionRangeStartProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

/// End date for date range mode.
final collectionRangeEndProvider = StateProvider<DateTime>((ref) {
  return DateTime.now();
});

final collectionSearchQueryProvider = StateProvider<String>((ref) => '');

/// Null means "all groups"; a non-null value filters by that group ID.
final collectionGroupFilterProvider = StateProvider<String?>((ref) => null);

enum CollectionSortBy { name, amountDue, amountPaid, outstanding, paymentDay }

final collectionSortByProvider =
    StateProvider<CollectionSortBy>((ref) => CollectionSortBy.name);

final futureScheduleProvider = FutureProvider<List<CollectionRow>>((ref) async {
  final repo = await ref.watch(collectionRepositoryProvider.future);
  final result = await repo.getFutureSchedule(daysAhead: 30);
  return result.when(
    success: (rows) => rows,
    failure: (f) => throw f,
  );
});

/// The Daily Collection list. Pinned to `loanType: 'daily'` so a weekly loan
/// can never appear on the Daily Collection screen — the shared
/// [CollectionRepository] queries stay loan-type aware (the collection report
/// still filters by type) but this provider is strictly daily.
final collectionListProvider = FutureProvider<List<CollectionRow>>((ref) async {
  final repo = await ref.watch(collectionRepositoryProvider.future);
  final isRange = ref.watch(collectionDateRangeModeProvider);
  final groupId = ref.watch(collectionGroupFilterProvider);
  final sortBy = ref.watch(collectionSortByProvider);
  final query = ref.watch(collectionSearchQueryProvider);

  final result = isRange
      ? await repo.getCollectionsByDateRange(
          ref.watch(collectionRangeStartProvider),
          ref.watch(collectionRangeEndProvider),
          loanType: 'daily',
          groupId: groupId,
        )
      : await repo.getDailyCollection(
          ref.watch(collectionDateFilterProvider),
          groupId: groupId,
          loanType: 'daily',
        );

  final rows = result.when(
    success: (rows) => rows,
    failure: (f) => throw f,
  );
  final filtered = query.trim().isEmpty
      ? rows
      : rows.where((r) =>
          r.customerName.toLowerCase().contains(query.trim().toLowerCase()))
          .toList();
  switch (sortBy) {
    case CollectionSortBy.name:
      filtered.sort((a, b) => a.customerName.toLowerCase().compareTo(b.customerName.toLowerCase()));
    case CollectionSortBy.amountDue:
      filtered.sort((a, b) => b.amountDue.compareTo(a.amountDue));
    case CollectionSortBy.amountPaid:
      filtered.sort((a, b) => b.amountPaid.compareTo(a.amountPaid));
    case CollectionSortBy.outstanding:
      filtered.sort((a, b) => b.outstandingBalance.compareTo(a.outstandingBalance));
    case CollectionSortBy.paymentDay:
      // Payment day has no meaning for daily loans — fall back to name.
      filtered.sort((a, b) => a.customerName.toLowerCase().compareTo(b.customerName.toLowerCase()));
  }
  return filtered;
});

// ---------------------------------------------------------------------------
// Weekly Collection (independent of the Daily Collection list)
// ---------------------------------------------------------------------------

final weeklyCollectionSearchQueryProvider = StateProvider<String>((ref) => '');

/// Date filter for weekly collection — single date or range.
/// Filters loans by their current installment's due_date.
final weeklyCollectionDateFilterProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// When true, weekly collection uses a date range instead of a single date.
final weeklyCollectionDateRangeModeProvider = StateProvider<bool>((ref) => false);

/// Start date for weekly collection date range mode.
final weeklyCollectionRangeStartProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

/// End date for weekly collection date range mode.
final weeklyCollectionRangeEndProvider = StateProvider<DateTime>((ref) {
  return DateTime.now();
});

/// Weekly list sort key. Reuses [CollectionSortBy]; `amountDue` maps to the
/// next installment's remaining amount for the weekly list. Defaults to
/// [CollectionSortBy.paymentDay] so the list groups every customer by their
/// recurring repayment day (Monday → Sunday), letting collectors see at a
/// glance which day each loan falls due.
final weeklyCollectionSortByProvider = StateProvider<CollectionSortBy>(
    (ref) => CollectionSortBy.paymentDay);

/// Weekly collection list filtered by date (single or range).
final weeklyCollectionListProvider =
    FutureProvider<List<WeeklyCollectionRow>>((ref) async {
  final repo = await ref.watch(collectionRepositoryProvider.future);
  final sortBy = ref.watch(weeklyCollectionSortByProvider);
  final query = ref.watch(weeklyCollectionSearchQueryProvider);
  final isRange = ref.watch(weeklyCollectionDateRangeModeProvider);

  final result = isRange
      ? await repo.getWeeklyCollectionByDateRange(
          ref.watch(weeklyCollectionRangeStartProvider),
          ref.watch(weeklyCollectionRangeEndProvider),
        )
      : await repo.getWeeklyCollectionByDate(
          ref.watch(weeklyCollectionDateFilterProvider),
        );
  final rows = result.when(
    success: (rows) => rows,
    failure: (f) => throw f,
  );
  final filtered = query.trim().isEmpty
      ? rows
      : rows
          .where((r) => r.customerName
              .toLowerCase()
              .contains(query.trim().toLowerCase()))
          .toList();
  switch (sortBy) {
    case CollectionSortBy.name:
      filtered.sort((a, b) => a.customerName.toLowerCase().compareTo(b.customerName.toLowerCase()));
    case CollectionSortBy.amountDue:
      filtered.sort((a, b) => b.installmentDue.compareTo(a.installmentDue));
    case CollectionSortBy.amountPaid:
      filtered.sort((a, b) => b.amountPaid.compareTo(a.amountPaid));
    case CollectionSortBy.outstanding:
      filtered.sort((a, b) => b.outstandingBalance.compareTo(a.outstandingBalance));
    case CollectionSortBy.paymentDay:
      filtered.sort((a, b) {
        final byDay = a.paymentDaySortValue.compareTo(b.paymentDaySortValue);
        if (byDay != 0) return byDay;
        return a.customerName.toLowerCase().compareTo(b.customerName.toLowerCase());
      });
  }
  return filtered;
});
