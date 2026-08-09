import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/widgets/keyboard_refreshable.dart';
import 'package:loantrack/core/widgets/refresh_bus.dart';

void main() {
  group('RefreshBus bookkeeping', () {
    test('register/unregister/clear', () {
      final bus = RefreshBus();
      final key = GlobalKey<RefreshIndicatorState>();
      expect(bus.isEmpty, isTrue);

      bus.register(key);
      expect(bus.isEmpty, isFalse);

      bus.unregister(key);
      expect(bus.isEmpty, isTrue);

      bus.register(key);
      bus.clear();
      expect(bus.isEmpty, isTrue);
    });

    test('refreshAll skips keys without a mounted state', () async {
      final bus = RefreshBus();
      bus.register(GlobalKey<RefreshIndicatorState>());
      // Must not throw or hang with no mounted indicator.
      await bus.refreshAll();
    });
  });

  group('KeyboardRefreshable integration', () {
    testWidgets('registers with the bus and refreshAll runs onRefresh', (
      tester,
    ) async {
      var refreshCount = 0;
      final bus = RefreshBus();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [refreshBusProvider.overrideWithValue(bus)],
          child: MaterialApp(
            home: Scaffold(
              body: KeyboardRefreshable(
                onRefresh: () async => refreshCount++,
                child: ListView(
                  children: const [
                    SizedBox(height: 800, child: Text('content')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(bus.isEmpty, isFalse);

      final refreshFuture = bus.refreshAll();
      // The indicator's snap animation ticker starts on the first frame
      // (elapsed zero) and only then advances with real durations, so pump a
      // zero-duration frame first, then enough time for the animation to
      // complete and onRefresh to run (mirrors Flutter's own show() tests).
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await refreshFuture;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(refreshCount, 1);
    });

    testWidgets('unregisters on dispose so refreshAll stops calling it', (
      tester,
    ) async {
      var refreshCount = 0;
      final bus = RefreshBus();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [refreshBusProvider.overrideWithValue(bus)],
          child: MaterialApp(
            home: Scaffold(
              body: KeyboardRefreshable(
                onRefresh: () async => refreshCount++,
                child: ListView(
                  children: const [
                    SizedBox(height: 800, child: Text('content')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      // Replace the screen entirely; the Refreshable disposes.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [refreshBusProvider.overrideWithValue(bus)],
          child: const MaterialApp(home: Scaffold(body: SizedBox())),
        ),
      );
      await tester.pump();

      expect(bus.isEmpty, isTrue);

      await bus.refreshAll();
      expect(refreshCount, 0);
    });
  });
}
