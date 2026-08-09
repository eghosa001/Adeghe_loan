import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Collects every mounted [RefreshIndicator] so a desktop keyboard shortcut
/// (F5 / Ctrl+R) can trigger the same refresh a pull gesture does on touch
/// devices. Screens register through [Refreshable] and unregister on dispose.
class RefreshBus {
  final Set<GlobalKey<RefreshIndicatorState>> _keys = {};

  bool get isEmpty => _keys.isEmpty;

  void register(GlobalKey<RefreshIndicatorState> key) => _keys.add(key);

  void unregister(GlobalKey<RefreshIndicatorState> key) => _keys.remove(key);

  void clear() => _keys.clear();

  /// Runs every registered, mounted indicator's onRefresh in turn. A failing
  /// refresh on one screen must not block the remaining screens.
  Future<void> refreshAll() async {
    for (final key in List<GlobalKey<RefreshIndicatorState>>.of(_keys)) {
      final state = key.currentState;
      if (state == null || !state.mounted) continue;
      try {
        await state.show();
      } catch (_) {
        // The screen surfaces its own refresh errors; never abort the rest.
      }
    }
  }
}

final refreshBusProvider = Provider<RefreshBus>((ref) {
  final bus = RefreshBus();
  ref.onDispose(bus.clear);
  return bus;
});
