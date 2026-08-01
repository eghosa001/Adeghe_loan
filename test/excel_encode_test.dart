import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('excel rename does not crash collection export pattern', () async {
    // Regression test: excel 2.1.0 rename() -> delete() calls
    // _archive.files.removeWhere() on an unmodifiable list and throws
    // "Unsupported operation: Cannot remove from an unmodifiable list".
    // exportCollectionToExcel previously used excel.rename() and always crashed.
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();

    final groups = ['Lagos Group', 'Ibadan Group', 'Enugu Group', 'Abuja Group'];

    bool isFirst = true;
    int sheetIndex = 0;
    for (var i = 0; i < groups.length; i += 2) {
      final String sheetName;
      if (isFirst) {
        sheetName = defaultSheet ?? groups[i];
        isFirst = false;
      } else {
        sheetName = 'Sheet_$sheetIndex';
        sheetIndex++;
      }
      final sheet = excel[sheetName];
      sheet.appendRow(List<dynamic>.filled(7, ''));
      sheet.cell(
              CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
          .value = groups[i];
      for (var r = 0; r < 1; r++) {
        for (var c = 0; c < 7; c++) {
          final cell = sheet.cell(
              CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
          cell.cellStyle = CellStyle(
            bold: true,
            bottomBorder: Border(borderStyle: BorderStyle.Thin),
            topBorder: Border(borderStyle: BorderStyle.Thin),
            leftBorder: Border(borderStyle: BorderStyle.Thin),
            rightBorder: Border(borderStyle: BorderStyle.Thin),
          );
        }
      }
      for (var c = 0; c < 7; c++) {
        sheet.setColWidth(c, 14.0);
      }
    }

    final bytes = excel.encode();
    expect(bytes, isNotNull, reason: 'encode should not throw/crash');

    final decoded = Excel.decodeBytes(bytes!);
    expect(decoded.tables.length, 2);
  });

  test('excel encode produces valid workbook with styling patterns', () async {
    final excel = Excel.createExcel();
    final sheet = excel['Report'];

    sheet.appendRow(['Financial Summary']);
    sheet.appendRow([]);
    sheet.appendRow(['Metric', 'Value']);
    sheet.appendRow(['Total Collected', '1,000.00']);

    for (var r = 0; r <= 3; r++) {
      for (var c = 0; c < 2; c++) {
        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        if (r == 0) {
          cell.cellStyle = CellStyle(
            fontColorHex: 'FFFFFFFF',
            backgroundColorHex: 'FF1F4E79',
            bold: true,
            fontSize: 16,
            horizontalAlign: HorizontalAlign.Center,
          );
        } else {
          cell.cellStyle = CellStyle(
            fontSize: 10,
            horizontalAlign: HorizontalAlign.Right,
          );
        }
      }
    }

    sheet.setColWidth(0, 30);
    sheet.setColWidth(1, 24);

    final bytes = excel.encode();
    expect(bytes, isNotNull);

    final decoded = Excel.decodeBytes(bytes!);
    expect(decoded.tables.keys, isNotEmpty);
    expect(decoded.tables.containsKey('Report'), isTrue);
  });

  test('excel encode with empty appendRow rows is valid', () async {
    final excel = Excel.createExcel();
    final sheet = excel['Summary'];

    sheet.appendRow(['Financial Summary  ·  Period']);
    sheet.appendRow([]);
    sheet.appendRow(['FINANCIAL OVERVIEW']);
    sheet.appendRow(['Total Disbursed', '500.00']);
    sheet.appendRow(['Total Collected', '600.00']);
    sheet.appendRow([]);
    sheet.appendRow(['DAILY LOANS']);
    sheet.appendRow(['Active', '5']);

    final bytes = excel.encode();
    expect(bytes, isNotNull);

    final decoded = Excel.decodeBytes(bytes!);
    expect(decoded.tables.containsKey('Summary'), isTrue);
  });
}
