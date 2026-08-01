import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/analytics_models.dart';
import 'report_provider.dart';

final portfolioBreakdownProvider = FutureProvider<PortfolioBreakdown>((ref) async {
  final repo = await ref.watch(reportRepositoryProvider.future);
  final result = await repo.getPortfolioBreakdown();
  return result.when(success: (d) => d, failure: (f) => throw f);
});

final collectionTrendsProvider = FutureProvider<List<CollectionTrend>>((ref) async {
  final repo = await ref.watch(reportRepositoryProvider.future);
  final result = await repo.getCollectionTrends(6);
  return result.when(success: (d) => d, failure: (f) => throw f);
});

final repaymentTrendsProvider = FutureProvider<List<MonthlyTrendPoint>>((ref) async {
  final repo = await ref.watch(reportRepositoryProvider.future);
  final result = await repo.getRepaymentTrends(6);
  return result.when(success: (d) => d, failure: (f) => throw f);
});

final growthStatsProvider = FutureProvider<GrowthStats>((ref) async {
  final repo = await ref.watch(reportRepositoryProvider.future);
  final result = await repo.getGrowthStats(6);
  return result.when(success: (d) => d, failure: (f) => throw f);
});

final savingsTrendsProvider = FutureProvider<List<SavingsTrendPoint>>((ref) async {
  final repo = await ref.watch(reportRepositoryProvider.future);
  final result = await repo.getSavingsTrends(6);
  return result.when(success: (d) => d, failure: (f) => throw f);
});
