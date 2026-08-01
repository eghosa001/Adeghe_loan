import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../data/models/report_summary.dart';
import '../providers/report_provider.dart';
import '../../services/export_manager.dart';
import 'analytics_tab.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _periodLabel(DateTime startDate, DateTime endDate) =>
      '${AppDateUtils.formatDate(startDate)} to ${AppDateUtils.formatDate(endDate)}';

  @override
  Widget build(BuildContext context) {
    final startDate = ref.watch(reportStartDateProvider);
    final endDate = ref.watch(reportEndDateProvider);
    final selectedLoanType = ref.watch(reportLoanTypeFilterProvider);
    final dateRange = ReportDateRange(start: startDate, end: endDate, loanType: selectedLoanType);
    final reportAsync = ref.watch(reportSummaryProvider(dateRange));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard_outlined)),
            Tab(text: 'Daily', icon: Icon(Icons.today)),
            Tab(text: 'Weekly', icon: Icon(Icons.date_range)),
            Tab(text: 'Overdue', icon: Icon(Icons.warning_amber_outlined)),
            Tab(text: 'Analytics', icon: Icon(Icons.analytics_outlined)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.file_download),
            onSelected: (value) async {
              final summary = await ref.read(reportSummaryProvider(dateRange).future);
              final range =
                  '${AppDateUtils.formatDate(startDate)} - ${AppDateUtils.formatDate(endDate)}';
              final currencySymbol =
                  ref.read(currencySymbolProvider).valueOrNull ??
                      CurrencyUtils.defaultSymbol;
              if (value == 'csv') {
                final file = await ExportManager.exportReportToCsv(
                    summary, 'Report_$range');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text('CSV exported: ${file.path.split(Platform.pathSeparator).last}')),
                  );
                }
              } else if (value == 'pdf') {
                final path =
                    await ExportManager.saveReportPdf(summary, 'Report_$range',
                        currencySymbol: currencySymbol);
                if (context.mounted && path != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('PDF saved to Documents')),
                  );
                }
              } else if (value == 'share_pdf') {
                await ExportManager.shareReportPdf(summary, 'Report_$range',
                    currencySymbol: currencySymbol);
              } else if (value == 'share_excel') {
                await ExportManager.shareReportXlsx(summary, 'Report_$range');
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'csv', child: Text('Export CSV')),
              const PopupMenuItem(value: 'pdf', child: Text('Save PDF')),
              const PopupMenuItem(value: 'share_pdf', child: Text('Share PDF')),
              const PopupMenuItem(value: 'share_excel', child: Text('Share Excel')),
            ],
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/reports'),
      body: Column(
        children: [
          // Period banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Row(
              children: [
                Icon(Icons.date_range, size: 16, color: Theme.of(context).colorScheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Report Period: ${_periodLabel(startDate, endDate)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: reportAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (summary) => TabBarView(
                controller: _tabController,
                children: [
                  _OverviewTab(summary: summary),
                  _DailyLoanTab(summary: summary),
                  _WeeklyLoanTab(summary: summary),
                  _OverdueTab(summary: summary),
                  const AnalyticsTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Overview Tab ───────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.summary});
  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final daily = summary.dailyLoans;
    final weekly = summary.weeklyLoans;
    final totalLoans = summary.activeLoans + summary.completedLoans + summary.defaultedLoans;
    final totalCustomers = summary.totalCustomers;
    final combinedEfficiency = (daily.expectedCollections + weekly.expectedCollections) > 0
        ? ((daily.amountCollected + weekly.amountCollected) /
            (daily.expectedCollections + weekly.expectedCollections) *
            100)
            .clamp(0.0, 100.0)
        : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Top-level summary row
        Row(
          children: [
            Expanded(child: _SummaryCard(
              title: 'Total Disbursed',
              value: CurrencyUtils.format(summary.totalDisbursed),
              icon: Icons.trending_up,
              color: Colors.orange,
            )),
            const SizedBox(width: 10),
            Expanded(child: _SummaryCard(
              title: 'Total Collected',
              value: CurrencyUtils.format(summary.totalCollected),
              icon: Icons.savings_outlined,
              color: Colors.green,
            )),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _SummaryCard(
              title: 'Net Profit',
              value: CurrencyUtils.format(summary.netProfit),
              icon: Icons.account_balance,
              color: summary.netProfit >= 0 ? Colors.teal : Colors.red,
            )),
            const SizedBox(width: 10),
            Expanded(child: _SummaryCard(
              title: 'Expected Collections',
              value: CurrencyUtils.format(daily.expectedCollections + weekly.expectedCollections),
              icon: Icons.calendar_today,
              color: Colors.blue,
            )),
          ],
        ),
        const SizedBox(height: 20),

        // Combined loan status
        Text('Loan Status Overview',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _StatusCard(
                label: 'Active', count: summary.activeLoans, color: Colors.green)),
            const SizedBox(width: 8),
            Expanded(child: _StatusCard(
                label: 'Completed', count: summary.completedLoans, color: Colors.blue)),
            const SizedBox(width: 8),
            Expanded(child: _StatusCard(
                label: 'Defaulted', count: summary.defaultedLoans, color: Colors.red)),
          ],
        ),
        const SizedBox(height: 16),

        // Second metrics row
        Row(
          children: [
            Expanded(child: _SummaryCard(
              title: 'Total Loans',
              value: totalLoans.toString(),
              icon: Icons.layers,
              color: Colors.indigo,
            )),
            const SizedBox(width: 10),
            Expanded(child: _SummaryCard(
              title: 'Total Customers',
              value: totalCustomers.toString(),
              icon: Icons.people,
              color: Colors.purple,
            )),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _SummaryCard(
              title: 'Interest Earned',
              value: CurrencyUtils.format(daily.interestEarned + weekly.interestEarned),
              icon: Icons.monetization_on,
              color: Colors.amber.shade700,
            )),
            const SizedBox(width: 10),
            Expanded(child: _SummaryCard(
              title: 'Fees Earned',
              value: CurrencyUtils.format(daily.feesEarned + weekly.feesEarned),
              icon: Icons.receipt,
              color: Colors.brown,
            )),
          ],
        ),
        const SizedBox(height: 10),

        // Collection efficiency with progress bar
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Collection Efficiency',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: combinedEfficiency / 100,
                          minHeight: 12,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation(
                            combinedEfficiency >= 75 ? Colors.green
                                : combinedEfficiency >= 50 ? Colors.orange
                                : Colors.red,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${combinedEfficiency.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: combinedEfficiency >= 75 ? Colors.green
                            : combinedEfficiency >= 50 ? Colors.orange
                            : Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Side-by-side comparison
        Text('Daily vs Weekly Breakdown',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _ComparisonCard(
              title: 'Daily',
              disbursed: daily.amountDisbursed,
              collected: daily.amountCollected,
              outstanding: daily.outstandingBalance,
              efficiency: daily.collectionEfficiency,
              active: daily.activeLoans,
              completed: daily.completedLoans,
              overdue: daily.overdueLoans,
            )),
            const SizedBox(width: 8),
            Expanded(child: _ComparisonCard(
              title: 'Weekly',
              disbursed: weekly.amountDisbursed,
              collected: weekly.amountCollected,
              outstanding: weekly.outstandingBalance,
              efficiency: weekly.collectionEfficiency,
              active: weekly.activeLoans,
              completed: weekly.completedLoans,
              overdue: weekly.overdueLoans,
            )),
          ],
        ),
        const SizedBox(height: 20),

        // Outstanding by client
        Text('Outstanding by Client',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (summary.clientReports.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No outstanding loans.'),
            ),
          )
        else
          ...summary.clientReports.map((c) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(c.customerName.isNotEmpty
                        ? c.customerName[0].toUpperCase()
                        : '?'),
                  ),
                  title: Text(c.customerName),
                  subtitle: Text(
                    '${c.loanType} loan${c.groupName != null ? ' — ${c.groupName}' : ''}'
                    '${c.phone.isNotEmpty ? '\n${c.phone}' : ''}',
                  ),
                  isThreeLine: c.phone.isNotEmpty,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        CurrencyUtils.format(c.outstandingBalance),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Paid: ${CurrencyUtils.format(c.totalPaid)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  onTap: () => context.push('/customers/${c.customerId}'),
                ),
              )),
      ],
    );
  }
}

// ── Daily Loan Tab ──────────────────────────────────────────────────────────

class _DailyLoanTab extends StatelessWidget {
  const _DailyLoanTab({required this.summary});
  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final daily = summary.dailyLoans;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Loan Status Row
        Row(children: [
          Expanded(child: _StatusCard(label: 'Active', count: daily.activeLoans, color: Colors.green)),
          const SizedBox(width: 8),
          Expanded(child: _StatusCard(label: 'Completed', count: daily.completedLoans, color: Colors.blue)),
          const SizedBox(width: 8),
          Expanded(child: _StatusCard(label: 'Defaulted', count: daily.defaultedLoans, color: Colors.red)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _StatusCard(label: 'Overdue', count: daily.overdueLoans, color: Colors.orange)),
          const SizedBox(width: 8),
          Expanded(child: _StatusCard(label: 'Customers', count: daily.customerCount, color: Colors.purple)),
          const SizedBox(width: 8),
          Expanded(child: _StatusCard(label: 'Total Loans', count: daily.activeLoans + daily.completedLoans + daily.defaultedLoans, color: Colors.indigo)),
        ]),
        const SizedBox(height: 12),

        // Financial Metrics
        _SummaryCard(title: 'Amount Disbursed', value: CurrencyUtils.format(daily.amountDisbursed), icon: Icons.trending_up, color: Colors.orange),
        const SizedBox(height: 10),
        _SummaryCard(title: 'Amount Collected', value: CurrencyUtils.format(daily.amountCollected), icon: Icons.savings_outlined, color: Colors.green),
        const SizedBox(height: 10),
        _SummaryCard(title: 'Outstanding Balance', value: CurrencyUtils.format(daily.outstandingBalance), icon: Icons.receipt_long, color: Colors.red),
        const SizedBox(height: 10),
        _SummaryCard(title: 'Expected Collections', value: CurrencyUtils.format(daily.expectedCollections), icon: Icons.calendar_today, color: Colors.blue),
        const SizedBox(height: 10),

        // Collection efficiency with progress bar
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Collection Efficiency',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (daily.collectionEfficiency / 100).clamp(0.0, 1.0),
                          minHeight: 10,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation(
                            daily.collectionEfficiency >= 75 ? Colors.green
                                : daily.collectionEfficiency >= 50 ? Colors.orange
                                : Colors.red,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${daily.collectionEfficiency.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: daily.collectionEfficiency >= 75 ? Colors.green
                            : daily.collectionEfficiency >= 50 ? Colors.orange
                            : Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Financial Breakdown
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Financial Breakdown', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const Divider(),
          _DetailRow(label: 'Interest Earned', value: CurrencyUtils.format(daily.interestEarned)),
          _DetailRow(label: 'Fees Earned', value: CurrencyUtils.format(daily.feesEarned)),
          _DetailRow(label: 'Savings from Overpayments', value: CurrencyUtils.format(daily.savingsFromOverpayments)),
          _DetailRow(label: 'Total Revenue', value: CurrencyUtils.format(daily.interestEarned + daily.feesEarned + daily.savingsFromOverpayments)),
        ]))),
        // Client breakdown
        const SizedBox(height: 16),
        Text('Outstanding by Client', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (daily.clientReports.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No outstanding loans.')))
        else
          ...daily.clientReports.map((c) => Card(child: ListTile(
            leading: CircleAvatar(child: Text(c.customerName.isNotEmpty ? c.customerName[0].toUpperCase() : '?')),
            title: Text(c.customerName),
            subtitle: Text(
              '${c.loanType} loan${c.groupName != null ? ' — ${c.groupName}' : ''}'
              '${c.phone.isNotEmpty ? '\n${c.phone}' : ''}',
            ),
            isThreeLine: c.phone.isNotEmpty,
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(CurrencyUtils.format(c.outstandingBalance), style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Paid: ${CurrencyUtils.format(c.totalPaid)}', style: Theme.of(context).textTheme.bodySmall),
            ]),
            onTap: () => context.push('/customers/${c.customerId}'),
          ))),
      ],
    );
  }
}

// ── Weekly Loan Tab ─────────────────────────────────────────────────────────

class _WeeklyLoanTab extends StatelessWidget {
  const _WeeklyLoanTab({required this.summary});
  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final weekly = summary.weeklyLoans;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Loan Status Row
        Row(children: [
          Expanded(child: _StatusCard(label: 'Active', count: weekly.activeLoans, color: Colors.green)),
          const SizedBox(width: 8),
          Expanded(child: _StatusCard(label: 'Completed', count: weekly.completedLoans, color: Colors.blue)),
          const SizedBox(width: 8),
          Expanded(child: _StatusCard(label: 'Defaulted', count: weekly.defaultedLoans, color: Colors.red)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _StatusCard(label: 'Overdue', count: weekly.overdueLoans, color: Colors.orange)),
          const SizedBox(width: 8),
          Expanded(child: _StatusCard(label: 'Customers', count: weekly.customerCount, color: Colors.purple)),
          const SizedBox(width: 8),
          Expanded(child: _StatusCard(label: 'Total Loans', count: weekly.activeLoans + weekly.completedLoans + weekly.defaultedLoans, color: Colors.indigo)),
        ]),
        const SizedBox(height: 12),

        // Financial Metrics
        _SummaryCard(title: 'Amount Disbursed', value: CurrencyUtils.format(weekly.amountDisbursed), icon: Icons.trending_up, color: Colors.orange),
        const SizedBox(height: 10),
        _SummaryCard(title: 'Amount Collected', value: CurrencyUtils.format(weekly.amountCollected), icon: Icons.savings_outlined, color: Colors.green),
        const SizedBox(height: 10),
        _SummaryCard(title: 'Outstanding Balance', value: CurrencyUtils.format(weekly.outstandingBalance), icon: Icons.receipt_long, color: Colors.red),
        const SizedBox(height: 10),
        _SummaryCard(title: 'Expected Collections', value: CurrencyUtils.format(weekly.expectedCollections), icon: Icons.calendar_today, color: Colors.blue),
        const SizedBox(height: 10),

        // Collection efficiency with progress bar
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Collection Efficiency',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (weekly.collectionEfficiency / 100).clamp(0.0, 1.0),
                          minHeight: 10,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation(
                            weekly.collectionEfficiency >= 75 ? Colors.green
                                : weekly.collectionEfficiency >= 50 ? Colors.orange
                                : Colors.red,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${weekly.collectionEfficiency.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: weekly.collectionEfficiency >= 75 ? Colors.green
                            : weekly.collectionEfficiency >= 50 ? Colors.orange
                            : Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Financial Breakdown
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Financial Breakdown', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const Divider(),
          _DetailRow(label: 'Interest Earned', value: CurrencyUtils.format(weekly.interestEarned)),
          _DetailRow(label: 'Fees Earned', value: CurrencyUtils.format(weekly.feesEarned)),
          _DetailRow(label: 'Savings from Overpayments', value: CurrencyUtils.format(weekly.savingsFromOverpayments)),
          _DetailRow(label: 'Total Revenue', value: CurrencyUtils.format(weekly.interestEarned + weekly.feesEarned + weekly.savingsFromOverpayments)),
        ]))),
        // Client breakdown
        const SizedBox(height: 16),
        Text('Outstanding by Client', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (weekly.clientReports.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No outstanding loans.')))
        else
          ...weekly.clientReports.map((c) => Card(child: ListTile(
            leading: CircleAvatar(child: Text(c.customerName.isNotEmpty ? c.customerName[0].toUpperCase() : '?')),
            title: Text(c.customerName),
            subtitle: Text(
              '${c.loanType} loan${c.groupName != null ? ' — ${c.groupName}' : ''}'
              '${c.phone.isNotEmpty ? '\n${c.phone}' : ''}',
            ),
            isThreeLine: c.phone.isNotEmpty,
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(CurrencyUtils.format(c.outstandingBalance), style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Paid: ${CurrencyUtils.format(c.totalPaid)}', style: Theme.of(context).textTheme.bodySmall),
            ]),
            onTap: () => context.push('/customers/${c.customerId}'),
          ))),
      ],
    );
  }
}

// ── Overdue Tab ─────────────────────────────────────────────────────────────

class _OverdueTab extends ConsumerWidget {
  const _OverdueTab({required this.summary});
  final ReportSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedLoanType = ref.watch(reportLoanTypeFilterProvider);
    final entries = selectedLoanType != null
        ? summary.overdueEntries.where((e) => e.loanType == selectedLoanType).toList()
        : summary.overdueEntries;

    final totalOverdue = entries.fold<double>(0, (sum, e) => sum + e.amountRemaining);
    final dailyOverdue = entries.where((e) => e.loanType == 'daily').toList();
    final weeklyOverdue = entries.where((e) => e.loanType == 'weekly').toList();
    final totalDaily = dailyOverdue.fold<double>(0, (s, e) => s + e.amountRemaining);
    final totalWeekly = weeklyOverdue.fold<double>(0, (s, e) => s + e.amountRemaining);
    final uniqueCustomers = entries.map((e) => e.customerId).toSet().length;

    if (entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
            SizedBox(height: 12),
            Text('No overdue installments', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary cards
        Row(
          children: [
            Expanded(child: _SummaryCard(
              title: 'Total Overdue',
              value: CurrencyUtils.format(totalOverdue),
              icon: Icons.warning_amber,
              color: Colors.red,
            )),
            const SizedBox(width: 10),
            Expanded(child: _SummaryCard(
              title: 'Installments',
              value: entries.length.toString(),
              icon: Icons.receipt_long,
              color: Colors.orange,
            )),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _SummaryCard(
              title: 'Affected Customers',
              value: uniqueCustomers.toString(),
              icon: Icons.people,
              color: Colors.red.shade700,
            )),
            const SizedBox(width: 10),
            Expanded(child: _SummaryCard(
              title: 'Avg. Overdue Days',
              value: entries.isEmpty
                  ? '0'
                  : '${(entries.fold<int>(0, (s, e) => s + e.overdueDays) / entries.length).round()}',
              icon: Icons.timer,
              color: Colors.orange.shade700,
            )),
          ],
        ),
        const SizedBox(height: 16),

        // Loan type breakdown
        if (dailyOverdue.isNotEmpty && weeklyOverdue.isNotEmpty) ...[
          Text('Overdue by Loan Type',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _TypeBreakdownCard(
                title: 'Daily Loans',
                amount: totalDaily,
                count: dailyOverdue.length,
                color: Colors.blue,
              )),
              const SizedBox(width: 8),
              Expanded(child: _TypeBreakdownCard(
                title: 'Weekly Loans',
                amount: totalWeekly,
                count: weeklyOverdue.length,
                color: Colors.teal,
              )),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // Overdue details
        Text('Overdue Installments',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...entries.map((e) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: e.overdueDays > 7
                      ? Colors.red.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.1),
                  child: Text(
                    '${e.overdueDays}d',
                    style: TextStyle(
                      color: e.overdueDays > 7 ? Colors.red : Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                title: Text(e.customerName),
                subtitle: Text(
                  '${e.loanType} loan — Installment #${e.installmentNumber}'
                  '${e.groupName != null ? ' — ${e.groupName}' : ''}'
                  '\nDue: ${e.dueDate}'
                  '${e.phone.isNotEmpty ? '\n${e.phone}' : ''}',
                ),
                isThreeLine: true,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      CurrencyUtils.format(e.amountRemaining),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                    Text(
                      'of ${CurrencyUtils.format(e.amountDue)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                onTap: () => context.push('/customers/${e.customerId}'),
              ),
            )),
      ],
    );
  }
}

// ── Shared Widgets ──────────────────────────────────────────────────────────

class _TypeBreakdownCard extends StatelessWidget {
  const _TypeBreakdownCard({
    required this.title,
    required this.amount,
    required this.count,
    required this.color,
  });

  final String title;
  final double amount;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(CurrencyUtils.format(amount),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                )),
            const SizedBox(height: 4),
            Text('$count installment(s)', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(value,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.title,
    required this.disbursed,
    required this.collected,
    required this.outstanding,
    required this.efficiency,
    required this.active,
    required this.completed,
    required this.overdue,
  });

  final String title;
  final double disbursed;
  final double collected;
  final double outstanding;
  final double efficiency;
  final int active;
  final int completed;
  final int overdue;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(),
            _DetailRow(label: 'Disbursed', value: CurrencyUtils.format(disbursed)),
            _DetailRow(label: 'Collected', value: CurrencyUtils.format(collected)),
            _DetailRow(label: 'Outstanding', value: CurrencyUtils.format(outstanding)),
            _DetailRow(label: 'Efficiency', value: '${efficiency.toStringAsFixed(1)}%'),
            const Divider(height: 8),
            _DetailRow(label: 'Active', value: active.toString()),
            _DetailRow(label: 'Completed', value: completed.toString()),
            _DetailRow(label: 'Overdue', value: overdue.toString()),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
