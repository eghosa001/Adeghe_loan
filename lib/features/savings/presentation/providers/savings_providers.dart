import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/savings_repository.dart';
import '../../data/models/savings_account_entity.dart';
import '../../data/models/savings_transaction_entity.dart';

final savingsRepositoryProvider = FutureProvider<SavingsRepository>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return SavingsRepository(dbService);
});

final savingsSearchQueryProvider = StateProvider<String>((ref) => '');

final allSavingsAccountsProvider =
    FutureProvider<List<SavingsAccount>>((ref) async {
  final repo = await ref.watch(savingsRepositoryProvider.future);
  return repo.getAllAccounts();
});

final filteredAccountsWithNamesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = await ref.watch(savingsRepositoryProvider.future);
  final query = ref.watch(savingsSearchQueryProvider);
  return repo.getAllAccountsWithCustomerNames(query: query);
});

final allAccountsWithNamesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = await ref.watch(savingsRepositoryProvider.future);
  return repo.getAllAccountsWithCustomerNames();
});

final savingsBalanceProvider =
    FutureProvider.family<double, String>((ref, customerId) async {
  final repo = await ref.watch(savingsRepositoryProvider.future);
  return repo.getSavingsBalance(customerId);
});

final savingsTransactionsProvider =
    FutureProvider.family<List<SavingsTransaction>, String>(
        (ref, customerId) async {
  final repo = await ref.watch(savingsRepositoryProvider.future);
  return repo.getTransactions(customerId);
});
