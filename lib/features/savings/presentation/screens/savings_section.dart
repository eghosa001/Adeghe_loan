import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../data/models/savings_transaction_entity.dart';
import '../providers/savings_providers.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../collection/presentation/providers/collection_provider.dart';
import '../../../reports/presentation/providers/report_provider.dart';

class SavingsSection extends ConsumerWidget {
  const SavingsSection({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(savingsBalanceProvider(customerId));
    final txAsync = ref.watch(savingsTransactionsProvider(customerId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Balance card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.savings_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text('Savings',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                balanceAsync.when(
                  loading: () => const CircularProgressIndicator(),
                  error: (e, _) => Text('Error: $e'),
                  data: (balance) => Text(
                    CurrencyUtils.format(balance),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _showTransactionModal(context, ref, isDeposit: true),
                        icon: const Icon(Icons.add),
                        label: const Text('Deposit'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showTransactionModal(context, ref,
                            isDeposit: false),
                        icon: const Icon(Icons.remove),
                        label: const Text('Withdraw'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Transaction history
        txAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (txs) {
            if (txs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No savings transactions yet.',
                    textAlign: TextAlign.center),
              );
            }
            return Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text('Transaction History',
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  ...txs.map((tx) => _TransactionTile(tx: tx)),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _showTransactionModal(BuildContext context, WidgetRef ref,
      {required bool isDeposit}) async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final currency =
        ref.read(currencySymbolProvider).valueOrNull ?? CurrencyUtils.defaultSymbol;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDeposit ? 'Deposit to Savings' : 'Withdraw from Savings'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountCtrl,
                decoration: InputDecoration(
                    labelText: 'Amount', prefixText: currency),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                validator: (v) {
                  final val = double.tryParse(v ?? '');
                  if (val == null || !val.isFinite || val <= 0) {
                    return 'Enter a valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: noteCtrl,
                decoration:
                    const InputDecoration(labelText: 'Note (optional)'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, true);
                }
              },
              child: Text(isDeposit ? 'Deposit' : 'Withdraw')),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    final amount = CurrencyUtils.tryParsePositiveAmount(amountCtrl.text) ?? 0;
    final note = noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim();

    try {
      final repo = await ref.read(savingsRepositoryProvider.future);
      await repo.recordTransaction(
            customerId: customerId,
            type: isDeposit
                ? SavingsTransactionType.deposit
                : SavingsTransactionType.withdrawal,
            amount: amount,
            note: note,
          );
      ref.invalidate(savingsBalanceProvider(customerId));
      ref.invalidate(savingsTransactionsProvider(customerId));
      ref.invalidate(allSavingsAccountsProvider);
      ref.invalidate(allAccountsWithNamesProvider);
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(collectionListProvider);
      ref.invalidate(reportSummaryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(isDeposit
                  ? 'Deposit recorded successfully.'
                  : 'Withdrawal recorded successfully.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.tx});
  final SavingsTransaction tx;

  @override
  Widget build(BuildContext context) {
    final isCredit = tx.type != SavingsTransactionType.withdrawal;
    final color = isCredit ? Colors.green : Colors.red;
    final icon = isCredit ? Icons.arrow_downward : Icons.arrow_upward;
    final label = switch (tx.type) {
      SavingsTransactionType.deposit => 'Deposit',
      SavingsTransactionType.withdrawal => 'Withdrawal',
      SavingsTransactionType.overpayment => 'Automatic Savings Deposit',
    };

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(label),
      subtitle: Text(
        [
          tx.createdAt.split('T').first,
          if (tx.note != null) tx.note!,
        ].join(' • '),
      ),
      trailing: Text(
        '${isCredit ? '+' : '-'}${CurrencyUtils.format(tx.amount)}',
        style: TextStyle(
            color: color, fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }
}
