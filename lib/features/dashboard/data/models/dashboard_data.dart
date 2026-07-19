import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/payments/data/models/payment_entity.dart';

class DashboardData {
  DashboardData({
    required this.totalCustomers,
    required this.activeLoans,
    required this.totalDisbursed,
    required this.totalCollected,
    required this.outstandingBalance,
    required this.recentLoans,
    required this.recentPayments,
  });

  final int totalCustomers;
  final int activeLoans;
  final double totalDisbursed;
  final double totalCollected;
  final double outstandingBalance;
  final List<Loan> recentLoans;
  final List<Payment> recentPayments;
}
