import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// A shared numeric keypad widget used by PIN login and setup screens.
class AppNumpad extends StatelessWidget {
  const AppNumpad({
    super.key,
    required this.onKeyPressed,
    required this.onDelete,
    this.enabled = true,
  });

  final ValueChanged<String> onKeyPressed;
  final VoidCallback onDelete;

  /// When false the keys are visually dimmed and taps are ignored (e.g. while
  /// the PIN is locked out).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final dimmed = !enabled;
    final effectiveBorder = Colors.white.withValues(alpha: 0.12);
    final effectiveTextColor =
        dimmed ? Colors.white.withValues(alpha: 0.3) : Colors.white;
    final effectiveKeyColor =
        dimmed ? Colors.white.withValues(alpha: 0.08) : Colors.white;

    void invoke(VoidCallback callback) {
      if (enabled) callback();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          for (final row in [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: row
                    .map((k) => _Key(
                          label: k,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            invoke(() => onKeyPressed(k));
                          },
                          keyColor: effectiveKeyColor,
                          keyAlpha: 0.08,
                          borderColor: effectiveBorder,
                          textColor: effectiveTextColor,
                        ))
                    .toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                const SizedBox(width: 68),
                _Key(
                  label: '0',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    invoke(() => onKeyPressed('0'));
                  },
                  keyColor: effectiveKeyColor,
                  keyAlpha: 0.08,
                  borderColor: effectiveBorder,
                  textColor: effectiveTextColor,
                ),
                Semantics(
                  button: true,
                  label: 'Delete',
                  onTap: () => invoke(onDelete),
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      invoke(onDelete);
                    },
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: effectiveTextColor.withValues(alpha: 0.05),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.backspace_outlined,
                          color: effectiveTextColor.withValues(alpha: 0.6),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.onTap,
    required this.keyColor,
    required this.keyAlpha,
    required this.borderColor,
    required this.textColor,
  });

  final String label;
  final VoidCallback onTap;
  final Color keyColor;
  final double keyAlpha;
  final Color borderColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: keyColor.withValues(alpha: keyAlpha),
            border: Border.all(color: borderColor),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
