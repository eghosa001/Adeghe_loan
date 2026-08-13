import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/presentation/providers/loan_providers.dart';
import 'package:loantrack/features/loans/presentation/screens/loan_creation_screen.dart';

/// Regression tests for the loan-form audit findings (2026-08-13):
///  * HIGH — a stale `customInstallmentAmount` from a previous create/edit
///    session leaked into an unrelated edit and silently redefined the loan's
///    repayment terms (`customAmount × duration`) on save.
///  * MEDIUM — editing the principal/duration cleared the custom amount in the
///    form state but left the visible "Collection amount" field showing it.
Loan _loan({double? customCollectionAmount}) => Loan(
      id: 'L1',
      customerId: 'C1',
      loanType: LoanType.daily,
      amount: 5000,
      interestRate: 15,
      duration: 23,
      loanDate: DateTime(2026, 8, 1),
      repaymentStartDate: DateTime(2026, 8, 1),
      totalRepayment: 5750,
      outstandingBalance: 5750,
      installmentAmount: 250,
      expectedCompletionDate: DateTime(2026, 8, 24),
      customCollectionAmount: customCollectionAmount,
    );

void main() {
  group('loadForEdit', () {
    test('clears a stale custom amount when the edited loan has none', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(loanFormProvider.notifier);

      // A previous create/edit session left a custom override behind (e.g. the
      // user typed one and backed out without saving).
      notifier.updateField(customInstallmentAmount: 1000);
      expect(container.read(loanFormProvider).customInstallmentAmount, 1000);

      notifier.loadForEdit(_loan());

      final state = container.read(loanFormProvider);
      expect(state.customInstallmentAmount, isNull);
      expect(state.principal, 5000);
      expect(state.interestRatePercent, 15);
      expect(state.duration, 23);
    });

    test('keeps the custom amount when the edited loan has one', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(loanFormProvider.notifier);

      notifier.loadForEdit(_loan(customCollectionAmount: 300));

      final state = container.read(loanFormProvider);
      expect(state.customInstallmentAmount, 300);
    });

    test('loadForEdit overwrites the previous session custom amount', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(loanFormProvider.notifier);

      notifier.updateField(customInstallmentAmount: 1000);
      notifier.loadForEdit(_loan(customCollectionAmount: 300));

      expect(container.read(loanFormProvider).customInstallmentAmount, 300);
    });
  });

  group('custom amount field/state sync', () {
    testWidgets('editing the principal clears the visible custom amount field',
        (tester) async {
      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: LoanCreationScreen(
            customerId: 'C1',
            existingLoan: _loan(customCollectionAmount: 300),
          ),
        ),
      ));
      await tester.pump();

      final customField = find.widgetWithText(
          TextFormField, 'Collection amount per period (optional)');
      expect(customField, findsOneWidget);
      expect(tester.widget<TextFormField>(customField).controller!.text, '300');

      final principalField =
          find.widgetWithText(TextFormField, 'Loan Amount (Principal)');
      await tester.enterText(principalField, '6000');
      await tester.pump();

      // The override was invalidated by the principal change, so both the
      // visible field and the form state must agree — no silently dropped
      // "Collection amount" on save.
      expect(
          tester.widget<TextFormField>(customField).controller!.text, isEmpty);
      expect(container.read(loanFormProvider).customInstallmentAmount, isNull);
    });
  });
}
