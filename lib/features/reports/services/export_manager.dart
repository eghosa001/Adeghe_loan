import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/currency_utils.dart';
import '../../../core/utils/date_utils.dart';
import '../../collection/data/models/collection_row.dart';
import '../data/models/report_summary.dart';

class ExportManager {
  ExportManager._();

  static const int _collectionColumnsPerGroup = 3;
  static const int _collectionSeparatorColumns = 1;

  static pw.Font? _font;
  static pw.Font? _fontBold;

  static Future<pw.Font> _getFont() async {
    _font ??= await PdfGoogleFonts.notoSansRegular();
    return _font!;
  }

  static Future<pw.Font> _getFontBold() async {
    _fontBold ??= await PdfGoogleFonts.notoSansBold();
    return _fontBold!;
  }

  static pw.TextStyle _titleStyle(pw.Font bold) => pw.TextStyle(
        font: bold,
        fontSize: 20,
        color: PdfColors.blue900,
      );

  static pw.TextStyle _sectionStyle(pw.Font bold) => pw.TextStyle(
        font: bold,
        fontSize: 13,
        color: PdfColors.blue900,
      );

  static pw.BoxDecoration _headerDecoration() => const pw.BoxDecoration(
        color: PdfColors.blue900,
        borderRadius: pw.BorderRadius.only(
          topLeft: pw.Radius.circular(4),
          topRight: pw.Radius.circular(4),
        ),
      );

  /// Opens the system "Save to..." dialog (Storage Access Framework on
  /// Android) so the PDF lands in user-visible storage (e.g. Documents).
  /// Returns the destination path, or null if the user canceled.
  static Future<String?> _savePdfViaPicker(
      Uint8List bytes, String fileName) {
    return FilePicker.platform.saveFile(
      dialogTitle: 'Save PDF',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      bytes: bytes,
    );
  }

  // ── Collection PDF ──────────────────────────────────────────────────────────

  static Future<Uint8List> _buildCollectionPdfBytes(
    List<CollectionRow> rows,
    DateTime date, {
    String? companyName,
    String? collectorName,
    String currencySymbol = CurrencyUtils.defaultSymbol,
  }) async {
    final font = await _getFont();
    final bold = await _getFontBold();
    final pdf = pw.Document();

    double totalDue = 0;
    for (final r in rows) {
      totalDue += r.amountDue;
    }

    // Group by groupName first
    final Map<String, List<CollectionRow>> groupedRows = {};
    for (final r in rows) {
      final g = (r.groupName != null && r.groupName!.trim().isNotEmpty)
          ? r.groupName!.trim()
          : 'Ungrouped';
      groupedRows.putIfAbsent(g, () => []).add(r);
    }

    final sortedGroups = groupedRows.keys.toList()
      ..sort((a, b) {
        if (a == 'Ungrouped') return 1;
        if (b == 'Ungrouped') return -1;
        return a.compareTo(b);
      });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          final widgets = <pw.Widget>[
            pw.Header(
              level: 0,
              child: pw.Text(
                companyName ?? 'Collection Sheet',
                style: _titleStyle(bold),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Date: ${AppDateUtils.formatDate(date)}',
              style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700),
            ),
            if (collectorName != null && collectorName.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                'Collector: $collectorName',
                style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700),
              ),
            ],
            pw.SizedBox(height: 2),
            pw.Text(
              'Total Customers: ${rows.length}   |   Total to Collect: ${CurrencyUtils.format(totalDue, symbol: currencySymbol)}',
              style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 16),
          ];

          for (final groupName in sortedGroups) {
            final groupRows = groupedRows[groupName]!;
            widgets.add(
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                child: pw.Text('Group: $groupName', style: _sectionStyle(bold)),
              ),
            );
            widgets.add(pw.SizedBox(height: 8));

            final dailyGroupRows = groupRows
                .where((r) => r.loanType.toLowerCase() == 'daily')
                .toList();
            final weeklyGroupRows = groupRows
                .where((r) => r.loanType.toLowerCase() == 'weekly')
                .toList();

            if (dailyGroupRows.isNotEmpty) {
              widgets.add(
                pw.Text('Daily Loans',
                    style: pw.TextStyle(
                        font: bold, fontSize: 11, color: PdfColors.blue800)),
              );
              widgets.add(pw.SizedBox(height: 4));
              widgets.add(_buildCollectionTableForPrint(dailyGroupRows, font, bold, currencySymbol));
              widgets.add(pw.SizedBox(height: 10));
            }

            if (weeklyGroupRows.isNotEmpty) {
              widgets.add(
                pw.Text('Weekly Loans',
                    style: pw.TextStyle(
                        font: bold, fontSize: 11, color: PdfColors.blue800)),
              );
              widgets.add(pw.SizedBox(height: 4));
              widgets.add(_buildCollectionTableForPrint(weeklyGroupRows, font, bold, currencySymbol));
              widgets.add(pw.SizedBox(height: 10));
            }

            widgets.add(pw.SizedBox(height: 10));
          }

          return widgets;
        },
      ),
    );

    return pdf.save();
  }

  static Future<File> exportCollectionToPdf(
    List<CollectionRow> rows,
    DateTime date, {
    String? companyName,
    String? collectorName,
    String currencySymbol = CurrencyUtils.defaultSymbol,
  }) async {
    final bytes = await _buildCollectionPdfBytes(rows, date,
        companyName: companyName,
        collectorName: collectorName,
        currencySymbol: currencySymbol);
    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        'collection_${date.toIso8601String().split('T').first.replaceAll('-', '')}_${_uniqueStamp()}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static String _uniqueStamp() {
    final now = DateTime.now();
    final d = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final t = '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}_'
        '${now.microsecond.toString().padLeft(6, '0')}';
    return '${d}_$t';
  }

  static String _reportPdfFileName(String title) =>
      '${title.replaceAll(' ', '_')}_${_uniqueStamp()}.pdf';

  static Future<File> exportReportToPdf(
      ReportSummary summary, String title,
      {String currencySymbol = CurrencyUtils.defaultSymbol}) async {
    final bytes = await _buildReportPdfBytes(summary, title,
        currencySymbol: currencySymbol);
    final dir = await getApplicationDocumentsDirectory();
    final fileName = _reportPdfFileName(title);
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<String?> saveReportPdf(
      ReportSummary summary, String title,
      {String currencySymbol = CurrencyUtils.defaultSymbol}) async {
    final bytes = await _buildReportPdfBytes(summary, title,
        currencySymbol: currencySymbol);
    return _savePdfViaPicker(bytes, _reportPdfFileName(title));
  }

  static Future<String?> saveCollectionPdf(
    List<CollectionRow> rows,
    DateTime date, {
    String? companyName,
    String? collectorName,
    String currencySymbol = CurrencyUtils.defaultSymbol,
  }) async {
    final bytes = await _buildCollectionPdfBytes(rows, date,
        companyName: companyName,
        collectorName: collectorName,
        currencySymbol: currencySymbol);
    final fileName =
        'collection_${date.toIso8601String().split('T').first.replaceAll('-', '')}_${_uniqueStamp()}.pdf';
    return _savePdfViaPicker(bytes, fileName);
  }

  static pw.Widget _buildCollectionTableForPrint(
      List<CollectionRow> rows,
      pw.Font font,
      pw.Font bold,
      String currencySymbol) {
    final headers = [
      'Customer Name',
      'Amount To Collect',
      'Paid',
    ];

    final data = rows
        .map((r) => [
              r.customerName,
              CurrencyUtils.format(r.amountDue, symbol: currencySymbol),
              '', // Blank for collector to write
            ])
        .toList();

    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.white),
      headerDecoration: _headerDecoration(),
      headerAlignment: pw.Alignment.centerLeft,
      cellStyle: pw.TextStyle(font: font, fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
      cellHeight: 32,
      cellAlignments: const {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.center,
      },
      headers: headers,
      data: data,
    );
  }

  static Future<void> shareCollectionPdf(
      List<CollectionRow> rows, DateTime date,
      {String? companyName,
      String? collectorName,
      String currencySymbol = CurrencyUtils.defaultSymbol}) async {
    final file = await exportCollectionToPdf(rows, date,
        companyName: companyName,
        collectorName: collectorName,
        currencySymbol: currencySymbol);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Collection ${AppDateUtils.formatDate(date)}',
      ),
    );
  }

  static Future<void> shareCollectionExcel(
      List<CollectionRow> rows, DateTime date) async {
    final file = await exportCollectionToExcel(rows, date);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        subject: 'Collection ${AppDateUtils.formatDate(date)}',
      ),
    );
  }

  // ── Collection Excel ────────────────────────────────────────────────────────

  static Future<File> exportCollectionToExcel(
      List<CollectionRow> rows, DateTime date) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();

    final Map<String, List<CollectionRow>> groupedRows = {};
    for (final r in rows) {
      final g = (r.groupName != null && r.groupName!.trim().isNotEmpty)
          ? r.groupName!.trim()
          : 'Ungrouped';
      groupedRows.putIfAbsent(g, () => []).add(r);
    }

    final sortedGroups = groupedRows.keys.toList()
      ..sort((a, b) {
        if (a == 'Ungrouped') return 1;
        if (b == 'Ungrouped') return -1;
        return a.compareTo(b);
      });

    bool isFirst = true;
    int sheetIndex = 0;

    for (var i = 0; i < sortedGroups.length; i += 2) {
      final nameA = sortedGroups[i];
      final groupA = groupedRows[nameA]!;
      final nameB = (i + 1 < sortedGroups.length) ? sortedGroups[i + 1] : null;
      final groupB = nameB != null ? groupedRows[nameB]! : null;

      final String sheetName;
      if (isFirst) {
        sheetName = defaultSheet ?? nameA;
        isFirst = false;
      } else {
        sheetName = 'Sheet_$sheetIndex';
        sheetIndex++;
      }

      final sheet = excel[sheetName];
      _populateSideBySideCollectionSheet(sheet, groupA, nameA, groupB, nameB);
    }

    final List<int>? bytes;
    try {
      bytes = excel.encode();
    } catch (e) {
      throw Exception('Failed to encode Excel file: $e');
    }
    if (bytes == null) throw Exception('Failed to encode Excel file: encode returned null');

    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        'collection_${date.toIso8601String().split('T').first.replaceAll('-', '')}_${_uniqueStamp()}.xlsx';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<File> exportOverdueToPdf(
    List<OverdueEntry> entries,
    String title, {
    String currencySymbol = CurrencyUtils.defaultSymbol,
  }) async {
    final bytes = await _buildOverduePdfBytes(entries, title,
        currencySymbol: currencySymbol);
    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        '${title.replaceAll(' ', '_')}_${_uniqueStamp()}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<String?> saveOverduePdf(
    List<OverdueEntry> entries,
    String title, {
    String currencySymbol = CurrencyUtils.defaultSymbol,
  }) async {
    final bytes = await _buildOverduePdfBytes(entries, title,
        currencySymbol: currencySymbol);
    final fileName =
        '${title.replaceAll(' ', '_')}_${_uniqueStamp()}.pdf';
    return _savePdfViaPicker(bytes, fileName);
  }

  static List<CollectionRow> _sortedCollectionRows(List<CollectionRow> rows) {
    final daily = rows
        .where((r) => r.loanType.toLowerCase() == 'daily')
        .toList()
      ..sort((a, b) => a.customerName.compareTo(b.customerName));
    final weekly = rows
        .where((r) => r.loanType.toLowerCase() == 'weekly')
        .toList()
      ..sort((a, b) => a.customerName.compareTo(b.customerName));
    return [...daily, ...weekly];
  }

  /// Builds a list of rows for a single group.
  /// Each row has exactly 3 entries (Name, Amount, Paid).
  /// Section headers only populate the first entry; others are null.
  static List<List<String?>> _buildCollectionRows(List<CollectionRow> rows) {
    final result = <List<String?>>[];

    final dailyRows =
        rows.where((r) => r.loanType.toLowerCase() == 'daily').toList();
    if (dailyRows.isNotEmpty) {
      result.add(['DAILY LOANS', null, null]);
      result.add(['Name', 'Amount', 'Paid']);
      for (final r in dailyRows) {
        result.add([r.customerName, r.amountDue.toStringAsFixed(2), '']);
      }
    }

    final weeklyRows =
        rows.where((r) => r.loanType.toLowerCase() == 'weekly').toList();
    if (weeklyRows.isNotEmpty) {
      if (dailyRows.isNotEmpty) {
        result.add(['', null, null]);
      }
      result.add(['WEEKLY LOANS', null, null]);
      result.add(['Name', 'Amount', 'Paid']);
      for (final r in weeklyRows) {
        result.add([r.customerName, r.amountDue.toStringAsFixed(2), '']);
      }
    }

    return result;
  }

  static void _populateSideBySideCollectionSheet(
    Sheet sheet,
    List<CollectionRow> groupA,
    String groupAName,
    List<CollectionRow>? groupB,
    String? groupBName,
  ) {
    final sortedA = _sortedCollectionRows(groupA);
    final sortedB = groupB != null ? _sortedCollectionRows(groupB) : null;

    const aCol = 0;
    const bCol = _collectionColumnsPerGroup + _collectionSeparatorColumns;
    const totalCols = bCol + _collectionColumnsPerGroup;

    final rowsA = _buildCollectionRows(sortedA);
    final rowsB = sortedB != null ? _buildCollectionRows(sortedB) : <List<String?>>[];

    final maxDataRows = rowsA.length > rowsB.length ? rowsA.length : rowsB.length;
    final totalRows = 1 + maxDataRows;

    // Pre-create all rows with appendRow to initialize internal structure reliably
    for (var i = 0; i < totalRows; i++) {
      sheet.appendRow(List<dynamic>.filled(totalCols, ''));
    }

    // Write group headers (row 0)
    _writeCellValue(sheet, 0, aCol, groupAName);
    if (groupBName != null) {
      _writeCellValue(sheet, 0, bCol, groupBName);
    }

    // Write sub-table data rows
    for (var i = 0; i < maxDataRows; i++) {
      if (i < rowsA.length) {
        for (var j = 0; j < rowsA[i].length && j < _collectionColumnsPerGroup; j++) {
          if (rowsA[i][j] != null) {
            _writeCellValue(sheet, 1 + i, aCol + j, rowsA[i][j]!);
          }
        }
      }
      if (i < rowsB.length) {
        for (var j = 0; j < rowsB[i].length && j < _collectionColumnsPerGroup; j++) {
          if (rowsB[i][j] != null) {
            _writeCellValue(sheet, 1 + i, bCol + j, rowsB[i][j]!);
          }
        }
      }
    }

    // Apply styles to all cells in the sheet
    for (var r = 0; r < totalRows; r++) {
      for (var c = aCol; c < totalCols; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(
          columnIndex: c,
          rowIndex: r,
        ));
        cell.cellStyle = CellStyle(
          bold: _isBoldCell(r, c, aCol, bCol, rowsA, rowsB),
          horizontalAlign: _horizontalAlignForCell(r, c, aCol, bCol),
          bottomBorder: Border(borderStyle: BorderStyle.Thin),
          topBorder: Border(borderStyle: BorderStyle.Thin),
          leftBorder: Border(borderStyle: BorderStyle.Thin),
          rightBorder: Border(borderStyle: BorderStyle.Thin),
        );
      }
    }

    // Set column widths
    for (var c = aCol; c < totalCols; c++) {
      var maxWidth = 0;
      for (var r = 0; r < totalRows; r++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(
          columnIndex: c,
          rowIndex: r,
        ));
        final text = cell.value?.toString() ?? '';
        if (text.length > maxWidth) maxWidth = text.length;
      }
      sheet.setColWidth(c, (maxWidth + 3).toDouble());
    }
  }

  static bool _isBoldCell(
    int row,
    int col,
    int aCol,
    int bCol,
    List<List<String?>> rowsA,
    List<List<String?>> rowsB,
  ) {
    if (row == 0) return true;
    final dataRow = row - 1;
    if (col >= aCol && col < aCol + _collectionColumnsPerGroup) {
      if (dataRow < rowsA.length && col == aCol) {
        final v = rowsA[dataRow][0];
        if (v == 'DAILY LOANS' || v == 'WEEKLY LOANS' || v == 'Name') return true;
      }
      if (dataRow < rowsA.length) {
        final v = rowsA[dataRow][col - aCol];
        if (v == 'Name' || v == 'Amount' || v == 'Paid') return true;
      }
    }
    if (col >= bCol && col < bCol + _collectionColumnsPerGroup) {
      if (dataRow < rowsB.length && col == bCol) {
        final v = rowsB[dataRow][0];
        if (v == 'DAILY LOANS' || v == 'WEEKLY LOANS' || v == 'Name') return true;
      }
      if (dataRow < rowsB.length) {
        final v = rowsB[dataRow][col - bCol];
        if (v == 'Name' || v == 'Amount' || v == 'Paid') return true;
      }
    }
    return false;
  }

  static HorizontalAlign _horizontalAlignForCell(
    int row,
    int col,
    int aCol,
    int bCol,
  ) {
    if (row == 0) return HorizontalAlign.Center;
    if (col == aCol || col == bCol) return HorizontalAlign.Left;
    if (col == aCol + 1 || col == bCol + 1) return HorizontalAlign.Right;
    if (col == aCol + 2 || col == bCol + 2) return HorizontalAlign.Center;
    return HorizontalAlign.Left;
  }

  static void _writeCellValue(
    Sheet sheet,
    int row,
    int col,
    String value,
  ) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(
      columnIndex: col,
      rowIndex: row,
    ));
    cell.value = value;
  }

  // ── Report PDF ──────────────────────────────────────────────────────

  static Future<Uint8List> _buildReportPdfBytes(
      ReportSummary summary, String title,
      {String currencySymbol = CurrencyUtils.defaultSymbol}) async {
    final font = await _getFont();
    final bold = await _getFontBold();
    final pdf = pw.Document();
    String fmt(num v) => CurrencyUtils.format(v, symbol: currencySymbol);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(title, style: _titleStyle(bold)),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Generated: ${AppDateUtils.formatDateTime(DateTime.now())}',
            style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 20),
          pw.Text('Financial Summary', style: _sectionStyle(bold)),
          pw.SizedBox(height: 8),
          _buildSummaryRow(font, bold, 'Total Disbursed',
              fmt(summary.totalDisbursed)),
          _buildSummaryRow(font, bold, 'Total Collected',
              fmt(summary.totalCollected)),
          _buildSummaryRow(font, bold, 'Net Profit',
              fmt(summary.netProfit)),
          pw.SizedBox(height: 16),
          pw.Text('Loan Status', style: _sectionStyle(bold)),
          pw.SizedBox(height: 8),
          _buildSummaryRow(font, bold, 'Active Loans', '${summary.activeLoans}'),
          _buildSummaryRow(
              font, bold, 'Completed Loans', '${summary.completedLoans}'),
          _buildSummaryRow(
              font, bold, 'Defaulted Loans', '${summary.defaultedLoans}'),
          pw.SizedBox(height: 16),
          pw.Text('Daily Loan Report', style: _sectionStyle(bold)),
          pw.SizedBox(height: 8),
          _buildSummaryRow(font, bold, 'Active', '${summary.dailyLoans.activeLoans}'),
          _buildSummaryRow(font, bold, 'Completed', '${summary.dailyLoans.completedLoans}'),
          _buildSummaryRow(font, bold, 'Overdue', '${summary.dailyLoans.overdueLoans}'),
          _buildSummaryRow(font, bold, 'Disbursed', fmt(summary.dailyLoans.amountDisbursed)),
          _buildSummaryRow(font, bold, 'Collected', fmt(summary.dailyLoans.amountCollected)),
          _buildSummaryRow(font, bold, 'Outstanding', fmt(summary.dailyLoans.outstandingBalance)),
          _buildSummaryRow(font, bold, 'Expected Collections', fmt(summary.dailyLoans.expectedCollections)),
          _buildSummaryRow(font, bold, 'Collection Efficiency', '${summary.dailyLoans.collectionEfficiency.toStringAsFixed(1)}%'),
          _buildSummaryRow(font, bold, 'Interest Earned', fmt(summary.dailyLoans.interestEarned)),
          _buildSummaryRow(font, bold, 'Fees Earned', fmt(summary.dailyLoans.feesEarned)),
          _buildSummaryRow(font, bold, 'Savings from Overpayments', fmt(summary.dailyLoans.savingsFromOverpayments)),
          _buildSummaryRow(font, bold, 'Customers', '${summary.dailyLoans.customerCount}'),
          pw.SizedBox(height: 16),
          pw.Text('Weekly Loan Report', style: _sectionStyle(bold)),
          pw.SizedBox(height: 8),
          _buildSummaryRow(font, bold, 'Active', '${summary.weeklyLoans.activeLoans}'),
          _buildSummaryRow(font, bold, 'Completed', '${summary.weeklyLoans.completedLoans}'),
          _buildSummaryRow(font, bold, 'Overdue', '${summary.weeklyLoans.overdueLoans}'),
          _buildSummaryRow(font, bold, 'Disbursed', fmt(summary.weeklyLoans.amountDisbursed)),
          _buildSummaryRow(font, bold, 'Collected', fmt(summary.weeklyLoans.amountCollected)),
          _buildSummaryRow(font, bold, 'Outstanding', fmt(summary.weeklyLoans.outstandingBalance)),
          _buildSummaryRow(font, bold, 'Expected Collections', fmt(summary.weeklyLoans.expectedCollections)),
          _buildSummaryRow(font, bold, 'Collection Efficiency', '${summary.weeklyLoans.collectionEfficiency.toStringAsFixed(1)}%'),
          _buildSummaryRow(font, bold, 'Interest Earned', fmt(summary.weeklyLoans.interestEarned)),
           _buildSummaryRow(font, bold, 'Fees Earned', fmt(summary.weeklyLoans.feesEarned)),
           _buildSummaryRow(font, bold, 'Savings from Overpayments', fmt(summary.weeklyLoans.savingsFromOverpayments)),
           _buildSummaryRow(font, bold, 'Customers', '${summary.weeklyLoans.customerCount}'),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildSummaryRow(
      pw.Font font, pw.Font bold, String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 10)),
          pw.Text(value,
              style: pw.TextStyle(font: bold, fontSize: 10)),
        ],
      ),
    );
  }

  static Future<void> shareReportPdf(
      ReportSummary summary, String title,
      {String currencySymbol = CurrencyUtils.defaultSymbol}) async {
    final file = await exportReportToPdf(summary, title,
        currencySymbol: currencySymbol);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: title,
      ),
    );
  }

  // ── Overdue Report PDF ───────────────────────────────────────────────────────

  static Future<Uint8List> _buildOverduePdfBytes(
    List<OverdueEntry> entries,
    String title, {
    String currencySymbol = CurrencyUtils.defaultSymbol,
  }) async {
    final font = await _getFont();
    final bold = await _getFontBold();
    final pdf = pw.Document();

    final totalOverdue = entries.fold<double>(0, (s, e) => s + e.amountRemaining);
    final uniqueCustomers = entries.map((e) => e.customerId).toSet().length;
    final avgDays = entries.isEmpty
        ? 0
        : entries.fold<int>(0, (s, e) => s + e.overdueDays) ~/ entries.length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(title, style: _titleStyle(bold)),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Generated: ${AppDateUtils.formatDateTime(DateTime.now())}',
            style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            children: [
              pw.Expanded(child: _buildOverdueSummaryCard(font, bold, 'Total Overdue', CurrencyUtils.format(totalOverdue, symbol: currencySymbol), PdfColors.red)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _buildOverdueSummaryCard(font, bold, 'Installments', '${entries.length}', PdfColors.orange)),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(child: _buildOverdueSummaryCard(font, bold, 'Customers', '$uniqueCustomers', PdfColors.red700)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _buildOverdueSummaryCard(font, bold, 'Avg Days', '$avgDays', PdfColors.orange700)),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text('Overdue Installments',
              style: pw.TextStyle(font: bold, fontSize: 13, color: PdfColors.blue900)),
          pw.SizedBox(height: 8),
          _buildOverdueTable(entries, font, bold, currencySymbol),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildOverdueSummaryCard(
    pw.Font font,
    pw.Font bold,
    String label,
    String value,
    PdfColor color,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(font: font, fontSize: 9, color: color)),
          pw.SizedBox(height: 4),
          pw.Text(value,
              style: pw.TextStyle(
                  font: bold, fontSize: 16, color: color)),
        ],
      ),
    );
  }

  static pw.Widget _buildOverdueTable(
    List<OverdueEntry> entries,
    pw.Font font,
    pw.Font bold,
    String currencySymbol,
  ) {
    final headers = [
      'Customer',
      'Phone',
      'Type',
      'Inst #',
      'Due Date',
      'Days',
      'Amount Due',
      'Paid',
      'Remaining',
      'Group',
    ];

    final data = entries.map((e) => [
          e.customerName,
          e.phone,
          e.loanType,
          '${e.installmentNumber}',
          e.dueDate,
          '${e.overdueDays}',
          CurrencyUtils.format(e.amountDue, symbol: currencySymbol),
          CurrencyUtils.format(e.paidAmount, symbol: currencySymbol),
          CurrencyUtils.format(e.amountRemaining, symbol: currencySymbol),
          e.groupName ?? '',
        ]).toList();

    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(font: bold, fontSize: 7, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.blue900,
        borderRadius: pw.BorderRadius.only(
          topLeft: pw.Radius.circular(4),
          topRight: pw.Radius.circular(4),
        ),
      ),
      cellStyle: pw.TextStyle(font: font, fontSize: 7),
      cellAlignment: pw.Alignment.centerLeft,
      cellHeight: 24,
      cellAlignments: const {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
        5: pw.Alignment.center,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
        8: pw.Alignment.centerRight,
        9: pw.Alignment.centerLeft,
      },
      headers: headers,
      data: data,
    );
  }

  static Future<void> shareOverduePdf(
    List<OverdueEntry> entries,
    String title, {
    String currencySymbol = CurrencyUtils.defaultSymbol,
  }) async {
    final file = await exportOverdueToPdf(entries, title,
        currencySymbol: currencySymbol);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: title,
      ),
    );
  }

  // ── Report CSV ──────────────────────────────────────────────────────────────

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
    buffer.writeln('Daily Loan - Active,${summary.dailyLoans.activeLoans}');
    buffer.writeln('Daily Loan - Completed,${summary.dailyLoans.completedLoans}');
    buffer.writeln('Daily Loan - Overdue,${summary.dailyLoans.overdueLoans}');
    buffer.writeln('Daily Loan - Disbursed,${summary.dailyLoans.amountDisbursed.toStringAsFixed(2)}');
    buffer.writeln('Daily Loan - Collected,${summary.dailyLoans.amountCollected.toStringAsFixed(2)}');
    buffer.writeln('Daily Loan - Outstanding,${summary.dailyLoans.outstandingBalance.toStringAsFixed(2)}');
    buffer.writeln('Daily Loan - Expected Collections,${summary.dailyLoans.expectedCollections.toStringAsFixed(2)}');
    buffer.writeln('Daily Loan - Collection Efficiency,${summary.dailyLoans.collectionEfficiency.toStringAsFixed(1)}%');
    buffer.writeln('Daily Loan - Interest Earned,${summary.dailyLoans.interestEarned.toStringAsFixed(2)}');
    buffer.writeln('Daily Loan - Fees Earned,${summary.dailyLoans.feesEarned.toStringAsFixed(2)}');
    buffer.writeln('Daily Loan - Overpayment Savings,${summary.dailyLoans.savingsFromOverpayments.toStringAsFixed(2)}');
    buffer.writeln('Daily Loan - Customers,${summary.dailyLoans.customerCount}');
    buffer.writeln('Weekly Loan - Active,${summary.weeklyLoans.activeLoans}');
    buffer.writeln('Weekly Loan - Completed,${summary.weeklyLoans.completedLoans}');
    buffer.writeln('Weekly Loan - Overdue,${summary.weeklyLoans.overdueLoans}');
    buffer.writeln('Weekly Loan - Disbursed,${summary.weeklyLoans.amountDisbursed.toStringAsFixed(2)}');
    buffer.writeln('Weekly Loan - Collected,${summary.weeklyLoans.amountCollected.toStringAsFixed(2)}');
    buffer.writeln('Weekly Loan - Outstanding,${summary.weeklyLoans.outstandingBalance.toStringAsFixed(2)}');
    buffer.writeln('Weekly Loan - Expected Collections,${summary.weeklyLoans.expectedCollections.toStringAsFixed(2)}');
    buffer.writeln('Weekly Loan - Collection Efficiency,${summary.weeklyLoans.collectionEfficiency.toStringAsFixed(1)}%');
    buffer.writeln('Weekly Loan - Interest Earned,${summary.weeklyLoans.interestEarned.toStringAsFixed(2)}');
    buffer.writeln('Weekly Loan - Fees Earned,${summary.weeklyLoans.feesEarned.toStringAsFixed(2)}');
    buffer.writeln('Weekly Loan - Overpayment Savings,${summary.weeklyLoans.savingsFromOverpayments.toStringAsFixed(2)}');
    buffer.writeln('Weekly Loan - Customers,${summary.weeklyLoans.customerCount}');

    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        '${title.replaceAll(' ', '_')}_${_uniqueStamp()}.csv';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(buffer.toString(), flush: true);
    return file;
  }

  // ── Report Excel ─────────────────────────────────────────────────────────────

  static Future<File> exportReportToXlsx(
      ReportSummary summary, String title) async {
    final excel = Excel.createExcel();
    final sheet = excel['Report'];

    sheet.appendRow(['Metric', 'Value']);
    sheet.appendRow(['Period', title]);
    sheet.appendRow([]);
    sheet.appendRow(['FINANCIAL SUMMARY']);
    sheet.appendRow(['Total Disbursed', summary.totalDisbursed.toStringAsFixed(2)]);
    sheet.appendRow(['Total Collected', summary.totalCollected.toStringAsFixed(2)]);
    sheet.appendRow(['Net Profit', summary.netProfit.toStringAsFixed(2)]);
    sheet.appendRow(['Expected Collections',
        (summary.dailyLoans.expectedCollections + summary.weeklyLoans.expectedCollections).toStringAsFixed(2)]);
    sheet.appendRow([]);
    sheet.appendRow(['LOAN STATUS']);
    sheet.appendRow(['Active Loans', summary.activeLoans]);
    sheet.appendRow(['Completed Loans', summary.completedLoans]);
    sheet.appendRow(['Defaulted Loans', summary.defaultedLoans]);
    sheet.appendRow([]);
    sheet.appendRow(['DAILY LOANS']);
    sheet.appendRow(['Active', summary.dailyLoans.activeLoans]);
    sheet.appendRow(['Completed', summary.dailyLoans.completedLoans]);
    sheet.appendRow(['Defaulted', summary.dailyLoans.defaultedLoans]);
    sheet.appendRow(['Overdue', summary.dailyLoans.overdueLoans]);
    sheet.appendRow(['Disbursed', summary.dailyLoans.amountDisbursed.toStringAsFixed(2)]);
    sheet.appendRow(['Collected', summary.dailyLoans.amountCollected.toStringAsFixed(2)]);
    sheet.appendRow(['Outstanding', summary.dailyLoans.outstandingBalance.toStringAsFixed(2)]);
    sheet.appendRow(['Expected Collections', summary.dailyLoans.expectedCollections.toStringAsFixed(2)]);
    sheet.appendRow(['Collection Efficiency', '${summary.dailyLoans.collectionEfficiency.toStringAsFixed(1)}%']);
    sheet.appendRow(['Interest Earned', summary.dailyLoans.interestEarned.toStringAsFixed(2)]);
    sheet.appendRow(['Fees Earned', summary.dailyLoans.feesEarned.toStringAsFixed(2)]);
    sheet.appendRow([]);
    sheet.appendRow(['WEEKLY LOANS']);
    sheet.appendRow(['Active', summary.weeklyLoans.activeLoans]);
    sheet.appendRow(['Completed', summary.weeklyLoans.completedLoans]);
    sheet.appendRow(['Defaulted', summary.weeklyLoans.defaultedLoans]);
    sheet.appendRow(['Overdue', summary.weeklyLoans.overdueLoans]);
    sheet.appendRow(['Disbursed', summary.weeklyLoans.amountDisbursed.toStringAsFixed(2)]);
    sheet.appendRow(['Collected', summary.weeklyLoans.amountCollected.toStringAsFixed(2)]);
    sheet.appendRow(['Outstanding', summary.weeklyLoans.outstandingBalance.toStringAsFixed(2)]);
    sheet.appendRow(['Expected Collections', summary.weeklyLoans.expectedCollections.toStringAsFixed(2)]);
    sheet.appendRow(['Collection Efficiency', '${summary.weeklyLoans.collectionEfficiency.toStringAsFixed(1)}%']);
    sheet.appendRow(['Interest Earned', summary.weeklyLoans.interestEarned.toStringAsFixed(2)]);
    sheet.appendRow(['Fees Earned', summary.weeklyLoans.feesEarned.toStringAsFixed(2)]);

    final List<int>? bytes;
    try {
      bytes = excel.encode();
    } catch (e) {
      throw Exception('Failed to encode Excel file: $e');
    }
    if (bytes == null) throw Exception('Failed to encode Excel file: encode returned null');

    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        '${title.replaceAll(' ', '_')}_${_uniqueStamp()}.xlsx';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> shareReportXlsx(
      ReportSummary summary, String title) async {
    final file = await exportReportToXlsx(summary, title);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(file.path,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
        ],
        text: title,
        subject: title,
      ),
    );
  }
}
