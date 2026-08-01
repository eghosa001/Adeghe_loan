import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/domain/schedule_generator.dart';

void main() {
  final startDate = DateTime(2026, 8, 3); // Monday

  group('ScheduleGenerator.generate', () {
    test('produces one installment per amount with the given amounts', () {
      final schedule = ScheduleGenerator.generate(
        loanId: 'L1',
        loanType: LoanType.daily,
        startDate: startDate,
        amounts: [1000, 2000, 3000],
        holidays: const [],
      );
      expect(schedule.length, 3);
      expect(schedule[0].amount, 1000);
      expect(schedule[1].amount, 2000);
      expect(schedule[2].amount, 3000);
      expect(schedule[0].installmentNumber, 1);
      expect(schedule[2].installmentNumber, 3);
    });

    test('splitEvenly installments sum exactly to total_repayment (H2 guard)', () {
      // total_repayment that does not divide evenly into 7 parts.
      const totalRepayment = 10000.67;
      const duration = 7;
      final amounts = CurrencyUtils.splitEvenly(totalRepayment, duration);
      expect(amounts.length, duration);

      final schedule = ScheduleGenerator.generate(
        loanId: 'L1',
        loanType: LoanType.daily,
        startDate: startDate,
        amounts: amounts,
        holidays: const [],
      );

      final sum = schedule.fold(0.0, (acc, i) => acc + i.amount);
      expect(sum, closeTo(totalRepayment, 0.001));
    });

    test('custom collection amount defines a total that the schedule matches', () {
      // H2: with a custom per-period amount, total_repayment = custom × duration
      // and every schedule row matches the custom amount.
      const customAmount = 5000.0;
      const duration = 10;
      final totalRepayment = customAmount * duration;
      final amounts = CurrencyUtils.splitEvenly(totalRepayment, duration);

      final schedule = ScheduleGenerator.generate(
        loanId: 'L1',
        loanType: LoanType.weekly,
        startDate: startDate,
        amounts: amounts,
        holidays: const [],
      );

      expect(schedule.length, duration);
      for (final i in schedule) {
        expect(i.amount, customAmount);
      }
      final sum = schedule.fold(0.0, (acc, i) => acc + i.amount);
      expect(sum, closeTo(totalRepayment, 0.001));
    });

    test('daily schedule skips weekends and keeps every installment', () {
      final schedule = ScheduleGenerator.generate(
        loanId: 'L1',
        loanType: LoanType.daily,
        startDate: DateTime(2026, 8, 7), // Friday
        amounts: [1000, 1000, 1000],
        holidays: const [],
      );
      // Fri(7), Mon(10), Tue(11) — weekend skipped.
      expect(schedule[0].dueDate, DateTime(2026, 8, 7));
      expect(schedule[1].dueDate, DateTime(2026, 8, 10));
      expect(schedule[2].dueDate, DateTime(2026, 8, 11));
    });
  });
}
