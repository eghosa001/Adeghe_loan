import 'package:excel/excel.dart';
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
    );
  }

  final bytes = ExportManager.buildWeeklyCollectionExcelBytes([row()], DateTime(2026, 8, 7));
  final decoded = Excel.decodeBytes(bytes);
  final sheet = decoded.tables[decoded.tables.keys.first]!;
  
  print('Max rows: ${sheet.maxRows}');
  for (int r = 0; r <= sheet.maxRows; r++) {
    for (int c = 0; c < 11; c++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
      final val = cell.value?.toString() ?? '';
      if (val.isNotEmpty) {
        print('Row $r, Col $c: "$val"');
      }
    }
  }
}