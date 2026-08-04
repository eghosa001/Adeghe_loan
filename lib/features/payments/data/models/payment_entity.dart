import 'package:loantrack/core/utils/date_utils.dart';

enum PaymentMethod { cash, transfer, pos, cheque, mobileMoney, savings }

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
  final String? remarks;

  /// The loan status before this payment was applied. Used by reversal to
  /// restore the loan's exact prior state (e.g. a 'defaulted' loan must not
  /// come back as 'active').
  final String? priorLoanStatus;

  /// Client-supplied idempotency key. A retry of the same logical payment
  /// (e.g. a double-tap that calls `createPayment` twice) reuses the same key,
  /// so the second call returns the already-recorded payment instead of
  /// creating a duplicate. Null for legacy/records written without one.
  final String? clientRequestId;

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
    this.remarks,
    this.priorLoanStatus,
    this.clientRequestId,
  });

  Payment copyWith({
    String? remarks,
    bool clearRemarks = false,
  }) {
    return Payment(
      id: id,
      loanId: loanId,
      customerId: customerId,
      amount: amount,
      method: method,
      referenceNumber: referenceNumber,
      receiptNumber: receiptNumber,
      paymentDate: paymentDate,
      collector: collector,
      type: type,
      status: status,
      remarks: clearRemarks ? null : (remarks ?? this.remarks),
      priorLoanStatus: priorLoanStatus,
      clientRequestId: clientRequestId,
    );
  }

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
        'type': type.name,
        'remarks': remarks,
        'status': status.name,
        'prior_loan_status': priorLoanStatus,
        'client_request_id': clientRequestId,
      };

  factory Payment.fromMap(Map<String, Object?> map) => Payment(
        id: map['id'] as String,
        loanId: map['loan_id'] as String,
        customerId: map['customer_id'] as String,
        amount: (map['amount'] as num).toDouble(),
        paymentDate:
            AppDateUtils.tryParseStorage(map['payment_date'] as String?) ??
                DateTime.now(),
        method: PaymentMethod.values.firstWhere(
            (method) => method.name == map['payment_method'],
            orElse: () => PaymentMethod.cash),
        referenceNumber: map['reference_no'] as String?,
        receiptNumber: map['receipt_no'] as String,
        collector: map['collector'] as String,
        type: PaymentType.values.firstWhere(
            (t) => t.name == map['type'],
            orElse: () => PaymentType.partial),
        status: PaymentStatus.values.firstWhere(
            (status) => status.name == map['status'],
            orElse: () => PaymentStatus.completed),
        remarks: map['remarks'] as String?,
        priorLoanStatus: map['prior_loan_status'] as String?,
        clientRequestId: map['client_request_id'] as String?,
      );
}
