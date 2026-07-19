import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/payment_repository.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  throw UnimplementedError('PaymentRepository requires DatabaseService injection');
});
