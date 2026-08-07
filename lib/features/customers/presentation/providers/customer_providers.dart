import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/providers.dart';
import '../../data/customer_repository.dart';
import '../../data/models/customer_entity.dart';

final customerSearchQueryProvider = StateProvider<String>((ref) => '');

/// Null means "all customers". A group ID filters to that group's members;
/// [ungroupedGroupFilter] filters to customers not in any group.
final customerGroupFilterProvider = StateProvider<String?>((ref) => null);

/// Filter for customer status: active (default) or archived.
final customerStatusFilterProvider = StateProvider<CustomerStatusFilter>((ref) => CustomerStatusFilter.active);

enum CustomerSortBy { name, group, amountOwed }

final customerSortByProvider = StateProvider<CustomerSortBy>(
    (ref) => CustomerSortBy.name);

final customerRepositoryProvider = FutureProvider<CustomerRepository>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return CustomerRepository(dbService);
});

/// Current page number (0-indexed) for customer list pagination.
final customerPageProvider = StateProvider<int>((ref) => 0);

/// Total number of customers matching current filters.
final customerCountProvider = FutureProvider<int>((ref) async {
  final repo = await ref.watch(customerRepositoryProvider.future);
  final query = ref.watch(customerSearchQueryProvider);
  final groupId = ref.watch(customerGroupFilterProvider);
  final statusFilter = ref.watch(customerStatusFilterProvider);
  return repo.count(query, groupId: groupId, statusFilter: statusFilter);
});

/// Paginated customer list — sorting is handled in SQL ORDER BY.
final customerListProvider = FutureProvider<List<Customer>>((ref) async {
  final query = ref.watch(customerSearchQueryProvider);
  final groupId = ref.watch(customerGroupFilterProvider);
  final sortBy = ref.watch(customerSortByProvider);
  final page = ref.watch(customerPageProvider);
  final statusFilter = ref.watch(customerStatusFilterProvider);
  final repo = await ref.watch(customerRepositoryProvider.future);
  return repo.searchPaginated(
    query,
    groupId: groupId,
    limit: AppConstants.defaultPageSize,
    offset: page * AppConstants.defaultPageSize,
    sortBy: sortBy._toSql,
    statusFilter: statusFilter,
  );
});

final customerProvider = FutureProvider.family<Customer?, String>((ref, id) async {
  final repo = await ref.watch(customerRepositoryProvider.future);
  return repo.getById(id);
});

/// ALL non-archived customers (unpaginated) for dropdown pickers (statements,
/// savings transfers, etc.). `customerListProvider` is page-size capped, so a
/// customer beyond the first page could never be selected in those pickers.
final allCustomersProvider = FutureProvider<List<Customer>>((ref) async {
  final repo = await ref.watch(customerRepositoryProvider.future);
  return repo.search('');
});

extension on CustomerSortBy {
  CustomerSortOption get _toSql => switch (this) {
    CustomerSortBy.name => CustomerSortOption.name,
    CustomerSortBy.group => CustomerSortOption.group,
    CustomerSortBy.amountOwed => CustomerSortOption.amountOwed,
  };
}
