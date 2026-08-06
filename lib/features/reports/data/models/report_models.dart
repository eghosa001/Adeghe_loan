/// Row types backing the new per-report screens. Each report screen owns its
/// own row type so exports and tables only ever render the filtered data that
/// screen produced.
library;

/// One customer line in the Customer Report. Loan aggregates are computed from
/// the money rule (completed payments only, overpayments excluded) so the
/// figures reconcile with every other report.
class CustomerReportRow {
  const CustomerReportRow({
    required this.customerId,
    required this.customerName,
    required this.phone,
    required this.email,
    required this.groupName,
    required this.dateRegistered,
    required this.loanCount,
    required this.activeLoanCount,
    required this.totalDisbursed,
    required this.totalCollected,
    required this.outstandingBalance,
    required this.savingsBalance,
  });

  final String customerId;
  final String customerName;
  final String phone;
  final String email;
  final String? groupName;
  final String dateRegistered;
  final int loanCount;
  final int activeLoanCount;
  final double totalDisbursed;
  final double totalCollected;
  final double outstandingBalance;
  final double savingsBalance;
}

/// One savings account line in the Savings Report. Balances are the live
/// `savings_accounts.balance`; deposits/withdrawals are lifetime ledger sums
/// so a per-customer statement can be reconciled from the totals row.
class SavingsReportRow {
  const SavingsReportRow({
    required this.customerId,
    required this.customerName,
    required this.phone,
    required this.groupName,
    required this.balance,
    required this.totalDeposits,
    required this.totalWithdrawals,
    required this.overpaymentSurplus,
    required this.lastActivityDate,
  });

  final String customerId;
  final String customerName;
  final String phone;
  final String? groupName;
  final double balance;
  final double totalDeposits;
  final double totalWithdrawals;
  final double overpaymentSurplus;
  final String? lastActivityDate;
}

/// One loan line in the Profit Report. Profit per loan is the expected
/// repayment plus fees minus the principal disbursed (cancelled loans are
/// excluded entirely because they never disbursed or earned).
class ProfitReportRow {
  const ProfitReportRow({
    required this.loanId,
    required this.customerId,
    required this.customerName,
    required this.loanType,
    required this.loanDate,
    required this.principal,
    required this.interest,
    required this.fees,
    required this.expectedRepayment,
    required this.totalCollected,
    required this.outstandingBalance,
    required this.status,
  });

  final String loanId;
  final String customerId;
  final String customerName;
  final String loanType;
  final String loanDate;
  final double principal;
  final double interest;
  final double fees;
  final double expectedRepayment;
  final double totalCollected;
  final double outstandingBalance;
  final String status;

  /// Expected gross profit = interest + fees (what the loan earns above the
  /// principal it disburses).
  double get expectedProfit => interest + fees;

  /// Realised profit so far = loan-applied collections minus principal repaid.
  double get realisedProfit =>
      (totalCollected - (principal - outstandingBalance)).clamp(
          0.0, double.infinity);

  double get profitRemaining =>
      (expectedProfit - (totalCollected - (principal - outstandingBalance)))
          .clamp(0.0, double.infinity);
}

/// One customer/loan collection line in the Collection Report. Rows come from
/// `CollectionRepository.getCollectionsByDateRange` semantics: due = unpaid
/// portion of installments due in period; paid = loan-applied payments in
/// period (money rule).
class CollectionReportRow {
  const CollectionReportRow({
    required this.customerId,
    required this.customerName,
    required this.phone,
    required this.loanId,
    required this.loanType,
    required this.amountDue,
    required this.amountPaid,
    required this.outstandingBalance,
    this.groupName,
  });

  final String customerId;
  final String customerName;
  final String phone;
  final String loanId;
  final String loanType;
  final double amountDue;
  final double amountPaid;
  final double outstandingBalance;
  final String? groupName;

  double get balanceRemaining => (amountDue - amountPaid).clamp(0.0, double.infinity);
}

/// A single bucket on a dashboard trend chart. Each chart plots one or two
/// series of these points over the selected report period (bucketed daily for
/// short ranges, weekly for medium, monthly for long).
class DashboardTrendPoint {
  const DashboardTrendPoint({
    required this.label,
    required this.value,
    this.secondValue,
  });

  final String label;
  final double value;
  final double? secondValue;
}

/// Aggregated dashboard trends honoring the active report date range. All
/// series use the money rule for any payment-derived figure.
class DashboardTrends {
  const DashboardTrends({
    required this.collected,
    required this.disbursed,
    required this.savingsIn,
    required this.savingsOut,
    required this.customers,
    required this.loans,
  });

  final List<DashboardTrendPoint> collected;
  final List<DashboardTrendPoint> disbursed;
  final List<DashboardTrendPoint> savingsIn;
  final List<DashboardTrendPoint> savingsOut;
  final List<DashboardTrendPoint> customers;
  final List<DashboardTrendPoint> loans;
}
