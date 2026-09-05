import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/payments/data/payment_logic.dart';

void main() {
  group('computePaymentSplit numeric boundaries', () {
    test('rejects NaN payment amount', () {
      expect(
        () => computePaymentSplit(
          paymentAmount: double.nan,
          outstandingBalance: 1000,
        ),
        throwsArgumentError,
      );
    });

    test('rejects infinite payment amount', () {
      expect(
        () => computePaymentSplit(
          paymentAmount: double.infinity,
          outstandingBalance: 1000,
        ),
        throwsArgumentError,
      );
    });

    test('rejects NaN installment due instead of treating it as omitted', () {
      expect(
        () => computePaymentSplit(
          paymentAmount: 100,
          outstandingBalance: 1000,
          installmentDue: double.nan,
        ),
        throwsArgumentError,
      );
    });

    test('rejects negative installment due', () {
      expect(
        () => computePaymentSplit(
          paymentAmount: 100,
          outstandingBalance: 1000,
          installmentDue: -1,
        ),
        throwsArgumentError,
      );
    });

    test('minor-unit split reconciles exactly at cent boundaries', () {
      final result = computePaymentSplit(
        paymentAmount: 10.01,
        outstandingBalance: 20.00,
        installmentDue: 10.00,
      );

      expect(result.appliedToLoan, 10.00);
      expect(result.overpaymentSurplus, 0.01);
      expect(
        result.appliedToLoan + result.overpaymentSurplus,
        closeTo(10.01, pow(10, -9).toDouble()),
      );
    });
  });

  group('computeSavingsReversal accounting boundaries', () {
    test('reverses the full overpayment when savings can cover it', () {
      final result = computeSavingsReversal(
        balance: 100.00,
        overpaymentSurplus: 25.00,
      );

      expect(result.$1, 75.00);
      expect(result.$2, 25.00);
    });

    test('rejects partial reversal when savings cannot cover the credit', () {
      expect(
        () => computeSavingsReversal(
          balance: 10.00,
          overpaymentSurplus: 25.00,
        ),
        throwsStateError,
      );
    });

    test('rejects non-finite savings balance', () {
      expect(
        () => computeSavingsReversal(
          balance: double.infinity,
          overpaymentSurplus: 1.00,
        ),
        throwsArgumentError,
      );
    });
  });
}
