import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/group_repository.dart';
import '../../data/models/customer_group_entity.dart';

export '../../data/models/customer_group_entity.dart';

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository(ref);
});

final groupListProvider = FutureProvider<List<CustomerGroup>>((ref) async {
  return ref.watch(groupRepositoryProvider).getAll();
});

/// null means "all groups". A non-null group ID string means filter by that group.
final selectedGroupFilterProvider = StateProvider<String?>((ref) => null);
