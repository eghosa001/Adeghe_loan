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
    required this.overdueAmount,
    required this.savingsBalance,
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
  /// Amount already paid towards the displayed (in-range) week's installment —
  /// the schedule's `paid_amount`, which is money-rule safe (it is recalculated
  /// from completed payments minus overpayment surpluses credited to savings).
  /// The row represents the week the money PAYS FOR, not the week it arrived:
  /// a late payment for an older missed installment shows on that installment's
  /// week. 0 when nothing has been applied to the displayed installment yet.
  final double collectedThisPeriod;
  /// Total accumulation of the customer's overdue — the sum of every past
  /// installment (due before today) that is not fully paid, following the
  /// money rule (`rs.amount - paid_amount`). 0 when nothing is overdue.
  final double overdueAmount;
  /// The customer's live savings account balance (`savings_accounts.balance`).
  final double savingsBalance;

  /// Total expected (principal + interest + charges) − Amount Paid, never
  /// negative.
  double get remainingBalance =>
      (expectedAmount - amountPaid).clamp(0.0, double.infinity);

  /// Disbursement date shown on the collection printout: exactly one week
  /// before the weekly repayment anchor (`start_date`), per the owner rule
  /// (disbursement starts a week before repayment). Falls back to the stored
  /// loan date when the anchor is unparseable.
  String get disbursementDate {
    final anchor = DateTime.tryParse(paymentAnchorDate);
    if (anchor == null) return loanDate;
    final disbursed = anchor.subtract(const Duration(days: 7));
    return '${disbursed.year.toString().padLeft(4, '0')}-'
        '${disbursed.month.toString().padLeft(2, '0')}-'
        '${disbursed.day.toString().padLeft(2, '0')}';
  }

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

  /// Whether the current installment is overdue. A loan is considered overdue
  /// if either the current installment is past due (daysOverdue > 0) OR if
  /// there is any accumulated overdue amount from previous unpaid installments.
  bool get isOverdue => overdueAmount > 0 || daysOverdue > 0;

  /// Whether the current installment is fully paid.
  bool get isCurrentInstallmentPaid => currentInstallmentStatus == 'paid';

  /// Whether the current installment is partially paid.
  bool get isCurrentInstallmentPartial => currentInstallmentStatus == 'partial';

  /// Whether the row reads as "Paid" for the viewed period — the whole loan is
  /// completed, OR the displayed (in-range) installment is fully paid.
  ///
  /// This is week-based, matching the new attribution rule: the row represents
  /// the week the customer pays FOR, so it is paid exactly when that week's
  /// installment is paid. A customer who paid the current week's installment in
  /// an EARLIER period (paid early) has no money arrive in this period, but the
  /// in-range installment is already 'paid' — the row must read "Paid", not
  /// "Pending", or a collector could double-charge (the quick-pay default would
  /// fall through to the whole outstanding balance).
  bool get isPaidForPeriod =>
      status == 'completed' || currentInstallmentStatus == 'paid';
}
