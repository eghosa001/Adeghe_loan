import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/collection/presentation/widgets/bulk_collection.dart';
import 'package:loantrack/features/payments/data/models/payment_entity.dart';

void main() {
  group('BulkCollectDraft.total', () {
    test('sums the confirmed amounts', () {
      final draft = BulkCollectDraft(
        items: const [],
        amounts: const [100, 250.5, 49.5],
        method: PaymentMethod.cash,
      );
      expect(draft.total, 400.0);
    });

    test('ignores non-finite amounts so a corrupt draft cannot blow up', () {
      final draft = BulkCollectDraft(
        items: const [],
        amounts: const [100, double.nan, double.infinity, 50],
        method: PaymentMethod.cash,
      );
      expect(draft.total, 150.0);
    });
  });

  group('bulkCollectSummary', () {
    test('success-only copy reports the collected total', () {
      expect(
        bulkCollectSummary(
          const BulkCollectOutcome(successCount: 3, failures: []),
          1200,
        ),
        'Collected ₦1,200.00 — 3 payment(s) recorded',
      );
    });

    test('all-failed copy lists every failure', () {
      expect(
        bulkCollectSummary(
          const BulkCollectOutcome(
            successCount: 0,
            failures: ['Ada: bad', 'Bola: worse'],
          ),
          0,
        ),
        'No payments recorded. Ada: bad; Bola: worse',
      );
    });

    test('mixed copy reports successes and failures', () {
      final message = bulkCollectSummary(
        const BulkCollectOutcome(
          successCount: 2,
          failures: ['Ada: over'],
        ),
        900,
      );
      expect(message, contains('2 payment(s) recorded'));
      expect(message, contains('1 failed: Ada: over'));
    });
  });

  group('BulkCollectBottomBar', () {
    testWidgets('shows the count and total, and disables collect at zero',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BulkCollectBottomBar(
              selectedCount: 0,
              total: 0,
              allSelected: false,
              onSelectAll: () {},
              onCollect: () {},
            ),
          ),
        ),
      );

      expect(find.text('0 selected'), findsOneWidget);
      final collectButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Collect'),
      );
      expect(collectButton.onPressed, isNull);
    });

    testWidgets('enables collect and renders the total once something is picked',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BulkCollectBottomBar(
              selectedCount: 3,
              total: 1650,
              allSelected: false,
              onSelectAll: () {},
              onCollect: () {},
            ),
          ),
        ),
      );

      expect(find.text('3 selected'), findsOneWidget);
      expect(find.text('₦1,650.00'), findsOneWidget);
      final collectButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Collect'),
      );
      expect(collectButton.onPressed, isNotNull);
    });

    testWidgets('labels the select-all toggle None when everything is picked',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BulkCollectBottomBar(
              selectedCount: 2,
              total: 0,
              allSelected: true,
              onSelectAll: () {},
              onCollect: () {},
            ),
          ),
        ),
      );

      expect(find.text('None'), findsOneWidget);
    });
  });
}
