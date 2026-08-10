import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/collection/data/models/weekly_collection_row.dart';
import 'package:loantrack/features/reports/services/export_manager.dart';

void main() {
  WeeklyCollectionRow row({
    String name = 'Ada',
    String phone = '0801',
    String guarantorName = 'Grace',
    String guarantorPhone = '0802',
    String paymentAnchorDate = '2026-08-05', // Wednesday
    String loanDate = '2026-08-01',
    double disbursed = 100000,
    double weekly = 10000,
    double total = 120000,
    double paid = 0,
    int installmentNumber = 1,
    String installmentDueDate = '2026-08-07',
    double installmentAmount = 10000,
    double installmentPaid = 0,
    String installmentStatus = 'pending',
    int daysOverdue = 0,
    double collectedThisPeriod = 0,
    double overdueAmount = 0,
    double savings = 0,
  }) {
    return WeeklyCollectionRow(
      customerId: 'c-$name',
      customerName: name,
      phone: phone,
      guarantorName: guarantorName,
      guarantorPhone: guarantorPhone,
      loanId: 'l-$name',
      loanType: 'weekly',
      amountDisbursed: disbursed,
      interestAmount: total - disbursed,
      expectedAmount: total,
      weeklyInstallment: weekly,
      amountPaid: paid,
      outstandingBalance: total - paid,
      installmentDue: weekly,
      loanDate: loanDate,
      paymentAnchorDate: paymentAnchorDate,
      status: 'active',
      currentInstallmentNumber: installmentNumber,
      currentInstallmentDueDate: installmentDueDate,
      currentInstallmentAmount: installmentAmount,
      currentInstallmentPaidAmount: installmentPaid,
      currentInstallmentStatus: installmentStatus,
      daysOverdue: daysOverdue,
      collectedThisPeriod: collectedThisPeriod,
      overdueAmount: overdueAmount,
      savingsBalance: savings,
    );
  }

  String cellText(Sheet sheet, int c, int r) =>
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
          .value
          ?.toString() ??
      '';

  // Layout: 0=title, 1=date, 2=headers, 3=blank, 4=first data row.
  // The blank at 3 comes from the header styling loop touching a row past the
  // appended header row (appendRow of an empty list is a no-op on maxRows).
  int headerRow = 2;
  int dataRow(int index) => 4 + index; // data starts at row 4

  Sheet buildSheet(List<WeeklyCollectionRow> rows) {
    final bytes = ExportManager.buildWeeklyCollectionExcelBytes(rows, DateTime(2026, 8, 7));
    final decoded = Excel.decodeBytes(bytes);
    return decoded.tables[decoded.tables.keys.first]!;
  }

  group('weekly collection export', () {
    test('headers match the requested collection sheet layout', () {
      final sheet = buildSheet([row()]);

      expect(cellText(sheet, 0, headerRow), 'Customer');
      expect(cellText(sheet, 1, headerRow), 'Phone');
      expect(cellText(sheet, 2, headerRow), 'Guarantor');
      expect(cellText(sheet, 3, headerRow), 'Guarantor Phone');
      expect(cellText(sheet, 4, headerRow), 'Disbursement Date');
      expect(cellText(sheet, 5, headerRow), 'Amount Disbursed');
      expect(cellText(sheet, 6, headerRow), 'Expected Amount');
      expect(cellText(sheet, 7, headerRow), 'Amount Paid');
      expect(cellText(sheet, 8, headerRow), 'Overdue');
      expect(cellText(sheet, 9, headerRow), 'Savings');
      expect(cellText(sheet, 10, headerRow), 'Remaining Balance');
      expect(cellText(sheet, 11, headerRow), ''); // no 12th column
    });

    test('date line shows the weekday name, not a relative label', () {
      // 2026-08-07 is a Friday.
      final bytes = ExportManager.buildWeeklyCollectionExcelBytes(
          [row()], DateTime(2026, 8, 7));
      final decoded = Excel.decodeBytes(bytes);
      final sheet = decoded.tables[decoded.tables.keys.first]!;
      expect(cellText(sheet, 0, 1), 'Date: 07 Aug 2026 — Friday');
    });

    test('expected is the weekly installment, amount paid is blank until paid',
        () {
      final sheet = buildSheet([
        row(
          name: 'Ada',
          phone: '080111',
          guarantorName: 'Grace',
          guarantorPhone: '080222',
          paymentAnchorDate: '2026-08-05',
          loanDate: '2026-08-01',
          disbursed: 100000,
          weekly: 10000,
          total: 120000,
          paid: 0, // nothing collected yet
          installmentNumber: 1,
          installmentDueDate: '2026-08-07',
          installmentAmount: 10000,
          installmentPaid: 0,
          installmentStatus: 'pending',
          daysOverdue: 0,
          collectedThisPeriod: 0,
          savings: 25000,
        ),
      ]);

      final r = dataRow(0);
      expect(cellText(sheet, 0, r), 'Ada');
      expect(cellText(sheet, 1, r), '080111');
      expect(cellText(sheet, 2, r), 'Grace');
      expect(cellText(sheet, 3, r), '080222');
      // Disbursement date is one week before the repayment anchor (08-05 − 7).
      expect(cellText(sheet, 4, r), '2026-07-29');
      expect(cellText(sheet, 5, r), '100000.00');
      expect(cellText(sheet, 6, r), '10000.00'); // weekly installment
      expect(cellText(sheet, 7, r), ''); // Amount Paid blank, not 0.00
      expect(cellText(sheet, 8, r), ''); // Overdue blank, not 0.00
      expect(cellText(sheet, 9, r), '25000.00'); // Savings
      expect(cellText(sheet, 10, r), '120000.00'); // total remaining
    });

    test('amount paid reflects the weekly amount once the customer pays this period',
        () {
      final sheet = buildSheet([
        row(
          name: 'Ada',
          disbursed: 100000,
          weekly: 10000,
          total: 120000,
          paid: 10000,
          installmentNumber: 1,
          installmentDueDate: '2026-08-07',
          installmentAmount: 10000,
          installmentPaid: 10000,
          installmentStatus: 'paid',
          daysOverdue: 0,
          collectedThisPeriod: 10000,
          savings: 25000,
        ),
      ]);

      final r = dataRow(0);
      expect(cellText(sheet, 6, r), '10000.00'); // Expected
      expect(cellText(sheet, 7, r), '10000.00'); // Amount Paid
      expect(cellText(sheet, 8, r), ''); // Overdue blank
      expect(cellText(sheet, 9, r), '25000.00'); // Savings
      expect(cellText(sheet, 10, r), '110000.00');
    });

    test('partial payment shows the amount paid and keeps remaining', () {
      final sheet = buildSheet([
        row(
          name: 'Ada',
          disbursed: 100000,
          weekly: 10000,
          total: 120000,
          paid: 5000,
          installmentNumber: 1,
          installmentDueDate: '2026-08-07',
          installmentAmount: 10000,
          installmentPaid: 5000,
          installmentStatus: 'partial',
          daysOverdue: 0,
          collectedThisPeriod: 5000,
        ),
      ]);

      final r = dataRow(0);
      expect(cellText(sheet, 6, r), '10000.00');
      expect(cellText(sheet, 7, r), '5000.00'); // Amount Paid
      expect(cellText(sheet, 9, r), '0.00'); // Savings
      expect(cellText(sheet, 10, r), '115000.00');
    });

    test('overdue accumulation shows in the Overdue column', () {
      final sheet = buildSheet([
        row(
          name: 'Ada',
          paid: 10000,
          installmentStatus: 'pending',
          daysOverdue: 5,
          overdueAmount: 30000,
        ),
      ]);

      final r = dataRow(0);
      expect(cellText(sheet, 8, r), '30000.00');
      expect(cellText(sheet, 7, r), ''); // nothing paid this period
    });

    test('remaining balance is never negative', () {
      final sheet = buildSheet([
        row(name: 'Overpaid', total: 120000, paid: 130000),
      ]);

      // remaining = max(0, 120000 − 130000) = 0
      expect(cellText(sheet, 10, dataRow(0)), '0.00');
    });

    test('overdue, savings, and remaining totals accumulate across rows', () {
      final sheet = buildSheet([
        row(
          name: 'Ada',
          disbursed: 100000,
          weekly: 10000,
          total: 120000,
          paid: 10000,
          collectedThisPeriod: 10000,
          installmentStatus: 'paid',
          overdueAmount: 5000,
          savings: 20000,
        ),
        row(
          name: 'Bola',
          disbursed: 50000,
          weekly: 5000,
          total: 60000,
          paid: 0,
          installmentStatus: 'pending',
          overdueAmount: 10000,
          savings: 30000,
        ),
      ]);

      final totalRow = dataRow(2); // totals row follows the last data row directly
      expect(cellText(sheet, 5, totalRow), '150000.00'); // disbursed
      expect(cellText(sheet, 6, totalRow), '15000.00'); // expected
      expect(cellText(sheet, 7, totalRow), '10000.00'); // amount paid
      expect(cellText(sheet, 8, totalRow), '15000.00'); // overdue
      expect(cellText(sheet, 9, totalRow), '50000.00'); // savings
      expect(cellText(sheet, 10, totalRow), '170000.00'); // remaining
    });

    test('empty list still produces a valid workbook with totals', () {
      final bytes = ExportManager.buildWeeklyCollectionExcelBytes(const [], DateTime(2026, 8, 7));
      final decoded = Excel.decodeBytes(bytes);
      final sheet = decoded.tables[decoded.tables.keys.first]!;

      expect(cellText(sheet, 0, headerRow), 'Customer');
      expect(cellText(sheet, 0, headerRow + 2), 'TOTAL'); // empty row + totals row
      expect(cellText(sheet, 5, headerRow + 2), '0.00'); // disbursed total
      expect(cellText(sheet, 7, headerRow + 2), ''); // amount paid total blank when nothing paid
      expect(cellText(sheet, 8, headerRow + 2), ''); // overdue total blank
      expect(cellText(sheet, 9, headerRow + 2), '0.00'); // savings total
    });
  });
}
