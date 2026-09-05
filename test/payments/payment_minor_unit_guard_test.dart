import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/payments/data/payment_logic.dart';

void main() {
  test('rejects positive payment that rounds to zero minor units', () {
    expect(
      () => computePaymentSplit(
        paymentAmount: 0.004,
        outstandingBalance: 1000,
      ),
      throwsArgumentError,
    );
  });

  test('accepts the smallest two-decimal payment', () {
    final result = computePaymentSplit(
      paymentAmount: 0.01,
      outstandingBalance: 1000,
    );

    expect(result.appliedToLoan, 0.01);
    expect(result.overpaymentSurplus, 0);
    expect(result.newLoanBalance, 999.99);
  });
}
