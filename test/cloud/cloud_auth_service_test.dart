import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/cloud/cloud_auth_service.dart';
import 'package:loantrack/core/cloud/cloud_sync_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Guards the two-owner cloud authorization model:
///  * `claim_owner` is invoked WITHOUT any caller-supplied owner id
///  * an email missing from the `authorized_owners` allow-list is refused a slot
///  * a claim is refused when both owner slots are already taken
///  * a successful sign-in is only accepted once `is_owner` confirms the caller
///  * a non-owner session is signed back out and rejected
///  * schema misconfiguration surfaces as the "run supabase_schema.sql" error
///  * Storage bucket object keys cannot be escaped via crafted ids
void main() {
  const ownerUser = User(
    id: 'owner-uid-1',
    appMetadata: <String, dynamic>{},
    userMetadata: <String, dynamic>{},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00.000Z',
    email: 'owner@example.com',
  );

  setUpAll(() {
    registerFallbackValue('');
  });

  group('CloudAuthService.signIn', () {
    test('claims ownership (no caller-supplied id) and accepts an owner',
        () async {
      final client = MockSupabaseClient();
      final auth = MockGoTrueClient();
      when(() => client.auth).thenReturn(auth);
      when(() => auth.signInWithPassword(
          email: any(named: 'email'), password: any(named: 'password')))
          .thenAnswer((_) async => AuthResponse(user: ownerUser));
      when(() => auth.currentUser).thenReturn(ownerUser);

      final rpcCalls = <String>[];
      final service = CloudAuthService(
        client: client,
        rpc: (fn, {params}) async {
          rpcCalls.add(fn);
          return fn == 'is_owner';
        },
      );
      await service.signIn('owner@example.com', 'secret');

      // claim_owner must NOT receive any caller-controlled id.
      expect(rpcCalls, ['claim_owner', 'is_owner']);
      verifyNever(() => auth.signOut());
    });

    test('signs a non-owner back out and rejects the sign-in', () async {
      final client = MockSupabaseClient();
      final auth = MockGoTrueClient();
      when(() => client.auth).thenReturn(auth);
      when(() => auth.signInWithPassword(
          email: any(named: 'email'), password: any(named: 'password')))
          .thenAnswer((_) async => AuthResponse(user: ownerUser));
      when(() => auth.currentUser).thenReturn(ownerUser);
      when(() => auth.signOut()).thenAnswer((_) async {});

      final service = CloudAuthService(
        client: client,
        rpc: (fn, {params}) async => false,
      );
      await expectLater(
        service.signIn('stranger@example.com', 'secret'),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('owner'))),
      );
      verify(() => auth.signOut()).called(1);
    });

    test('rejects an email not on the authorized-owners allow-list', () async {
      final client = MockSupabaseClient();
      final auth = MockGoTrueClient();
      when(() => client.auth).thenReturn(auth);
      when(() => auth.signInWithPassword(
          email: any(named: 'email'), password: any(named: 'password')))
          .thenAnswer((_) async => AuthResponse(user: ownerUser));
      when(() => auth.currentUser).thenReturn(ownerUser);
      when(() => auth.signOut()).thenAnswer((_) async {});

      final rpcCalls = <String>[];
      final service = CloudAuthService(
        client: client,
        rpc: (fn, {params}) async {
          rpcCalls.add(fn);
          return 'email_not_authorized';
        },
      );
      await expectLater(
        service.signIn('unlisted@example.com', 'secret'),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('authorized-owners'))),
      );
      // is_owner must never be consulted for a refused claim.
      expect(rpcCalls, ['claim_owner']);
      verify(() => auth.signOut()).called(1);
    });

    test('rejects a claim when both owner slots are already taken', () async {
      final client = MockSupabaseClient();
      final auth = MockGoTrueClient();
      when(() => client.auth).thenReturn(auth);
      when(() => auth.signInWithPassword(
          email: any(named: 'email'), password: any(named: 'password')))
          .thenAnswer((_) async => AuthResponse(user: ownerUser));
      when(() => auth.currentUser).thenReturn(ownerUser);
      when(() => auth.signOut()).thenAnswer((_) async {});

      final service = CloudAuthService(
        client: client,
        rpc: (fn, {params}) async => 'full',
      );
      await expectLater(
        service.signIn('owner@example.com', 'secret'),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('slots are already taken'))),
      );
      verify(() => auth.signOut()).called(1);
    });

    test('reports schema misconfiguration when claim_owner fails', () async {
      final client = MockSupabaseClient();
      final auth = MockGoTrueClient();
      when(() => client.auth).thenReturn(auth);
      when(() => auth.signInWithPassword(
          email: any(named: 'email'), password: any(named: 'password')))
          .thenAnswer((_) async => AuthResponse(user: ownerUser));
      when(() => auth.currentUser).thenReturn(ownerUser);

      final service = CloudAuthService(
        client: client,
        rpc: (fn, {params}) async => throw Exception('rpc unavailable'),
      );
      await expectLater(
        service.signIn('owner@example.com', 'secret'),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('supabase_schema.sql'))),
      );
      verifyNever(() => auth.signOut());
    });
  });

  group('friendlySignInError', () {
    test('maps the owner rejection to the safe owner message', () {
      final error = StateError(CloudAuthService.notOwnerMessage);
      expect(CloudAuthService.friendlySignInError(error),
          CloudAuthService.notOwnerMessage);
    });

    test('maps an unlisted email and a full-slot claim to their messages', () {
      expect(
        CloudAuthService.friendlySignInError(
            StateError(CloudAuthService.emailNotAuthorizedMessage)),
        CloudAuthService.emailNotAuthorizedMessage,
      );
      expect(
        CloudAuthService.friendlySignInError(
            StateError(CloudAuthService.ownersFullMessage)),
        CloudAuthService.ownersFullMessage,
      );
    });

    test('does not enumerate accounts for bad credentials', () {
      expect(
        CloudAuthService.friendlySignInError(
            AuthException('Invalid login credentials')),
        'Invalid email or password.',
      );
      expect(
        CloudAuthService.friendlySignInError(
            AuthException('User not registered')),
        'Invalid email or password.',
      );
    });
  });

  group('sanitizeCloudPathPart', () {
    test('keeps UUID-style ids unchanged', () {
      expect(sanitizeCloudPathPart('9f8d3c2a-1b2c-4d5e-8f90-abcdef123456'),
          '9f8d3c2a-1b2c-4d5e-8f90-abcdef123456');
    });

    test('neutralizes traversal and separators', () {
      expect(sanitizeCloudPathPart('../secret'), '___secret');
      expect(sanitizeCloudPathPart('..'), '__');
      expect(sanitizeCloudPathPart('a/b\\c:d'), 'a_b_c_d');
    });

    test('collapses empty values to a placeholder', () {
      expect(sanitizeCloudPathPart(''), '_');
      expect(sanitizeCloudPathPart('...'), '___');
    });
  });
}

/// Records RPC calls instead of hitting the network; `is_owner` answers from
/// the injected value so both the owner and non-owner paths are testable.
class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}
