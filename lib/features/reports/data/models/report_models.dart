/// Row types backing the new per-report screens. Each report screen owns its
/// own row type so exports and tables only ever render the filtered data that
/// screen produced.
library;

import 'report_summary.dart';

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

// ===========================================================================
// Report dashboard aggregates (redesigned Reports dashboard, 2026-08-11)
// ===========================================================================
//
// These types are produced by ONE repository call (`getReportDashboard`) so
// the dashboard, its trend deltas, and every section read from a single
// consistent snapshot of the money rule — no two sections can disagree.

/// One collector's today-total on the "Today's Collection" section.
class CollectorTotal {
  const CollectorTotal({
    required this.collector,
    required this.amount,
    required this.count,
  });

  final String collector;
  final double amount;
  final int count;
}

/// "Today's Collection" section data. All figures are Dart-local-date based
/// and follow the money rule (`completed` payments minus savings overpayments).
class TodayCollection {
  const TodayCollection({
    required this.paymentCount,
    required this.collectedAmount,
    required this.dueToday,
    required this.dueTodayLoans,
    required this.dueTodayCustomers,
    this.topCollectors = const [],
  });

  final int paymentCount;
  final double collectedAmount;

  /// Unpaid portion of installments due today on active loans (holidays
  /// excluded) — "what was due today but not collected yet".
  final double dueToday;
  final int dueTodayLoans;
  final int dueTodayCustomers;
  final List<CollectorTotal> topCollectors;
}

/// One overdue-age bucket (1–7, 8–14, 15+ days) in the Overdue & Risk section.
class OverdueBucket {
  const OverdueBucket({
    required this.label,
    required this.loanCount,
    required this.amount,
  });

  final String label;
  final int loanCount;
  final double amount;
}

/// One account in the "top overdue accounts" list.
class OverdueAccount {
  const OverdueAccount({
    required this.customerName,
    required this.loanId,
    required this.loanType,
    required this.amount,
  });

  final String customerName;
  final String loanId;
  final String loanType;
  final double amount;
}

/// "Overdue & Risk" section data. Counts are DISTINCT loans; amounts are the
/// unpaid portion of overdue installments (money rule, holidays excluded).
class OverdueRisk {
  const OverdueRisk({
    required this.totalAmount,
    required this.overdueLoans,
    required this.buckets,
    required this.topAccounts,
  });

  final double totalAmount;
  final int overdueLoans;
  final List<OverdueBucket> buckets;
  final List<OverdueAccount> topAccounts;
}

/// "Savings" section data. In/out are period-scoped; balance is the live
/// `savings_accounts.balance` sum across non-archived customers.
class SavingsSummary {
  const SavingsSummary({
    required this.totalBalance,
    required this.inflow,
    required this.outflow,
  });

  final double totalBalance;
  final double inflow;
  final double outflow;

  double get netFlow => inflow - outflow;
}

/// "Customers" section data. [totalCustomers] is all non-archived customers;
/// [activeLoanCustomers] is the distinct count with an active/defaulted loan.
class CustomerStats {
  const CustomerStats({
    required this.totalCustomers,
    required this.newInPeriod,
    required this.activeLoanCustomers,
  });

  final int totalCustomers;
  final int newInPeriod;
  final int activeLoanCustomers;
}

/// The single snapshot backing the redesigned Reports dashboard. One
/// repository call computes the period summary, the previous-period summary
/// (for deltas), today's collections, overdue risk, savings and customer
/// stats — so the whole dashboard renders from one consistent dataset.
class ReportDashboardData {
  const ReportDashboardData({
    required this.summary,
    required this.previousSummary,
    required this.today,
    required this.overdue,
    required this.savings,
    required this.customers,
  });

  final ReportSummary summary;
  final ReportSummary previousSummary;
  final TodayCollection today;
  final OverdueRisk overdue;
  final SavingsSummary savings;
  final CustomerStats customers;

  double get totalOutstandingBalance =>
      summary.dailyLoans.outstandingBalance + summary.weeklyLoans.outstandingBalance;

  double get totalExpectedCollections =>
      summary.dailyLoans.expectedCollections + summary.weeklyLoans.expectedCollections;
}
