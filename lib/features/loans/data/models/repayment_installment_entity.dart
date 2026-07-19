import 'package:loantrack/core/utils/date_utils.dart';

enum RepaymentStatus { pending, paid, partial, missed }

class RepaymentInstallment {
  final String id;
  final String loanId;
  final int installmentNumber;
  final DateTime dueDate;
  final double amount;
  final RepaymentStatus status;

  RepaymentInstallment({
    required this.id,
    required this.loanId,
    required this.installmentNumber,
    required this.dueDate,
    required this.amount,
    this.status = RepaymentStatus.pending,
  });

  RepaymentInstallment copyWith({
    String? id,
    String? loanId,
    int? installmentNumber,
    DateTime? dueDate,
    double? amount,
    RepaymentStatus? status,
  }) {
    return RepaymentInstallment(
      id: id ?? this.id,
      loanId: loanId ?? this.loanId,
      installmentNumber: installmentNumber ?? this.installmentNumber,
      dueDate: dueDate ?? this.dueDate,
      amount: amount ?? this.amount,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'loan_id': loanId,
      'installment_number': installmentNumber,
      'due_date': AppDateUtils.formatForStorage(dueDate),
      'amount': amount,
      'status': status.name,
    };
  }

  factory RepaymentInstallment.fromMap(Map<String, dynamic> map) {
    return RepaymentInstallment(
      id: map['id'] as String,
      loanId: map['loan_id'] as String,
      installmentNumber: map['installment_number'] as int,
      dueDate: AppDateUtils.tryParseStorage(map['due_date'] as String) ?? DateTime.now(),
      amount: map['amount'] as double,
      status: RepaymentStatus.values.firstWhere((e) => e.name == map['status'], orElse: () => RepaymentStatus.pending),
    );
  }
}
