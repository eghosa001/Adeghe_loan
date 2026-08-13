import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../data/models/report_summary.dart';
import '../../services/export_manager.dart';
import '../providers/report_provider.dart';
import '../widgets/report_ui.dart';

/// Weekly Loan Report: one row per weekly loan in the selected period. Each
/// row shows the savings collected and the start date with its weekday
/// (e.g. "12 August 2026 (Wednesday)").
class WeeklyLoanReportScreen extends ConsumerStatefulWidget {
  const WeeklyLoanReportScreen({super.key});

  @override
  ConsumerState<WeeklyLoanReportScreen> createState() =>
      _WeeklyLoanReportScreenState();
}

class _WeeklyLoanReportScreenState
    extends ConsumerState<WeeklyLoanReportScreen> {
  late ReportPeriod _period;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _period = ReportPeriod(
      DateTime(now.year, now.month, 1),
      DateTime(now.year, now.month + 1, 0),
      'This Month',
    );
  }

  @override
  Widget build(BuildContext context) {
    final range = ReportDateRange(
        start: _period.start, end: _period.end, loanType: 'weekly');
    final summaryAsync = ref.watch(reportSummaryProvider(range));
    final currencySymbol = ref.watch(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;

    final summary = summaryAsync.valueOrNull;
    final reports = (summary?.weeklyLoans.clientReports ?? [])
        .where((r) => _statusFilter == null || r.loanStatus == _statusFilter)
        .toList();

    return ReportScreenShell(
      title: 'Weekly Loan Report',
      subtitle: _period.label,
      children: [
        ReportPeriodSelector(
          onChanged: (period) => setState(() => _period = period),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Loan Status',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '', label: Text('All')),
                    ButtonSegment(value: 'active', label: Text('Active')),
                    ButtonSegment(value: 'defaulted', label: Text('Defaulted')),
                  ],
                  selected: {_statusFilter ?? ''},
                  onSelectionChanged: (selection) => setState(
                      () => _statusFilter =
                          selection.first.isEmpty ? null : selection.first),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
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
          data: (s) {
            final d = s.weeklyLoans;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReportMetricStrip(
                  cards: [
                    ReportMetricCard(
                        label: 'Active',
                        value: '${d.activeLoans}',
                        icon: Icons.fact_check_rounded),
                    ReportMetricCard(
                        label: 'Completed',
                        value: '${d.completedLoans}',
                        icon: Icons.check_circle_rounded),
                    ReportMetricCard(
                        label: 'Overdue',
                        value: '${d.overdueLoans}',
                        icon: Icons.warning_rounded,
                        accent: d.overdueLoans > 0),
                    ReportMetricCard(
                        label: 'Disbursed',
                        value: CurrencyUtils.format(d.amountDisbursed,
                            symbol: currencySymbol),
                        icon: Icons.payments_rounded),
                    ReportMetricCard(
                        label: 'Collected',
                        value: CurrencyUtils.format(d.amountCollected,
                            symbol: currencySymbol),
                        icon: Icons.savings_rounded),
                    ReportMetricCard(
                        label: 'Savings',
                        value: CurrencyUtils.format(
                            d.savingsFromOverpayments,
                            symbol: currencySymbol),
                        icon: Icons.savings_rounded),
                    ReportMetricCard(
                        label: 'Outstanding',
                        value: CurrencyUtils.format(d.outstandingBalance,
                            symbol: currencySymbol),
                        icon: Icons.account_balance_rounded),
                    ReportMetricCard(
                        label: 'Efficiency',
                        value: '${d.collectionEfficiency.toStringAsFixed(1)}%',
                        icon: Icons.speed_rounded),
                  ],
                ),
                const SizedBox(height: 16),
                ReportDataTable(
                  columns: const [
                    'Customer',
                    'Phone',
                    'Guarantor',
                    'G. Phone',
                    'Disbursement Date',
                    'Amount',
                    'Interest',
                    'Savings',
                    'Expected',
                    'Collected',
                    'Remaining',
                    'Status'
                  ],
                  rightAlignColumns: const [5, 6, 7, 8, 9, 10],
                  rows: reports.map((r) => _row(r, currencySymbol)).toList(),
                  totalsRow: _totalsRow(reports, currencySymbol),
                ),
                const SizedBox(height: 16),
                ReportExportBar(
                  onSavePdf: () => _export(context, 'pdf'),
                  onExcel: () => _export(context, 'excel'),
                  onPrint: () => _export(context, 'print'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  List<String> _row(ClientReport r, String symbol) {
    final date = DateTime.tryParse(r.loanDate) ?? DateTime.now();
    // For weekly loans, the loanDate comes from l.loan_date (disbursement date).
    // in the repository query. For daily loans, it's the loan_date.
    final dateStr = AppDateUtils.formatDate(date, format: 'dd MMMM yyyy (EEEE)');
    return [
      r.customerName,
      r.phone,
      r.guarantorName,
      r.guarantorPhone,
      dateStr,
      CurrencyUtils.format(r.amountBorrowed, symbol: symbol),
      CurrencyUtils.format(r.interestAmount, symbol: symbol),
      CurrencyUtils.format(r.savingsAmount, symbol: symbol),
      CurrencyUtils.format(r.expectedAmount, symbol: symbol),
      CurrencyUtils.format(r.totalPaid, symbol: symbol),
      CurrencyUtils.format(r.amountRemaining, symbol: symbol),
      _statusLabel(r.loanStatus),
    ];
  }

  List<String>? _totalsRow(List<ClientReport> reports, String symbol) {
    if (reports.isEmpty) return null;
    double sum(Iterable<double> values) =>
        values.fold<double>(0, (a, b) => a + b);
    return [
      'Total (${reports.length})',
      '',
      '',
      '',
      '',
      CurrencyUtils.format(sum(reports.map((r) => r.amountBorrowed)), symbol: symbol),
      CurrencyUtils.format(sum(reports.map((r) => r.interestAmount)), symbol: symbol),
      CurrencyUtils.format(sum(reports.map((r) => r.savingsAmount)), symbol: symbol),
      CurrencyUtils.format(sum(reports.map((r) => r.expectedAmount)), symbol: symbol),
      CurrencyUtils.format(sum(reports.map((r) => r.totalPaid)), symbol: symbol),
      CurrencyUtils.format(sum(reports.map((r) => r.amountRemaining)), symbol: symbol),
      '',
    ];
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'completed':
        return 'Completed';
      case 'defaulted':
        return 'Defaulted';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  Future<void> _export(BuildContext context, String action) async {
    final summary = ref
        .read(reportSummaryProvider(ReportDateRange(
            start: _period.start, end: _period.end, loanType: 'weekly')))
        .valueOrNull;
    if (summary == null) return;
    final reports = summary.weeklyLoans.clientReports
        .where((r) => _statusFilter == null || r.loanStatus == _statusFilter)
        .toList();
    final symbol = ref.read(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;
    final d = summary.weeklyLoans;

    final cards = <ReportCard>[
      ReportCard('Active Loans', '${d.activeLoans}'),
      ReportCard('Completed Loans', '${d.completedLoans}'),
      ReportCard('Overdue Loans', '${d.overdueLoans}'),
      ReportCard('Disbursed', CurrencyUtils.format(d.amountDisbursed, symbol: symbol)),
      ReportCard('Collected', CurrencyUtils.format(d.amountCollected, symbol: symbol)),
      ReportCard('Savings Collected', CurrencyUtils.format(d.savingsFromOverpayments, symbol: symbol)),
      ReportCard('Outstanding', CurrencyUtils.format(d.outstandingBalance, symbol: symbol)),
      ReportCard('Expected', CurrencyUtils.format(d.expectedCollections, symbol: symbol)),
      ReportCard('Efficiency', '${d.collectionEfficiency.toStringAsFixed(1)}%'),
      ReportCard('Interest', CurrencyUtils.format(d.interestEarned, symbol: symbol)),
      ReportCard('Fees', CurrencyUtils.format(d.feesEarned, symbol: symbol)),
      ReportCard('Customers', '${d.customerCount}'),
    ];

    final data = ReportExportData(
      reportName: 'Weekly Loan Report',
      periodLabel: _period.label,
      cards: cards,
      headers: const [
        'Customer',
        'Phone',
        'Guarantor',
        'G. Phone',
        'Disbursement Date',
        'Amount',
        'Interest',
        'Savings',
        'Expected',
        'Collected',
        'Remaining',
        'Status'
      ],
      rightAlignColumns: const [5, 6, 7, 8, 9, 10],
      rows: reports.map((r) => _row(r, symbol)).toList(),
      totalsRow: _totalsRow(reports, symbol),
    );
    await runReportExport(context: context, ref: ref, action: action, data: data);
  }
}
