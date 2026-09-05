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
///
/// - [loanPaid] = min(paymentAmount, cap) where cap = installmentDue > 0
///   ? installmentDue : outstandingBalance
/// - [savingsDeposit] = paymentAmount - loanPaid
/// - [newBalance] = outstandingBalance - loanPaid (always >= 0)
PaymentAmounts computePaymentSplit({
  required double paymentAmount,
  required double outstandingBalance,
  double? installmentDue,
}) {
  // Runtime checks (the debug-only asserts never ran in release builds, so a
  // NaN/±Infinity amount could flow straight into the DB). Non-finite inputs
  // come from typed text like "1e309"; reject them loudly instead of letting
  // SQLite store NULL.
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

  // The cap is the unpaid installment — but never more than what is actually
  // owed. Without the clamp a payment on a nearly-settled loan whose
  // installment exceeds the remaining balance would apply (and count as
  // "collected on the loan") money the loan no longer owes, instead of
  // crediting the excess to savings.
  final cap = (installmentDue != null && installmentDue > 0)
      ? min(installmentDue, outstandingBalance)
      : outstandingBalance;
  final rawLoanPaid = min(paymentAmount, cap);

  // Perform the split in minor units so the two destinations always reconcile
  // exactly to the entered payment after currency rounding. Doing the surplus
  // calculation from [rawLoanPaid] while rounding [loanPaid] separately can
  // otherwise create a one-cent accounting mismatch at half-cent boundaries.
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
/// Returns the amount that should be **added back** to `outstanding_balance`.
/// This is [paymentAmount] minus any [overpaymentSurplus] that went to savings,
/// because the surplus was never deducted from the loan balance.
double computeReversalLoanDelta({
  required double paymentAmount,
  required double overpaymentSurplus,
}) {
  assert(overpaymentSurplus >= 0, 'overpaymentSurplus must be non-negative');
  assert(overpaymentSurplus <= paymentAmount,
      'overpaymentSurplus cannot exceed paymentAmount');
  return paymentAmount - overpaymentSurplus;
}

/// Compute the savings balance after unwinding an overpayment credit.
///
/// Returns the (newBalance, amountDeducted) pair.
(double newBalance, double amountDeducted) computeSavingsReversal({
  required double balance,
  required double overpaymentSurplus,
}) {
  assert(balance >= 0, 'balance must be non-negative');
  assert(overpaymentSurplus > 0, 'overpaymentSurplus must be positive');

  final toDeduct = min(overpaymentSurplus, balance);
  return (balance - toDeduct, toDeduct);
}
