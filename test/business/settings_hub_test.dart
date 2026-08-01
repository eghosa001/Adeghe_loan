import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/features/business/presentation/screens/business_settings_screen.dart';
import 'package:loantrack/features/business/presentation/providers/business_providers.dart';
import 'package:loantrack/features/business/data/models/business_profile_entity.dart';

void main() {
  testWidgets('Business settings screen shows profile fields',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          businessProfileProvider.overrideWith((ref) {
            final notifier = BusinessProfileNotifier(ref);
            notifier.state = AsyncValue.data(BusinessProfile(
              id: '1',
              name: 'Test Business',
              ownerName: 'Test Owner',
              address: 'Test Address',
              phone: '123456',
              email: 'test@test.com',
              regNo: 'REG123',
            ));
            return notifier;
          }),
        ],
        child: const MaterialApp(home: BusinessSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Business Name'), findsOneWidget);
    expect(find.text('Business Profile'), findsOneWidget);
  });
}
