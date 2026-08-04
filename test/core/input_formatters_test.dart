import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/utils/input_formatters.dart';

void main() {
  group('NoControlCharactersFormatter', () {
    final formatter = NoControlCharactersFormatter();

    test('keeps normal text unchanged', () {
      final value = const TextEditingValue(text: 'Hello Ada');
      final result =
          formatter.formatEditUpdate(const TextEditingValue(), value);
      expect(result.text, 'Hello Ada');
    });

    test('strips null, vertical-tab, and DEL control characters', () {
      final result = formatter.formatEditUpdate(
          const TextEditingValue(), const TextEditingValue(text: 'A\x00B\x0B C\x7F'));
      expect(result.text, 'AB C');
    });

    test('preserves newline and tab for multiline notes', () {
      final result = formatter.formatEditUpdate(const TextEditingValue(),
          const TextEditingValue(text: 'line1\n\tline2'));
      expect(result.text, 'line1\n\tline2');
    });
  });

  group('textFormatters', () {
    test('caps input length', () {
      final formatters = textFormatters(maxLength: 5);
      final result = formatters.last.formatEditUpdate(
          const TextEditingValue(), const TextEditingValue(text: '1234567890'));
      expect(result.text, '12345');
    });

    test('strips control characters then caps', () {
      final formatters = textFormatters(maxLength: 3);
      var result = formatters.first.formatEditUpdate(
          const TextEditingValue(), const TextEditingValue(text: 'a\x00b'));
      result = formatters.last.formatEditUpdate(const TextEditingValue(), result);
      expect(result.text, 'ab');
    });
  });
}
