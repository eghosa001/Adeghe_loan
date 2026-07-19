import 'package:flutter/material.dart';

class PinKeyboard extends StatelessWidget {
  final void Function(String key) onKey;
  final VoidCallback? onDelete;
  final VoidCallback? onBiometric;

  const PinKeyboard({
    super.key,
    required this.onKey,
    this.onDelete,
    this.onBiometric,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildRow(['1', '2', '3']),
        const SizedBox(height: 12),
        _buildRow(['4', '5', '6']),
        const SizedBox(height: 12),
        _buildRow(['7', '8', '9']),
        const SizedBox(height: 12),
        _buildBottomRow(),
      ],
    );
  }

  Widget _buildRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys
          .map((k) => _PinKey(
                label: k,
                onTap: () => onKey(k),
              ))
          .toList(),
    );
  }

  Widget _buildBottomRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (onBiometric != null)
          _PinKey(
            icon: Icons.fingerprint,
            onTap: onBiometric!,
          )
        else
          const SizedBox(width: 64),
        _PinKey(
          label: '0',
          onTap: () => onKey('0'),
        ),
        if (onDelete != null)
          _PinKey(
            icon: Icons.backspace_outlined,
            onTap: onDelete!,
          )
        else
          const SizedBox(width: 64),
      ],
    );
  }
}

class _PinKey extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  const _PinKey({this.label, this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, size: 24)
            : Text(label!,
                style: Theme.of(context).textTheme.headlineSmall),
      ),
    );
  }
}
