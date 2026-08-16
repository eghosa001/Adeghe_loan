import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/error/failure.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/features/business/presentation/providers/business_providers.dart';
import 'package:loantrack/features/collection/data/collection_repository.dart';
import 'package:loantrack/features/collection/data/models/collection_row.dart';
import 'package:loantrack/features/collection/presentation/providers/collection_provider.dart';
import 'package:loantrack/features/collection/presentation/screens/daily_collection_screen.dart';

CollectionRow _row(String loanId, String name) {
  return CollectionRow(
    customerId: 'C_$name',
    customerName: name,
    phone: '0801',
    loanId: loanId,
    loanType: 'daily',
    amountDue: 1000,
    amountPaid: 0,
    installmentAmount: 1000,
    outstandingBalance: 20000,
    status: 'active',
    scheduleStatus: 'pending',
  );
}

/// Mirrors the real repository, which returns unmodifiable lists
/// (`toList(growable: false)`). The provider must copy before sorting.
class _FakeCollectionRepository extends CollectionRepository {
  _FakeCollectionRepository() : super(DatabaseService(SecureStorageService()));

  @override
  Future<Result<List<CollectionRow>>> getDailyCollection(DateTime date,
      {String? groupId, String? loanType}) async {
    return Result.success(List.unmodifiable([
      _row('L1', 'Alice Daily'),
      _row('L2', 'Bob Daily'),
    ]));
  }

  @override
  Future<Result<List<CollectionRow>>> getCollectionsByDateRange(
      DateTime start, DateTime end,
      {String? loanType, String? groupId}) async {
    return Result.success(List.unmodifiable([
      _row('L1', 'Alice Daily'),
      _row('L2', 'Bob Daily'),
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
      child: const MaterialApp(home: DailyCollectionScreen()),
    );
  }

  testWidgets(
      'daily list renders with an empty search query even when the repository '
      'returns an unmodifiable list (regression: cannot modify an unmodifiable '
      'list)', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Error:'), findsNothing);
    expect(find.text('Alice Daily'), findsOneWidget);
    expect(find.text('Bob Daily'), findsOneWidget);
  });

  testWidgets('daily list also sorts in date range mode with an empty search',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // Switch on date range mode — the provider must copy before sorting there
    // as well.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Error:'), findsNothing);
    expect(find.text('Alice Daily'), findsOneWidget);
    expect(find.text('Bob Daily'), findsOneWidget);
  });
}
