import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/utils/currency_utils.dart';

void main() {
  group('roundToCents', () {
    test('rounds normal values to 2 decimals', () {
      expect(CurrencyUtils.roundToCents(12.345), 12.35);
      expect(CurrencyUtils.roundToCents(10000), 10000.0);
    });

    test('NaN rounds to 0 instead of throwing (1e309 crash guard)', () {
      expect(CurrencyUtils.roundToCents(double.nan), 0);
    });

    test('Infinity rounds to 0 instead of throwing', () {
      expect(CurrencyUtils.roundToCents(double.infinity), 0);
      expect(CurrencyUtils.roundToCents(double.negativeInfinity), 0);
    });

    test('finite-but-huge value does not overflow (1e307 crash guard)', () {
      // amount * 100 overflows Infinity; must not throw on .round().
      expect(CurrencyUtils.roundToCents(1e307), 1e307);
      expect(CurrencyUtils.roundToCents(1e300).isFinite, isTrue);
    });
  });

  group('splitEvenly', () {
    test('sum of installments equals total', () {
      final amounts = CurrencyUtils.splitEvenly(10001, 3);
      expect(amounts.fold<double>(0, (a, b) => a + b), closeTo(10001, 0.001));
    });

    test('non-finite total returns an empty list (OOM guard)', () {
      expect(CurrencyUtils.splitEvenly(double.infinity, 100), isEmpty);
      expect(CurrencyUtils.splitEvenly(double.nan, 100), isEmpty);
    });

    test('non-positive parts return an empty list', () {
      expect(CurrencyUtils.splitEvenly(1000, 0), isEmpty);
      expect(CurrencyUtils.splitEvenly(1000, -5), isEmpty);
    });

    test('finite-but-huge total does not overflow (1e307 crash guard)', () {
      final amounts = CurrencyUtils.splitEvenly(1e307, 3);
      expect(amounts.length, 3);
      expect(amounts.every((a) => a.isFinite), isTrue);
      expect(amounts.fold<double>(0, (a, b) => a + b), closeTo(1e307, 1e293));
    });
  });

  group('tryParseAmount', () {
    test('parses plain and decimal numbers', () {
      expect(CurrencyUtils.tryParseAmount('1000'), 1000);
      expect(CurrencyUtils.tryParseAmount('12.50'), 12.5);
      expect(CurrencyUtils.tryParseAmount(' 42 '), 42);
    });

    test('rejects NaN and Infinity', () {
      expect(CurrencyUtils.tryParseAmount('1e309'), isNull); // Infinity
      expect(CurrencyUtils.tryParseAmount('NaN'), isNull);
      expect(CurrencyUtils.tryParseAmount('-1e309'), isNull);
    });

    test('rejects negatives and non-numbers', () {
      expect(CurrencyUtils.tryParseAmount('-5'), isNull);
      expect(CurrencyUtils.tryParseAmount('abc'), isNull);
      expect(CurrencyUtils.tryParseAmount(''), isNull);
      expect(CurrencyUtils.tryParseAmount(null), isNull);
    });
  });

  group('tryParsePositiveAmount', () {
    test('accepts only strictly positive finite values', () {
      expect(CurrencyUtils.tryParsePositiveAmount('500'), 500);
      expect(CurrencyUtils.tryParsePositiveAmount('0'), isNull);
      expect(CurrencyUtils.tryParsePositiveAmount('-1'), isNull);
      expect(CurrencyUtils.tryParsePositiveAmount('1e309'), isNull);
      expect(CurrencyUtils.tryParsePositiveAmount('NaN'), isNull);
    });
  });
}
