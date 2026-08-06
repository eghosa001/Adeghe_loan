import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../../groups/presentation/providers/group_providers.dart';
import '../../data/models/report_models.dart';
import '../../services/export_manager.dart';
import '../providers/report_provider.dart';
import '../widgets/report_ui.dart';

/// Collections Report: per-loan due/paid/outstanding across the selected
/// period. Built from the same source as the Collection screen so figures
/// always reconcile.
class CollectionsReportScreen extends ConsumerStatefulWidget {
  const CollectionsReportScreen({super.key});

  @override
  ConsumerState<CollectionsReportScreen> createState() =>
      _CollectionsReportScreenState();
}

class _CollectionsReportScreenState extends ConsumerState<CollectionsReportScreen> {
  late ReportPeriod _period;
  String? _loanType;
  String? _groupId;

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
    final collectionsAsync = ref.watch(collectionReportProvider(range));
    final groupsAsync = ref.watch(groupListProvider);
    final currencySymbol = ref.watch(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;

    final all = collectionsAsync.valueOrNull ?? const <CollectionReportRow>[];
    final rows = _groupId == null
        ? all
        : all.where((r) => r.groupName == _groupId).toList();

    return ReportScreenShell(
      title: 'Collections Report',
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
                groupsAsync.when(
                  loading: () => const SizedBox(
                    height: 36,
                    child: Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))),
                  ),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (groups) => DropdownButtonFormField<String>(
                    initialValue: _groupId,
                    decoration: const InputDecoration(
                      labelText: 'Group',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text('All Groups')),
                      ...groups.map((g) => DropdownMenuItem(
                          value: g.name, child: Text(g.name))),
                    ],
                    onChanged: (value) => setState(() =>
                        _groupId =
                            (value == null || value.isEmpty) ? null : value),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        collectionsAsync.when(
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
                      label: 'Loans Due',
                      value: '${rows.length}',
                      icon: Icons.request_quote_rounded),
                  ReportMetricCard(
                      label: 'Total Due',
                      value: CurrencyUtils.format(
                          _sum(rows, (r) => r.amountDue),
                          symbol: currencySymbol),
                      icon: Icons.event_available_rounded),
                  ReportMetricCard(
                      label: 'Total Paid',
                      value: CurrencyUtils.format(
                          _sum(rows, (r) => r.amountPaid),
                          symbol: currencySymbol),
                      icon: Icons.check_circle_rounded),
                  ReportMetricCard(
                      label: 'Remaining Due',
                      value: CurrencyUtils.format(
                          _sum(rows, (r) => r.balanceRemaining),
                          symbol: currencySymbol),
                      icon: Icons.hourglass_bottom_rounded),
                  ReportMetricCard(
                      label: 'Outstanding Bal.',
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
                  'Phone',
                  'Type',
                  'Group',
                  'Due',
                  'Paid',
                  'Remaining',
                  'Outstanding'
                ],
                rightAlignColumns: const [4, 5, 6, 7],
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

  double _sum(
          List<CollectionReportRow> rows, double Function(CollectionReportRow) f) =>
      rows.fold<double>(0, (a, b) => a + f(b));

  List<String> _row(CollectionReportRow r, String symbol) => [
        r.customerName,
        r.phone,
        r.loanType == 'daily' ? 'Daily' : 'Weekly',
        r.groupName ?? '—',
        CurrencyUtils.format(r.amountDue, symbol: symbol),
        CurrencyUtils.format(r.amountPaid, symbol: symbol),
        CurrencyUtils.format(r.balanceRemaining, symbol: symbol),
        CurrencyUtils.format(r.outstandingBalance, symbol: symbol),
      ];

  List<String>? _totalsRow(List<CollectionReportRow> rows, String symbol) {
    if (rows.isEmpty) return null;
    return [
      'Total (${rows.length})',
      '',
      '',
      '',
      CurrencyUtils.format(_sum(rows, (r) => r.amountDue), symbol: symbol),
      CurrencyUtils.format(_sum(rows, (r) => r.amountPaid), symbol: symbol),
      CurrencyUtils.format(_sum(rows, (r) => r.balanceRemaining), symbol: symbol),
      CurrencyUtils.format(
          _sum(rows, (r) => r.outstandingBalance), symbol: symbol),
    ];
  }

  Future<void> _export(
      BuildContext context, String action, List<CollectionReportRow> rows) async {
    final symbol = ref.read(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;
    final data = ReportExportData(
      reportName: 'Collections Report',
      periodLabel: _period.label,
      cards: [
        ReportCard('Loans Due', '${rows.length}'),
        ReportCard('Total Due', CurrencyUtils.format(_sum(rows, (r) => r.amountDue), symbol: symbol)),
        ReportCard('Total Paid', CurrencyUtils.format(_sum(rows, (r) => r.amountPaid), symbol: symbol)),
        ReportCard('Remaining Due', CurrencyUtils.format(_sum(rows, (r) => r.balanceRemaining), symbol: symbol)),
        ReportCard('Outstanding Bal.', CurrencyUtils.format(_sum(rows, (r) => r.outstandingBalance), symbol: symbol)),
      ],
      headers: const [
        'Customer',
        'Phone',
        'Type',
        'Group',
        'Due',
        'Paid',
        'Remaining',
        'Outstanding'
      ],
      rightAlignColumns: const [4, 5, 6, 7],
      rows: rows.map((r) => _row(r, symbol)).toList(),
      totalsRow: _totalsRow(rows, symbol),
    );
    await runReportExport(context: context, ref: ref, action: action, data: data);
  }
}
