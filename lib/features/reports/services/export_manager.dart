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
import '../../business/data/models/business_profile_entity.dart';
import '../../collection/data/models/collection_row.dart';

/// A summary card shown above the table in generated PDF reports.
class ReportCard {
  const ReportCard(this.label, this.value, {this.highlight = false});

  final String label;
  final String value;
  final bool highlight;
}

/// Everything needed to render/export one report. Rows are pre-formatted
/// display strings (currency formatted by the caller), so the exporter only
/// lays them out — it can never produce a number different from the screen's
/// filtered data. This is why exports always contain exactly the current
/// report's data.
class ReportExportData {
  const ReportExportData({
    required this.reportName,
    required this.periodLabel,
    required this.headers,
    required this.rows,
    required this.rightAlignColumns,
    this.cards = const [],
    this.totalsRow,
  });

  final String reportName;
  final String periodLabel;
  final List<ReportCard> cards;
  final List<String> headers;
  final List<List<String>> rows;

  /// Column indexes whose values should be right-aligned (currency, counts).
  final List<int> rightAlignColumns;

  /// Optional right-aligned totals row rendered after the table.
  final List<String>? totalsRow;
}

class ExportManager {
  ExportManager._();

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

  static String _pdfFileName(ReportExportData data) =>
      '${data.reportName.replaceAll(' ', '_')}_${_uniqueStamp()}.pdf';

  static String _xlsxFileName(ReportExportData data) =>
      '${data.reportName.replaceAll(' ', '_')}_${_uniqueStamp()}.xlsx';

  // ── Generic branded PDF export (all report screens) ────────────────────────

  static Future<Uint8List?> _loadLogo(BusinessProfile? profile) async {
    if (profile?.logoPath == null) return null;
    try {
      final file = File(profile!.logoPath!);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> _buildReportPdfBytes(
    ReportExportData data,
    BusinessProfile? profile,
  ) async {
    final font = await _getFont();
    final bold = await _getFontBold();
    final pdf = pw.Document();

    final companyName = (profile?.name ?? '').trim().isNotEmpty
        ? profile!.name.trim()
        : 'Adeghe Professional Services';
    final companyAddress = (profile?.address ?? '').trim();

    final logoBytes = await _loadLogo(profile);

    final headers = data.headers;
    final alignments = <pw.Alignment>[];
    for (var i = 0; i < headers.length; i++) {
      alignments.add(data.rightAlignColumns.contains(i)
          ? pw.Alignment.centerRight
          : pw.Alignment.centerLeft);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          final widgets = <pw.Widget>[
            _buildLetterhead(font, bold, companyName, companyAddress, logoBytes),
            pw.SizedBox(height: 16),
            pw.Text(
              data.reportName,
              style: pw.TextStyle(font: bold, fontSize: 20, color: PdfColors.blue900),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Report Period: ${data.periodLabel}',
              style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700),
            ),
            if (data.cards.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              ..._buildCards(font, bold, data.cards),
            ],
            pw.SizedBox(height: 16),
            _buildPdfTable(
                font, bold, headers, data.rows, alignments),
            if (data.totalsRow != null) ...[
              pw.SizedBox(height: 8),
              _buildTotalsRow(font, bold, data.totalsRow!, alignments),
            ],
          ];
          return widgets;
        },
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildLetterhead(
    pw.Font font,
    pw.Font bold,
    String companyName,
    String companyAddress,
    Uint8List? logoBytes,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logoBytes != null) ...[
          pw.Image(pw.MemoryImage(logoBytes), height: 36, fit: pw.BoxFit.contain),
          pw.SizedBox(width: 12),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(companyName,
                  style: pw.TextStyle(font: bold, fontSize: 14, color: PdfColors.blue900)),
              if (companyAddress.isNotEmpty)
                pw.Text(companyAddress,
                    style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700)),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Generated: ${AppDateUtils.formatDateTime(DateTime.now())}',
              style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Created by AIGHEWI EGHOSA',
              style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      ],
    );
  }

  static List<pw.Widget> _buildCards(
      pw.Font font, pw.Font bold, List<ReportCard> cards) {
    const perRow = 5;
    final rows = <List<ReportCard>>[];
    for (var i = 0; i < cards.length; i += perRow) {
      rows.add(cards.sublist(i, i + perRow > cards.length ? cards.length : i + perRow));
    }

    return [
      for (final row in rows)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(
            children: [
              for (var i = 0; i < row.length; i++) ...[
                if (i > 0) pw.SizedBox(width: 8),
                pw.Expanded(child: _buildCard(font, bold, row[i])),
              ],
            ],
          ),
        ),
    ];
  }

  static pw.Widget _buildCard(pw.Font font, pw.Font bold, ReportCard card) {
    final color = card.highlight ? PdfColors.red700 : PdfColors.blue900;
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(card.label,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(font: font, fontSize: 7, color: color)),
          pw.SizedBox(height: 3),
          pw.Text(card.value,
              maxLines: 1,
              style: pw.TextStyle(font: bold, fontSize: 11, color: PdfColors.black)),
        ],
      ),
    );
  }

  static pw.Widget _buildPdfTable(
    pw.Font font,
    pw.Font bold,
    List<String> headers,
    List<List<String>> rows,
    List<pw.Alignment> alignments,
  ) {
    if (rows.isEmpty) {
      return pw.Text('No records match the current filters.',
          style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700));
    }
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(font: bold, fontSize: 8, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.blue900,
        borderRadius: pw.BorderRadius.only(
          topLeft: pw.Radius.circular(4),
          topRight: pw.Radius.circular(4),
        ),
      ),
      cellStyle: pw.TextStyle(font: font, fontSize: 7),
      cellHeight: 20,
      cellAlignments: {
        for (var i = 0; i < alignments.length; i++) i: alignments[i],
      },
      headers: headers,
      data: rows,
    );
  }

  static pw.Widget _buildTotalsRow(
    pw.Font font,
    pw.Font bold,
    List<String> totals,
    List<pw.Alignment> alignments,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        children: [
          for (var i = 0; i < totals.length; i++)
            pw.Expanded(
              child: pw.Container(
                alignment: alignments[i],
                child: pw.Text(totals[i],
                    style: pw.TextStyle(font: bold, fontSize: 8, color: PdfColors.black)),
              ),
            ),
        ],
      ),
    );
  }

  /// Saves a branded PDF via the system save dialog. Returns the chosen path
  /// or null if the user canceled.
  static Future<String?> saveReportPdf(
    ReportExportData data, {
    BusinessProfile? profile,
  }) async {
    final bytes = await _buildReportPdfBytes(data, profile);
    return _savePdfViaPicker(bytes, _pdfFileName(data));
  }

  /// Writes the branded PDF to the app documents directory and returns the File.
  static Future<File> exportReportToPdf(
    ReportExportData data, {
    BusinessProfile? profile,
  }) async {
    final bytes = await _buildReportPdfBytes(data, profile);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${_pdfFileName(data)}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> shareReportPdf(
    ReportExportData data, {
    BusinessProfile? profile,
  }) async {
    final file = await exportReportToPdf(data, profile: profile);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: data.reportName,
      ),
    );
  }

  /// Prints the same branded landscape layout the PDF export produces.
  static Future<void> printReportPdf(
    ReportExportData data, {
    BusinessProfile? profile,
  }) async {
    final bytes = await _buildReportPdfBytes(data, profile);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  // ── Generic Excel export (all report screens) ──────────────────────────────

  static Future<File> exportReportToXlsx(
    ReportExportData data,
  ) async {
    final excel = Excel.createExcel();
    final sheet = excel['Report'];

    // Title + period
    _appendStyled(sheet, 0, [data.reportName], bold: true, size: 13);
    _appendStyled(sheet, 1, ['Period: ${data.periodLabel}']);
    _appendStyled(sheet, 2, const []);

    var rowIdx = 3;
    // Summary cards (label / value)
    for (final card in data.cards) {
      _appendStyled(sheet, rowIdx, [card.label, card.value], bold: true);
      rowIdx++;
    }
    if (data.cards.isNotEmpty) {
      _appendStyled(sheet, rowIdx, const []);
      rowIdx++;
    }

    // Table header
    _appendStyled(sheet, rowIdx, data.headers, header: true);
    rowIdx++;
    for (final row in data.rows) {
      _appendStyled(sheet, rowIdx, row);
      rowIdx++;
    }
    if (data.totalsRow != null) {
      _appendStyled(sheet, rowIdx, const []);
      rowIdx++;
      _appendStyled(sheet, rowIdx, data.totalsRow!, bold: true);
    }

    // Autosize columns from populated cells.
    final maxCols = data.headers.length;
    for (var c = 0; c < maxCols; c++) {
      var maxWidth = 0;
      for (var r = 0; r < sheet.maxRows; r++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        final text = cell.value?.toString() ?? '';
        if (text.length > maxWidth) maxWidth = text.length;
      }
      sheet.setColWidth(c, (maxWidth + 4).clamp(10, 60).toDouble());
    }

    final List<int>? bytes;
    try {
      bytes = excel.encode();
    } catch (e) {
      throw Exception('Failed to encode Excel file: $e');
    }
    if (bytes == null) {
      throw Exception('Failed to encode Excel file: encode returned null');
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${_xlsxFileName(data)}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static void _appendStyled(
    Sheet sheet,
    int rowIndex,
    List<String> cells, {
    bool bold = false,
    bool header = false,
    int size = 10,
  }) {
    sheet.appendRow(cells);
    for (var c = 0; c < cells.length; c++) {
      final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex));
      cell.cellStyle = CellStyle(
        bold: bold || header,
        fontSize: header ? 10 : size,
        backgroundColorHex: header ? 'FFEAF0F7' : 'none',
        bottomBorder:
            header ? Border(borderStyle: BorderStyle.Thin) : null,
      );
    }
  }

  // ── Collection PDF/Excel (preserved public API for the Collection screen) ──

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
                style: pw.TextStyle(font: bold, fontSize: 20, color: PdfColors.blue900),
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
                child: pw.Text('Group: $groupName',
                    style: pw.TextStyle(font: bold, fontSize: 13, color: PdfColors.blue900)),
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

    const totalCols = 3;
    final allRows = <List<String?>>[];
    final boldRows = <bool>[];

    for (final groupName in sortedGroups) {
      allRows.add([groupName, null, null]);
      boldRows.add(true);
      final block = _buildCollectionRows(
          _sortedCollectionRows(groupedRows[groupName]!));
      for (final r in block) {
        allRows.add(r);
        boldRows.add(false);
      }
      allRows.add([null, null, null]);
      boldRows.add(false);
    }

    final sheet = excel[defaultSheet ?? 'Collections'];
    for (final row in allRows) {
      sheet.appendRow([
        row[0] ?? '',
        row[1] ?? '',
        row[2] ?? '',
      ]);
    }

    final totalRows = sheet.maxRows;
    for (var r = 0; r < totalRows; r++) {
      for (var c = 0; c < totalCols; c++) {
        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        final value = cell.value?.toString() ?? '';
        cell.cellStyle = CellStyle(
          bold: boldRows[r] || _isCollectionHeaderValue(value),
          horizontalAlign: HorizontalAlign.Left,
          bottomBorder: Border(borderStyle: BorderStyle.Thin),
          topBorder: Border(borderStyle: BorderStyle.Thin),
          leftBorder: Border(borderStyle: BorderStyle.Thin),
          rightBorder: Border(borderStyle: BorderStyle.Thin),
        );
      }
    }

    for (var c = 0; c < totalCols; c++) {
      var maxWidth = 0;
      for (var r = 0; r < totalRows; r++) {
        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        final text = cell.value?.toString() ?? '';
        if (text.length > maxWidth) maxWidth = text.length;
      }
      sheet.setColWidth(c, (maxWidth + 3).toDouble());
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

  static bool _isCollectionHeaderValue(String value) {
    return value == 'DAILY LOANS' ||
        value == 'WEEKLY LOANS' ||
        value == 'Name' ||
        value == 'Amount' ||
        value == 'Paid';
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

  static List<List<String?>> _buildCollectionRows(List<CollectionRow> rows) {
    final result = <List<String?>>[];

    final dailyRows =
        rows.where((r) => r.loanType.toLowerCase() == 'daily').toList();
    if (dailyRows.isNotEmpty) {
      result.add(['DAILY LOANS', null, null]);
      result.add(['Name', 'Amount', 'Paid']);
      for (final r in dailyRows) {
        result.add([r.customerName, r.amountDue.toStringAsFixed(2), r.amountPaid.toStringAsFixed(2)]);
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
        result.add([r.customerName, r.amountDue.toStringAsFixed(2), r.amountPaid.toStringAsFixed(2)]);
      }
    }

    return result;
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
              CurrencyUtils.format(r.amountPaid, symbol: currencySymbol),
            ])
        .toList();

    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.white),
      headerDecoration: pw.BoxDecoration(
        color: PdfColors.blue900,
        borderRadius: pw.BorderRadius.only(
          topLeft: pw.Radius.circular(4),
          topRight: pw.Radius.circular(4),
        ),
      ),
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
}
