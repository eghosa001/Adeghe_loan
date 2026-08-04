import 'package:flutter/services.dart';

/// Strips control characters (everything below 0x20 except tab/LF/CR, plus
/// DEL) that are invisible but bloat exports, PDF/Excel output, and UI lists
/// when pasted into a field.
class NoControlCharactersFormatter extends TextInputFormatter {
  const NoControlCharactersFormatter();

  static final RegExp _controlChars =
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final filtered = newValue.text.replaceAll(_controlChars, '');
    if (filtered == newValue.text) return newValue;
    final offset = filtered.length;
    return newValue.copyWith(
      text: filtered,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// The standard guard stack for free-text fields: strip control characters
/// and cap the length. Feed this to `inputFormatters:` on TextFormFields
/// (see AGENTS.md finding M7). Newlines are preserved for multiline notes.
List<TextInputFormatter> textFormatters({required int maxLength}) => [
      NoControlCharactersFormatter(),
      LengthLimitingTextInputFormatter(maxLength),
    ];
