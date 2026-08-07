import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../loans/data/loan_schedule_service.dart';
import '../../data/models/payment_entity.dart';
import '../../data/payment_repository.dart';

final paymentRepositoryProvider = FutureProvider<PaymentRepository>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  final scheduleService = await ref.watch(loanScheduleServiceProvider.future);
  return PaymentRepository(dbService, scheduleService: scheduleService);
});

final paymentsForLoanProvider =
    FutureProvider.family<List<Payment>, String>((ref, loanId) async {
  final repo = await ref.watch(paymentRepositoryProvider.future);
  return repo.getPaymentsForLoan(loanId);
});
