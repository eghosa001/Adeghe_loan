import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/error/failure.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/features/business/presentation/providers/business_providers.dart';
import 'package:loantrack/features/collection/data/collection_repository.dart';
import 'package:loantrack/features/collection/data/models/weekly_collection_row.dart';
import 'package:loantrack/features/collection/presentation/providers/collection_provider.dart';
import 'package:loantrack/features/collection/presentation/screens/weekly_collection_screen.dart';

WeeklyCollectionRow _row(String loanId, String name) {
  return WeeklyCollectionRow(
    customerId: 'C_$name',
    customerName: name,
    phone: '0801',
    guarantorName: '',
    guarantorPhone: '',
    loanId: loanId,
    loanType: 'weekly',
    amountDisbursed: 2000,
    interestAmount: 200,
    expectedAmount: 2200,
    weeklyInstallment: 550,
    amountPaid: 0,
    outstandingBalance: 2000,
    installmentDue: 550,
    loanDate: '2026-07-29',
    paymentAnchorDate: '2026-08-05',
    status: 'active',
    currentInstallmentNumber: 1,
    currentInstallmentDueDate: '2026-08-12',
    currentInstallmentAmount: 550,
    currentInstallmentPaidAmount: 0,
    currentInstallmentStatus: 'pending',
    daysOverdue: 0,
    collectedThisPeriod: 0,
    overdueAmount: 0,
    savingsBalance: 0,
  );
}

class _FakeCollectionRepository extends CollectionRepository {
  _FakeCollectionRepository() : super(DatabaseService(SecureStorageService()));

  @override
  Future<Result<List<WeeklyCollectionRow>>> getWeeklyCollectionByDate(
      DateTime date) async {
    return Result.success(List.unmodifiable([
      _row('L1', 'Alice Weekly'),
      _row('L2', 'Bob Daily'),
      _row('L3', 'Charlie Falls'),
    ]));
  }

  @override
  Future<Result<List<WeeklyCollectionRow>>> getWeeklyCollectionByDateRange(
      DateTime start, DateTime end) async {
    return Result.success(List.unmodifiable([
      _row('L1', 'Alice Weekly'),
      _row('L2', 'Bob Daily'),
      _row('L3', 'Charlie Falls'),
    ]));
  }
}

void main() {
  Widget wrap() {
    return ProviderScope(
      overrides: [
        collectionRepositoryProvider.overrideWith(
          (ref) async => _FakeCollectionRepository(),
        ),
        currencySymbolProvider.overrideWith((ref) async => '₦'),
      ],
      child: const MaterialApp(home: WeeklyCollectionScreen()),
    );
  }

  testWidgets('type first, then switch to range mode: search still applies',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Alice Weekly'), findsOneWidget);
    expect(find.text('Bob Daily'), findsOneWidget);

    // Type a customer name (single-date mode).
    await tester.enterText(find.byType(TextField).first, 'alice');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Alice Weekly'), findsOneWidget);
    expect(find.text('Bob Daily'), findsNothing);

    // Now switch on date range mode — search must still be applied.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Alice Weekly'), findsOneWidget);
    expect(find.text('Bob Daily'), findsNothing);

    // Pick a date range via the range tile (accept the default initial dates).
    await tester.tap(find.textContaining('—'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Search query must still filter the range results.
    expect(find.text('Alice Weekly'), findsOneWidget);
    expect(find.text('Bob Daily'), findsNothing);
  });
}
