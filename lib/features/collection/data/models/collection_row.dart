class CollectionRow {
  CollectionRow({
    required this.customerId,
    required this.customerName,
    required this.phone,
    required this.loanId,
    required this.loanType,
    required this.amountDue,
    required this.amountPaid,
    required this.installmentAmount,
    required this.outstandingBalance,
    required this.status,
    required this.scheduleStatus,
    this.groupName,
    this.remarks,
    this.dueDate,
    this.overdueAmount = 0,
  });

  final String customerId;
  final String customerName;
  final String phone;
  final String loanId;
  final String loanType;
  /// Display amount: custom collection amount or schedule amount.
  final double amountDue;
  final double amountPaid;
  /// The calculated installment amount from the schedule (used for payment logic).
  final double installmentAmount;
  final double outstandingBalance;
  final String status;
  final String scheduleStatus;
  final String? groupName;
  final String? remarks;
  final String? dueDate;
  /// Total accumulation of the customer's overdue — the sum of every past
  /// unpaid installment on this loan (money rule: `rs.amount - paid_amount`).
  /// 0 when nothing is overdue.
  final double overdueAmount;

  bool get isPaid => scheduleStatus == 'paid';
  bool get isPartial => scheduleStatus == 'partial';
  bool get isPending => scheduleStatus == 'pending';

  /// Whether the loan has any unpaid installment due before today.
  bool get isOverdue => overdueAmount > 0;
}
