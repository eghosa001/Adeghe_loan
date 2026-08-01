import 'dart:async';

import 'package:flutter/material.dart';

/// A [TextField] that defers [onChanged] until the user stops typing for
/// [debounceDuration]. Keeps DB-backed search providers from re-running
/// their query on every keystroke.
class DebouncedTextField extends StatefulWidget {
  const DebouncedTextField({
    super.key,
    required this.onChanged,
    this.controller,
    this.initialValue = '',
    this.debounceDuration = const Duration(milliseconds: 300),
    this.decoration,
    this.textInputAction,
    this.onSubmitted,
  });

  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final String initialValue;
  final Duration debounceDuration;
  final InputDecoration? decoration;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<DebouncedTextField> createState() => _DebouncedTextFieldState();
}

class _DebouncedTextFieldState extends State<DebouncedTextField> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(widget.debounceDuration, () {
      if (mounted) widget.onChanged(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: _onChanged,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      decoration: widget.decoration,
    );
  }
}
