import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/providers.dart';
import '../../data/business_repository.dart';
import '../../data/models/business_profile_entity.dart';
import '../../data/models/financial_settings_entity.dart';

final businessRepoProvider = FutureProvider<BusinessRepository>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return BusinessRepository(dbService);
});

/// Session auto-lock timeout in minutes from the settings table (default 5).
/// Invalidate after changing the setting so the active timeout updates live.
final sessionTimeoutMinutesProvider = FutureProvider<int>((ref) async {
  final repo = await ref.read(businessRepoProvider.future);
  final value = await repo.getSetting('session_timeout_minutes');
  return int.tryParse(value ?? '') ??
      AppConstants.defaultInactivityTimeout.inMinutes;
});

class BusinessProfileNotifier
    extends StateNotifier<AsyncValue<BusinessProfile?>> {
  final Ref ref;
  BusinessProfileNotifier(this.ref) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final repo = await ref.read(businessRepoProvider.future);
      final profile = await repo.getBusinessProfile();
      state = AsyncValue.data(profile);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> saveProfile(BusinessProfile profile) async {
    final repo = await ref.read(businessRepoProvider.future);
    await repo.saveBusinessProfile(profile);
    state = AsyncValue.data(profile);
  }
}

final businessProfileProvider = StateNotifierProvider<BusinessProfileNotifier,
    AsyncValue<BusinessProfile?>>((ref) {
  return BusinessProfileNotifier(ref);
});

final financialSettingsProvider =
    FutureProvider<FinancialSettings>((ref) async {
  final repo = await ref.read(businessRepoProvider.future);
  return await repo.getFinancialSettings();
});

/// The configured currency symbol for display in amount fields and prefixes.
final currencySymbolProvider = FutureProvider<String>((ref) async {
  final settings = await ref.read(financialSettingsProvider.future);
  return settings.currency.isNotEmpty
      ? settings.currency
      : AppConstants.defaultCurrencySymbol;
});
