import 'package:flutter_test/flutter_test.dart';

import 'package:loantrack/core/cloud/cloud_auth_service.dart';

void main() {
  group('CloudAuthService.friendlySignInError', () {
    test('does not expose whether an account exists', () {
      expect(
        CloudAuthService.friendlySignInError(
          StateError('Invalid login credentials'),
        ),
        'Invalid email or password.',
      );
      expect(
        CloudAuthService.friendlySignInError(
          StateError('Email not registered'),
        ),
        'Invalid email or password.',
      );
    });

    test('maps owner authorization failures to safe messages', () {
      expect(
        CloudAuthService.friendlySignInError(
          StateError('email_not_authorized'),
        ),
        CloudAuthService.emailNotAuthorizedMessage,
      );
      expect(
        CloudAuthService.friendlySignInError(
          StateError('owner slots are already taken'),
        ),
        CloudAuthService.ownersFullMessage,
      );
      expect(
        CloudAuthService.friendlySignInError(
          StateError('not one of the cloud owners'),
        ),
        CloudAuthService.notOwnerMessage,
      );
    });
  });
}
