import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_service.dart';
import 'models/business_profile_entity.dart';
import 'models/financial_settings_entity.dart';

class BusinessRepository {
  BusinessRepository(this._dbService);
  final DatabaseService _dbService;

  Future<Database> get _db async => _dbService.database;

  Future<void> saveBusinessProfile(BusinessProfile profile) async {
    final db = await _db;
    await db.insert('business_profile', profile.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<BusinessProfile?> getBusinessProfile() async {
    final db = await _db;
    final maps = await db.query('business_profile');
    if (maps.isNotEmpty) return BusinessProfile.fromMap(maps.first);
    return null;
  }

  Future<void> saveSettings(Map<String, String> settings) async {
    final db = await _db;
    final batch = db.batch();
    settings.forEach((k, v) {
      batch.insert('settings', {'key': k, 'value': v},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await batch.commit(noResult: true);
  }

  Future<String?> getSetting(String key) async {
    final db = await _db;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<FinancialSettings> getFinancialSettings() async {
    final db = await _db;
    final maps = await db.query('settings');
    final map = {for (var e in maps) e['key'] as String: e['value'] as String};
    return FinancialSettings(
      currency: map['currency'] ?? '₦',
      defaultInterestRate: _finiteDouble(map['default_interest']),
      defaultInsuranceFee: _finiteDouble(map['default_insurance']),
      defaultCommission: _finiteDouble(map['default_commission']),
      defaultProcessingFee: _finiteDouble(map['default_processing']),
      defaultPenaltyRules: map['default_penalty_rules'] ?? '',
      defaultLoanDurationDays: _finiteDuration(map['default_loan_duration_days']),
      defaultLoanType: map['default_loan_type'] ?? 'daily',
    );
  }

  /// Parses a stored settings value into a finite non-negative double. Guards
  /// against legacy rows where `double.tryParse('Infinity')` (from a "1e309"
  /// save) would otherwise poison every new loan calculation.
  double _finiteDouble(String? raw) {
    final v = double.tryParse(raw ?? '');
    return (v != null && v.isFinite && v >= 0) ? v : 0.0;
  }

  /// Parses a stored duration into a sane installments count (1..max).
  int _finiteDuration(String? raw) {
    final v = int.tryParse(raw ?? '');
    if (v == null || v < 1 || v > AppConstants.maxLoanDuration) return 30;
    return v;
  }
}
