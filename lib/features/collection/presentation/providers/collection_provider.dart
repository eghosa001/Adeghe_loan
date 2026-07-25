import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/collection_repository.dart';
import '../../data/models/collection_row.dart';

final _collectionRepositoryProvider = FutureProvider<CollectionRepository>(
    (ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return CollectionRepository(dbService);
});

final collectionDateFilterProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Null means "all groups"; a non-null value filters by that group ID.
final collectionGroupFilterProvider = StateProvider<String?>((ref) => null);

final collectionListProvider = FutureProvider<List<CollectionRow>>((ref) async {
  final repo = await ref.watch(_collectionRepositoryProvider.future);
  final date = ref.watch(collectionDateFilterProvider);
  final groupId = ref.watch(collectionGroupFilterProvider);
  final result = await repo.getDailyCollection(date, groupId: groupId);
  return result.when(
    success: (rows) => rows,
    failure: (f) => throw f,
  );
});
