import 'package:loantrack/core/utils/date_utils.dart';

enum PaymentMethod { cash, transfer, pos, cheque, mobileMoney }

enum PaymentType { partial, full, advance, overpayment }

enum PaymentStatus { completed, reversed }

class Payment {
  final String id;
  final String loanId;
  final String customerId;
  final double amount;
  final PaymentMethod method;
  final String? referenceNumber;
  final String receiptNumber;
  final DateTime paymentDate;
  final String collector;
  final PaymentType type;
  final PaymentStatus status;

  Payment({
    required this.id,
    required this.loanId,
    required this.customerId,
    required this.amount,
    required this.method,
    this.referenceNumber,
    required this.receiptNumber,
    required this.paymentDate,
    required this.collector,
    this.type = PaymentType.partial,
    this.status = PaymentStatus.completed,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'loan_id': loanId,
        'customer_id': customerId,
        'amount': amount,
        'payment_date': AppDateUtils.formatForStorage(paymentDate),
        'payment_method': method.name,
        'reference_no': referenceNumber,
        'receipt_no': receiptNumber,
        'collector': collector,
        'remarks': null,
        'status': status.name,
      };

  factory Payment.fromMap(Map<String, Object?> map) => Payment(
        id: map['id'] as String,
        loanId: map['loan_id'] as String,
        customerId: map['customer_id'] as String,
        amount: (map['amount'] as num).toDouble(),
        paymentDate: AppDateUtils.tryParseStorage(map['payment_date'] as String)!,
        method: PaymentMethod.values.firstWhere(
            (method) => method.name == map['payment_method'],
            orElse: () => PaymentMethod.cash),
        referenceNumber: map['reference_no'] as String?,
        receiptNumber: map['receipt_no'] as String,
        collector: map['collector'] as String,
        type: PaymentType.partial,
        status: PaymentStatus.values.firstWhere(
            (status) => status.name == map['status'],
            orElse: () => PaymentStatus.completed),
      );
}
