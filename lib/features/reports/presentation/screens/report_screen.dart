import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../../../core/utils/date_utils.dart';
import '../../data/models/report_summary.dart';
import '../providers/report_provider.dart';
import '../../services/export_manager.dart';

class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(reportSummaryProvider);
    final startDate = ref.watch(reportStartDateProvider);
    final endDate = ref.watch(reportEndDateProvider);

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
          PopupMenuButton<String>(
            icon: const Icon(Icons.file_download),
            onSelected: (value) async {
              final summary = await ref.read(reportSummaryProvider.future);
              final range =
                  '${AppDateUtils.formatDate(startDate)} - ${AppDateUtils.formatDate(endDate)}';
              if (value == 'csv') {
                final file = await ExportManager.exportReportToCsv(
                    summary, 'Report_$range');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text('CSV exported: ${file.path.split('/').last}')),
                  );
                }
              } else if (value == 'pdf') {
                final file = await ExportManager.exportReportToPdf(
                    summary, 'Report_$range');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text('PDF exported: ${file.path.split('/').last}')),
                  );
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'csv', child: Text('Export CSV')),
              const PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
            ],
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/reports'),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Row(
            children: [
              Expanded(
                child: _DateSelector(
                  label: 'From',
                  date: startDate,
                  onPicked: (d) =>
                      ref.read(reportStartDateProvider.notifier).state = d,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateSelector(
                  label: 'To',
                  date: endDate,
                  onPicked: (d) =>
                      ref.read(reportEndDateProvider.notifier).state = d,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          reportAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (summary) => _buildReportContent(context, summary),
          ),
        ],
      ),
    );
  }

  Widget _buildReportContent(BuildContext context, ReportSummary summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReportCard(
          title: 'Total Disbursed',
          value: CurrencyUtils.format(summary.totalDisbursed),
          icon: Icons.trending_up,
          color: Colors.orange,
        ),
        const SizedBox(height: 12),
        _ReportCard(
          title: 'Total Collected',
          value: CurrencyUtils.format(summary.totalCollected),
          icon: Icons.savings_outlined,
          color: Colors.green,
        ),
        const SizedBox(height: 12),
        _ReportCard(
          title: 'Net Profit',
          value: CurrencyUtils.format(summary.netProfit),
          icon: Icons.account_balance,
          color: summary.netProfit >= 0 ? Colors.teal : Colors.red,
        ),
        const SizedBox(height: 24),
        Text(
          'Loan Status Breakdown',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        _StatusRow(
          label: 'Active',
          count: summary.activeLoans,
          color: Colors.green,
        ),
        _StatusRow(
          label: 'Completed',
          count: summary.completedLoans,
          color: Colors.blue,
        ),
        _StatusRow(
          label: 'Defaulted',
          count: summary.defaultedLoans,
          color: Colors.red,
        ),
        const SizedBox(height: 24),
        _ChartPlaceholder(summary: summary),
      ],
    );
  }
}

class _DateSelector extends StatelessWidget {
  const _DateSelector({
    required this.label,
    required this.date,
    required this.onPicked,
  });

  final String label;
  final DateTime date;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null) onPicked(picked);
      },
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(AppDateUtils.formatDate(date)),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
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
        padding: const EdgeInsets.all(16.0),
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

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final total = 1.0;
    final fraction = count / (total > 0 ? total : 1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                backgroundColor: color.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(count.toString(),
                textAlign: TextAlign.end,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _ChartPlaceholder extends StatelessWidget {
  const _ChartPlaceholder({required this.summary});
  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final total = summary.activeLoans + summary.completedLoans + summary.defaultedLoans;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text(
              'Loan Status Distribution',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            if (total == 0)
              const Text('No loan data to display.')
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _PieSlice(
                      label: 'Active',
                      count: summary.activeLoans,
                      total: total,
                      color: Colors.green),
                  _PieSlice(
                      label: 'Completed',
                      count: summary.completedLoans,
                      total: total,
                      color: Colors.blue),
                  _PieSlice(
                      label: 'Defaulted',
                      count: summary.defaultedLoans,
                      total: total,
                      color: Colors.red),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PieSlice extends StatelessWidget {
  const _PieSlice({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (count / total * 100).toStringAsFixed(1) : '0';
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$pct%',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text('$count',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
