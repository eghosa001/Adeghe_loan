import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/payments/data/payment_logic.dart';

void main() {
  group('computePaymentSplit', () {
    test('partial payment: applied = amount, surplus = 0', () {
      final result = computePaymentSplit(paymentAmount: 5000, outstandingBalance: 10000);
      expect(result.appliedToLoan, 5000);
      expect(result.overpaymentSurplus, 0);
      expect(result.newLoanBalance, 5000);
    });

    test('exact payment: clears loan, no surplus', () {
      final result = computePaymentSplit(paymentAmount: 10000, outstandingBalance: 10000);
      expect(result.appliedToLoan, 10000);
      expect(result.overpaymentSurplus, 0);
      expect(result.newLoanBalance, 0);
    });

    test('overpayment: excess goes to savings', () {
      final result = computePaymentSplit(paymentAmount: 12000, outstandingBalance: 10000);
      expect(result.appliedToLoan, 10000);
      expect(result.overpaymentSurplus, 2000);
      expect(result.newLoanBalance, 0);
    });

    test('overpayment never makes loan negative', () {
      final result = computePaymentSplit(paymentAmount: 50000, outstandingBalance: 1000);
      expect(result.newLoanBalance, 0);
      expect(result.overpaymentSurplus, 49000);
    });

    test('small overpayment is precise', () {
      final result = computePaymentSplit(paymentAmount: 10001, outstandingBalance: 10000);
      expect(result.overpaymentSurplus, closeTo(1, 0.001));
      expect(result.appliedToLoan, 10000);
    });

    test('payment larger than one installment without installment context applies to loan', () {
      final result = computePaymentSplit(paymentAmount: 7000, outstandingBalance: 10000);
      expect(result.appliedToLoan, 7000);
      expect(result.overpaymentSurplus, 0);
      expect(result.newLoanBalance, 3000);
    });

    test('payment less than outstanding is partial', () {
      final result = computePaymentSplit(paymentAmount: 3000, outstandingBalance: 10000);
      expect(result.appliedToLoan, 3000);
      expect(result.overpaymentSurplus, 0);
      expect(result.newLoanBalance, 7000);
    });

    test('zero outstanding sends payment to savings', () {
      final result = computePaymentSplit(paymentAmount: 5000, outstandingBalance: 0);
      expect(result.appliedToLoan, 0);
      expect(result.overpaymentSurplus, 5000);
      expect(result.newLoanBalance, 0);
    });

    test('excess over installment goes to savings', () {
      final result = computePaymentSplit(
        paymentAmount: 1500,
        outstandingBalance: 10000,
        installmentDue: 1000,
      );
      expect(result.appliedToLoan, 1000);
      expect(result.overpaymentSurplus, 500);
      expect(result.newLoanBalance, 9000);
    });

    test('payment at or below installment applies to loan', () {
      final result = computePaymentSplit(
        paymentAmount: 800,
        outstandingBalance: 10000,
        installmentDue: 1000,
      );
      expect(result.appliedToLoan, 800);
      expect(result.overpaymentSurplus, 0);
      expect(result.newLoanBalance, 9200);
    });

    test('zero installment falls back to outstanding balance', () {
      final result = computePaymentSplit(
        paymentAmount: 7000,
        outstandingBalance: 10000,
        installmentDue: 0,
      );
      expect(result.appliedToLoan, 7000);
      expect(result.overpaymentSurplus, 0);
      expect(result.newLoanBalance, 3000);
    });

    test('large overpayment with installment context caps loan at installment', () {
      final result = computePaymentSplit(
        paymentAmount: 12000,
        outstandingBalance: 10000,
        installmentDue: 1000,
      );
      expect(result.appliedToLoan, 1000);
      expect(result.overpaymentSurplus, 11000);
      expect(result.newLoanBalance, 9000);
    });
  });

  group('computeReversalLoanDelta', () {
    test('normal payment restores full applied amount', () {
      expect(computeReversalLoanDelta(paymentAmount: 5000, overpaymentSurplus: 0), 5000);
    });

    test('overpayment reversal excludes savings surplus', () {
      expect(computeReversalLoanDelta(paymentAmount: 12000, overpaymentSurplus: 2000), 10000);
    });

    test('reversal delta equals the amount originally applied to loan', () {
      const paymentAmount = 15000.0;
      const outstanding = 10000.0;
      final split = computePaymentSplit(
        paymentAmount: paymentAmount,
        outstandingBalance: outstanding,
      );
      final delta = computeReversalLoanDelta(
        paymentAmount: paymentAmount,
        overpaymentSurplus: split.overpaymentSurplus,
      );
      expect(delta, split.appliedToLoan);
      expect(delta, outstanding);
    });
  });

  group('computeSavingsReversal', () {
    test('sufficient balance: full surplus deducted', () {
      final (newBalance, deducted) = computeSavingsReversal(
        balance: 5000,
        overpaymentSurplus: 2000,
      );
      expect(newBalance, 3000);
      expect(deducted, 2000);
    });

    test('insufficient balance: reversal is rejected atomically', () {
      // A partial deduction would leave the payment marked reversed while the
      // remaining overpayment still exists in savings, breaking accounting.
      expect(
        () => computeSavingsReversal(balance: 1500, overpaymentSurplus: 2000),
        throwsStateError,
      );
    });

    test('exact balance: account reaches zero', () {
      final (newBalance, deducted) = computeSavingsReversal(
        balance: 2000,
        overpaymentSurplus: 2000,
      );
      expect(newBalance, 0);
      expect(deducted, 2000);
    });
  });

  group('schedule recalculation — mixed payment sequences', () {
    double simulateScheduleTotal(
        List<({double amount, double overpaymentSurplus})> payments) {
      return payments.fold(0.0, (sum, p) => sum + (p.amount - p.overpaymentSurplus));
    }

    test('partial + overpayment: schedule uses loan-applied portions', () {
      const outstanding = 10000.0;
      final p1 = computePaymentSplit(paymentAmount: 3000, outstandingBalance: outstanding);
      final p2 = computePaymentSplit(
        paymentAmount: 8000,
        outstandingBalance: outstanding - p1.appliedToLoan,
      );
      final total = simulateScheduleTotal([
        (amount: 3000, overpaymentSurplus: p1.overpaymentSurplus),
        (amount: 8000, overpaymentSurplus: p2.overpaymentSurplus),
      ]);
      expect(total, closeTo(outstanding, 0.001));
      expect(p2.overpaymentSurplus, closeTo(1000, 0.001));
    });

    test('raw payment totals overstate schedule when surplus exists', () {
      const outstanding = 10000.0;
      final p1 = computePaymentSplit(paymentAmount: 3000, outstandingBalance: outstanding);
      final p2 = computePaymentSplit(
        paymentAmount: 8000,
        outstandingBalance: outstanding - p1.appliedToLoan,
      );
      final corrected = simulateScheduleTotal([
        (amount: 3000, overpaymentSurplus: p1.overpaymentSurplus),
        (amount: 8000, overpaymentSurplus: p2.overpaymentSurplus),
      ]);
      expect(3000.0 + 8000.0, 11000);
      expect(corrected, closeTo(10000, 0.001));
    });
  });

  group('end-to-end invariants', () {
    test('loan and savings balances are restored after payment reversal', () {
      const outstanding = 10000.0;
      const initialSavings = 500.0;
      const paymentAmount = 12500.0;
      final split = computePaymentSplit(
        paymentAmount: paymentAmount,
        outstandingBalance: outstanding,
      );
      final loanAfterPayment = split.newLoanBalance;
      final savingsAfterPayment = initialSavings + split.overpaymentSurplus;
      final loanDelta = computeReversalLoanDelta(
        paymentAmount: paymentAmount,
        overpaymentSurplus: split.overpaymentSurplus,
      );
      final (savingsAfterReversal, _) = computeSavingsReversal(
        balance: savingsAfterPayment,
        overpaymentSurplus: split.overpaymentSurplus,
      );
      expect(loanAfterPayment + loanDelta, closeTo(outstanding, 0.001));
      expect(savingsAfterReversal, closeTo(initialSavings, 0.001));
    });

    test('normal payment reversal fully restores loan', () {
      const outstanding = 8000.0;
      const paymentAmount = 3000.0;
      final split = computePaymentSplit(
        paymentAmount: paymentAmount,
        outstandingBalance: outstanding,
      );
      final delta = computeReversalLoanDelta(
        paymentAmount: paymentAmount,
        overpaymentSurplus: 0,
      );
      expect(split.newLoanBalance + delta, closeTo(outstanding, 0.001));
    });
  });

  group('invalid numeric inputs are rejected', () {
    test('NaN paymentAmount throws', () {
      expect(
        () => computePaymentSplit(paymentAmount: double.nan, outstandingBalance: 10000),
        throwsArgumentError,
      );
    });

    test('Infinity paymentAmount throws', () {
      expect(
        () => computePaymentSplit(paymentAmount: double.infinity, outstandingBalance: 10000),
        throwsArgumentError,
      );
      expect(
        () => computePaymentSplit(paymentAmount: double.negativeInfinity, outstandingBalance: 10000),
        throwsArgumentError,
      );
    });

    test('zero and negative paymentAmount throw', () {
      expect(
        () => computePaymentSplit(paymentAmount: 0, outstandingBalance: 10000),
        throwsArgumentError,
      );
      expect(
        () => computePaymentSplit(paymentAmount: -100, outstandingBalance: 10000),
        throwsArgumentError,
      );
    });

    test('non-finite outstandingBalance throws', () {
      expect(
        () => computePaymentSplit(paymentAmount: 500, outstandingBalance: double.nan),
        throwsArgumentError,
      );
      expect(
        () => computePaymentSplit(paymentAmount: 500, outstandingBalance: double.infinity),
        throwsArgumentError,
      );
    });

    test('valid installment payment still splits correctly', () {
      final split = computePaymentSplit(
        paymentAmount: 1200,
        outstandingBalance: 10000,
        installmentDue: 500,
      );
      expect(split.appliedToLoan, 500);
      expect(split.overpaymentSurplus, 700);
      expect(split.newLoanBalance, 9500);
    });
  });
}
