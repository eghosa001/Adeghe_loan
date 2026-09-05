import 'dart:math';

import '../../../core/utils/currency_utils.dart';

// Pure financial calculation functions for payment processing.
// These functions are isolated from the database layer so they can be
// unit-tested without SQLite infrastructure.

/// Overpayment calculation result.
class PaymentAmounts {
  const PaymentAmounts({
    required this.appliedToLoan,
    required this.overpaymentSurplus,
    required this.newLoanBalance,
  });

  /// The portion of the payment actually applied to reduce the loan balance.
  final double appliedToLoan;

  /// The amount in excess of the installment, credited to savings.
  /// Zero for normal (non-overpayment) payments.
  final double overpaymentSurplus;

  /// The loan's outstanding balance after the payment is applied.
  final double newLoanBalance;
}

/// Compute how a [paymentAmount] splits between loan repayment and savings.
///
/// The loan receives the full payment up to the current [installmentDue]
/// (the unpaid portion of the installment the customer is collecting on);
/// any excess over that amount is credited to savings as an overpayment.
/// When [installmentDue] is omitted/zero the payment caps at the full
/// [outstandingBalance] so "pay in full" and loan-settlement payments apply
/// entirely to the loan.
PaymentAmounts computePaymentSplit({
  required double paymentAmount,
  required double outstandingBalance,
  double? installmentDue,
}) {
  if (!paymentAmount.isFinite || paymentAmount <= 0) {
    throw ArgumentError.value(
        paymentAmount, 'paymentAmount', 'must be a finite number > 0');
  }
  if (!outstandingBalance.isFinite || outstandingBalance < 0) {
    throw ArgumentError.value(outstandingBalance, 'outstandingBalance',
        'must be a finite number >= 0');
  }
  if (installmentDue != null &&
      (!installmentDue.isFinite || installmentDue < 0)) {
    throw ArgumentError.value(installmentDue, 'installmentDue',
        'must be null or a finite number >= 0');
  }

  final cap = (installmentDue != null && installmentDue > 0)
      ? min(installmentDue, outstandingBalance)
      : outstandingBalance;

  // Work in integer minor units so loan + savings always reconciles to the
  // entered currency amount after rounding.
  final paymentCents = CurrencyUtils.toMinorUnits(paymentAmount);
  final capCents = CurrencyUtils.toMinorUnits(cap);
  final loanPaidCents = min(paymentCents, capCents);
  final surplusCents = paymentCents - loanPaidCents;
  final outstandingCents = CurrencyUtils.toMinorUnits(outstandingBalance);
  final newBalanceCents = max(0, outstandingCents - loanPaidCents);

  return PaymentAmounts(
    appliedToLoan: CurrencyUtils.fromMinorUnits(loanPaidCents),
    overpaymentSurplus: CurrencyUtils.fromMinorUnits(surplusCents),
    newLoanBalance: CurrencyUtils.fromMinorUnits(newBalanceCents),
  );
}

/// Compute loan balance restoration amounts when reversing a payment.
///
/// Returns the amount that should be added back to `outstanding_balance`.
double computeReversalLoanDelta({
  required double paymentAmount,
  required double overpaymentSurplus,
}) {
  if (!paymentAmount.isFinite || paymentAmount <= 0) {
    throw ArgumentError.value(
        paymentAmount, 'paymentAmount', 'must be a finite number > 0');
  }
  if (!overpaymentSurplus.isFinite ||
      overpaymentSurplus < 0 ||
      overpaymentSurplus > paymentAmount) {
    throw ArgumentError.value(
      overpaymentSurplus,
      'overpaymentSurplus',
      'must be finite, non-negative, and no greater than paymentAmount',
    );
  }
  return CurrencyUtils.fromMinorUnits(
    CurrencyUtils.toMinorUnits(paymentAmount) -
        CurrencyUtils.toMinorUnits(overpaymentSurplus),
  );
}

/// Compute the savings balance after unwinding an overpayment credit.
///
/// Reversal is deliberately all-or-nothing. Silently deducting only the
/// available balance would allow a payment to be marked reversed while part
/// of its overpayment remained in savings, creating an accounting imbalance.
(double newBalance, double amountDeducted) computeSavingsReversal({
  required double balance,
  required double overpaymentSurplus,
}) {
  if (!balance.isFinite || balance < 0) {
    throw ArgumentError.value(
        balance, 'balance', 'must be a finite number >= 0');
  }
  if (!overpaymentSurplus.isFinite || overpaymentSurplus <= 0) {
    throw ArgumentError.value(overpaymentSurplus, 'overpaymentSurplus',
        'must be a finite number > 0');
  }
  if (overpaymentSurplus > balance) {
    throw StateError(
      'Insufficient savings balance to reverse the full overpayment credit.',
    );
  }

  final balanceCents = CurrencyUtils.toMinorUnits(balance);
  final surplusCents = CurrencyUtils.toMinorUnits(overpaymentSurplus);
  final newBalanceCents = balanceCents - surplusCents;
  return (
    CurrencyUtils.fromMinorUnits(newBalanceCents),
    CurrencyUtils.fromMinorUnits(surplusCents),
  );
}
