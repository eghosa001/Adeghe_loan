import 'dart:async';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _resetTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _resetTimer,
      onPanDown: (_) => _resetTimer(),
      child: widget.child,
    );
  }
}
