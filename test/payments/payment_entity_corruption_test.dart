import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/payments/data/models/payment_entity.dart';

Map<String, Object?> _validPayment() => {
      'id': 'payment-1',
      'loan_id': 'loan-1',
      'customer_id': 'customer-1',
      'amount': 1000.0,
      'payment_date': '2026-09-05T10:00:00.000Z',
      'payment_method': 'cash',
      'receipt_no': 'REC-1',
      'collector': 'Collector',
      'type': 'partial',
      'status': 'completed',
    };

void main() {
  test('rejects non-finite payment amount instead of accepting corrupt data', () {
    final row = _validPayment()..['amount'] = double.nan;
    expect(() => Payment.fromMap(row), throwsFormatException);
  });

  test('rejects malformed payment date instead of substituting current time', () {
    final row = _validPayment()..['payment_date'] = 'not-a-date';
    expect(() => Payment.fromMap(row), throwsFormatException);
  });

  test('rejects unknown payment method instead of silently converting to cash', () {
    final row = _validPayment()..['payment_method'] = 'future_method';
    expect(() => Payment.fromMap(row), throwsFormatException);
  });
}
