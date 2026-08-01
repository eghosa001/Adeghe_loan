import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/group_repository.dart';
import '../../data/models/customer_group_entity.dart';

export '../../data/models/customer_group_entity.dart';

final groupRepositoryProvider = FutureProvider<GroupRepository>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return GroupRepository(dbService);
});

final groupListProvider = FutureProvider<List<CustomerGroup>>((ref) async {
  final repo = await ref.watch(groupRepositoryProvider.future);
  return repo.getAll();
});
