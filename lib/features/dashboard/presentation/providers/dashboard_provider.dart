import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/dashboard_repository.dart';
import '../../data/models/dashboard_data.dart';

final _dashboardRepositoryProvider = FutureProvider<DashboardRepository>(
    (ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return DashboardRepository(dbService);
});

final dashboardDataProvider = FutureProvider<DashboardData>((ref) async {
  final repo = await ref.watch(_dashboardRepositoryProvider.future);
  final result = await repo.getDashboardData();
  return result.when(
    success: (data) => data,
    failure: (f) => throw f,
  );
});
