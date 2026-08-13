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

/// Reports dashboard: one snapshot (`reportDashboardProvider`) renders the six
/// primary KPIs with previous-period deltas, then section-by-section coverage
/// of today's collections, the loan portfolio, collection performance, overdue
/// risk, income & profit, savings and customers — each with its own charts and
/// a link into the matching per-report screen.
class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preset = ref.watch(reportPeriodPresetProvider);
    final start = ref.watch(reportStartDateProvider);
    final end = ref.watch(reportEndDateProvider);
    final loanType = ref.watch(reportLoanTypeFilterProvider);

    final range = ReportDateRange(start: start, end: end, loanType: loanType);
    final dashboardAsync = ref.watch(reportDashboardProvider(range));
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
              ref.invalidate(reportDashboardProvider(range));
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
              dashboardAsync,
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
          ref.invalidate(reportDashboardProvider(range));
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
            const SizedBox(height: 10),
            _LoanTypeFilter(selected: loanType),
            const SizedBox(height: 16),
            dashboardAsync.when(
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
              data: (dashboard) => _DashboardBody(
                dashboard: dashboard,
                trends: trendsAsync.valueOrNull,
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
    AsyncValue<ReportDashboardData> dashboardAsync,
    AsyncValue<DashboardTrends> trendsAsync,
    String periodLabel,
  ) async {
    final dashboard = dashboardAsync.valueOrNull;
    final trends = trendsAsync.valueOrNull;
    if (dashboard == null || trends == null) {
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
    final data = _buildExportData(
      dashboard,
      trends,
      periodLabel,
      currencySymbol,
    );
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
    ReportDashboardData dashboard,
    DashboardTrends t,
    String periodLabel,
    String currencySymbol,
  ) {
    final s = dashboard.summary;
    String fmt(num v) => CurrencyUtils.format(v, symbol: currencySymbol);
    final cards = <ReportCard>[
      ReportCard('Total Collected', fmt(s.totalCollected)),
      ReportCard('Total Disbursed', fmt(s.totalDisbursed)),
      ReportCard('Net Profit', fmt(s.netProfit), highlight: s.netProfit < 0),
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
        'Total Customers',
        '${dashboard.customers.totalCustomers}',
      ),
      ReportCard('Active Loans', '${s.activeLoans}'),
      ReportCard('Completed Loans', '${s.completedLoans}'),
      ReportCard('Defaulted Loans', '${s.defaultedLoans}'),
      ReportCard(
        'Interest',
        fmt(s.dailyLoans.interestEarned + s.weeklyLoans.interestEarned),
      ),
      ReportCard(
        'Fees',
        fmt(s.dailyLoans.feesEarned + s.weeklyLoans.feesEarned),
      ),
      ReportCard('Daily Disbursed', fmt(s.dailyLoans.amountDisbursed)),
      ReportCard('Daily Collected', fmt(s.dailyLoans.amountCollected)),
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

/// Compact loan-type filter kept directly under the period selector so the two
/// report filters read as one control block.
class _LoanTypeFilter extends ConsumerWidget {
  const _LoanTypeFilter({required this.selected});

  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.filter_alt_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            const Text('Loan Type',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            Expanded(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: '', label: Text('All')),
                  ButtonSegment(value: 'daily', label: Text('Daily')),
                  ButtonSegment(value: 'weekly', label: Text('Weekly')),
                ],
                selected: {selected ?? ''},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                onSelectionChanged: (selection) {
                  final next = selection.first;
                  ref.read(reportLoanTypeFilterProvider.notifier).state =
                      next.isEmpty ? null : next;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.dashboard,
    required this.trends,
    required this.currencySymbol,
  });

  final ReportDashboardData dashboard;
  final DashboardTrends? trends;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final s = dashboard.summary;
    final t = trends;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PrimaryKpis(dashboard: dashboard, currencySymbol: currencySymbol),
        const SizedBox(height: 8),
        _SectionHeader(
          title: "Today's Collection",
          icon: Icons.today_rounded,
          trailing: TextButton.icon(
            onPressed: () => context.push('/collections'),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Collection Screen'),
          ),
        ),
        _TodaySection(today: dashboard.today, currencySymbol: currencySymbol),
        const SizedBox(height: 8),
        _SectionHeader(
          title: 'Loan Portfolio',
          icon: Icons.account_balance_rounded,
        ),
        _LoanPortfolioSection(
          dashboard: dashboard,
          currencySymbol: currencySymbol,
        ),
        const SizedBox(height: 8),
        _SectionHeader(
          title: 'Collection Performance',
          icon: Icons.speed_rounded,
        ),
        _PerformanceSection(
          summary: s,
          trends: t,
          currencySymbol: currencySymbol,
        ),
        const SizedBox(height: 8),
        _SectionHeader(
          title: 'Overdue & Risk',
          icon: Icons.warning_amber_rounded,
          trailing: TextButton.icon(
            onPressed: () => context.push('/reports/overdue'),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Overdue Report'),
          ),
        ),
        _OverdueSection(overdue: dashboard.overdue, currencySymbol: currencySymbol),
        const SizedBox(height: 8),
        _SectionHeader(
          title: 'Income & Profit',
          icon: Icons.trending_up_rounded,
          trailing: TextButton.icon(
            onPressed: () => context.push('/reports/profit'),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Profit Report'),
          ),
        ),
        _ProfitSection(summary: s, currencySymbol: currencySymbol),
        const SizedBox(height: 8),
        _SectionHeader(
          title: 'Savings',
          icon: Icons.savings_rounded,
          trailing: TextButton.icon(
            onPressed: () => context.push('/reports/savings-report'),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Savings Report'),
          ),
        ),
        _SavingsSection(
          savings: dashboard.savings,
          trends: t,
          currencySymbol: currencySymbol,
        ),
        const SizedBox(height: 8),
        _SectionHeader(
          title: 'Customers',
          icon: Icons.people_alt_rounded,
          trailing: TextButton.icon(
            onPressed: () => context.push('/reports/customers'),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Customer Report'),
          ),
        ),
        _CustomersSection(
          customers: dashboard.customers,
          trends: t,
          currencySymbol: currencySymbol,
        ),
        const SizedBox(height: 8),
        _SectionHeader(
          title: 'Report Screens',
          icon: Icons.grid_view_rounded,
        ),
        const _ReportNavGrid(),
      ],
    );
  }
}

/// Six primary KPI cards, each with a delta vs the previous equal-length period.
class _PrimaryKpis extends StatelessWidget {
  const _PrimaryKpis({required this.dashboard, required this.currencySymbol});

  final ReportDashboardData dashboard;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final s = dashboard.summary;
    final p = dashboard.previousSummary;
    final outstanding = dashboard.totalOutstandingBalance;
    final expected = dashboard.totalExpectedCollections;
    final prevOutstanding =
        p.dailyLoans.outstandingBalance + p.weeklyLoans.outstandingBalance;
    final prevExpected =
        p.dailyLoans.expectedCollections + p.weeklyLoans.expectedCollections;

    String fmt(num v) => CurrencyUtils.format(v, symbol: currencySymbol);

    // Last tuple element marks "lower is better" metrics (Outstanding,
    // Expected) so their delta colors are inverted — a fall is good (green).
    final items = <(String, String, IconData, Color, String, bool)>[
      (
        'Total Collected',
        fmt(s.totalCollected),
        Icons.savings_rounded,
        AppTheme.secondaryColor,
        _deltaLabel(s.totalCollected, p.totalCollected),
        false,
      ),
      (
        'Total Disbursed',
        fmt(s.totalDisbursed),
        Icons.payments_rounded,
        Theme.of(context).colorScheme.primary,
        _deltaLabel(s.totalDisbursed, p.totalDisbursed),
        false,
      ),
      (
        'Net Profit',
        fmt(s.netProfit),
        Icons.trending_up_rounded,
        s.netProfit < 0 ? AppTheme.errorColor : Colors.green,
        _deltaLabel(s.netProfit, p.netProfit),
        false,
      ),
      (
        'Outstanding',
        fmt(outstanding),
        Icons.account_balance_rounded,
        Theme.of(context).colorScheme.tertiary,
        _deltaLabel(outstanding, prevOutstanding),
        true,
      ),
      (
        'Expected',
        fmt(expected),
        Icons.event_available_rounded,
        Theme.of(context).colorScheme.secondary,
        _deltaLabel(expected, prevExpected),
        true,
      ),
      (
        'Efficiency',
        '${s.collectionEfficiency.toStringAsFixed(1)}%',
        Icons.speed_rounded,
        AppTheme.accentColor,
        _ppDeltaLabel(s.collectionEfficiency, p.collectionEfficiency),
        false,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisExtent: 108,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final (label, value, icon, color, delta, deltaInverted) = items[index];
        return _KpiCard(
          label: label,
          value: value,
          icon: icon,
          accent: color,
          delta: delta,
          deltaInverted: deltaInverted,
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.delta,
    this.deltaInverted = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final String delta;

  /// True when a falling value is an improvement (Outstanding, Expected) so
  /// the delta chip is colored accordingly.
  final bool deltaInverted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final positive = delta.startsWith('+');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              delta,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _deltaColor(positive, delta,
                    inverted: deltaInverted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small labelled tile used inside sections.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.subtitle,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = color ?? colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: accent),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TodaySection extends StatelessWidget {
  const _TodaySection({required this.today, required this.currencySymbol});

  final TodayCollection today;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    String fmt(num v) => CurrencyUtils.format(v, symbol: currencySymbol);
    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 210,
            mainAxisExtent: 92,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemCount: 3,
          itemBuilder: (context, index) {
            return switch (index) {
              0 => _Tile(
                  label: 'Collected Today',
                  value: fmt(today.collectedAmount),
                  icon: Icons.savings_rounded,
                  color: AppTheme.secondaryColor,
                  subtitle: '${today.paymentCount} payments',
                ),
              1 => _Tile(
                  label: 'Due Today',
                  value: fmt(today.dueToday),
                  icon: Icons.event_available_rounded,
                  color: Theme.of(context).colorScheme.error,
                  subtitle:
                      '${today.dueTodayLoans} loans · ${today.dueTodayCustomers} customers',
                ),
              _ => _Tile(
                  label: 'Collection Progress',
                  value: _progressLabel(today),
                  icon: Icons.donut_large_rounded,
                  color: AppTheme.accentColor,
                  subtitle: _progressDetail(today),
                ),
            };
          },
        ),
        if (today.topCollectors.isNotEmpty) ...[
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top Collectors',
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < today.topCollectors.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.1),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              today.topCollectors[i].collector,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${today.topCollectors[i].count} payments',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            fmt(today.topCollectors[i].amount),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _progressLabel(TodayCollection today) {
    if (today.dueToday <= 0) return 'All clear';
    final pct = ((today.collectedAmount / today.dueToday) * 100).clamp(0.0, 100.0);
    return '${pct.toStringAsFixed(0)}%';
  }

  String _progressDetail(TodayCollection today) {
    if (today.dueToday <= 0) return 'Nothing due today';
    return 'collected of what is due today';
  }
}

class _LoanPortfolioSection extends StatelessWidget {
  const _LoanPortfolioSection({
    required this.dashboard,
    required this.currencySymbol,
  });

  final ReportDashboardData dashboard;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final s = dashboard.summary;
    String fmt(num v) => CurrencyUtils.format(v, symbol: currencySymbol);
    final tiles = <Widget>[
      _Tile(
        label: 'Active Loans',
        value: '${s.activeLoans}',
        icon: Icons.fact_check_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
      _Tile(
        label: 'Disbursed (Period)',
        value: fmt(s.totalDisbursed),
        icon: Icons.payments_rounded,
        color: AppTheme.secondaryColor,
      ),
      _Tile(
        label: 'Outstanding',
        value: fmt(dashboard.totalOutstandingBalance),
        icon: Icons.account_balance_rounded,
        color: Theme.of(context).colorScheme.tertiary,
      ),
      _Tile(
        label: 'Loans Due Today',
        value: '${dashboard.today.dueTodayLoans}',
        icon: Icons.event_available_rounded,
        color: AppTheme.accentColor,
      ),
      _Tile(
        label: 'Defaulted',
        value: '${s.defaultedLoans}',
        icon: Icons.error_rounded,
        color: s.defaultedLoans > 0
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      _Tile(
        label: 'Completed',
        value: '${s.completedLoans}',
        icon: Icons.check_circle_rounded,
        color: Colors.green,
      ),
    ];
    return _TileGrid(tiles: tiles);
  }
}

class _PerformanceSection extends StatelessWidget {
  const _PerformanceSection({
    required this.summary,
    required this.trends,
    required this.currencySymbol,
  });

  final ReportSummary summary;
  final DashboardTrends? trends;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final efficiency = summary.collectionEfficiency;
    final expected = summary.dailyLoans.expectedCollections +
        summary.weeklyLoans.expectedCollections;
    final collected = summary.dailyLoans.amountCollected +
        summary.weeklyLoans.amountCollected;
    String fmt(num v) => CurrencyUtils.format(v, symbol: currencySymbol);

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _EfficiencyDonut(efficiency: efficiency),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Collected vs Expected',
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      _VsRow('Collected', fmt(collected), AppTheme.secondaryColor),
                      const SizedBox(height: 6),
                      _VsRow(
                        'Expected',
                        fmt(expected),
                        Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (trends != null && trends!.collected.isNotEmpty)
          _BarTrendChart(
            title: 'Collected vs Disbursed',
            series1: trends!.collected,
            series2: trends!.disbursed,
            series1Color: AppTheme.secondaryColor,
            series2Color: Theme.of(context).colorScheme.primary,
            series1Label: 'Collected',
            series2Label: 'Disbursed',
            currencySymbol: currencySymbol,
          ),
      ],
    );
  }
}

class _EfficiencyDonut extends StatelessWidget {
  const _EfficiencyDonut({required this.efficiency});

  final double efficiency;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pct = efficiency.clamp(0.0, 100.0);
    return SizedBox(
      width: 130,
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              startDegreeOffset: -90,
              sections: [
                PieChartSectionData(
                  value: pct,
                  color: AppTheme.secondaryColor,
                  radius: 24,
                  showTitle: false,
                ),
                PieChartSectionData(
                  value: 100 - pct,
                  color: colorScheme.surfaceContainerHighest,
                  radius: 24,
                  showTitle: false,
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                'Efficiency',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VsRow extends StatelessWidget {
  const _VsRow(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
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
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _OverdueSection extends StatelessWidget {
  const _OverdueSection({required this.overdue, required this.currencySymbol});

  final OverdueRisk overdue;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    String fmt(num v) => CurrencyUtils.format(v, symbol: currencySymbol);
    final maxAmount = overdue.buckets.fold<double>(
      0,
      (a, b) => b.amount > a ? b.amount : a,
    );

    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 210,
            mainAxisExtent: 92,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemCount: 2,
          itemBuilder: (context, index) {
            return switch (index) {
              0 => _Tile(
                  label: 'Overdue Amount',
                  value: fmt(overdue.totalAmount),
                  icon: Icons.warning_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
              _ => _Tile(
                  label: 'Overdue Loans',
                  value: '${overdue.overdueLoans}',
                  icon: Icons.error_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
            };
          },
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overdue by Age',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                for (final bucket in overdue.buckets)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _OverdueBucketBar(
                      bucket: bucket,
                      maxAmount: maxAmount,
                      currencySymbol: currencySymbol,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (overdue.topAccounts.isNotEmpty) ...[
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top Overdue Accounts',
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  for (var i = 0; i < overdue.topAccounts.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  overdue.topAccounts[i].customerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${overdue.topAccounts[i].loanType == 'daily' ? 'Daily' : 'Weekly'} loan',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            fmt(overdue.topAccounts[i].amount),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _OverdueBucketBar extends StatelessWidget {
  const _OverdueBucketBar({
    required this.bucket,
    required this.maxAmount,
    required this.currencySymbol,
  });

  final OverdueBucket bucket;
  final double maxAmount;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final color = switch (bucket.label) {
      '8-14 days' => Colors.orange.shade700,
      '15+ days' => Theme.of(context).colorScheme.error,
      _ => Colors.amber.shade700,
    };
    final value = maxAmount > 0 ? bucket.amount / maxAmount : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              bucket.label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Text(
              '${bucket.loanCount} loans',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              CurrencyUtils.format(bucket.amount, symbol: currencySymbol),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }
}

class _ProfitSection extends StatelessWidget {
  const _ProfitSection({required this.summary, required this.currencySymbol});

  final ReportSummary summary;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    String fmt(num v) => CurrencyUtils.format(v, symbol: currencySymbol);
    final interest =
        s.dailyLoans.interestEarned + s.weeklyLoans.interestEarned;
    final fees = s.dailyLoans.feesEarned + s.weeklyLoans.feesEarned;
    final dailyProfit = s.dailyLoans.interestEarned + s.dailyLoans.feesEarned;
    final weeklyProfit =
        s.weeklyLoans.interestEarned + s.weeklyLoans.feesEarned;

    final tiles = <Widget>[
      _Tile(
        label: 'Net Profit',
        value: fmt(s.netProfit),
        icon: Icons.trending_up_rounded,
        color: s.netProfit < 0
            ? Theme.of(context).colorScheme.error
            : Colors.green,
      ),
      _Tile(
        label: 'Interest Earned',
        value: fmt(interest),
        icon: Icons.percent_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
      _Tile(
        label: 'Fees Earned',
        value: fmt(fees),
        icon: Icons.receipt_rounded,
        color: Theme.of(context).colorScheme.tertiary,
      ),
      _Tile(
        label: 'Daily Profit',
        value: fmt(dailyProfit),
        icon: Icons.today_rounded,
        color: AppTheme.secondaryColor,
      ),
      _Tile(
        label: 'Weekly Profit',
        value: fmt(weeklyProfit),
        icon: Icons.calendar_view_week_rounded,
        color: AppTheme.accentColor,
      ),
    ];
    return _TileGrid(tiles: tiles);
  }
}

class _SavingsSection extends StatelessWidget {
  const _SavingsSection({
    required this.savings,
    required this.trends,
    required this.currencySymbol,
  });

  final SavingsSummary savings;
  final DashboardTrends? trends;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    String fmt(num v) => CurrencyUtils.format(v, symbol: currencySymbol);
    final tiles = <Widget>[
      _Tile(
        label: 'Total Savings',
        value: fmt(savings.totalBalance),
        icon: Icons.savings_rounded,
        color: AppTheme.secondaryColor,
      ),
      _Tile(
        label: 'Savings In (Period)',
        value: fmt(savings.inflow),
        icon: Icons.south_west_rounded,
        color: Colors.green,
      ),
      _Tile(
        label: 'Savings Out (Period)',
        value: fmt(savings.outflow),
        icon: Icons.north_east_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      _Tile(
        label: 'Net Flow (Period)',
        value: fmt(savings.netFlow),
        icon: Icons.swap_vert_rounded,
        color: savings.netFlow < 0
            ? Theme.of(context).colorScheme.error
            : Colors.green,
      ),
    ];
    return Column(
      children: [
        _TileGrid(tiles: tiles),
        if (trends != null &&
            trends!.savingsIn.isNotEmpty &&
            trends!.savingsOut.isNotEmpty) ...[
          const SizedBox(height: 10),
          _LineTrendChart(
            title: 'Savings In vs Out',
            series1: trends!.savingsIn,
            series2: trends!.savingsOut,
            series1Color: AppTheme.secondaryColor,
            series2Color: AppTheme.accentColor,
            series1Label: 'Savings In',
            series2Label: 'Savings Out',
            currencySymbol: currencySymbol,
          ),
        ],
      ],
    );
  }
}

class _CustomersSection extends StatelessWidget {
  const _CustomersSection({
    required this.customers,
    required this.trends,
    required this.currencySymbol,
  });

  final CustomerStats customers;
  final DashboardTrends? trends;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _Tile(
        label: 'Total Customers',
        value: '${customers.totalCustomers}',
        icon: Icons.people_alt_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
      _Tile(
        label: 'New This Period',
        value: '${customers.newInPeriod}',
        icon: Icons.person_add_alt_rounded,
        color: Colors.green,
      ),
      _Tile(
        label: 'With Active Loans',
        value: '${customers.activeLoanCustomers}',
        icon: Icons.fact_check_rounded,
        color: AppTheme.accentColor,
      ),
    ];
    return Column(
      children: [
        _TileGrid(tiles: tiles),
        if (trends != null && trends!.customers.isNotEmpty) ...[
          const SizedBox(height: 10),
          _BarTrendChart(
            title: 'New Customers',
            series1: trends!.customers,
            series1Color: Theme.of(context).colorScheme.primary,
            series1Label: 'Customers',
            currencySymbol: currencySymbol,
            formatCounts: true,
          ),
        ],
        if (trends != null && trends!.loans.isNotEmpty) ...[
          const SizedBox(height: 10),
          _BarTrendChart(
            title: 'New Loans',
            series1: trends!.loans,
            series1Color: AppTheme.accentColor,
            series1Label: 'Loans',
            currencySymbol: currencySymbol,
            formatCounts: true,
          ),
        ],
      ],
    );
  }
}

/// Wrapping grid of [_Tile]s sized like the KPI grid.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisExtent: 92,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, index) => tiles[index],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
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

// ── Delta helpers ────────────────────────────────────────────────────────────

String _deltaLabel(double current, double previous) {
  if (previous <= 0) return current == 0 ? 'No change' : 'New';
  final change = (current - previous) / previous * 100;
  return '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}% vs prev';
}

String _ppDeltaLabel(double current, double previous) {
  final diff = current - previous;
  return '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}pp vs prev';
}

Color _deltaColor(bool positive, String delta, {bool inverted = false}) {
  if (delta == 'No change' || delta == 'New') {
    return AppTheme.primaryColor;
  }
  final good = inverted ? !positive : positive;
  return good ? Colors.green : AppTheme.errorColor;
}
