import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_constants.dart';

class InactivityWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback? onInactivity;
  final Duration timeout;

  const InactivityWrapper(
      {super.key,
      required this.child,
      this.onInactivity,
      this.timeout = AppConstants.defaultInactivityTimeout});

  @override
  State<InactivityWrapper> createState() => _InactivityWrapperState();
}

class _InactivityWrapperState extends State<InactivityWrapper> {
  Timer? _timer;

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, () {
      widget.onInactivity?.call();
    });
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) _resetTimer();
    return false;
  }

  @override
  void initState() {
    super.initState();
    _resetTimer();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void didUpdateWidget(covariant InactivityWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-arm when the configured session-timeout setting changes so the new
    // timeout applies without a restart.
    if (oldWidget.timeout != widget.timeout) _resetTimer();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listener (rather than GestureDetector) also catches mouse-wheel scrolls
    // and pointer moves; the global keyboard handler catches typing.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetTimer(),
      onPointerMove: (_) => _resetTimer(),
      onPointerSignal: (_) => _resetTimer(),
      child: widget.child,
    );
  }
}
