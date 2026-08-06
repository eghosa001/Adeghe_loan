import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../collection/presentation/providers/collection_provider.dart';
import '../../data/models/report_summary.dart';
import '../../data/models/report_models.dart';
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

/// Report period quick presets selectable on the Reports screen. Each maps to
/// a start/end date range; [ReportPeriodPreset.thisMonth] is the default.
enum ReportPeriodPreset {
  today('Today'),
  yesterday('Yesterday'),
  thisWeek('This Week'),
  lastWeek('Last Week'),
  thisMonth('This Month'),
  lastMonth('Last Month'),
  last30Days('Last 30 Days');

  const ReportPeriodPreset(this.label);

  /// Display label shown on the preset chips.
  final String label;
}

/// Currently selected report period preset, or `null` when a custom date
/// range is active.
final reportPeriodPresetProvider =
    StateProvider<ReportPeriodPreset?>((ref) => ReportPeriodPreset.thisMonth);

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

/// Customer Report (all customers, no date filter — aggregates are lifetime).
final customerReportProvider = FutureProvider<List<CustomerReportRow>>((ref) async {
  final repo = await ref.watch(reportRepositoryProvider.future);
  final result = await repo.getCustomerReport();
  return result.when(success: (rows) => rows, failure: (f) => throw f);
});

/// Savings Report (all savings accounts, no date filter — balances are live).
final savingsReportProvider = FutureProvider<List<SavingsReportRow>>((ref) async {
  final repo = await ref.watch(reportRepositoryProvider.future);
  final result = await repo.getSavingsReport();
  return result.when(success: (rows) => rows, failure: (f) => throw f);
});

/// Profit Report per date range + optional loan type filter.
final profitReportProvider =
    FutureProvider.family<List<ProfitReportRow>, ReportDateRange>((ref, dates) async {
  final repo = await ref.watch(reportRepositoryProvider.future);
  final result = await repo.getProfitReport(
    startDate: dates.start,
    endDate: dates.end,
    loanType: dates.loanType,
  );
  return result.when(success: (rows) => rows, failure: (f) => throw f);
});

/// Dashboard trend series per date range + optional loan type filter.
final dashboardTrendsProvider =
    FutureProvider.family<DashboardTrends, ReportDateRange>((ref, dates) async {
  final repo = await ref.watch(reportRepositoryProvider.future);
  final result = await repo.getDashboardTrends(
    startDate: dates.start,
    endDate: dates.end,
    loanType: dates.loanType,
  );
  return result.when(success: (trends) => trends, failure: (f) => throw f);
});

/// Collection Report per date range + optional loan type/group filter, built
/// from the same source as the Collection screen (`getCollectionsByDateRange`)
/// so the numbers always match.
final collectionReportProvider =
    FutureProvider.family<List<CollectionReportRow>, ReportDateRange>((ref, dates) async {
  final repo = await ref.watch(collectionRepositoryProvider.future);
  final result = await repo.getCollectionsByDateRange(
    dates.start,
    dates.end,
    loanType: dates.loanType,
  );
  return result.when(
    success: (rows) => rows
        .map((row) => CollectionReportRow(
              customerId: row.customerId,
              customerName: row.customerName,
              phone: row.phone,
              loanId: row.loanId,
              loanType: row.loanType,
              amountDue: row.amountDue,
              amountPaid: row.amountPaid,
              outstandingBalance: row.outstandingBalance,
              groupName: row.groupName,
            ))
        .toList(growable: false),
    failure: (f) => throw f,
  );
});
