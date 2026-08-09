import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/collection/data/models/weekly_collection_row.dart';

void main() {
  WeeklyCollectionRow row({
    String paymentAnchorDate = '2026-08-05',
    String loanDate = '2026-08-01',
    String currentInstallmentStatus = 'pending',
    int daysOverdue = 0,
    double overdueAmount = 0,
  }) {
    return WeeklyCollectionRow(
      customerId: 'c1',
      customerName: 'Ada',
      phone: '0801',
      guarantorName: 'Grace',
      guarantorPhone: '0802',
      loanId: 'l1',
      loanType: 'weekly',
      amountDisbursed: 2000,
      interestAmount: 200,
      expectedAmount: 2200,
      weeklyInstallment: 550,
      amountPaid: 0,
      outstandingBalance: 2200,
      installmentDue: 550,
      loanDate: loanDate,
      paymentAnchorDate: paymentAnchorDate,
      status: 'active',
      currentInstallmentNumber: 1,
      currentInstallmentDueDate: '2026-08-05',
      currentInstallmentAmount: 550,
      currentInstallmentPaidAmount: 0,
      currentInstallmentStatus: currentInstallmentStatus,
      daysOverdue: daysOverdue,
      collectedThisPeriod: 0,
      overdueAmount: overdueAmount,
    );
  }

  group('weekly collection row getters', () {
    test('disbursementDate is exactly one week before the repayment anchor', () {
      expect(row(paymentAnchorDate: '2026-08-05').disbursementDate, '2026-07-29');
      expect(
        row(paymentAnchorDate: '2026-01-01').disbursementDate,
        '2025-12-25',
      );
      // Anchor across the year boundary keeps the offset.
      expect(
        row(paymentAnchorDate: '2026-01-05').disbursementDate,
        '2025-12-29',
      );
    });

    test('disbursementDate falls back to loanDate when the anchor is unparseable',
        () {
      final r = row(paymentAnchorDate: 'not-a-date', loanDate: '2026-08-01');
      expect(r.disbursementDate, '2026-08-01');
    });

    test('statusLabel: paid when the current installment is fully paid', () {
      expect(
        row(currentInstallmentStatus: 'paid', daysOverdue: 0).statusLabel,
        'Paid',
      );
    });

    test('statusLabel: overdue when owing from a previous date', () {
      expect(
        row(currentInstallmentStatus: 'pending', daysOverdue: 3).statusLabel,
        'Overdue',
      );
      // An overdue partial payment is still overdue.
      expect(
        row(currentInstallmentStatus: 'partial', daysOverdue: 2).statusLabel,
        'Overdue',
      );
    });

    test('statusLabel: pending when not yet paid and not overdue', () {
      expect(
        row(currentInstallmentStatus: 'pending', daysOverdue: 0).statusLabel,
        'Pending',
      );
      expect(
        row(currentInstallmentStatus: 'partial', daysOverdue: 0).statusLabel,
        'Pending',
      );
    });
  });
}
