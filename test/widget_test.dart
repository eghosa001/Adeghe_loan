// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/customers/data/models/customer_entity.dart';

void main() {
  test('customer mapping retains its status and identifiers', () {
    const customer = Customer(
      id: 'CUS-1001',
      fullName: 'Ada Okafor',
      phone: '08030000000',
      dateRegistered: '2026-07-18',
      status: CustomerStatus.blacklisted,
    );
    final restored = Customer.fromMap(customer.toMap());
    expect(restored.id, 'CUS-1001');
    expect(restored.status, CustomerStatus.blacklisted);
  });
}
