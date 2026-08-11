import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'keyboard_scrollable.dart';
import 'refresh_bus.dart';

/// A [RefreshIndicator] that also registers itself with the global
/// [RefreshBus], so the desktop refresh shortcut (F5 / Ctrl+R) triggers this
/// screen's refresh exactly like a pull-to-refresh gesture would on touch
/// devices. On desktop it additionally wraps its child in [KeyboardScrollable]
/// so the physical Up / Down / PageUp / PageDown / Home / End keys scroll the
/// list. On touch platforms it behaves as a plain [RefreshIndicator].
class KeyboardRefreshable extends ConsumerStatefulWidget {
  const KeyboardRefreshable({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final RefreshCallback onRefresh;
  final Widget child;

  @override
  ConsumerState<KeyboardRefreshable> createState() =>
      _KeyboardRefreshableState();
}

class _KeyboardRefreshableState extends ConsumerState<KeyboardRefreshable> {
  final GlobalKey<RefreshIndicatorState> _indicatorKey =
      GlobalKey<RefreshIndicatorState>();

  // Cached at initState: `ref` cannot be used from dispose().
  RefreshBus? _bus;

  @override
  void initState() {
    super.initState();
    _bus = ref.read(refreshBusProvider);
    _bus!.register(_indicatorKey);
  }

  @override
  void dispose() {
    _bus?.unregister(_indicatorKey);
    _bus = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardScrollable(
      child: RefreshIndicator(
        key: _indicatorKey,
        onRefresh: widget.onRefresh,
        child: widget.child,
      ),
    );
  }
}
