import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/savings_repository.dart';
import '../../data/models/savings_transaction_entity.dart';

final savingsRepositoryProvider = Provider<SavingsRepository>((ref) {
  return SavingsRepository(ref);
});

final savingsBalanceProvider =
    FutureProvider.family<double, String>((ref, customerId) {
  return ref.watch(savingsRepositoryProvider).getSavingsBalance(customerId);
});

final savingsTransactionsProvider =
    FutureProvider.family<List<SavingsTransaction>, String>(
        (ref, customerId) async {
  return ref.watch(savingsRepositoryProvider).getTransactions(customerId);
});
