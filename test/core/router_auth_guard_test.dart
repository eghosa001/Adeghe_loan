import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/router/app_router.dart';
import 'package:loantrack/features/auth/presentation/providers/auth_provider.dart';

void main() {
  test('locked state allows public routes only', () {
    const redirect = authRedirect;

    // Public routes: no redirect.
    expect(redirect(AuthState.locked, '/splash'), isNull);
    expect(redirect(AuthState.locked, '/onboarding'), isNull);
    expect(redirect(AuthState.locked, '/auth/pin'), isNull);
    expect(redirect(AuthState.locked, '/auth/setup_pin'), isNull);
    expect(redirect(AuthState.locked, '/auth/forgot_pin'), isNull);

    // Protected routes: sent to PIN.
    expect(redirect(AuthState.locked, '/dashboard'), '/auth/pin');
    expect(redirect(AuthState.locked, '/loans'), '/auth/pin');
    expect(redirect(AuthState.locked, '/customers/CUS-1'), '/auth/pin');
    expect(redirect(AuthState.locked, '/collections/future-schedule'), '/auth/pin');
    expect(redirect(AuthState.locked, '/collections'), '/auth/pin');
    expect(redirect(AuthState.locked, '/collections/weekly'), '/auth/pin');
  });

  test('unlocked state allows everything', () {
    expect(authRedirect(AuthState.unlocked, '/dashboard'), isNull);
    expect(authRedirect(AuthState.unlocked, '/loans'), isNull);
    expect(authRedirect(AuthState.unlocked, '/auth/pin'), isNull);
  });

  test('initialSetup routes everything to setup_pin except public', () {
    expect(authRedirect(AuthState.initialSetup, '/dashboard'), '/auth/setup_pin');
    expect(authRedirect(AuthState.initialSetup, '/auth/setup_pin'), isNull);
    expect(authRedirect(AuthState.initialSetup, '/splash'), isNull);
  });
}
