import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';

Map<String, dynamic> _validLoan() => {
      'id': 'loan-1',
      'customer_id': 'customer-1',
      'loan_type': 'daily',
      'status': 'active',
      'amount': 10000.0,
      'interest_rate': 15.0,
      'insurance_fee': 0.0,
      'commission': 0.0,
      'processing_fee': 0.0,
      'admin_fee': 0.0,
      'other_charges': 0.0,
      'duration_days': 23,
      'duration_weeks': null,
      'daily_payment': 500.0,
      'weekly_payment': null,
      'loan_date': '2026-09-01T00:00:00.000Z',
      'start_date': '2026-09-02T00:00:00.000Z',
      'total_repayment': 11500.0,
      'outstanding_balance': 11500.0,
      'expected_completion_date': '2026-09-30T00:00:00.000Z',
    };

void main() {
  test('rejects unknown loan type instead of defaulting to daily', () {
    final row = _validLoan()..['loan_type'] = 'future_type';
    expect(() => Loan.fromMap(row), throwsFormatException);
  });

  test('rejects unknown loan status instead of defaulting to active', () {
    final row = _validLoan()..['status'] = 'future_status';
    expect(() => Loan.fromMap(row), throwsFormatException);
  });

  test('rejects malformed loan date instead of substituting now', () {
    final row = _validLoan()..['loan_date'] = 'not-a-date';
    expect(() => Loan.fromMap(row), throwsFormatException);
  });

  test('rejects non-finite financial values', () {
    final row = _validLoan()..['amount'] = double.nan;
    expect(() => Loan.fromMap(row), throwsFormatException);
  });

  test('rejects missing duration instead of silently using one', () {
    final row = _validLoan()..['duration_days'] = null;
    expect(() => Loan.fromMap(row), throwsFormatException);
  });

  test('does not silently clamp an invalid duration', () {
    final row = _validLoan()..['duration_days'] = 9999;
    final loan = Loan.fromMap(row);
    expect(loan.duration, 9999);
  });

  test('rejects total repayment below amount disbursed', () {
    final row = _validLoan()..['total_repayment'] = 9999.99;
    expect(() => Loan.fromMap(row), throwsFormatException);
  });

  test('rejects outstanding balance above total repayment', () {
    final row = _validLoan()..['outstanding_balance'] = 11500.01;
    expect(() => Loan.fromMap(row), throwsFormatException);
  });
}
