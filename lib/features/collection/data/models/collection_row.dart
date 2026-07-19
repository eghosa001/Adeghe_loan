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
  final String? remarks;
}
