import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AuthState { locked, unlocked, initialSetup }

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState.locked);

  void unlock() => state = AuthState.unlocked;
  void lock() => state = AuthState.locked;
  void requireSetup() => state = AuthState.initialSetup;
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
