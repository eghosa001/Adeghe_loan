import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../data/models/report_models.dart';
import '../../services/export_manager.dart';
import '../providers/report_provider.dart';
import '../widgets/report_ui.dart';

/// Savings Report: every savings account with its live balance and lifetime
/// ledger sums. Totals reflect net savings held across all customers.
class SavingsReportScreen extends ConsumerStatefulWidget {
  const SavingsReportScreen({super.key});

  @override
  ConsumerState<SavingsReportScreen> createState() =>
      _SavingsReportScreenState();
}

class _SavingsReportScreenState extends ConsumerState<SavingsReportScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final savingsAsync = ref.watch(savingsReportProvider);
    final currencySymbol = ref.watch(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;

    final all = savingsAsync.valueOrNull ?? const <SavingsReportRow>[];
    final query = _query.trim().toLowerCase();
    final filtered = all
        .where((s) =>
            query.isEmpty ||
            s.customerName.toLowerCase().contains(query) ||
            s.phone.contains(query))
        .toList();

    return ReportScreenShell(
      title: 'Savings Report',
      subtitle: 'Savings held across all customers',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by name or phone',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
        const SizedBox(height: 16),
        savingsAsync.when(
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
                      label: 'Accounts',
                      value: '${filtered.length}',
                      icon: Icons.savings_rounded),
                  ReportMetricCard(
                      label: 'Total Balance',
                      value: CurrencyUtils.format(
                          _sum(filtered, (s) => s.balance),
                          symbol: currencySymbol),
                      icon: Icons.account_balance_wallet_rounded),
                  ReportMetricCard(
                      label: 'Total Deposits',
                      value: CurrencyUtils.format(
                          _sum(filtered, (s) => s.totalDeposits),
                          symbol: currencySymbol),
                      icon: Icons.south_west_rounded),
                  ReportMetricCard(
                      label: 'Total Withdrawals',
                      value: CurrencyUtils.format(
                          _sum(filtered, (s) => s.totalWithdrawals),
                          symbol: currencySymbol),
                      icon: Icons.north_east_rounded),
                  ReportMetricCard(
                      label: 'Overpayment Surplus',
                      value: CurrencyUtils.format(
                          _sum(filtered, (s) => s.overpaymentSurplus),
                          symbol: currencySymbol),
                      icon: Icons.savings_rounded),
                ],
              ),
              const SizedBox(height: 16),
              ReportDataTable(
                columns: const [
                  'Customer',
                  'Phone',
                  'Group',
                  'Balance',
                  'Deposits',
                  'Withdrawals',
                  'Overpayment',
                  'Last Activity'
                ],
                rightAlignColumns: const [3, 4, 5, 6],
                rows:
                    filtered.map((s) => _row(s, currencySymbol)).toList(),
                totalsRow: _totalsRow(filtered, currencySymbol),
              ),
              const SizedBox(height: 16),
              ReportExportBar(
                enabled: filtered.isNotEmpty,
                onSavePdf: () => _export(context, 'pdf', filtered),
                onExcel: () => _export(context, 'excel', filtered),
                onPrint: () => _export(context, 'print', filtered),
              ),
            ],
          ),
        ),
      ],
    );
  }

  double _sum(List<SavingsReportRow> rows, double Function(SavingsReportRow) f) =>
      rows.fold<double>(0, (a, b) => a + f(b));

  List<String> _row(SavingsReportRow s, String symbol) => [
        s.customerName,
        s.phone,
        s.groupName ?? '—',
        CurrencyUtils.format(s.balance, symbol: symbol),
        CurrencyUtils.format(s.totalDeposits, symbol: symbol),
        CurrencyUtils.format(s.totalWithdrawals, symbol: symbol),
        CurrencyUtils.format(s.overpaymentSurplus, symbol: symbol),
        _lastActivity(s.lastActivityDate),
      ];

  String _lastActivity(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return AppDateUtils.formatDate(dt);
  }

  List<String>? _totalsRow(List<SavingsReportRow> rows, String symbol) {
    if (rows.isEmpty) return null;
    return [
      'Total (${rows.length})',
      '',
      '',
      CurrencyUtils.format(_sum(rows, (s) => s.balance), symbol: symbol),
      CurrencyUtils.format(_sum(rows, (s) => s.totalDeposits), symbol: symbol),
      CurrencyUtils.format(_sum(rows, (s) => s.totalWithdrawals), symbol: symbol),
      CurrencyUtils.format(_sum(rows, (s) => s.overpaymentSurplus), symbol: symbol),
      '',
    ];
  }

  Future<void> _export(
      BuildContext context, String action, List<SavingsReportRow> rows) async {
    final symbol = ref.read(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;
    final data = ReportExportData(
      reportName: 'Savings Report',
      periodLabel: 'All time',
      cards: [
        ReportCard('Accounts', '${rows.length}'),
        ReportCard('Total Balance', CurrencyUtils.format(_sum(rows, (s) => s.balance), symbol: symbol)),
        ReportCard('Total Deposits', CurrencyUtils.format(_sum(rows, (s) => s.totalDeposits), symbol: symbol)),
        ReportCard('Total Withdrawals', CurrencyUtils.format(_sum(rows, (s) => s.totalWithdrawals), symbol: symbol)),
        ReportCard('Overpayment Surplus', CurrencyUtils.format(_sum(rows, (s) => s.overpaymentSurplus), symbol: symbol)),
      ],
      headers: const [
        'Customer',
        'Phone',
        'Group',
        'Balance',
        'Deposits',
        'Withdrawals',
        'Overpayment',
        'Last Activity'
      ],
      rightAlignColumns: const [3, 4, 5, 6],
      rows: rows.map((s) => _row(s, symbol)).toList(),
      totalsRow: _totalsRow(rows, symbol),
    );
    await runReportExport(context: context, ref: ref, action: action, data: data);
  }
}
