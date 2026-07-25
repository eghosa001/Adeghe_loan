import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/currency_utils.dart';
import '../providers/savings_providers.dart';

class SavingsSection extends ConsumerWidget {
  const SavingsSection({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(savingsAccountProvider(customerId));
    final txnsAsync = ref.watch(savingsTransactionsProvider(customerId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        accountAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Savings error: $e'),
          data: (account) {
            final balance = account?.balance ?? 0.0;
            return Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Savings Balance',
                              style: Theme.of(context).textTheme.labelLarge),
                          Text(CurrencyUtils.format(balance),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        _ActionButton(
                          icon: Icons.add,
                          label: 'Deposit',
                          onTap: () =>
                              _showDepositDialog(context, ref, customerId),
                        ),
                        const SizedBox(width: 8),
                        _ActionButton(
                          icon: Icons.remove,
                          label: 'Withdraw',
                          onTap: balance > 0
                              ? () => _showWithdrawDialog(
                                  context, ref, customerId, balance)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text('Savings History',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        txnsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
          data: (txns) => txns.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No transactions yet.',
                      style: TextStyle(color: Colors.grey)),
                )
              : Column(
                  children: txns.take(20).map((t) => _TxnTile(txn: t)).toList(),
                ),
        ),
      ],
    );
  }

  void _showDepositDialog(
      BuildContext context, WidgetRef ref, String customerId) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deposit to Savings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(
                  labelText: 'Amount', prefixText: '₦'),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text);
              if (amount == null || amount <= 0) return;
              final repo = await ref.read(savingsRepositoryProvider.future);
              await repo.credit(
                customerId: customerId,
                amount: amount,
                type: SavingsTransactionType.deposit,
                note: noteCtrl.text.trim().isEmpty
                    ? 'Manual deposit'
                    : noteCtrl.text.trim(),
              );
              ref.invalidate(savingsAccountProvider(customerId));
              ref.invalidate(savingsTransactionsProvider(customerId));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Deposit'),
          ),
        ],
      ),
    );
  }

  void _showWithdrawDialog(BuildContext context, WidgetRef ref,
      String customerId, double maxBalance) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw from Savings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Available: ${CurrencyUtils.format(maxBalance)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(
                  labelText: 'Amount', prefixText: '₦'),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text);
              if (amount == null || amount <= 0) return;
              try {
                final repo =
                    await ref.read(savingsRepositoryProvider.future);
                await repo.withdraw(
                  customerId: customerId,
                  amount: amount,
                  note: noteCtrl.text.trim().isEmpty
                      ? 'Manual withdrawal'
                      : noteCtrl.text.trim(),
                );
                ref.invalidate(savingsAccountProvider(customerId));
                ref.invalidate(savingsTransactionsProvider(customerId));
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(e.toString())));
                }
              }
            },
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {required this.icon,
      required this.label,
      required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton.filled(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          iconSize: 36,
        ),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _TxnTile extends StatelessWidget {
  const _TxnTile({required this.txn});
  final SavingsTransaction txn;

  @override
  Widget build(BuildContext context) {
    final isCredit = txn.type != SavingsTransactionType.withdrawal;
    final color =
        isCredit ? Colors.green : Theme.of(context).colorScheme.error;
    final sign = isCredit ? '+' : '-';
    final typeLabel = switch (txn.type) {
      SavingsTransactionType.deposit => 'Deposit',
      SavingsTransactionType.withdrawal => 'Withdrawal',
      SavingsTransactionType.overpayment => 'Overpayment credit',
    };
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(
          isCredit ? Icons.arrow_downward : Icons.arrow_upward,
          size: 16,
          color: color,
        ),
      ),
      title: Text(typeLabel),
      subtitle: Text(txn.note),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('$sign${CurrencyUtils.format(txn.amount)}',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold)),
          Text(
            txn.createdAt.split('T').first,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
