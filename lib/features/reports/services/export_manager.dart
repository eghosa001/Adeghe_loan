import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../collection/data/models/collection_row.dart';
import '../data/models/report_summary.dart';

class ExportManager {
  ExportManager._();

  static Future<File> exportCollectionToExcel(
      List<CollectionRow> rows, DateTime date) async {
    final excel = Excel.createExcel();
    final sheetName = 'Collection ${date.day}-${date.month}-${date.year}';
    final sheet = excel[sheetName];

    final headers = [
      'Customer',
      'Phone',
      'Loan ID',
      'Loan Type',
      'Amount Due',
      'Amount Paid',
      'Outstanding',
      'Status',
    ];
    sheet.appendRow(headers);

    for (final row in rows) {
      sheet.appendRow([
        row.customerName,
        row.phone,
        row.loanId,
        row.loanType,
        row.amountDue.toStringAsFixed(2),
        row.amountPaid.toStringAsFixed(2),
        row.outstandingBalance.toStringAsFixed(2),
        row.status,
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode Excel file');

    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        'collection_${date.toIso8601String().split('T').first.replaceAll('-', '')}.xlsx';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<File> exportReportToCsv(
      ReportSummary summary, String title) async {
    final buffer = StringBuffer();
    buffer.writeln('Metric,Value');
    buffer.writeln(
        'Total Disbursed,${summary.totalDisbursed.toStringAsFixed(2)}');
    buffer.writeln(
        'Total Collected,${summary.totalCollected.toStringAsFixed(2)}');
    buffer.writeln('Net Profit,${summary.netProfit.toStringAsFixed(2)}');
    buffer.writeln('Active Loans,${summary.activeLoans}');
    buffer.writeln('Completed Loans,${summary.completedLoans}');
    buffer.writeln('Defaulted Loans,${summary.defaultedLoans}');

    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        '${title.replaceAll(' ', '_')}_${DateTime.now().toIso8601String().split('T').first.replaceAll('-', '')}.csv';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(buffer.toString(), flush: true);
    return file;
  }

  static Future<File> exportReportToPdf(
      ReportSummary summary, String title) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(text: title),
          pw.SizedBox(height: 20),
          _buildSummaryTable(summary),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        '${title.replaceAll(' ', '_')}_${DateTime.now().toIso8601String().split('T').first.replaceAll('-', '')}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(await pdf.save(), flush: true);
    return file;
  }

  static pw.Widget _buildSummaryTable(ReportSummary summary) {
    return pw.TableHelper.fromTextArray(
      headers: ['Metric', 'Value'],
      data: [
        ['Total Disbursed', summary.totalDisbursed.toStringAsFixed(2)],
        ['Total Collected', summary.totalCollected.toStringAsFixed(2)],
        ['Net Profit', summary.netProfit.toStringAsFixed(2)],
        ['Active Loans', summary.activeLoans.toString()],
        ['Completed Loans', summary.completedLoans.toString()],
        ['Defaulted Loans', summary.defaultedLoans.toString()],
      ],
    );
  }
}
