import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/business/presentation/screens/business_settings_screen.dart';

void main() {
  testWidgets('Business settings screen shows profile fields',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BusinessSettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Business Name'), findsOneWidget);
    expect(find.text('Save Profile'), findsOneWidget);
  });
}
