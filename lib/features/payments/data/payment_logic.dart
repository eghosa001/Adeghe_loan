/// Pure financial calculation functions for payment processing.
///
/// These functions are isolated from the database layer so they can be
/// unit-tested without SQLite infrastructure.
library payment_logic;

/// Overpayment calculation result.
class PaymentAmounts {
  const PaymentAmounts({
    required this.appliedToLoan,
    required this.overpaymentSurplus,
    required this.newLoanBalance,
  });

  /// The portion of the payment actually applied to reduce the loan balance.
  final double appliedToLoan;

  /// The amount in excess of the outstanding balance, credited to savings.
  /// Zero for normal (non-overpayment) payments.
  final double overpaymentSurplus;

  /// The loan's outstanding balance after the payment is applied.
  final double newLoanBalance;
}

/// Compute how a [paymentAmount] splits between a loan with [outstandingBalance].
///
/// - [appliedToLoan] = min(paymentAmount, outstandingBalance)
/// - [overpaymentSurplus] = max(0, paymentAmount − outstandingBalance)
/// - [newLoanBalance] = outstandingBalance − appliedToLoan  (always ≥ 0)
PaymentAmounts computePaymentSplit({
  required double paymentAmount,
  required double outstandingBalance,
}) {
  assert(paymentAmount > 0, 'paymentAmount must be positive');
  assert(outstandingBalance >= 0, 'outstandingBalance must be non-negative');

  final surplus = (paymentAmount - outstandingBalance).clamp(0.0, double.infinity);
  final applied = paymentAmount - surplus;
  final newBalance = (outstandingBalance - applied).clamp(0.0, double.infinity);

  return PaymentAmounts(
    appliedToLoan: applied,
    overpaymentSurplus: surplus,
    newLoanBalance: newBalance,
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
/// Guards against negative: if the customer's current savings [balance] is less
/// than the [overpaymentSurplus] to deduct, only deducts what is available.
/// Returns the (newBalance, amountDeducted) pair.
(double newBalance, double amountDeducted) computeSavingsReversal({
  required double balance,
  required double overpaymentSurplus,
}) {
  assert(balance >= 0, 'balance must be non-negative');
  assert(overpaymentSurplus > 0, 'overpaymentSurplus must be positive');

  final toDeduct = overpaymentSurplus.clamp(0.0, balance);
  return (balance - toDeduct, toDeduct);
}
