import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../data/models/report_summary.dart';
import '../../services/export_manager.dart';
import '../providers/report_provider.dart';
import '../widgets/report_ui.dart';

/// Unified Overdue Report. Tabs (All / Daily / Weekly) and each tab's export
/// only ever contain that tab's filtered rows, so summaries and exports never
/// diverge from what is on screen.
class OverdueReportScreen extends ConsumerStatefulWidget {
  const OverdueReportScreen({super.key});

  @override
  ConsumerState<OverdueReportScreen> createState() => _OverdueReportScreenState();
}

class _OverdueReportScreenState extends ConsumerState<OverdueReportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  static const _tabs = ['All', 'Daily', 'Weekly'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String? get _loanTypeFilter {
    switch (_tabController.index) {
      case 1:
        return 'daily';
      case 2:
        return 'weekly';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final overdueAsync = ref.watch(overdueReportProvider);
    final currencySymbol = ref.watch(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;

    return ReportScreenShell(
      title: 'Overdue Report',
      subtitle: 'Unpaid installments past their due date',
      children: [
        overdueAsync.when(
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
          data: (entries) {
            final filtered = entries
                .where((e) =>
                    _loanTypeFilter == null ||
                    e.loanType.toLowerCase() == _loanTypeFilter)
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'All'),
                    Tab(text: 'Daily'),
                    Tab(text: 'Weekly'),
                  ],
                  onTap: (_) => setState(() {}),
                  labelColor: Theme.of(context).colorScheme.primary,
                  unselectedLabelColor:
                      Theme.of(context).colorScheme.onSurfaceVariant,
                  indicatorColor: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                _SummaryStrip(entries: filtered, currencySymbol: currencySymbol),
                const SizedBox(height: 16),
                ReportDataTable(
                  columns: const [
                    'Customer',
                    'Phone',
                    'Type',
                    'Inst #',
                    'Due Date',
                    'Amount Due',
                    'Amount Owed',
                    'Days'
                  ],
                  rightAlignColumns: const [5, 6, 7],
                  rows: filtered.map((e) => _row(e, currencySymbol)).toList(),
                  totalsRow: _totalsRow(filtered, currencySymbol),
                  emptyMessage: 'No overdue installments.',
                ),
                const SizedBox(height: 16),
                ReportExportBar(
                  enabled: filtered.isNotEmpty,
                  onSavePdf: () => _export(context, 'pdf', filtered),
                  onExcel: () => _export(context, 'excel', filtered),
                  onPrint: () => _export(context, 'print', filtered),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  List<String> _row(OverdueEntry e, String symbol) => [
        e.customerName,
        e.phone,
        e.loanType,
        '${e.installmentNumber}',
        e.dueDate,
        CurrencyUtils.format(e.amountDue, symbol: symbol),
        CurrencyUtils.format(e.amountRemaining, symbol: symbol),
        '${e.overdueDays}',
      ];

  List<String>? _totalsRow(List<OverdueEntry> entries, String symbol) {
    if (entries.isEmpty) return null;
    final totalDue =
        entries.fold<double>(0, (s, e) => s + e.amountDue);
    final totalOwed = entries.fold<double>(0, (s, e) => s + e.amountRemaining);
    return [
      'Total (${entries.length})',
      '',
      '',
      '',
      '',
      CurrencyUtils.format(totalDue, symbol: symbol),
      CurrencyUtils.format(totalOwed, symbol: symbol),
      '',
    ];
  }

  Future<void> _export(
      BuildContext context, String action, List<OverdueEntry> filtered) async {
    final symbol = ref.read(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;
    final totalOwed =
        filtered.fold<double>(0, (s, e) => s + e.amountRemaining);
    final customers = filtered.map((e) => e.customerId).toSet().length;
    final avgDays = filtered.isEmpty
        ? 0
        : filtered.fold<int>(0, (s, e) => s + e.overdueDays) ~/
            filtered.length;

    final tabLabel = _tabs[_tabController.index];
    final data = ReportExportData(
      reportName: 'Overdue Report - $tabLabel',
      periodLabel: 'As at ${AppDateUtils.formatDate(DateTime.now())}',
      cards: [
        ReportCard('Total Overdue', CurrencyUtils.format(totalOwed, symbol: symbol), highlight: true),
        ReportCard('Installments', '${filtered.length}'),
        ReportCard('Customers', '$customers'),
        ReportCard('Avg Days', '$avgDays'),
      ],
      headers: const [
        'Customer',
        'Phone',
        'Type',
        'Inst #',
        'Due Date',
        'Amount Due',
        'Amount Owed',
        'Days'
      ],
      rightAlignColumns: const [5, 6, 7],
      rows: filtered.map((e) => _row(e, symbol)).toList(),
      totalsRow: _totalsRow(filtered, symbol),
    );
    await runReportExport(context: context, ref: ref, action: action, data: data);
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.entries, required this.currencySymbol});

  final List<OverdueEntry> entries;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final totalOwed = entries.fold<double>(0, (s, e) => s + e.amountRemaining);
    final customers = entries.map((e) => e.customerId).toSet().length;
    final avgDays = entries.isEmpty
        ? 0
        : entries.fold<int>(0, (s, e) => s + e.overdueDays) ~/ entries.length;
    return ReportMetricStrip(
      cards: [
        ReportMetricCard(
          label: 'Total Overdue',
          value: CurrencyUtils.format(totalOwed, symbol: currencySymbol),
          icon: Icons.warning_rounded,
          accent: totalOwed > 0,
        ),
        ReportMetricCard(
            label: 'Installments',
            value: '${entries.length}',
            icon: Icons.event_busy_rounded),
        ReportMetricCard(
            label: 'Customers',
            value: '$customers',
            icon: Icons.people_alt_rounded),
        ReportMetricCard(
            label: 'Avg Days',
            value: '$avgDays',
            icon: Icons.timer_rounded),
      ],
    );
  }
}
