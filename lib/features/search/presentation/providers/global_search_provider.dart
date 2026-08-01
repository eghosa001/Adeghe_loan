import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';
import '../../data/global_search_repository.dart';

final globalSearchRepositoryProvider = FutureProvider<GlobalSearchRepository>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return GlobalSearchRepository(dbService);
});

final globalSearchQueryProvider = StateProvider<String>((ref) => '');

final globalSearchResultsProvider = FutureProvider<List<SearchResultItem>>((ref) async {
  final query = ref.watch(globalSearchQueryProvider);
  if (query.trim().isEmpty) return [];
  final repo = await ref.watch(globalSearchRepositoryProvider.future);
  return repo.search(query);
});
