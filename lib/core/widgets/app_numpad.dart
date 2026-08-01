import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// A shared numeric keypad widget used by PIN login and setup screens.
class AppNumpad extends StatelessWidget {
  const AppNumpad({
    super.key,
    required this.onKeyPressed,
    required this.onDelete,
    this.keyColor = Colors.white,
    this.keyAlpha = 0.08,
    this.borderColor,
    this.textColor = Colors.white,
  });

  final ValueChanged<String> onKeyPressed;
  final VoidCallback onDelete;

  /// Color of the key text and delete icon.
  final Color keyColor;

  /// Opacity of the key background.
  final double keyAlpha;

  /// Override border color (defaults to [keyColor] at 12% opacity).
  final Color? borderColor;

  /// Text/icon color for keys.
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final effectiveBorder = borderColor ?? textColor.withValues(alpha: 0.12);

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
                            onKeyPressed(k);
                          },
                          keyColor: keyColor,
                          keyAlpha: keyAlpha,
                          borderColor: effectiveBorder,
                          textColor: textColor,
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
                    onKeyPressed('0');
                  },
                  keyColor: keyColor,
                  keyAlpha: keyAlpha,
                  borderColor: effectiveBorder,
                  textColor: textColor,
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onDelete();
                  },
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: textColor.withValues(alpha: 0.05),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.backspace_outlined,
                        color: textColor.withValues(alpha: 0.6),
                        size: 22,
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
    return GestureDetector(
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
    );
  }
}
