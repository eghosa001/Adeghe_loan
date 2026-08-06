import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../../groups/presentation/providers/group_providers.dart';
import '../../data/models/report_models.dart';
import '../../services/export_manager.dart';
import '../providers/report_provider.dart';
import '../widgets/report_ui.dart';

/// Customer Report: one row per customer with lifetime loan aggregates and
/// their savings balance. No date filter — figures are lifetime so the
/// report reconciles with the summary and profit screens.
class CustomerReportScreen extends ConsumerStatefulWidget {
  const CustomerReportScreen({super.key});

  @override
  ConsumerState<CustomerReportScreen> createState() =>
      _CustomerReportScreenState();
}

class _CustomerReportScreenState extends ConsumerState<CustomerReportScreen> {
  String? _groupFilter;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customerReportProvider);
    final groupsAsync = ref.watch(groupListProvider);
    final currencySymbol = ref.watch(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;

    final groups = groupsAsync.valueOrNull ?? const [];
    final allCustomers = customersAsync.valueOrNull ?? const <CustomerReportRow>[];

    final filtered = allCustomers
        .where((c) {
          final groupMatches = _groupFilter == null ||
              (c.groupName ?? '') == _groupFilter;
          final query = _query.trim().toLowerCase();
          final queryMatches = query.isEmpty ||
              c.customerName.toLowerCase().contains(query) ||
              c.phone.contains(query);
          return groupMatches && queryMatches;
        })
        .toList();

    return ReportScreenShell(
      title: 'Customer Report',
      subtitle: 'Lifetime aggregates per customer',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search by name or phone',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _groupChip('All Groups', _groupFilter == null, () {
                        setState(() => _groupFilter = null);
                      }),
                      for (final g in groups) ...[
                        const SizedBox(width: 6),
                        _groupChip(
                            g.name, _groupFilter == g.name, () {
                          setState(() => _groupFilter = g.name);
                        }),
                      ],
                      const SizedBox(width: 6),
                      _groupChip('No Group', _groupFilter == '', () {
                        setState(() => _groupFilter = '');
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        customersAsync.when(
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
                      label: 'Customers',
                      value: '${filtered.length}',
                      icon: Icons.people_alt_rounded),
                  ReportMetricCard(
                      label: 'Total Disbursed',
                      value: CurrencyUtils.format(
                          _sum(filtered, (c) => c.totalDisbursed),
                          symbol: currencySymbol),
                      icon: Icons.payments_rounded),
                  ReportMetricCard(
                      label: 'Total Collected',
                      value: CurrencyUtils.format(
                          _sum(filtered, (c) => c.totalCollected),
                          symbol: currencySymbol),
                      icon: Icons.savings_rounded),
                  ReportMetricCard(
                      label: 'Outstanding',
                      value: CurrencyUtils.format(
                          _sum(filtered, (c) => c.outstandingBalance),
                          symbol: currencySymbol),
                      icon: Icons.account_balance_rounded),
                  ReportMetricCard(
                      label: 'Total Savings',
                      value: CurrencyUtils.format(
                          _sum(filtered, (c) => c.savingsBalance),
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
                  'Registered',
                  'Loans',
                  'Active',
                  'Disbursed',
                  'Collected',
                  'Outstanding',
                  'Savings'
                ],
                rightAlignColumns: const [6, 7, 8, 9],
                rows:
                    filtered.map((c) => _row(c, currencySymbol)).toList(),
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

  Widget _groupChip(String label, bool selected, VoidCallback onTap) {
    final colorScheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: colorScheme.primary.withValues(alpha: 0.12),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
    );
  }

  double _sum(List<CustomerReportRow> rows, double Function(CustomerReportRow) f) =>
      rows.fold<double>(0, (a, b) => a + f(b));

  List<String> _row(CustomerReportRow c, String symbol) => [
        c.customerName,
        c.phone,
        c.groupName ?? '—',
        c.dateRegistered,
        '${c.loanCount}',
        '${c.activeLoanCount}',
        CurrencyUtils.format(c.totalDisbursed, symbol: symbol),
        CurrencyUtils.format(c.totalCollected, symbol: symbol),
        CurrencyUtils.format(c.outstandingBalance, symbol: symbol),
        CurrencyUtils.format(c.savingsBalance, symbol: symbol),
      ];

  List<String>? _totalsRow(List<CustomerReportRow> rows, String symbol) {
    if (rows.isEmpty) return null;
    return [
      'Total (${rows.length})',
      '',
      '',
      '',
      _sum(rows, (c) => c.loanCount.toDouble()).toStringAsFixed(0),
      _sum(rows, (c) => c.activeLoanCount.toDouble()).toStringAsFixed(0),
      CurrencyUtils.format(_sum(rows, (c) => c.totalDisbursed), symbol: symbol),
      CurrencyUtils.format(_sum(rows, (c) => c.totalCollected), symbol: symbol),
      CurrencyUtils.format(_sum(rows, (c) => c.outstandingBalance), symbol: symbol),
      CurrencyUtils.format(_sum(rows, (c) => c.savingsBalance), symbol: symbol),
    ];
  }

  Future<void> _export(
      BuildContext context, String action, List<CustomerReportRow> rows) async {
    final symbol = ref.read(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;
    final data = ReportExportData(
      reportName: 'Customer Report',
      periodLabel: 'All time',
      cards: [
        ReportCard('Customers', '${rows.length}'),
        ReportCard('Total Disbursed', CurrencyUtils.format(_sum(rows, (c) => c.totalDisbursed), symbol: symbol)),
        ReportCard('Total Collected', CurrencyUtils.format(_sum(rows, (c) => c.totalCollected), symbol: symbol)),
        ReportCard('Outstanding', CurrencyUtils.format(_sum(rows, (c) => c.outstandingBalance), symbol: symbol)),
        ReportCard('Total Savings', CurrencyUtils.format(_sum(rows, (c) => c.savingsBalance), symbol: symbol)),
      ],
      headers: const [
        'Customer',
        'Phone',
        'Group',
        'Registered',
        'Loans',
        'Active',
        'Disbursed',
        'Collected',
        'Outstanding',
        'Savings'
      ],
      rightAlignColumns: const [6, 7, 8, 9],
      rows: rows.map((c) => _row(c, symbol)).toList(),
      totalsRow: _totalsRow(rows, symbol),
    );
    await runReportExport(context: context, ref: ref, action: action, data: data);
  }
}
