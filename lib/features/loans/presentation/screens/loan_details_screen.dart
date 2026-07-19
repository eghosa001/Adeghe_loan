import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:loantrack/core/utils/date_utils.dart';
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
                  expandedHeight: 200.0,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Padding(
                      padding: const EdgeInsets.all(16.0),
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
                                    color:
                                        Theme.of(context).colorScheme.primary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                              'Total Repayment: ${CurrencyUtils.format(loan.totalRepayment)}'),
                          Text(
                              'Completion Date: ${AppDateUtils.formatDate(loan.expectedCompletionDate)}'),
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
                    return ListTile(
                      leading: CircleAvatar(
                          child: Text('${installment.installmentNumber}')),
                      title: Text(CurrencyUtils.format(installment.amount)),
                      subtitle: Text(
                          'Due: ${AppDateUtils.formatDate(installment.dueDate)}'),
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

  Color _statusColor(BuildContext context, RepaymentStatus status) {
    return switch (status) {
      RepaymentStatus.paid => Colors.green.shade100,
      RepaymentStatus.missed => Colors.red.shade100,
      RepaymentStatus.partial => Colors.orange.shade100,
      RepaymentStatus.pending => Colors.grey.shade200,
    };
  }
}
