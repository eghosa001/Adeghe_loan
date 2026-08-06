import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../../collection/data/models/collection_row.dart';
import '../../../collection/presentation/providers/collection_provider.dart';
import '../../../reports/services/export_manager.dart';

class CollectionStatementScreen extends ConsumerStatefulWidget {
  const CollectionStatementScreen({super.key});

  @override
  ConsumerState<CollectionStatementScreen> createState() => _CollectionStatementScreenState();
}

class _CollectionStatementScreenState extends ConsumerState<CollectionStatementScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  late Future<List<CollectionRow>> _collectionsFuture;

  String get _currencySymbol =>
      ref.read(currencySymbolProvider).valueOrNull ??
      CurrencyUtils.defaultSymbol;

  @override
  void initState() {
    super.initState();
    _collectionsFuture = _fetchCollections();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collection Statement'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print',
            onPressed: _printCollectionSheet,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share PDF',
            onPressed: _shareCollectionSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // Date range picker
          ListTile(
            leading: const Icon(Icons.date_range),
            title: Text(
                '${AppDateUtils.formatDate(_startDate)} — ${AppDateUtils.formatDate(_endDate)}'),
            subtitle: const Text('Tap to change date range'),
            onTap: () async {
              final now = DateTime.now();
              final pickedStart = await showDatePicker(
                context: context,
                initialDate: _startDate,
                firstDate: DateTime(2020),
                lastDate: now,
              );
              if (pickedStart != null) {
                if (!context.mounted) return;
                final pickedEnd = await showDatePicker(
                  context: context,
                  initialDate: _endDate,
                  firstDate: pickedStart,
                  lastDate: now,
                );
                setState(() {
                  _startDate = pickedStart;
                  if (pickedEnd != null) _endDate = pickedEnd;
                  _collectionsFuture = _fetchCollections();
                });
              }
            },
          ),
          const Divider(height: 1),
          // Collection list
          Expanded(
            child: _buildCollectionList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionList() {
    // Use the existing collection provider with date range mode
    return FutureBuilder(
      future: _collectionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.collections, size: 80,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text('No collections in this date range.',
                    style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          );
        }

        // Summary
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
                  _SummaryItem(label: 'Total Due', value: CurrencyUtils.format(totalDue)),
                  _SummaryItem(label: 'Total Paid', value: CurrencyUtils.format(totalPaid)),
                  _SummaryItem(label: 'Remaining', value: CurrencyUtils.format(totalDue - totalPaid)),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return ListTile(
                    title: Text(row.customerName),
                    subtitle: Text(
                        '${row.loanType}${row.groupName != null ? ' — ${row.groupName}' : ''}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(CurrencyUtils.format(row.amountPaid),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('/ ${CurrencyUtils.format(row.amountDue)}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<List<CollectionRow>> _fetchCollections() async {
    final repo = await ref.read(collectionRepositoryProvider.future);
    final result = await repo.getCollectionsByDateRange(_startDate, _endDate);
    return result.when(
      success: (rows) => rows,
      failure: (f) => throw f,
    );
  }

  Future<void> _printCollectionSheet() async {
    try {
      final rows = await _fetchCollections();
      if (!mounted) return;
      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No collections to print')),
        );
        return;
      }
      final file = await ExportManager.exportCollectionToPdf(
          rows, _startDate,
          currencySymbol: _currencySymbol);
      if (!mounted) return;
      await Printing.layoutPdf(onLayout: (format) async => file.readAsBytesSync());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to print: $e')),
        );
      }
    }
  }

  Future<void> _shareCollectionSheet() async {
    try {
      final rows = await _fetchCollections();
      if (!mounted) return;
      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No collections to share')),
        );
        return;
      }
      final file = await ExportManager.exportCollectionToPdf(
          rows, _startDate,
          currencySymbol: _currencySymbol);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Collection Statement ${AppDateUtils.formatDate(_startDate)} - ${AppDateUtils.formatDate(_endDate)}',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share: $e')),
        );
      }
    }
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
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
