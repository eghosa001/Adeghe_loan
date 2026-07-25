import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/customer_repository.dart';
import '../../data/models/customer_entity.dart';

final customerSearchQueryProvider = StateProvider<String>((ref) => '');

/// Null means "all groups". A group ID string filters the customer list.
final customerGroupFilterProvider = StateProvider<String?>((ref) => null);

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(ref);
});

final customerListProvider = FutureProvider<List<Customer>>((ref) async {
  final query = ref.watch(customerSearchQueryProvider);
  final groupId = ref.watch(customerGroupFilterProvider);
  return ref.watch(customerRepositoryProvider).search(query, groupId: groupId);
});

final customerProvider = FutureProvider.family<Customer?, String>((ref, id) {
  return ref.watch(customerRepositoryProvider).getById(id);
});

void refreshCustomers(Ref ref) {
  ref.invalidate(customerListProvider);
}
