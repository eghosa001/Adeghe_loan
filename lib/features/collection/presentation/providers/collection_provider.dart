import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/collection_repository.dart';
import '../../data/models/collection_row.dart';

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

/// Filter by loan type: null = all, 'daily' or 'weekly'.
final collectionLoanTypeFilterProvider = StateProvider<String?>((ref) => null);

enum CollectionSortBy { name, amountDue, amountPaid, outstanding }

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

final collectionListProvider = FutureProvider<List<CollectionRow>>((ref) async {
  final repo = await ref.watch(collectionRepositoryProvider.future);
  final isRange = ref.watch(collectionDateRangeModeProvider);
  final groupId = ref.watch(collectionGroupFilterProvider);
  final loanType = ref.watch(collectionLoanTypeFilterProvider);
  final sortBy = ref.watch(collectionSortByProvider);
  final query = ref.watch(collectionSearchQueryProvider);

  final result = isRange
      ? await repo.getCollectionsByDateRange(
          ref.watch(collectionRangeStartProvider),
          ref.watch(collectionRangeEndProvider),
          loanType: loanType,
          groupId: groupId,
        )
      : await repo.getDailyCollection(
          ref.watch(collectionDateFilterProvider),
          groupId: groupId,
          loanType: loanType,
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
  }
  return filtered;
});
