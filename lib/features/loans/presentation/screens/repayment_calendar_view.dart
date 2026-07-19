import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:loantrack/core/utils/date_utils.dart';
import 'package:loantrack/features/loans/data/models/repayment_installment_entity.dart';
import 'package:loantrack/features/loans/presentation/providers/loan_providers.dart';

class RepaymentCalendarView extends ConsumerWidget {
  final String loanId;
  const RepaymentCalendarView({super.key, required this.loanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(loanScheduleProvider(loanId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Repayment Schedule'),
      ),
      body: scheduleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (schedule) {
          if (schedule.isEmpty) {
            return const Center(
              child: Text('No repayment schedule found.'),
            );
          }

          return Column(
            children: [
              _buildLegend(),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: schedule.length,
                  itemBuilder: (context, index) {
                    final installment = schedule[index];
                    return _buildInstallmentCard(context, installment);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Wrap(
        spacing: 16.0,
        runSpacing: 8.0,
        children: [
          _legendItem(Colors.green, 'Paid'),
          _legendItem(Colors.orange, 'Partial'),
          _legendItem(Colors.red, 'Missed'),
          _legendItem(Colors.grey.shade400, 'Pending'),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  Widget _buildInstallmentCard(
      BuildContext context, RepaymentInstallment installment) {
    final color = _statusColor(installment.status);
    final isOverdue = installment.status == RepaymentStatus.missed;

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 6,
              color: color,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '${installment.dueDate.day}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isOverdue ? Colors.red : null,
                          ),
                        ),
                        Text(
                          _monthAbbrev(installment.dueDate.month),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Installment #${installment.installmentNumber}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            AppDateUtils.formatDate(installment.dueDate),
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          CurrencyUtils.format(installment.amount),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            installment.status.name.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: color.computeLuminance() > 0.5
                                  ? Colors.black87
                                  : color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(RepaymentStatus status) {
    return switch (status) {
      RepaymentStatus.paid => Colors.green,
      RepaymentStatus.partial => Colors.orange,
      RepaymentStatus.missed => Colors.red,
      RepaymentStatus.pending => Colors.grey.shade400,
    };
  }

  String _monthAbbrev(int month) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[month];
  }
}
