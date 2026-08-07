import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/holidays/data/models/holiday_entity.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/domain/loan_schedule_calculator.dart';

/// Guards the derived-schedule calculator:
///  * installments split evenly so their sum exactly equals total_repayment
///  * the applied total is allocated chronologically (paid/partial/pending)
///  * the applied total is clamped to [0, total_repayment]
///  * the result is identical given the same source data (deterministic)
///  * pendingBalance is always computed, never stored
void main() {
  Loan loan({
    String id = 'L1',
    LoanType loanType = LoanType.daily,
    double amount = 10000.0,
    int duration = 5,
    double totalRepayment = 10000.0,
    DateTime? start,
  }) {
    return Loan(
      id: id,
      customerId: 'C1',
      loanType: loanType,
      amount: amount,
      interestRate: 10.0,
      duration: duration,
      loanDate: DateTime(2026, 8, 3),
      repaymentStartDate: start ?? DateTime(2026, 8, 3),
      totalRepayment: totalRepayment,
      outstandingBalance: totalRepayment,
      installmentAmount: amount / duration,
      expectedCompletionDate: DateTime(2026, 9, 1),
    );
  }

  test('installments sum exactly to total_repayment (H2 guard)', () {
    final result = LoanScheduleCalculator.build(
      loan: loan(totalRepayment: 10000.67),
      holidays: const [],
      totalAppliedToLoan: 0.0,
    );
    final sum =
        result.installments.fold(0.0, (acc, i) => acc + i.amount);
    expect(sum, closeTo(10000.67, 0.001));
    expect(result.installments.length, 5);
  });

  test('allocates applied money chronologically (paid then pending)', () {
    final result = LoanScheduleCalculator.build(
      loan: loan(totalRepayment: 10000.0), // 5 x 2000
      holidays: const [],
      totalAppliedToLoan: 4000.0,
    );
    expect(result.installments[0].status.name, 'paid');
    expect(result.installments[0].paidAmount, 2000.0);
    expect(result.installments[1].status.name, 'paid');
    expect(result.installments[1].paidAmount, 2000.0);
    expect(result.installments[2].status.name, 'pending');
    expect(result.installments[2].paidAmount, 0.0);
    expect(result.totalPaid, 4000.0);
    expect(result.pendingBalance, 6000.0);
  });

  test('marks a fractional application as partial', () {
    final result = LoanScheduleCalculator.build(
      loan: loan(totalRepayment: 10000.0), // 5 x 2000
      holidays: const [],
      totalAppliedToLoan: 500.0,
    );
    expect(result.installments[0].status.name, 'partial');
    expect(result.installments[0].paidAmount, 500.0);
    expect(result.installments[1].status.name, 'pending');
    expect(result.pendingBalance, 9500.0);
  });

  test('clamps applied money to [0, total_repayment]', () {
    final over = LoanScheduleCalculator.build(
      loan: loan(totalRepayment: 10000.0),
      holidays: const [],
      totalAppliedToLoan: 99999.0,
    );
    expect(over.totalPaid, 10000.0);
    expect(over.pendingBalance, 0.0);
    expect(over.installments.every((i) => i.status.name == 'paid'), isTrue);

    final negative = LoanScheduleCalculator.build(
      loan: loan(totalRepayment: 10000.0),
      holidays: const [],
      totalAppliedToLoan: -500.0,
    );
    expect(negative.totalPaid, 0.0);
    expect(negative.pendingBalance, 10000.0);
    expect(negative.installments.every((i) => i.status.name == 'pending'),
        isTrue);
  });

  test('non-finite applied money is treated as zero (N1 hardening)', () {
    final result = LoanScheduleCalculator.build(
      loan: loan(totalRepayment: 10000.0),
      holidays: const [],
      totalAppliedToLoan: double.infinity,
    );
    expect(result.totalPaid, 0.0);
    expect(result.pendingBalance, 10000.0);
  });

  test('same source data always derives the same schedule', () {
    final holidays = [
      Holiday(
        id: 'H1',
        name: 'Public Holiday',
        date: DateTime(2026, 8, 10),
      ),
    ];
    final a = LoanScheduleCalculator.build(
      loan: loan(loanType: LoanType.weekly, totalRepayment: 4000.0),
      holidays: holidays,
      totalAppliedToLoan: 1000.0,
    );
    final b = LoanScheduleCalculator.build(
      loan: loan(loanType: LoanType.weekly, totalRepayment: 4000.0),
      holidays: holidays,
      totalAppliedToLoan: 1000.0,
    );
    expect(
      b.installments.map((i) => i.id),
      a.installments.map((i) => i.id),
    );
    expect(
      b.installments.map((i) => i.dueDate),
      a.installments.map((i) => i.dueDate),
    );
    expect(
      b.installments.map((i) => i.status),
      a.installments.map((i) => i.status),
    );
  });

  test('a custom-collection loan still splits total_repayment evenly', () {
    // The calculator derives amounts from total_repayment (sum must equal it);
    // a loan with a custom per-period amount keeps that invariant regardless.
    final result = LoanScheduleCalculator.build(
      loan: loan(totalRepayment: 5000.0, duration: 5)
          .copyWith(customCollectionAmount: 1000.0),
      holidays: const [],
      totalAppliedToLoan: 0.0,
    );
    expect(result.installments.every((i) => i.amount == 1000.0), isTrue);
  });
}
