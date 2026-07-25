import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/customer_repository.dart';
import '../../data/models/customer_entity.dart';

final customerSearchQueryProvider = StateProvider<String>((ref) => '');

/// Null means "all groups". A group ID string filters the customer list.
final customerGroupFilterProvider = StateProvider<String?>((ref) => null);

enum CustomerSortBy { name, group }

final customerSortByProvider = StateProvider<CustomerSortBy>(
    (ref) => CustomerSortBy.name);

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(ref);
});

final customerListProvider = FutureProvider<List<Customer>>((ref) async {
  final query = ref.watch(customerSearchQueryProvider);
  final groupId = ref.watch(customerGroupFilterProvider);
  final sortBy = ref.watch(customerSortByProvider);
  final customers =
      await ref.watch(customerRepositoryProvider).search(query, groupId: groupId);
  switch (sortBy) {
    case CustomerSortBy.name:
      customers.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
      break;
    case CustomerSortBy.group:
      customers.sort((a, b) {
        final groupCompare = (a.groupId ?? '').compareTo(b.groupId ?? '');
        if (groupCompare != 0) return groupCompare;
        return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
      });
      break;
  }
  return customers;
});

final customerProvider = FutureProvider.family<Customer?, String>((ref, id) {
  return ref.watch(customerRepositoryProvider).getById(id);
});

void refreshCustomers(Ref ref) {
  ref.invalidate(customerListProvider);
}
