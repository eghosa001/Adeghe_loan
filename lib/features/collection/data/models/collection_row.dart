class CollectionRow {
  CollectionRow({
    required this.customerName,
    required this.phone,
    required this.loanId,
    required this.loanType,
    required this.amountDue,
    required this.amountPaid,
    required this.outstandingBalance,
    required this.status,
    required this.scheduleStatus,
    this.groupName,
    this.remarks,
  });

  final String customerName;
  final String phone;
  final String loanId;
  final String loanType;
  final double amountDue;
  final double amountPaid;
  final double outstandingBalance;
  final String status;
  /// Status from repayment_schedule: 'pending', 'paid', or 'partial'
  final String scheduleStatus;
  final String? groupName;
  final String? remarks;

  bool get isPaid => scheduleStatus == 'paid';
  bool get isPartial => scheduleStatus == 'partial';
  bool get isPending => scheduleStatus == 'pending';
}
