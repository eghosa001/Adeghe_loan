import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:loantrack/core/di/providers.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:loantrack/core/utils/date_utils.dart';
import 'package:loantrack/core/widgets/keyboard_scrollable.dart';
import 'package:loantrack/features/loans/data/loan_repository.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/data/models/repayment_installment_entity.dart';
import 'package:loantrack/features/loans/presentation/providers/loan_providers.dart';
import 'package:loantrack/features/savings/presentation/providers/savings_providers.dart';
import 'package:loantrack/features/payments/presentation/providers/payment_providers.dart';
import 'package:loantrack/features/collection/presentation/providers/collection_provider.dart';
import 'package:loantrack/features/customers/presentation/providers/customer_providers.dart';
import 'package:loantrack/features/dashboard/presentation/providers/dashboard_provider.dart';
import 'package:loantrack/features/reports/presentation/providers/report_provider.dart';

class LoanDetailsScreen extends ConsumerWidget {
  final String loanId;
  const LoanDetailsScreen({super.key, required this.loanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loanAsync = ref.watch(loanDetailsProvider(loanId));
    final scheduleAsync = ref.watch(loanScheduleProvider(loanId));

    return Scaffold(
      body: loanAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (loan) {
          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  title: const Text('Loan Details'),
                  floating: true,
                  pinned: true,
                  expandedHeight: 220.0,
                  actions: [
                    if (loan.status == LoanStatus.active)
                      IconButton(
                        icon: const Icon(Icons.payment),
                        tooltip: 'Record Payment',
                        onPressed: () {
                          final installmentDue =
                              _todaysInstallment(scheduleAsync.valueOrNull);
                          context.push(
                            '/loans/${loan.id}/record-payment',
                            extra: {
                              'customerId': loan.customerId,
                              'currentBalance': loan.outstandingBalance,
                              'installmentDue': installmentDue,
                            },
                          );
                        },
                      ),
                    // Overflow menu: an active loan used to push six icon
                    // buttons onto the AppBar, which overflows on narrow
                    // phones. The most-used action stays direct; the rest live
                    // behind the menu.
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      tooltip: 'More',
                      onSelected: (value) {
                        switch (value) {
                          case 'clear':
                            _clearWithSavings(context, ref, loan);
                          case 'edit':
                            context.push('/loans/${loan.id}/edit', extra: loan);
                          case 'cancel':
                            _cancelLoan(context, ref, loan);
                          case 'calendar':
                            context.push(
                              '/loans/$loanId/repayment-calendar',
                              extra: loan,
                            );
                          case 'payments':
                            context.push(
                              '/loans/$loanId/payments',
                              extra: {'customerId': loan.customerId},
                            );
                        }
                      },
                      itemBuilder: (context) => [
                        if (loan.status == LoanStatus.active)
                          const PopupMenuItem(
                            value: 'clear',
                            child: Text('Clear with Savings'),
                          ),
                        if (loan.status == LoanStatus.active)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit Loan'),
                          ),
                        if (loan.status == LoanStatus.active)
                          const PopupMenuItem(
                            value: 'cancel',
                            child: Text('Cancel Loan'),
                          ),
                        const PopupMenuItem(
                          value: 'calendar',
                          child: Text('Repayment Calendar'),
                        ),
                        const PopupMenuItem(
                          value: 'payments',
                          child: Text('Payment History'),
                        ),
                      ],
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Outstanding Balance',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(
                            CurrencyUtils.format(loan.outstandingBalance),
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                              'Total Repayment: ${CurrencyUtils.format(loan.totalRepayment)}'),
                          Text(
                              'Completion Date: ${AppDateUtils.formatDate(loan.expectedCompletionDate)}'),
                          Text('Status: ${loan.status.name.toUpperCase()}'),
                          if (loan.notes != null && loan.notes!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Notes: ${loan.notes}',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ];
            },
            body: scheduleAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) =>
                  Center(child: Text('Error loading schedule: $err')),
              data: (schedule) {
                return KeyboardScrollable(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: schedule.length,
                    itemBuilder: (context, index) {
                      final installment = schedule[index];
                      final isToday = _isToday(installment.dueDate);
                      return ListTile(
                        leading: CircleAvatar(
                            backgroundColor: isToday
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            child: Text(
                              '${installment.installmentNumber}',
                              style: TextStyle(
                                  color: isToday ? Colors.white : null),
                            )),
                        title: Text(CurrencyUtils.format(installment.amount)),
                        subtitle: Text(
                            'Due: ${AppDateUtils.formatDate(installment.dueDate)}'
                            '${isToday ? " (Today)" : ""}'),
                        trailing: Chip(
                          label: Text(installment.status.name.toUpperCase()),
                          backgroundColor:
                              _statusColor(context, installment.status),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Returns the remaining amount due on today's installment,
  /// or the next pending installment if today has none.
  double? _todaysInstallment(List<RepaymentInstallment>? schedule) {
    if (schedule == null || schedule.isEmpty) return null;
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    for (final inst in schedule) {
      final dueDateStr = inst.dueDate.toIso8601String().split('T').first;
      if (dueDateStr == todayStr && inst.status != RepaymentStatus.paid) {
        return inst.amount - inst.paidAmount;
      }
    }
    // Next pending or partial installment
    for (final inst in schedule) {
      if (inst.status == RepaymentStatus.pending ||
          inst.status == RepaymentStatus.partial) {
        return inst.amount - inst.paidAmount;
      }
    }
    return null;
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  Color _statusColor(BuildContext context, RepaymentStatus status) {
    return switch (status) {
      RepaymentStatus.paid => Colors.green.shade100,
      RepaymentStatus.missed => Colors.red.shade100,
      RepaymentStatus.partial => Colors.orange.shade100,
      RepaymentStatus.pending => Colors.grey.shade200,
    };
  }

  Future<void> _cancelLoan(BuildContext context, WidgetRef ref, Loan loan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this loan?'),
        content: Text(
          'This will mark the loan as cancelled. '
          'Outstanding balance (${CurrencyUtils.format(loan.outstandingBalance)}) will be set to zero.\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, cancel loan')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final repo = await ref.read(loanRepositoryProvider.future);
      final result = await repo.cancelLoan(loan.id);
      result.when(
        success: (_) {
          ref.invalidate(loanDetailsProvider(loan.id));
          ref.invalidate(loanScheduleProvider(loan.id));
          ref.invalidate(dashboardDataProvider);
          ref.invalidate(collectionListProvider);
          invalidateReportData(ref.invalidate);
          ref.invalidate(futureScheduleProvider);
          ref.invalidate(allLoansProvider);
          ref.invalidate(activeLoansForCustomerProvider(loan.customerId));
          ref.invalidate(allLoansForCustomerProvider(loan.customerId));
          logAuditAction(ref, 'CANCEL', 'Loan ${loan.id} cancelled');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Loan cancelled.')),
            );
          }
        },
        failure: (f) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed: $f')),
            );
          }
        },
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _clearWithSavings(
      BuildContext context, WidgetRef ref, Loan loan) async {
    final double savingsBalance;
    try {
      savingsBalance =
          await ref.read(savingsBalanceProvider(loan.customerId).future);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load savings balance.')),
        );
      }
      return;
    }

    if (!context.mounted) return;

    if (savingsBalance < loan.outstandingBalance) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Insufficient savings (${CurrencyUtils.format(savingsBalance)}) '
          'to clear this loan (${CurrencyUtils.format(loan.outstandingBalance)})',
        ),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear loan with savings?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Outstanding: ${CurrencyUtils.format(loan.outstandingBalance)}'),
            const SizedBox(height: 4),
            Text('Savings balance: ${CurrencyUtils.format(savingsBalance)}'),
            const SizedBox(height: 12),
            const Text(
              'This will deduct the outstanding amount from the customer\'s savings and mark the loan as completed.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final repo = await ref.read(paymentRepositoryProvider.future);
      await repo.clearLoanWithSavings(
        loanId: loan.id,
        customerId: loan.customerId,
      );
      ref.invalidate(loanDetailsProvider(loan.id));
      ref.invalidate(loanScheduleProvider(loan.id));
      ref.invalidate(savingsBalanceProvider(loan.customerId));
      ref.invalidate(savingsTransactionsProvider(loan.customerId));
      ref.invalidate(allSavingsAccountsProvider);
      ref.invalidate(allAccountsWithNamesProvider);
      ref.invalidate(activeLoansForCustomerProvider(loan.customerId));
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(collectionListProvider);
      invalidateReportData(ref.invalidate);
      ref.invalidate(futureScheduleProvider);
      ref.invalidate(weeklyCollectionListProvider);
      ref.invalidate(customerProvider(loan.customerId));
      ref.invalidate(paymentsForLoanProvider(loan.id));
      ref.invalidate(allLoansProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loan cleared with savings.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }
}
