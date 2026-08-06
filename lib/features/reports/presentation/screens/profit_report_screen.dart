import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../data/models/report_models.dart';
import '../../services/export_manager.dart';
import '../providers/report_provider.dart';
import '../widgets/report_ui.dart';

/// Profit Report: one row per loan (cancelled loans excluded) in the selected
/// period. Profit = interest + fees earned above the principal disbursed.
class ProfitReportScreen extends ConsumerStatefulWidget {
  const ProfitReportScreen({super.key});

  @override
  ConsumerState<ProfitReportScreen> createState() => _ProfitReportScreenState();
}

class _ProfitReportScreenState extends ConsumerState<ProfitReportScreen> {
  late ReportPeriod _period;
  String? _loanType;
  String? _status;

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
        start: _period.start, end: _period.end, loanType: _loanType);
    final profitAsync = ref.watch(profitReportProvider(range));
    final currencySymbol = ref.watch(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;

    final all = profitAsync.valueOrNull ?? const <ProfitReportRow>[];
    final rows = all
        .where((r) => _status == null || r.status == _status)
        .toList();

    return ReportScreenShell(
      title: 'Profit Report',
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
                  'Filters',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '', label: Text('All Types')),
                    ButtonSegment(value: 'daily', label: Text('Daily')),
                    ButtonSegment(value: 'weekly', label: Text('Weekly')),
                  ],
                  selected: {_loanType ?? ''},
                  onSelectionChanged: (selection) => setState(
                      () => _loanType =
                          selection.first.isEmpty ? null : selection.first),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '', label: Text('All Status')),
                    ButtonSegment(value: 'active', label: Text('Active')),
                    ButtonSegment(value: 'completed', label: Text('Completed')),
                    ButtonSegment(value: 'defaulted', label: Text('Defaulted')),
                  ],
                  selected: {_status ?? ''},
                  onSelectionChanged: (selection) => setState(
                      () => _status =
                          selection.first.isEmpty ? null : selection.first),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        profitAsync.when(
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
          data: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReportMetricStrip(
                cards: [
                  ReportMetricCard(
                      label: 'Loans',
                      value: '${rows.length}',
                      icon: Icons.request_quote_rounded),
                  ReportMetricCard(
                      label: 'Total Principal',
                      value: CurrencyUtils.format(
                          _sum(rows, (r) => r.principal),
                          symbol: currencySymbol),
                      icon: Icons.payments_rounded),
                  ReportMetricCard(
                      label: 'Interest',
                      value: CurrencyUtils.format(
                          _sum(rows, (r) => r.interest),
                          symbol: currencySymbol),
                      icon: Icons.percent_rounded),
                  ReportMetricCard(
                      label: 'Fees',
                      value: CurrencyUtils.format(_sum(rows, (r) => r.fees),
                          symbol: currencySymbol),
                      icon: Icons.receipt_rounded),
                  ReportMetricCard(
                      label: 'Expected Profit',
                      value: CurrencyUtils.format(
                          _sum(rows, (r) => r.expectedProfit),
                          symbol: currencySymbol),
                      icon: Icons.trending_up_rounded),
                  ReportMetricCard(
                      label: 'Realised Profit',
                      value: CurrencyUtils.format(
                          _sum(rows, (r) => r.realisedProfit),
                          symbol: currencySymbol),
                      icon: Icons.savings_rounded),
                  ReportMetricCard(
                      label: 'Collected',
                      value: CurrencyUtils.format(
                          _sum(rows, (r) => r.totalCollected),
                          symbol: currencySymbol),
                      icon: Icons.done_all_rounded),
                  ReportMetricCard(
                      label: 'Outstanding',
                      value: CurrencyUtils.format(
                          _sum(rows, (r) => r.outstandingBalance),
                          symbol: currencySymbol),
                      icon: Icons.account_balance_rounded),
                ],
              ),
              const SizedBox(height: 16),
              ReportDataTable(
                columns: const [
                  'Customer',
                  'Type',
                  'Date',
                  'Principal',
                  'Interest',
                  'Fees',
                  'Expected',
                  'Collected',
                  'Outstanding',
                  'Profit',
                  'Status'
                ],
                rightAlignColumns: const [3, 4, 5, 6, 7, 8, 9],
                rows: rows.map((r) => _row(r, currencySymbol)).toList(),
                totalsRow: _totalsRow(rows, currencySymbol),
              ),
              const SizedBox(height: 16),
              ReportExportBar(
                enabled: rows.isNotEmpty,
                onSavePdf: () => _export(context, 'pdf', rows),
                onExcel: () => _export(context, 'excel', rows),
                onPrint: () => _export(context, 'print', rows),
              ),
            ],
          ),
        ),
      ],
    );
  }

  double _sum(List<ProfitReportRow> rows, double Function(ProfitReportRow) f) =>
      rows.fold<double>(0, (a, b) => a + f(b));

  List<String> _row(ProfitReportRow r, String symbol) => [
        r.customerName,
        r.loanType,
        r.loanDate,
        CurrencyUtils.format(r.principal, symbol: symbol),
        CurrencyUtils.format(r.interest, symbol: symbol),
        CurrencyUtils.format(r.fees, symbol: symbol),
        CurrencyUtils.format(r.expectedRepayment, symbol: symbol),
        CurrencyUtils.format(r.totalCollected, symbol: symbol),
        CurrencyUtils.format(r.outstandingBalance, symbol: symbol),
        CurrencyUtils.format(r.expectedProfit, symbol: symbol),
        _statusLabel(r.status),
      ];

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

  List<String>? _totalsRow(List<ProfitReportRow> rows, String symbol) {
    if (rows.isEmpty) return null;
    return [
      'Total (${rows.length})',
      '',
      '',
      CurrencyUtils.format(_sum(rows, (r) => r.principal), symbol: symbol),
      CurrencyUtils.format(_sum(rows, (r) => r.interest), symbol: symbol),
      CurrencyUtils.format(_sum(rows, (r) => r.fees), symbol: symbol),
      CurrencyUtils.format(_sum(rows, (r) => r.expectedRepayment), symbol: symbol),
      CurrencyUtils.format(_sum(rows, (r) => r.totalCollected), symbol: symbol),
      CurrencyUtils.format(_sum(rows, (r) => r.outstandingBalance), symbol: symbol),
      CurrencyUtils.format(_sum(rows, (r) => r.expectedProfit), symbol: symbol),
      '',
    ];
  }

  Future<void> _export(
      BuildContext context, String action, List<ProfitReportRow> rows) async {
    final symbol = ref.read(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;
    final data = ReportExportData(
      reportName: 'Profit Report',
      periodLabel: _period.label,
      cards: [
        ReportCard('Loans', '${rows.length}'),
        ReportCard('Total Principal', CurrencyUtils.format(_sum(rows, (r) => r.principal), symbol: symbol)),
        ReportCard('Interest', CurrencyUtils.format(_sum(rows, (r) => r.interest), symbol: symbol)),
        ReportCard('Fees', CurrencyUtils.format(_sum(rows, (r) => r.fees), symbol: symbol)),
        ReportCard('Expected Profit', CurrencyUtils.format(_sum(rows, (r) => r.expectedProfit), symbol: symbol)),
        ReportCard('Realised Profit', CurrencyUtils.format(_sum(rows, (r) => r.realisedProfit), symbol: symbol)),
        ReportCard('Collected', CurrencyUtils.format(_sum(rows, (r) => r.totalCollected), symbol: symbol)),
        ReportCard('Outstanding', CurrencyUtils.format(_sum(rows, (r) => r.outstandingBalance), symbol: symbol)),
      ],
      headers: const [
        'Customer',
        'Type',
        'Date',
        'Principal',
        'Interest',
        'Fees',
        'Expected',
        'Collected',
        'Outstanding',
        'Profit',
        'Status'
      ],
      rightAlignColumns: const [3, 4, 5, 6, 7, 8, 9],
      rows: rows.map((r) => _row(r, symbol)).toList(),
      totalsRow: _totalsRow(rows, symbol),
    );
    await runReportExport(context: context, ref: ref, action: action, data: data);
  }
}
