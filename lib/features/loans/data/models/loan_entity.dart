import 'package:loantrack/core/utils/date_utils.dart';

enum LoanType { daily, monthly }

enum LoanStatus { active, completed, defaulted, pending }

class Loan {
  final String id;
  final String customerId;
  final LoanType loanType;
  final LoanStatus status;

  // Inputs from form
  final double amount;
  final double interestRate; // This is a percentage
  final double insuranceFee; // This is a percentage
  final double commission; // This is a percentage
  final double processingFee; // This is a flat amount
  final double administrativeFee; // This is a flat amount
  final double otherCharges; // This is a flat amount
  final int duration; // Days for Daily, Months for Monthly
  final DateTime loanDate;
  final DateTime repaymentStartDate;

  // Calculated values to be stored
  final double totalRepayment;
  final double outstandingBalance;
  final double installmentAmount;
  final DateTime expectedCompletionDate;

  // Optional fields
  final String? collector;
  final String? notes;

  Loan({
    required this.id,
    required this.customerId,
    required this.loanType,
    this.status = LoanStatus.active,
    required this.amount,
    required this.interestRate,
    this.insuranceFee = 0.0,
    this.commission = 0.0,
    this.processingFee = 0.0,
    this.administrativeFee = 0.0,
    this.otherCharges = 0.0,
    required this.duration,
    required this.loanDate,
    required this.repaymentStartDate,
    required this.totalRepayment,
    required this.outstandingBalance,
    required this.installmentAmount,
    required this.expectedCompletionDate,
    this.collector,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_id': customerId,
      'loan_type': loanType.name,
      'status': status.name,
      'amount': amount,
      'interest_rate': interestRate,
      'insurance_fee': insuranceFee,
      'commission': commission,
      'processing_fee': processingFee,
      'admin_fee': administrativeFee,
      'other_charges': otherCharges,
      'duration_months': loanType == LoanType.monthly ? duration : null,
      // NOTE: Assumes a 'duration_days' column was added for daily loans
      'duration_days': loanType == LoanType.daily ? duration : null,
      'repayment_frequency': loanType.name,
      'daily_payment': loanType == LoanType.daily ? installmentAmount : null,
      'monthly_payment': loanType == LoanType.monthly ? installmentAmount : null,
      'loan_date': AppDateUtils.formatForStorage(loanDate),
      'start_date': AppDateUtils.formatForStorage(repaymentStartDate),
      'total_repayment': totalRepayment,
      'outstanding_balance': outstandingBalance,
      'expected_completion_date':
          AppDateUtils.formatForStorage(expectedCompletionDate),
      'collector': collector,
      'notes': notes,
    };
  }

  factory Loan.fromMap(Map<String, dynamic> map) {
    return Loan(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
      loanType: LoanType.values
          .firstWhere((e) => e.name == map['loan_type'], orElse: () => LoanType.daily),
      status: LoanStatus.values
          .firstWhere((e) => e.name == map['status'], orElse: () => LoanStatus.pending),
      amount: (map['amount'] as num).toDouble(),
      interestRate: (map['interest_rate'] as num).toDouble(),
      insuranceFee: (map['insurance_fee'] as num?)?.toDouble() ?? 0.0,
      commission: (map['commission'] as num?)?.toDouble() ?? 0.0,
      processingFee: (map['processing_fee'] as num?)?.toDouble() ?? 0.0,
      administrativeFee: (map['admin_fee'] as num?)?.toDouble() ?? 0.0,
      otherCharges: (map['other_charges'] as num?)?.toDouble() ?? 0.0,
      duration: (map['duration_days'] ?? map['duration_months']) as int,
      loanDate: AppDateUtils.tryParseStorage(map['loan_date'] as String)!,
      repaymentStartDate:
          AppDateUtils.tryParseStorage(map['start_date'] as String)!,
      totalRepayment: (map['total_repayment'] as num).toDouble(),
      outstandingBalance: (map['outstanding_balance'] as num).toDouble(),
      installmentAmount:
          ((map['daily_payment'] ?? map['monthly_payment']) as num).toDouble(),
      expectedCompletionDate: AppDateUtils.tryParseStorage(
          map['expected_completion_date'] as String)!,
      collector: map['collector'] as String?,
      notes: map['notes'] as String?,
    );
  }
}
