import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';
import 'package:loantrack/core/widgets/keyboard_refreshable.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../data/models/report_models.dart';
import '../../data/models/report_summary.dart';
import '../../services/export_manager.dart';
import '../providers/report_provider.dart';
import '../widgets/report_ui.dart';

/// Reports dashboard: 18 financial summary cards + 4 filter-aware trend
/// charts + navigation into the seven per-report screens.
class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preset = ref.watch(reportPeriodPresetProvider);
    final start = ref.watch(reportStartDateProvider);
    final end = ref.watch(reportEndDateProvider);
    final loanType = ref.watch(reportLoanTypeFilterProvider);

    final range = ReportDateRange(start: start, end: end, loanType: loanType);
    final summaryAsync = ref.watch(reportSummaryProvider(range));
    final trendsAsync = ref.watch(dashboardTrendsProvider(range));
    final currencySymbol =
        ref.watch(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;

    final periodLabel = _periodLabel(preset, start, end);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh (F5)',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(reportSummaryProvider(range));
              ref.invalidate(dashboardTrendsProvider(range));
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.download),
            tooltip: 'Export',
            onSelected: (value) => _handleExport(
              context,
              ref,
              value,
              summaryAsync,
              trendsAsync,
              periodLabel,
            ),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Save PDF')),
              PopupMenuItem(value: 'excel', child: Text('Export Excel')),
              PopupMenuItem(value: 'print', child: Text('Print')),
            ],
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/reports'),
      body: KeyboardRefreshable(
        onRefresh: () async {
          // Invalidate only the current range so switching periods or pulling
          // to refresh does not re-run every cached date range's queries.
          ref.invalidate(reportSummaryProvider(range));
          ref.invalidate(dashboardTrendsProvider(range));
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ReportPeriodSelector(
              onChanged: (period) {
                ref.read(reportPeriodPresetProvider.notifier).state =
                    _presetFromLabel(period.label);
                ref.read(reportStartDateProvider.notifier).state = period.start;
                ref.read(reportEndDateProvider.notifier).state = period.end;
              },
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Loan Type',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: '', label: Text('All')),
                        ButtonSegment(value: 'daily', label: Text('Daily')),
                        ButtonSegment(value: 'weekly', label: Text('Weekly')),
                      ],
                      selected: {loanType ?? ''},
                      onSelectionChanged: (selection) {
                        ref.read(reportLoanTypeFilterProvider.notifier).state =
                            selection.first.isEmpty ? null : selection.first;
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Financial Summary',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            summaryAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error: $e'),
                ),
              ),
              data: (summary) => _SummaryGrid(
                summary: summary,
                currencySymbol: currencySymbol,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Report Screens',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            const _ReportNavGrid(),
            const SizedBox(height: 20),
            Text(
              'Trends',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            trendsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error: $e'),
                ),
              ),
              data: (trends) => _TrendsSection(
                trends: trends,
                currencySymbol: currencySymbol,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _periodLabel(
    ReportPeriodPreset? preset,
    DateTime start,
    DateTime end,
  ) {
    if (preset != null) return preset.label;
    return '${AppDateUtils.formatDate(start)} - ${AppDateUtils.formatDate(end)}';
  }

  ReportPeriodPreset? _presetFromLabel(String label) {
    for (final preset in ReportPeriodPreset.values) {
      if (preset.label == label) return preset;
    }
    return null;
  }

  Future<void> _handleExport(
    BuildContext context,
    WidgetRef ref,
    String value,
    AsyncValue<ReportSummary> summaryAsync,
    AsyncValue<DashboardTrends> trendsAsync,
    String periodLabel,
  ) async {
    final summary = summaryAsync.valueOrNull;
    final trends = trendsAsync.valueOrNull;
    if (summary == null || trends == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report data not ready yet.')),
        );
      }
      return;
    }
    final profile = ref.read(businessProfileProvider).valueOrNull;
    final currencySymbol =
        ref.read(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;
    final data = _buildExportData(summary, trends, periodLabel, currencySymbol);
    try {
      if (value == 'pdf') {
        final path = await ExportManager.saveReportPdf(data, profile: profile);
        if (context.mounted && path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF saved to Documents')),
          );
        }
      } else if (value == 'excel') {
        final file = await ExportManager.exportReportToXlsx(data);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Excel exported: ${file.path.split(RegExp(r'[/\\]')).last}',
              ),
            ),
          );
        }
      } else if (value == 'print') {
        await ExportManager.printReportPdf(data, profile: profile);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  ReportExportData _buildExportData(
    ReportSummary s,
    DashboardTrends t,
    String periodLabel,
    String currencySymbol,
  ) {
    String fmt(num v) => CurrencyUtils.format(v, symbol: currencySymbol);
    final cards = <ReportCard>[
      ReportCard('Total Disbursed', fmt(s.totalDisbursed)),
      ReportCard('Total Collected', fmt(s.totalCollected)),
      ReportCard('Net Profit', fmt(s.netProfit), highlight: s.netProfit < 0),
      ReportCard('Total Customers', '${s.totalCustomers}'),
      ReportCard('Active Loans', '${s.activeLoans}'),
      ReportCard('Completed Loans', '${s.completedLoans}'),
      ReportCard('Defaulted Loans', '${s.defaultedLoans}'),
      ReportCard(
        'Outstanding',
        fmt(s.dailyLoans.outstandingBalance + s.weeklyLoans.outstandingBalance),
      ),
      ReportCard(
        'Expected',
        fmt(
          s.dailyLoans.expectedCollections + s.weeklyLoans.expectedCollections,
        ),
      ),
      ReportCard('Efficiency', '${s.collectionEfficiency.toStringAsFixed(1)}%'),
      ReportCard(
        'Interest',
        fmt(s.dailyLoans.interestEarned + s.weeklyLoans.interestEarned),
      ),
      ReportCard(
        'Fees',
        fmt(s.dailyLoans.feesEarned + s.weeklyLoans.feesEarned),
      ),
      ReportCard(
        'Savings',
        fmt(
          s.dailyLoans.savingsFromOverpayments +
              s.weeklyLoans.savingsFromOverpayments,
        ),
      ),
      ReportCard('Daily Disbursed', fmt(s.dailyLoans.amountDisbursed)),
      ReportCard('Daily Collected', fmt(s.dailyLoans.amountCollected)),
      ReportCard('Daily Overdue', '${s.dailyLoans.overdueLoans}'),
      ReportCard('Weekly Disbursed', fmt(s.weeklyLoans.amountDisbursed)),
      ReportCard('Weekly Collected', fmt(s.weeklyLoans.amountCollected)),
    ];

    final headers = [
      'Period',
      'Collected',
      'Disbursed',
      'Savings In',
      'Savings Out',
      'Customers',
      'Loans',
    ];
    final rows = <List<String>>[];
    var totalCollected = 0.0;
    var totalDisbursed = 0.0;
    var totalSavingsIn = 0.0;
    var totalSavingsOut = 0.0;
    var totalCustomers = 0.0;
    var totalLoans = 0.0;
    for (var i = 0; i < t.collected.length; i++) {
      final label = t.collected[i].label;
      final collected = t.collected[i].value;
      final disbursed = i < t.disbursed.length ? t.disbursed[i].value : 0;
      final sin = i < t.savingsIn.length ? t.savingsIn[i].value : 0;
      final sout = i < t.savingsOut.length ? t.savingsOut[i].value : 0;
      final cus = i < t.customers.length ? t.customers[i].value : 0;
      final lo = i < t.loans.length ? t.loans[i].value : 0;
      totalCollected += collected;
      totalDisbursed += disbursed;
      totalSavingsIn += sin;
      totalSavingsOut += sout;
      totalCustomers += cus;
      totalLoans += lo;
      rows.add([
        label,
        fmt(collected),
        fmt(disbursed),
        fmt(sin),
        fmt(sout),
        cus.toStringAsFixed(0),
        lo.toStringAsFixed(0),
      ]);
    }

    return ReportExportData(
      reportName: 'Reports Dashboard',
      periodLabel: periodLabel,
      cards: cards,
      headers: headers,
      rows: rows,
      rightAlignColumns: const [1, 2, 3, 4, 5, 6],
      totalsRow: [
        'Total',
        fmt(totalCollected),
        fmt(totalDisbursed),
        fmt(totalSavingsIn),
        fmt(totalSavingsOut),
        totalCustomers.toStringAsFixed(0),
        totalLoans.toStringAsFixed(0),
      ],
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary, required this.currencySymbol});

  final ReportSummary summary;
  final String currencySymbol;

  String fmt(num v) => CurrencyUtils.format(v, symbol: currencySymbol);

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final items = <(String, String, IconData, bool)>[
      ('Total Disbursed', fmt(s.totalDisbursed), Icons.payments_rounded, false),
      ('Total Collected', fmt(s.totalCollected), Icons.savings_rounded, false),
      (
        'Net Profit',
        fmt(s.netProfit),
        Icons.trending_up_rounded,
        s.netProfit < 0,
      ),
      (
        'Total Customers',
        '${s.totalCustomers}',
        Icons.people_alt_rounded,
        false,
      ),
      ('Active Loans', '${s.activeLoans}', Icons.fact_check_rounded, false),
      (
        'Completed Loans',
        '${s.completedLoans}',
        Icons.check_circle_rounded,
        false,
      ),
      (
        'Defaulted Loans',
        '${s.defaultedLoans}',
        Icons.error_rounded,
        s.defaultedLoans > 0,
      ),
      (
        'Outstanding',
        fmt(s.dailyLoans.outstandingBalance + s.weeklyLoans.outstandingBalance),
        Icons.account_balance_rounded,
        false,
      ),
      (
        'Expected',
        fmt(
          s.dailyLoans.expectedCollections + s.weeklyLoans.expectedCollections,
        ),
        Icons.event_available_rounded,
        false,
      ),
      (
        'Efficiency',
        '${s.collectionEfficiency.toStringAsFixed(1)}%',
        Icons.speed_rounded,
        false,
      ),
      (
        'Interest Earned',
        fmt(s.dailyLoans.interestEarned + s.weeklyLoans.interestEarned),
        Icons.percent_rounded,
        false,
      ),
      (
        'Fees Earned',
        fmt(s.dailyLoans.feesEarned + s.weeklyLoans.feesEarned),
        Icons.receipt_rounded,
        false,
      ),
      (
        'Savings',
        fmt(
          s.dailyLoans.savingsFromOverpayments +
              s.weeklyLoans.savingsFromOverpayments,
        ),
        Icons.savings_rounded,
        false,
      ),
      (
        'Daily Disbursed',
        fmt(s.dailyLoans.amountDisbursed),
        Icons.today_rounded,
        false,
      ),
      (
        'Daily Collected',
        fmt(s.dailyLoans.amountCollected),
        Icons.done_all_rounded,
        false,
      ),
      (
        'Daily Overdue',
        '${s.dailyLoans.overdueLoans}',
        Icons.warning_rounded,
        s.dailyLoans.overdueLoans > 0,
      ),
      (
        'Weekly Disbursed',
        fmt(s.weeklyLoans.amountDisbursed),
        Icons.calendar_view_week_rounded,
        false,
      ),
      (
        'Weekly Collected',
        fmt(s.weeklyLoans.amountCollected),
        Icons.task_alt_rounded,
        false,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisExtent: 86,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final (label, value, icon, accent) = items[index];
        return ReportMetricCard(
          label: label,
          value: value,
          icon: icon,
          accent: accent,
        );
      },
    );
  }
}

class _ReportNavGrid extends StatelessWidget {
  const _ReportNavGrid();

  static const _destinations = [
    (Icons.today_rounded, 'Daily Loans', '/reports/daily-loans'),
    (Icons.calendar_view_week_rounded, 'Weekly Loans', '/reports/weekly-loans'),
    (Icons.warning_amber_rounded, 'Overdue', '/reports/overdue'),
    (Icons.people_alt_rounded, 'Customers', '/reports/customers'),
    (Icons.savings_rounded, 'Savings', '/reports/savings-report'),
    (Icons.trending_up_rounded, 'Profit', '/reports/profit'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 92,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: _destinations.length,
      itemBuilder: (context, index) {
        final (icon, label, route) = _destinations[index];
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push(route),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 26,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TrendsSection extends StatelessWidget {
  const _TrendsSection({required this.trends, required this.currencySymbol});

  final DashboardTrends trends;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _BarTrendChart(
          title: 'Collected vs Disbursed',
          series1: trends.collected,
          series2: trends.disbursed,
          series1Color: AppTheme.secondaryColor,
          series2Color: Theme.of(context).colorScheme.primary,
          series1Label: 'Collected',
          series2Label: 'Disbursed',
          currencySymbol: currencySymbol,
        ),
        const SizedBox(height: 16),
        _LineTrendChart(
          title: 'Savings In vs Out',
          series1: trends.savingsIn,
          series2: trends.savingsOut,
          series1Color: AppTheme.secondaryColor,
          series2Color: AppTheme.accentColor,
          series1Label: 'Savings In',
          series2Label: 'Savings Out',
          currencySymbol: currencySymbol,
        ),
        const SizedBox(height: 16),
        _BarTrendChart(
          title: 'New Customers',
          series1: trends.customers,
          series1Color: Theme.of(context).colorScheme.primary,
          series1Label: 'Customers',
          currencySymbol: currencySymbol,
          formatCounts: true,
        ),
        const SizedBox(height: 16),
        _BarTrendChart(
          title: 'New Loans',
          series1: trends.loans,
          series1Color: AppTheme.accentColor,
          series1Label: 'Loans',
          currencySymbol: currencySymbol,
          formatCounts: true,
        ),
      ],
    );
  }
}

class _BarTrendChart extends StatelessWidget {
  const _BarTrendChart({
    required this.title,
    required this.series1,
    this.series2,
    required this.series1Color,
    this.series2Color,
    required this.series1Label,
    this.series2Label,
    required this.currencySymbol,
    this.formatCounts = false,
  });

  final String title;
  final List<DashboardTrendPoint> series1;
  final List<DashboardTrendPoint>? series2;
  final Color series1Color;
  final Color? series2Color;
  final String series1Label;
  final String? series2Label;
  final String currencySymbol;
  final bool formatCounts;

  @override
  Widget build(BuildContext context) {
    final maxValue = [
      ...series1.map((e) => e.value),
      if (series2 != null) ...series2!.map((e) => e.value),
    ].fold<double>(0, (a, b) => b > a ? b : a);

    final groups = series1.length;
    final spots = <BarChartGroupData>[];
    for (var i = 0; i < groups; i++) {
      final s1 = series1[i];
      final rods = <BarChartRodData>[
        BarChartRodData(
          toY: s1.value,
          color: series1Color,
          width: 7,
          borderRadius: BorderRadius.circular(3),
        ),
        if (series2 != null && i < series2!.length)
          BarChartRodData(
            toY: series2![i].value,
            color: series2Color,
            width: 7,
            borderRadius: BorderRadius.circular(3),
          ),
      ];
      spots.add(BarChartGroupData(x: i, barRods: rods));
    }

    String fmt(double v) => formatCounts
        ? v.toStringAsFixed(0)
        : CurrencyUtils.format(v, symbol: currencySymbol);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: groups == 0
                  ? const Center(child: Text('No data in this period'))
                  : BarChart(
                      BarChartData(
                        maxY: maxValue <= 0 ? 1 : maxValue * 1.15,
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                fmt(rod.toY),
                                const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx < 0 || idx >= groups) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    series1[idx].label,
                                    style: const TextStyle(fontSize: 9),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        gridData: const FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: spots,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _LegendDot(color: series1Color, label: series1Label),
                if (series2Label != null) ...[
                  const SizedBox(width: 16),
                  _LegendDot(color: series2Color!, label: series2Label!),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LineTrendChart extends StatelessWidget {
  const _LineTrendChart({
    required this.title,
    required this.series1,
    required this.series2,
    required this.series1Color,
    required this.series2Color,
    required this.series1Label,
    required this.series2Label,
    required this.currencySymbol,
  });

  final String title;
  final List<DashboardTrendPoint> series1;
  final List<DashboardTrendPoint> series2;
  final Color series1Color;
  final Color series2Color;
  final String series1Label;
  final String series2Label;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final maxValue = [
      ...series1.map((e) => e.value),
      ...series2.map((e) => e.value),
    ].fold<double>(0, (a, b) => b > a ? b : a);

    FlSpot spot(int i, double v) => FlSpot(i.toDouble(), v);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: series1.isEmpty
                  ? const Center(child: Text('No data in this period'))
                  : LineChart(
                      LineChartData(
                        maxY: maxValue <= 0 ? 1 : maxValue * 1.15,
                        minY: 0,
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (spots) {
                              return spots
                                  .map(
                                    (spot) => LineTooltipItem(
                                      CurrencyUtils.format(
                                        spot.y,
                                        symbol: currencySymbol,
                                      ),
                                      const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                  .toList();
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx < 0 || idx >= series1.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    series1[idx].label,
                                    style: const TextStyle(fontSize: 9),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        gridData: const FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (var i = 0; i < series1.length; i++)
                                spot(i, series1[i].value),
                            ],
                            isCurved: true,
                            color: series1Color,
                            barWidth: 2.5,
                            dotData: const FlDotData(show: false),
                          ),
                          LineChartBarData(
                            spots: [
                              for (var i = 0; i < series2.length; i++)
                                spot(i, series2[i].value),
                            ],
                            isCurved: true,
                            color: series2Color,
                            barWidth: 2.5,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _LegendDot(color: series1Color, label: series1Label),
                const SizedBox(width: 16),
                _LegendDot(color: series2Color, label: series2Label),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
