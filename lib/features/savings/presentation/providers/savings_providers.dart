import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/savings_repository.dart';
import '../../data/models/savings_account_entity.dart';

export '../../data/models/savings_account_entity.dart';

final savingsRepositoryProvider = FutureProvider<SavingsRepository>((ref) async {
  final service = await ref.watch(databaseServiceProvider.future);
  return SavingsRepository(service);
});

final savingsAccountProvider =
    FutureProvider.family<SavingsAccount?, String>((ref, customerId) async {
  final repo = await ref.watch(savingsRepositoryProvider.future);
  return repo.getByCustomer(customerId);
});

final savingsTransactionsProvider =
    FutureProvider.family<List<SavingsTransaction>, String>((ref, customerId) async {
  final repo = await ref.watch(savingsRepositoryProvider.future);
  return repo.getTransactions(customerId);
});

final totalSavingsBalanceProvider = FutureProvider<double>((ref) async {
  final repo = await ref.watch(savingsRepositoryProvider.future);
  return repo.totalSavingsBalance();
});
