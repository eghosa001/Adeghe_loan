import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/business_repository.dart';
import '../../data/models/business_profile_entity.dart';
import '../../data/models/financial_settings_entity.dart';

final businessRepoProvider = Provider<BusinessRepository>((ref) {
  return BusinessRepository(ref);
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
      final repo = ref.read(businessRepoProvider);
      final profile = await repo.getBusinessProfile();
      state = AsyncValue.data(profile);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> saveProfile(BusinessProfile profile) async {
    final repo = ref.read(businessRepoProvider);
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
  final repo = ref.read(businessRepoProvider);
  return await repo.getFinancialSettings();
});
