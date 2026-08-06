import 'package:flutter/material.dart';

/// Lightweight convenience extension used across the app to derive colors with
/// modified alpha (and future tweaks). Kept intentionally tiny so it cannot
/// introduce behavior changes.
extension ColorWithValues on Color {
  /// Returns a copy of this color with the given alpha (0.0 - 1.0). If
  /// [alpha] is null the original color is returned.
  Color withValues({double? alpha}) {
    if (alpha == null) return this;
    return withAlpha((alpha.clamp(0.0, 1.0) * 255).round());
  }
}
