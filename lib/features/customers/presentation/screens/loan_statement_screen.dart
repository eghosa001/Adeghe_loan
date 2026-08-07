import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../customers/presentation/providers/customer_providers.dart';
import '../../../loans/presentation/providers/loan_providers.dart';
import '../../../loans/data/models/loan_entity.dart';

class LoanStatementScreen extends ConsumerStatefulWidget {
  const LoanStatementScreen({super.key});

  @override
  ConsumerState<LoanStatementScreen> createState() => _LoanStatementScreenState();
}

class _LoanStatementScreenState extends ConsumerState<LoanStatementScreen> {
  String? _selectedCustomerId;

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(allCustomersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loan Statement'),
        actions: [
          if (_selectedCustomerId != null)
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Print statement',
              onPressed: _printStatement,
            ),
          if (_selectedCustomerId != null)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share statement',
              onPressed: _shareStatement,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: customersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
              data: (customers) => DropdownButtonFormField<String>(
                initialValue: _selectedCustomerId,
                decoration: const InputDecoration(
                  labelText: 'Select Customer',
                  border: OutlineInputBorder(),
                ),
                items: customers
                    .map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.fullName),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCustomerId = v),
              ),
            ),
          ),
          if (_selectedCustomerId == null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long, size: 80, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    Text('Select a customer to view their loan statement',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            )),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: _LoanStatementBody(customerId: _selectedCustomerId!),
            ),
        ],
      ),
    );
  }

  void _printStatement() async {
    try {
      final service = await ref.read(statementServiceProvider.future);
      await service.printCustomerStatement(_selectedCustomerId!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to print statement: $e')),
        );
      }
    }
  }

  void _shareStatement() async {
    try {
      final service = await ref.read(statementServiceProvider.future);
      final bytes = await service.buildCustomerStatementPdf(_selectedCustomerId!);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}loan_statement.pdf');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Loan Statement',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share statement: $e')),
        );
      }
    }
  }
}

class _LoanStatementBody extends ConsumerWidget {
  const _LoanStatementBody({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(allLoansForCustomerProvider(customerId));

    return loansAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (loans) {
        if (loans.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 80,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text('No loans for this customer.',
                    style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: loans.length,
          itemBuilder: (context, index) {
            final loan = loans[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(loan.loanType.name.toUpperCase(),
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                )),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: switch (loan.status) {
                              LoanStatus.active => Colors.green.withValues(alpha: 0.1),
                              LoanStatus.completed => Colors.blue.withValues(alpha: 0.1),
                              _ => Colors.orange.withValues(alpha: 0.1),
                            },
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(loan.status.name,
                              style: TextStyle(
                                fontSize: 12,
                                color: switch (loan.status) {
                                  LoanStatus.active => Colors.green.shade800,
                                  LoanStatus.completed => Colors.blue.shade800,
                                  _ => Colors.orange.shade800,
                                },
                              )),
                        ),
                      ],
                    ),
                    const Divider(),
                    _detailRow('Principal', CurrencyUtils.format(loan.amount)),
                    _detailRow('Total Repayment', CurrencyUtils.format(loan.totalRepayment)),
                    _detailRow('Outstanding', CurrencyUtils.format(loan.outstandingBalance)),
                    _detailRow('Interest Rate', '${loan.interestRate}%'),
                    _detailRow('Loan Date', loan.loanDate.toString().split(' ').first),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
