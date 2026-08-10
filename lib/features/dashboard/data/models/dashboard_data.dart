import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/payments/data/models/payment_entity.dart';

class DashboardData {
  DashboardData({
    required this.totalCustomers,
    required this.activeLoans,
    required this.completedLoans,
    required this.dailyActiveLoans,
    required this.weeklyActiveLoans,
    required this.totalDisbursed,
    required this.periodDisbursed,
    required this.dailyDisbursed,
    required this.weeklyDisbursed,
    required this.totalCollected,
    required this.periodCollected,
    required this.dailyCollected,
    required this.weeklyCollected,
    required this.outstandingBalance,
    required this.dailyOutstandingBalance,
    required this.weeklyOutstandingBalance,
    required this.totalExpected,
    required this.dailyExpected,
    required this.weeklyExpected,
    required this.totalOverdue,
    required this.overdue1to7Days,
    required this.overdue8to30Days,
    required this.overdue31PlusDays,
    required this.overdueLoansCount,
    required this.overdueCustomersCount,
    required this.par1Plus,
    required this.par7Plus,
    required this.par30Plus,
    required this.totalInterestEarned,
    required this.totalFeesEarned,
    required this.totalExpenses,
    required this.totalSavingsBalance,
    required this.savingsDepositsThisMonth,
    required this.savingsWithdrawalsThisMonth,
    required this.newCustomersToday,
    required this.newCustomersThisWeek,
    required this.newCustomersThisMonth,
    required this.todayExpected,
    required this.todayCollected,
    required this.todayDueCustomers,
    required this.todayPaidCustomers,
    required this.todayPendingCustomers,
    this.totalGroups = 0,
    this.recentLoans = const [],
    this.recentPayments = const [],
    this.recentSavingsTransactions = const [],
  });

  final int totalCustomers;
  final int activeLoans;
  final int completedLoans;
  final int dailyActiveLoans;
  final int weeklyActiveLoans;
  final double totalDisbursed;
  final double periodDisbursed;
  final double dailyDisbursed;
  final double weeklyDisbursed;
  final double totalCollected;
  final double periodCollected;
  final double dailyCollected;
  final double weeklyCollected;
  final double outstandingBalance;
  final double dailyOutstandingBalance;
  final double weeklyOutstandingBalance;
  final double totalExpected;
  final double dailyExpected;
  final double weeklyExpected;
  final double totalOverdue;
  final double overdue1to7Days;
  final double overdue8to30Days;
  final double overdue31PlusDays;
  final int overdueLoansCount;
  final int overdueCustomersCount;
  final double par1Plus;
  final double par7Plus;
  final double par30Plus;
  final double totalInterestEarned;
  final double totalFeesEarned;
  final double totalExpenses;
  final double totalSavingsBalance;
  final double savingsDepositsThisMonth;
  final double savingsWithdrawalsThisMonth;
  final int newCustomersToday;
  final int newCustomersThisWeek;
  final int newCustomersThisMonth;
  final double todayExpected;
  final double todayCollected;
  final int todayDueCustomers;
  final int todayPaidCustomers;
  final int todayPendingCustomers;
  final int totalGroups;
  final List<Loan> recentLoans;
  final List<Payment> recentPayments;
  final List<DashboardSavingsTransaction> recentSavingsTransactions;

  double get netProfit => (totalInterestEarned + totalFeesEarned) - totalExpenses;
  double get collectionRate => todayExpected > 0 ? ((todayCollected / todayExpected) * 100).clamp(0.0, 100.0) : 0.0;
}

class DashboardSavingsTransaction {
  DashboardSavingsTransaction({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.type,
    required this.amount,
    required this.createdAt,
  });

  final String id;
  final String customerId;
  final String customerName;
  final String type;
  final double amount;
  final String createdAt;

  bool get isCredit => type == 'deposit' || type == 'overpayment';
  bool get isDebit => type == 'withdrawal';

  String get typeLabel {
    switch (type) {
      case 'deposit':
        return 'Deposit';
      case 'overpayment':
        return 'Overpayment';
      case 'withdrawal':
        return 'Withdrawal';
      default:
        return type;
    }
  }

  factory DashboardSavingsTransaction.fromMap(Map<String, dynamic> row) {
    return DashboardSavingsTransaction(
      id: row['id'] as String? ?? '',
      customerId: row['customerId'] as String? ?? '',
      customerName: row['customerName'] as String? ?? '',
      type: row['type'] as String? ?? '',
      amount: (row['amount'] as num?)?.toDouble() ?? 0.0,
      createdAt: row['createdAt'] as String? ?? '',
    );
  }
}
