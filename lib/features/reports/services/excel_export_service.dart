import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ExcelExportService {
  ExcelExportService._();

  static const _headerBg = 'FF1F4E79';
  static const _headerFg = 'FFFFFFFF';
  static const _colHeaderBg = 'FFD6E4F0';
  static const _colHeaderFg = 'FF1F4E79';
  static const _altRowBg = 'FFF2F7FB';

  static CellStyle _titleStyle() => CellStyle(
        fontColorHex: _headerFg,
        backgroundColorHex: _headerBg,
        bold: true,
        fontSize: 16,
        horizontalAlign: HorizontalAlign.Center,
      );

  static CellStyle _colHeaderStyle() => CellStyle(
        fontColorHex: _colHeaderFg,
        backgroundColorHex: _colHeaderBg,
        bold: true,
        fontSize: 11,
        horizontalAlign: HorizontalAlign.Center,
      );

  static CellStyle _dataStyle({bool alt = false}) => CellStyle(
        backgroundColorHex: alt ? _altRowBg : 'FFFFFFFF',
        fontSize: 10,
      );

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

  static Future<File> _saveBytes(List<int> bytes, String fileName) async {
    final dot = fileName.lastIndexOf('.');
    final stamped = dot == -1
        ? '${fileName}_${_uniqueStamp()}'
        : '${fileName.substring(0, dot)}_${_uniqueStamp()}${fileName.substring(dot)}';
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$stamped');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> shareXlsx(File file, String title) async {
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

  /// Generic styled Excel builder using appendRow pattern.
  static Future<File> buildXlsx({
    required List<String> headers,
    required List<List<String>> rows,
    required String title,
    String sheetName = 'Sheet1',
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel[sheetName];

    sheet.appendRow([title]);
    sheet.appendRow([]);
    sheet.appendRow(headers);

    for (final row in rows) {
      sheet.appendRow(row);
    }

    // Apply styling
    final totalRows = 2 + rows.length;
    final totalCols = headers.length;

    for (var r = 0; r <= totalRows; r++) {
      for (var c = 0; c < totalCols; c++) {
        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        final rowData = r - 2;
        if (r == 0) {
          cell.cellStyle = _titleStyle();
        } else if (r == 2) {
          cell.cellStyle = _colHeaderStyle();
        } else if (r > 2) {
          cell.cellStyle = _dataStyle(alt: rowData.isOdd);
        }
      }
    }

    // Auto column widths
    for (var c = 0; c < totalCols; c++) {
      var maxWidth = headers[c].length;
      for (var r = 0; r < rows.length; r++) {
        if (c < rows[r].length && rows[r][c].length > maxWidth) {
          maxWidth = rows[r][c].length;
        }
      }
      sheet.setColWidth(c, (maxWidth + 3).toDouble());
    }

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode Excel file');
    return _saveBytes(bytes, '${title.replaceAll(' ', '_')}.xlsx');
  }
}
