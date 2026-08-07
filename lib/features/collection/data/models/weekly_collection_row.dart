/// One row of the Weekly Collection list — a single active weekly loan with
/// its repayment position. Amounts are always derived from the loan's own
/// stored terms and the linked completed payments (the money rule), never
/// from a cached total, so the exported figures stay accurate.
class WeeklyCollectionRow {
  WeeklyCollectionRow({
    required this.customerId,
    required this.customerName,
    required this.phone,
    required this.guarantorName,
    required this.guarantorPhone,
    required this.loanId,
    required this.loanType,
    required this.amountDisbursed,
    required this.interestAmount,
    required this.expectedAmount,
    required this.weeklyInstallment,
    required this.amountPaid,
    required this.outstandingBalance,
    required this.installmentDue,
    required this.loanDate,
    required this.paymentAnchorDate,
    required this.status,
    required this.currentInstallmentNumber,
    required this.currentInstallmentDueDate,
    required this.currentInstallmentAmount,
    required this.currentInstallmentPaidAmount,
    required this.currentInstallmentStatus,
    required this.daysOverdue,
    required this.collectedThisPeriod,
  });

  final String customerId;
  final String customerName;
  final String phone;
  final String guarantorName;
  final String guarantorPhone;
  final String loanId;
  final String loanType;
  /// Principal disbursed (Principal only).
  final double amountDisbursed;
  /// Total interest charged on the loan.
  final double interestAmount;
  /// Principal + interest + any applicable charges (the stored
  /// `loans.total_repayment`).
  final double expectedAmount;
  /// The fixed amount collected from this customer every week (their per-week
  /// installment). For a ₦100,000 loan over 12 weeks at 20% this is ₦10,000.
  final double weeklyInstallment;
  /// Total loan-applied repayments (completed payments minus overpayments
  /// credited to savings).
  final double amountPaid;
  final double outstandingBalance;
  /// Remaining amount of the next unpaid installment (used to cap quick-pay
  /// so excess flows to savings).
  final double installmentDue;
  /// Disbursement date — the date the loan was issued (`yyyy-MM-dd`).
  final String loanDate;
  /// The weekly repayment anchor (`loans.start_date`, `yyyy-MM-dd`) — its
  /// weekday is the customer's recurring payment day.
  final String paymentAnchorDate;
  final String status;
  /// The installment number of the current due installment.
  final int currentInstallmentNumber;
  /// The due date of the current installment (`yyyy-MM-dd`).
  final String currentInstallmentDueDate;
  /// The scheduled amount for the current installment.
  final double currentInstallmentAmount;
  /// The amount already paid towards the current installment.
  final double currentInstallmentPaidAmount;
  /// Status of the current installment: 'pending', 'partial', 'paid', 'overdue'.
  final String currentInstallmentStatus;
  /// Days overdue for the current installment (0 if not overdue).
  final int daysOverdue;
  /// Amount collected for the current collection period (this week's installment).
  /// Empty/0 when no payment has been made for this installment yet.
  final double collectedThisPeriod;

  /// Total expected (principal + interest + charges) − Amount Paid, never
  /// negative.
  double get remainingBalance =>
      (expectedAmount - amountPaid).clamp(0.0, double.infinity);

  /// The recurring payment day ("Monday".."Sunday") derived from the weekly
  /// anchor date's weekday — weekly installments are anchored to the
  /// `start_date` weekday and resume it after a weekend/holiday shift.
  /// Returns an empty string when the date is unparseable.
  String get paymentDay {
    final date = DateTime.tryParse(paymentAnchorDate);
    if (date == null) return '';
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[date.weekday - 1];
  }

  /// Numeric sort key for the recurring payment day: 1 = Monday .. 7 = Sunday,
  /// so a list ordered by this value groups every customer by repayment day
  /// starting from Monday. Unparseable anchor dates sort last (8).
  int get paymentDaySortValue {
    final date = DateTime.tryParse(paymentAnchorDate);
    if (date == null) return 8;
    return date.weekday;
  }

  /// Whether the current installment is overdue.
  bool get isOverdue => daysOverdue > 0;

  /// Whether the current installment is fully paid.
  bool get isCurrentInstallmentPaid => currentInstallmentStatus == 'paid';

  /// Whether the current installment is partially paid.
  bool get isCurrentInstallmentPartial => currentInstallmentStatus == 'partial';

  /// Whether the current installment is pending (not paid, not overdue).
  bool get isCurrentInstallmentPending => currentInstallmentStatus == 'pending';

  /// Remaining amount for the current installment.
  double get currentInstallmentRemaining =>
      (currentInstallmentAmount - currentInstallmentPaidAmount).clamp(0.0, double.infinity);
}
