import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/loans/domain/loan_calculator.dart';

void main() {
  const validArgs = (
    interestRatePercent: 5.0,
    insuranceFeePercent: 1.0,
    commissionPercent: 0.0,
    processingFee: 0.0,
    administrativeFee: 0.0,
    otherCharges: 0.0,
  );

  LoanCalculationResult run({
    required double principal,
    required int duration,
  }) =>
      LoanCalculator.calculate(
        principal: principal,
        interestRatePercent: validArgs.interestRatePercent,
        insuranceFeePercent: validArgs.insuranceFeePercent,
        commissionPercent: validArgs.commissionPercent,
        processingFee: validArgs.processingFee,
        administrativeFee: validArgs.administrativeFee,
        otherCharges: validArgs.otherCharges,
        duration: duration,
      );

  test('calculates a normal loan', () {
    final r = run(principal: 10000, duration: 10);
    expect(r.totalRepayment, 10600); // 10000 + 5% interest + 1% insurance
    expect(r.installmentAmount, 1060);
  });

  test('Infinity principal does not crash (1e309 crash guard)', () {
    final r = run(principal: double.infinity, duration: 10);
    expect(r.totalRepayment, 0);
    expect(r.installmentAmount, 0);
    expect(r.interestAmount, 0);
  });

  test('NaN principal does not crash', () {
    final r = run(principal: double.nan, duration: 10);
    expect(r.totalRepayment, 0);
    expect(r.installmentAmount, 0);
  });

  test('non-positive duration returns zeros instead of crashing', () {
    final r = run(principal: 10000, duration: 0);
    expect(r.installmentAmount, 0);
    expect(r.totalRepayment, 10000);
  });
}
