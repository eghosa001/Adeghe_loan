import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../reports/services/export_manager.dart';
import '../providers/collection_provider.dart';

class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionAsync = ref.watch(collectionListProvider);
    final selectedDate = ref.watch(collectionDateFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Collection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export to Excel',
            onPressed: () async {
              final result = await ref.read(collectionListProvider.future);
              final file = await ExportManager.exportCollectionToExcel(
                  result, selectedDate);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Exported: ${file.path.split('/').last}')),
                );
              }
            },
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/collections'),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.file_download),
        label: const Text('Download Excel'),
        onPressed: () async {
          final result = await ref.read(collectionListProvider.future);
          final file = await ExportManager.exportCollectionToExcel(
              result, selectedDate);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'Spreadsheet saved: ${file.path.split('/').last}')),
            );
          }
        },
      ),
      body: Column(
        children: [
          _DatePickerTile(
            selectedDate: selectedDate,
            onDatePicked: (date) {
              ref.read(collectionDateFilterProvider.notifier).state = date;
            },
          ),
          Expanded(
            child: collectionAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Center(
                      child: Text('No collection data for this date.'));
                }
                return _buildSummaryAndList(context, rows);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryAndList(BuildContext context, List<dynamic> rows) {
    double totalDue = 0;
    double totalPaid = 0;
    for (final row in rows) {
      totalDue += row.amountDue;
      totalPaid += row.amountPaid;
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SummaryItem(
                  label: 'Total Due',
                  value: CurrencyUtils.format(totalDue)),
              _SummaryItem(
                  label: 'Total Paid',
                  value: CurrencyUtils.format(totalPaid)),
              _SummaryItem(
                  label: 'Remaining',
                  value: CurrencyUtils.format(totalDue - totalPaid)),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = rows[index];
              final statusLabel = row.isPaid
                  ? 'Paid'
                  : row.isPartial
                      ? 'Partial'
                      : 'Scheduled';
              final statusColor = row.isPaid
                  ? Colors.green
                  : row.isPartial
                      ? Colors.orange
                      : Theme.of(context).colorScheme.primary;
              return ListTile(
                title: Text(row.customerName),
                subtitle: Text('${row.loanType} loan'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      row.isPaid
                          ? CurrencyUtils.format(row.amountPaid)
                          : '${CurrencyUtils.format(row.amountPaid)} / ${CurrencyUtils.format(row.amountDue)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  const _DatePickerTile({
    required this.selectedDate,
    required this.onDatePicked,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDatePicked;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.calendar_today),
      title: Text(AppDateUtils.formatDate(selectedDate)),
      subtitle: Text(AppDateUtils.formatRelative(selectedDate)),
      trailing: const Icon(Icons.edit_calendar),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(now.year + 5, now.month, now.day),
        );
        if (picked != null) onDatePicked(picked);
      },
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                )),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
