import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/features/business/presentation/screens/financial_settings_tab.dart';
import 'package:loantrack/features/business/data/models/financial_settings_entity.dart';
import 'package:loantrack/features/business/presentation/providers/business_providers.dart';

void main() {
  testWidgets('FinancialSettingsTab shows fields', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: [
        financialSettingsProvider
            .overrideWith((ref) => Future.value(FinancialSettings())),
      ], child: const MaterialApp(home: FinancialSettingsTab())),
    );

    await tester.pumpAndSettle();

    expect(find.text('Currency'), findsOneWidget);
    expect(find.text('Interest Rate'), findsOneWidget);
    expect(find.text('Insurance Fee'), findsOneWidget);
    expect(find.text('Commission'), findsOneWidget);
    expect(find.text('Processing Fee'), findsOneWidget);
  });
}
