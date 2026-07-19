import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/models/report_summary.dart';
import '../../data/report_repository.dart';

final _reportRepositoryProvider = FutureProvider<ReportRepository>(
    (ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return ReportRepository(dbService);
});

final reportStartDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

final reportEndDateProvider = StateProvider<DateTime>((ref) {
  return DateTime.now();
});

final reportSummaryProvider = FutureProvider<ReportSummary>((ref) async {
  final repo = await ref.watch(_reportRepositoryProvider.future);
  final start = ref.watch(reportStartDateProvider);
  final end = ref.watch(reportEndDateProvider);
  final result = await repo.getReportSummary(start, end);
  return result.when(
    success: (summary) => summary,
    failure: (f) => throw f,
  );
});
