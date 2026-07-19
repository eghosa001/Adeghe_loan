import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/di/providers.dart';
import 'models/business_profile_entity.dart';
import 'models/financial_settings_entity.dart';

class BusinessRepository {
  final Ref ref;
  BusinessRepository(this.ref);

  Future<Database> _db() async {
    final dbService = await ref.read(databaseServiceProvider.future);
    return await dbService.database;
  }

  Future<void> saveBusinessProfile(BusinessProfile profile) async {
    final db = await _db();
    await db.insert('business_profile', profile.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<BusinessProfile?> getBusinessProfile() async {
    final db = await _db();
    final maps = await db.query('business_profile');
    if (maps.isNotEmpty) return BusinessProfile.fromMap(maps.first);
    return null;
  }

  Future<void> saveSettings(Map<String, String> settings) async {
    final db = await _db();
    final batch = db.batch();
    settings.forEach((k, v) {
      batch.insert('settings', {'key': k, 'value': v},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await batch.commit(noResult: true);
  }

  Future<FinancialSettings> getFinancialSettings() async {
    final db = await _db();
    final maps = await db.query('settings');
    final map = {for (var e in maps) e['key'] as String: e['value'] as String};
    return FinancialSettings(
      currency: map['currency'] ?? '₦',
      defaultInterestRate:
          double.tryParse(map['default_interest'] ?? '0') ?? 0.0,
      defaultInsuranceFee:
          double.tryParse(map['default_insurance'] ?? '0') ?? 0.0,
      defaultCommission:
          double.tryParse(map['default_commission'] ?? '0') ?? 0.0,
      defaultProcessingFee:
          double.tryParse(map['default_processing'] ?? '0') ?? 0.0,
      defaultPenaltyRules: map['default_penalty_rules'] ?? '',
    );
  }
}
