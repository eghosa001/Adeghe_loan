import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/app_drawer.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../data/models/report_summary.dart';
import '../../services/export_manager.dart';
import '../providers/report_provider.dart';

class OverdueReportScreen extends ConsumerStatefulWidget {
  const OverdueReportScreen({super.key});

  @override
  ConsumerState<OverdueReportScreen> createState() => _OverdueReportScreenState();
}

class _OverdueReportScreenState extends ConsumerState<OverdueReportScreen> {
  String? _selectedLoanType;
  int _minDaysOverdue = 0;

  List<OverdueEntry> _applyFilters(List<OverdueEntry> entries) {
    var filtered = entries;
    if (_selectedLoanType != null) {
      filtered = filtered.where((e) => e.loanType == _selectedLoanType).toList();
    }
    if (_minDaysOverdue > 0) {
      filtered = filtered.where((e) => e.overdueDays >= _minDaysOverdue).toList();
    }
    return filtered;
  }

  Future<void> _savePdf(List<OverdueEntry> entries) async {
    final filtered = _applyFilters(entries);
    try {
      final path = await ExportManager.saveOverduePdf(filtered, 'Overdue Report',
          currencySymbol: _currencySymbol);
      if (!mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF saved to Documents')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save PDF: $e')),
      );
    }
  }

  Future<void> _sharePdf(List<OverdueEntry> entries) async {
    final filtered = _applyFilters(entries);
    try {
      await ExportManager.shareOverduePdf(filtered, 'Overdue Report',
          currencySymbol: _currencySymbol);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share PDF: $e')),
      );
    }
  }

  String get _currencySymbol =>
      ref.read(currencySymbolProvider).valueOrNull ??
      CurrencyUtils.defaultSymbol;

  @override
  Widget build(BuildContext context) {
    final asyncEntries = ref.watch(overdueReportProvider);
    final theme = Theme.of(context);

    return Scaffold(
      drawer: const AppDrawer(currentRoute: '/overdue-report'),
      appBar: AppBar(
        title: const Text('Overdue Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Save PDF',
            onPressed: asyncEntries.whenOrNull(
              data: (entries) => () => _savePdf(entries),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share PDF',
            onPressed: asyncEntries.whenOrNull(
              data: (entries) => () => _sharePdf(entries),
            ),
          ),
        ],
      ),
      body: asyncEntries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Failed to load overdue report: $e',
                style: const TextStyle(color: Colors.red)),
          ),
        ),
        data: (allEntries) {
          final entries = _applyFilters(allEntries);
          final totalOverdue = entries.fold<double>(0, (s, e) => s + e.amountRemaining);
          final uniqueCustomers = entries.map((e) => e.customerId).toSet().length;
          final avgDays = entries.isEmpty
              ? 0
              : entries.fold<int>(0, (s, e) => s + e.overdueDays) ~/ entries.length;
          final dailyCount = entries.where((e) => e.loanType == 'daily').length;
          final weeklyCount = entries.where((e) => e.loanType == 'weekly').length;

          return RefreshIndicator(
            onRefresh: () => ref.refresh(overdueReportProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        title: 'Total Overdue',
                        value: CurrencyUtils.format(totalOverdue,
                            symbol: _currencySymbol),
                        icon: Icons.warning_amber,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryCard(
                        title: 'Installments',
                        value: entries.length.toString(),
                        icon: Icons.receipt_long,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        title: 'Customers',
                        value: uniqueCustomers.toString(),
                        icon: Icons.people,
                        color: Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryCard(
                        title: 'Avg Days',
                        value: avgDays.toString(),
                        icon: Icons.timer,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                FilterChipRow(
                  label: 'Loan Type',
                  options: const ['All', 'Daily', 'Weekly'],
                  selected: _selectedLoanType ?? 'All',
                  onSelected: (v) {
                    setState(() => _selectedLoanType = v == 'All' ? null : v.toLowerCase());
                  },
                ),
                const SizedBox(height: 8),
                FilterChipRow(
                  label: 'Min Overdue',
                  options: const ['All', '7+ days', '30+ days'],
                  selected: _minDaysOverdue == 0
                      ? 'All'
                      : _minDaysOverdue == 7
                          ? '7+ days'
                          : '30+ days',
                  onSelected: (v) {
                    setState(() {
                      _minDaysOverdue = switch (v) {
                        '7+ days' => 7,
                        '30+ days' => 30,
                        _ => 0,
                      };
                    });
                  },
                ),
                const SizedBox(height: 16),

                if (dailyCount > 0 && weeklyCount > 0) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _TypeBreakdownCard(
                          title: 'Daily Loans',
                          amount: entries
                              .where((e) => e.loanType == 'daily')
                              .fold<double>(0, (s, e) => s + e.amountRemaining),
                          count: dailyCount,
                          color: Colors.blue,
                          currencySymbol: _currencySymbol,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _TypeBreakdownCard(
                          title: 'Weekly Loans',
                          amount: entries
                              .where((e) => e.loanType == 'weekly')
                              .fold<double>(0, (s, e) => s + e.amountRemaining),
                          count: weeklyCount,
                          color: Colors.teal,
                          currencySymbol: _currencySymbol,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                Text('Overdue Installments',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),

                if (entries.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 48, color: Colors.green),
                          SizedBox(height: 12),
                          Text('No overdue installments',
                              style: TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                  )
                else
                  ...entries.map(
                    (e) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: e.overdueDays > 7
                              ? Colors.red.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                          child: Text(
                            '${e.overdueDays}d',
                            style: TextStyle(
                              color:
                                  e.overdueDays > 7 ? Colors.red : Colors.orange,
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
                              CurrencyUtils.format(e.amountRemaining,
                                  symbol: _currencySymbol),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red),
                            ),
                            Text(
                              'of ${CurrencyUtils.format(e.amountDue, symbol: _currencySymbol)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                        onTap: () => context.push('/customers/${e.customerId}'),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
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
                  Text(title,
                      style: Theme.of(context).textTheme.bodySmall),
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

class _TypeBreakdownCard extends StatelessWidget {
  const _TypeBreakdownCard({
    required this.title,
    required this.amount,
    required this.count,
    required this.color,
    this.currencySymbol = CurrencyUtils.defaultSymbol,
  });

  final String title;
  final double amount;
  final int count;
  final Color color;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(CurrencyUtils.format(amount, symbol: currencySymbol),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    )),
            const SizedBox(height: 4),
            Text('$count installment(s)',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String label;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: options.map((option) {
            final isSelected = option == selected;
            return ChoiceChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (_) => onSelected(option),
            );
          }).toList(),
        ),
      ],
    );
  }
}
