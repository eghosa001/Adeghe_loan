import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:loantrack/core/utils/date_utils.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/data/models/repayment_installment_entity.dart';
import 'package:loantrack/features/loans/presentation/providers/loan_providers.dart';

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
                    IconButton(
                      icon: const Icon(Icons.calendar_month_outlined),
                      tooltip: 'Repayment Calendar',
                      onPressed: () => context
                          .push('/loans/$loanId/repayment-calendar', extra: loan),
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
                return ListView.builder(
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
}
