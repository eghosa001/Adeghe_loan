import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../customers/presentation/providers/customer_providers.dart';
import '../../../savings/presentation/providers/savings_providers.dart';
import '../../../savings/data/models/savings_transaction_entity.dart';

class SavingsStatementScreen extends ConsumerStatefulWidget {
  const SavingsStatementScreen({super.key});

  @override
  ConsumerState<SavingsStatementScreen> createState() => _SavingsStatementScreenState();
}

class _SavingsStatementScreenState extends ConsumerState<SavingsStatementScreen> {
  String? _selectedCustomerId;

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customerListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Savings Statement'),
        actions: [
          if (_selectedCustomerId != null)
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Print statement',
              onPressed: _printStatement,
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
                    Icon(Icons.savings, size: 80, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    Text('Select a customer to view their savings statement',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            )),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: _SavingsStatementBody(customerId: _selectedCustomerId!),
            ),
        ],
      ),
    );
  }

  void _printStatement() async {
    final service = await ref.read(statementServiceProvider.future);
    await service.printCustomerStatement(_selectedCustomerId!);
  }
}

class _SavingsStatementBody extends ConsumerWidget {
  const _SavingsStatementBody({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(savingsBalanceProvider(customerId));
    final transactionsAsync = ref.watch(savingsTransactionsProvider(customerId));

    return Column(
      children: [
        // Balance card
        balanceAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (balance) => Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text('Current Balance',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                Text(CurrencyUtils.format(balance),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        // Transactions list
        Expanded(
          child: transactionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (transactions) {
              if (transactions.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long, size: 80,
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text('No transactions yet.',
                          style: Theme.of(context).textTheme.bodyLarge),
                    ],
                  ),
                );
              }
              return ListView.separated(
                itemCount: transactions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final tx = transactions[index];
                  final type = tx.type.value;
                  final isCredit = tx.type == SavingsTransactionType.deposit ||
                      tx.type == SavingsTransactionType.overpayment;
                  final date = DateTime.tryParse(tx.createdAt);

                  return ListTile(
                    leading: CircleAvatar(
                      child: Icon(
                        isCredit ? Icons.add : Icons.remove,
                        color: isCredit ? Colors.green : Colors.red,
                      ),
                    ),
                    title: Text(type.toUpperCase()),
                    subtitle: Text(tx.note ?? ''),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${isCredit ? '+' : '-'}${CurrencyUtils.format(tx.amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isCredit ? Colors.green : Colors.red,
                          ),
                        ),
                        if (date != null)
                          Text(AppDateUtils.formatDate(date),
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
