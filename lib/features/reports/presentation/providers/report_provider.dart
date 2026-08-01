import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/models/report_summary.dart';
import '../../data/report_repository.dart';

final reportRepositoryProvider = FutureProvider<ReportRepository>(
    (ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return ReportRepository(dbService);
});

/// Filter by loan type: null = all, 'daily' or 'weekly'.
final reportLoanTypeFilterProvider = StateProvider<String?>((ref) => null);

final reportStartDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

final reportEndDateProvider = StateProvider<DateTime>((ref) {
  return DateTime.now();
});

/// Key used to memoize report queries per date range.
class ReportDateRange {
  const ReportDateRange({required this.start, required this.end, this.loanType});
  final DateTime start;
  final DateTime end;
  final String? loanType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportDateRange &&
          start.isAtSameMomentAs(other.start) &&
          end.isAtSameMomentAs(other.end) &&
          loanType == other.loanType;

  @override
  int get hashCode => start.hashCode ^ end.hashCode ^ loanType.hashCode;
}

/// Overdue report fetching all overdue entries (no date range).
final overdueReportProvider = FutureProvider<List<OverdueEntry>>((ref) async {
  final repo = await ref.watch(reportRepositoryProvider.future);
  final result = await repo.getOverdueReport();
  return result.when(
    success: (entries) => entries,
    failure: (f) => throw f,
  );
});

/// Cached per date-range. Rebuilds only when the start/end dates change.
final reportSummaryProvider =
    FutureProvider.family<ReportSummary, ReportDateRange>((ref, dates) async {
  final repo = await ref.watch(reportRepositoryProvider.future);
  final result = await repo.getReportSummary(dates.start, dates.end, loanType: dates.loanType);
  return result.when(
    success: (summary) => summary,
    failure: (f) => throw f,
  );
});
