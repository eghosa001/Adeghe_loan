import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/payment_entity.dart';
import '../../data/payment_repository.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  throw UnimplementedError('PaymentRepository requires DatabaseService injection');
});

final paymentsForLoanProvider =
    FutureProvider.family<List<Payment>, String>((ref, loanId) async {
  final repo = ref.watch(paymentRepositoryProvider);
  return repo.getPaymentsForLoan(loanId);
});
