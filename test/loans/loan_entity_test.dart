import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';

void main() {
  Map<String, dynamic> baseMap() => {
        'id': 'LOAN-1',
        'customer_id': 'CUS-1',
        'customer_name': 'Aisha Bello',
        'loan_type': 'daily',
        'status': 'active',
        'amount': 10000.0,
        'interest_rate': 5.0,
        'duration_days': 10,
        'loan_date': '2026-07-01',
        'start_date': '2026-07-02',
        'total_repayment': 10500.0,
        'outstanding_balance': 10500.0,
        'daily_payment': 1050.0,
        'expected_completion_date': '2026-07-11',
      };

  test('Loan.fromMap retains customer_name (regression for list crash)', () {
    final loan = Loan.fromMap(baseMap());
    expect(loan.customerName, 'Aisha Bello');
  });

  test('Loan.fromMap tolerates missing customer_name (non-list queries)', () {
    final map = baseMap()..remove('customer_name');
    final loan = Loan.fromMap(map);
    expect(loan.customerName, isNull);
  });

  test('Loan.fromMap keeps status and identifiers', () {
    final loan = Loan.fromMap(baseMap());
    expect(loan.id, 'LOAN-1');
    expect(loan.customerId, 'CUS-1');
    expect(loan.status, LoanStatus.active);
  });
}
