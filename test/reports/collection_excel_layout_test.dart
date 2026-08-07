import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/collection/data/models/collection_row.dart';
import 'package:loantrack/features/reports/services/export_manager.dart';

void main() {
  CollectionRow row(
    String name, {
    String group = 'Group 1',
    String loanType = 'daily',
    double due = 2500,
    double paid = 0,
  }) {
    return CollectionRow(
      customerId: 'c-$name',
      customerName: name,
      phone: '0800000000',
      loanId: 'l-$name',
      loanType: loanType,
      amountDue: due,
      amountPaid: paid,
      installmentAmount: due,
      outstandingBalance: due - paid,
      status: 'active',
      scheduleStatus: paid >= due ? 'paid' : 'pending',
      groupName: group.isEmpty ? null : group,
    );
  }

  String cellText(Sheet sheet, int c, int r) =>
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
          .value
          ?.toString() ??
      '';

  Sheet buildSheet(List<CollectionRow> rows) {
    final bytes = ExportManager.buildCollectionExcelBytes(
        rows, DateTime(2026, 1, 5));
    final decoded = Excel.decodeBytes(bytes);
    return decoded.tables[decoded.tables.keys.first]!;
  }

  group('collection sheet two-column group layout', () {
    test('single group: daily/weekly separated, blank paid, right slot empty',
        () {
      final sheet = buildSheet([
        row('John', loanType: 'daily', due: 2500, paid: 0),
        row('Mary', loanType: 'daily', due: 3000, paid: 3000),
        row('Peter', loanType: 'weekly', due: 1800, paid: 0),
      ]);

      // Left slot (cols 0-2) at rows 0-7.
      expect(cellText(sheet, 0, 0), 'Group 1');
      expect(cellText(sheet, 0, 1), 'DAILY LOANS');
      expect(cellText(sheet, 0, 2), 'Name');
      expect(cellText(sheet, 1, 2), 'Amount');
      expect(cellText(sheet, 2, 2), 'Paid');
      expect(cellText(sheet, 0, 3), 'John');
      expect(cellText(sheet, 1, 3), '2500.00');
      expect(cellText(sheet, 2, 3), ''); // unpaid -> blank, not 0.00
      expect(cellText(sheet, 0, 4), 'Mary');
      expect(cellText(sheet, 1, 4), '3000.00');
      expect(cellText(sheet, 2, 4), '3000.00'); // paid -> amount
      expect(cellText(sheet, 0, 5), 'WEEKLY LOANS');
      expect(cellText(sheet, 0, 6), 'Name');
      expect(cellText(sheet, 0, 7), 'Peter');
      expect(cellText(sheet, 1, 7), '1800.00');
      expect(cellText(sheet, 2, 7), '');

      // Right slot (cols 4-6) and spacer col 3 stay empty.
      for (var c = 3; c <= 6; c++) {
        expect(cellText(sheet, c, 0), '');
      }
    });

    test('two groups sit side by side on the same row block', () {
      final sheet = buildSheet([
        row('Alpha', group: 'G1'),
        row('Beta', group: 'G2'),
      ]);

      expect(cellText(sheet, 0, 0), 'G1');
      expect(cellText(sheet, 4, 0), 'G2');
      expect(cellText(sheet, 0, 1), 'DAILY LOANS');
      expect(cellText(sheet, 4, 1), 'DAILY LOANS');
      expect(cellText(sheet, 0, 3), 'Alpha');
      expect(cellText(sheet, 4, 3), 'Beta');
    });

    test('mixed sizes: next pair starts below the taller block', () {
      final g1 = List.generate(10, (i) => row('G1_$i', group: 'G1'));
      final g2 = List.generate(2, (i) => row('G2_$i', group: 'G2'));
      final g3 = [row('G3_a', group: 'G3')];

      final sheet = buildSheet([...g1, ...g2, ...g3]);

      // G1 block: 1 title + 1 subheader + 1 header + 10 rows = 13 lines.
      // Pair 1 ends at row 12; one blank gap row (13); G3 starts at row 14.
      expect(cellText(sheet, 0, 0), 'G1');
      expect(cellText(sheet, 4, 0), 'G2');
      expect(cellText(sheet, 0, 12), 'G1_9');
      expect(cellText(sheet, 4, 12), ''); // G2 (5 lines) ended at row 4
      expect(cellText(sheet, 0, 13), ''); // gap row
      expect(cellText(sheet, 4, 13), '');
      expect(cellText(sheet, 0, 14), 'G3');
      expect(cellText(sheet, 4, 14), ''); // odd group: right side empty
    });

    test('right block taller than left still advances the next pair', () {
      final g1 = [row('G1_a', group: 'G1')];
      final g2 = List.generate(8, (i) => row('G2_$i', group: 'G2'));
      final g3 = [row('G3_a', group: 'G3')];

      final sheet = buildSheet([...g1, ...g2, ...g3]);

      // G2 block = 1 + 1 + 1 + 8 = 11 lines (rows 0-10). Gap at 11, G3 at 12.
      expect(cellText(sheet, 0, 0), 'G1');
      expect(cellText(sheet, 4, 0), 'G2');
      expect(cellText(sheet, 4, 10), 'G2_7');
      expect(cellText(sheet, 0, 11), '');
      expect(cellText(sheet, 0, 12), 'G3');
    });

    test('three groups: pair then lone group', () {
      final sheet = buildSheet([
        row('a', group: 'G1'),
        row('b', group: 'G2'),
        row('c', group: 'G3'),
      ]);

      // Every block here is 4 lines; pairs advance by 5 rows.
      expect(cellText(sheet, 0, 0), 'G1');
      expect(cellText(sheet, 4, 0), 'G2');
      expect(cellText(sheet, 0, 5), 'G3');
      expect(cellText(sheet, 4, 5), '');
    });

    test('five groups: two pairs then lone group', () {
      final sheet = buildSheet([
        row('a', group: 'G1'),
        row('b', group: 'G2'),
        row('c', group: 'G3'),
        row('d', group: 'G4'),
        row('e', group: 'G5'),
      ]);

      expect(cellText(sheet, 0, 0), 'G1');
      expect(cellText(sheet, 4, 0), 'G2');
      expect(cellText(sheet, 0, 5), 'G3');
      expect(cellText(sheet, 4, 5), 'G4');
      expect(cellText(sheet, 0, 10), 'G5');
      expect(cellText(sheet, 4, 10), '');
    });

    test('ten groups: five pairs, all in the left/right slots', () {
      final rows = [
        for (var g = 1; g <= 10; g++)
          row('m', group: 'G${g.toString().padLeft(2, '0')}'),
      ];
      final sheet = buildSheet(rows);

      for (var pair = 0; pair < 5; pair++) {
        final r = pair * 5;
        expect(cellText(sheet, 0, r), 'G${(pair * 2 + 1).toString().padLeft(2, '0')}');
        expect(cellText(sheet, 4, r), 'G${(pair * 2 + 2).toString().padLeft(2, '0')}');
      }
    });

    test('ungrouped customers render as their own group', () {
      final sheet = buildSheet([
        row('Solo', group: ''),
      ]);

      expect(cellText(sheet, 0, 0), 'Ungrouped');
      expect(cellText(sheet, 0, 1), 'DAILY LOANS');
      expect(cellText(sheet, 0, 3), 'Solo');
    });

    test('groups stay alphabetical with Ungrouped last', () {
      final sheet = buildSheet([
        row('z', group: 'Zebra'),
        row('a', group: 'Alpha'),
        row('u', group: ''),
      ]);

      expect(cellText(sheet, 0, 0), 'Alpha');
      expect(cellText(sheet, 4, 0), 'Zebra');
      expect(cellText(sheet, 0, 5), 'Ungrouped');
    });

    test('no customers produces a message row and a valid workbook', () {
      final bytes = ExportManager.buildCollectionExcelBytes(
          const [], DateTime(2026, 1, 5));
      final decoded = Excel.decodeBytes(bytes);
      final sheet = decoded.tables[decoded.tables.keys.first]!;
      expect(cellText(sheet, 0, 0), startsWith('No collections'));
    });

    test('100+ customer groups layout without overlap', () {
      final rows = [
        for (var i = 0; i < 120; i++)
          row('D$i', group: 'BigDaily', paid: i == 0 ? 500 : 0),
        for (var i = 0; i < 60; i++)
          row('W$i', group: 'BigDaily', loanType: 'weekly'),
      ];
      final sheet = buildSheet(rows);

      // BigDaily block = 1 title + 1 DAILY + 1 header + 120 + 1 WEEKLY + 1 header + 60 = 185 lines.
      expect(cellText(sheet, 0, 0), 'BigDaily');
      expect(cellText(sheet, 0, 1), 'DAILY LOANS');
      expect(cellText(sheet, 0, 2), 'Name');
      expect(cellText(sheet, 0, 123), 'WEEKLY LOANS');
      expect(cellText(sheet, 0, 124), 'Name');
      for (var r = 3; r <= 122; r++) {
        expect(cellText(sheet, 0, r), isNotEmpty, reason: 'daily row $r');
      }
      for (var r = 125; r <= 184; r++) {
        expect(cellText(sheet, 0, r), isNotEmpty, reason: 'weekly row $r');
      }
      expect(cellText(sheet, 0, 185), ''); // block ends; no overlap below
      expect(cellText(sheet, 4, 0), ''); // right slot stays empty
    });

    test('row cap rolls the layout onto a second worksheet', () {
      final rows = [
        for (var g = 1; g <= 410; g++) row('c$g', group: 'G$g'),
      ];
      final bytes = ExportManager.buildCollectionExcelBytes(
          rows, DateTime(2026, 1, 5));
      final decoded = Excel.decodeBytes(bytes);

      expect(decoded.tables.length, 2);
      final sheet2 = decoded.tables['Collections 2']!;
      expect(cellText(sheet2, 0, 0), isNotEmpty);
      expect(cellText(sheet2, 4, 0), isNotEmpty);
    });
  });
}
