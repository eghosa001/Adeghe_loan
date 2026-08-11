import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../utils/platform_utils.dart';

/// Wraps a scrollable page body so the physical Up / Down / PageUp / PageDown /
/// Home / End keys scroll it on desktop without requiring the user to click
/// into the list first (Flutter's own arrow-key scrolling only works once the
/// `Scrollable` has keyboard focus). On touch platforms it is a transparent
/// passthrough that does not steal focus.
///
/// The widget autofocuses itself so it receives arrow keys on pages where
/// nothing else is focused; if a descendant (e.g. a text field) takes focus
/// instead, its own key handling wins and this wrapper only sees keys the
/// descendant did not consume.
class KeyboardScrollable extends StatefulWidget {
  const KeyboardScrollable({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardScrollable> createState() => _KeyboardScrollableState();
}

class _KeyboardScrollableState extends State<KeyboardScrollable> {
  /// Per-press step for the plain arrow keys, in logical pixels.
  static const double _arrowStep = 60.0;

  final FocusNode _focusNode = FocusNode(debugLabel: 'KeyboardScrollable');

  ScrollableState? _scrollable;

  @override
  void initState() {
    super.initState();
    if (isDesktopPlatform) {
      _scheduleCapture();
    }
  }

  @override
  void didUpdateWidget(KeyboardScrollable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (isDesktopPlatform && oldWidget.child != widget.child) {
      // The page rebuilt (async data landed, tab switched, …) so the primary
      // scrollable may have appeared / been replaced — find it again.
      _scheduleCapture();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _scheduleCapture() {
    // Capture after the frame so any scrollable that just appeared in this
    // build is already mounted when we walk the element tree.
    SchedulerBinding.instance.addPostFrameCallback((_) => _captureScrollable());
  }

  void _captureScrollable() {
    if (!mounted) return;
    ScrollableState? found;
    void visit(Element element) {
      if (found != null) return;
      final state = element is StatefulElement ? element.state : null;
      if (state is ScrollableState) {
        found = state;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    _scrollable = found;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final scrollable = _scrollable;
    if (scrollable == null || !scrollable.mounted) {
      return KeyEventResult.ignored;
    }
    final position = scrollable.position;
    if (!position.hasContentDimensions) return KeyEventResult.ignored;

    final LogicalKeyboardKey key = event.logicalKey;
    final bool homeEnd = key == LogicalKeyboardKey.home ||
        key == LogicalKeyboardKey.end;

    final double delta;
    if (key == LogicalKeyboardKey.arrowDown) {
      delta = _arrowStep;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      delta = -_arrowStep;
    } else if (key == LogicalKeyboardKey.pageDown) {
      delta = position.viewportDimension;
    } else if (key == LogicalKeyboardKey.pageUp) {
      delta = -position.viewportDimension;
    } else if (key == LogicalKeyboardKey.home) {
      delta = -position.maxScrollExtent;
    } else if (key == LogicalKeyboardKey.end) {
      delta = position.maxScrollExtent;
    } else {
      return KeyEventResult.ignored;
    }

    final double target =
        (position.pixels + delta).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ).toDouble();
    if (target == position.pixels) return KeyEventResult.ignored;

    if (homeEnd) {
      position.jumpTo(target);
    } else {
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
      );
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return widget.child;
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }
}
