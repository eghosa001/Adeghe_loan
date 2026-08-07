class AppConstants {
  AppConstants._();

  static const String appName = 'Adeghe Professional Services';
  static const String appVersion = '1.0.0';
  static const int appBuildNumber = 1;

  // Database
  static const String databaseName = 'adeghe_loans.db';

  static const String tableCustomers = 'customers';
  static const String tableLoans = 'loans';
  static const String tableRepaymentSchedule = 'repayment_schedule';
  static const String tablePayments = 'payments';
  static const String tableBusinessProfile = 'business_profile';
  static const String tableDocuments = 'documents';
  static const String tableHolidays = 'holidays';
  static const String tableAuditLog = 'audit_logs';
  static const String tableSettings = 'settings';

  // Secure storage keys
  static const String keyPinHash = 'secure_pin_hash';
  static const String keyPinSalt = 'secure_pin_salt';
  static const String keyRecoverySalt = 'secure_recovery_salt';
  static const String keyBiometricEnabled = 'secure_biometric_enabled';
  static const String keyEncryptionKey = 'secure_file_encryption_key';
  static const String keyFailedAttempts = 'secure_failed_pin_attempts';
  static const String keyLockoutUntil = 'secure_lockout_until';
  static const String keyLockoutCycles = 'secure_lockout_cycles';
  static const String keyPermanentLock = 'secure_permanent_lock';
  static const String keyRecoveryPasswordHash = 'secure_recovery_password_hash';

  // Shared preference keys
  static const String prefFirstLaunch = 'pref_first_launch';
  static const String prefThemeMode = 'pref_theme_mode';
  static const String prefLastBackupDate = 'pref_last_backup_date';
  static const String prefAutoBackupEnabled = 'pref_auto_backup_enabled';
  static const String prefCurrencyCode = 'pref_currency_code';
  static const String prefLocale = 'pref_locale';
  static const String prefSessionTimeoutMinutes = 'pref_session_timeout_minutes';

  // Auth / security
  static const int pinLength = 4;
  static const int maxPinLength = pinLength;
  static const int maxPinAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 5);
  // Lockout length doubles per cycle: 5m, 10m, 20m, 40m, then permanent.
  static const int maxLockoutCycles = 5;
  static const Duration lockoutMaxDuration = Duration(hours: 24);
  static const Duration defaultInactivityTimeout = Duration(minutes: 5);

  // Loans
  static const double minLoanAmount = 1000;
  static const double maxLoanAmount = 50000000;
  static const int minLoanTermInDays = 7;
  static const int maxLoanTermInDays = 365;
  static const double defaultInterestRate = 5.0;

  // Upper bound for the duration field (days for daily loans, weeks for
  // weekly loans). Guards against a typo like "9999999999" allocating an
  // unbounded repayment schedule (`List.generate`) that OOMs the device.
  static const int maxLoanDuration = 365;

  // Free-text field limits (finding M7: no inputFormatters/length caps
  // anywhere). Length caps prevent multi-KB pasted strings from bloating
  // exports/PDFs; the control-character strip is applied in
  // core/utils/input_formatters.dart.
  static const int maxNameLength = 100;
  static const int maxPhoneLength = 20;
  static const int maxEmailLength = 120;
  static const int maxAddressLength = 200;
  static const int maxNotesLength = 2000;
  static const int maxGroupNameLength = 80;
  static const int maxGroupDescriptionLength = 300;
  static const int maxReferenceLength = 50;
  static const int maxIdentifierLength = 11; // NIN / BVN

  // Session timeout (minutes) bounds for the auto-lock setting (finding M10).
  static const int minSessionTimeoutMinutes = 1;
  static const int maxSessionTimeoutMinutes = 120;

  // Pagination / limits
  static const int defaultPageSize = 25;
  static const int recentItemsLimit = 10;
  static const int maxDocumentSizeBytes = 20 * 1024 * 1024;

  // Image preview safety caps (security: decompression-bomb bounds).
  // The preview decodes images at, and never wider than, this dimension so a
  // crafted file with huge intrinsic dimensions cannot exhaust device memory.
  static const int maxDocumentImageDimension = 2048;

  // Backup
  static const String backupFileExtension = '.ltbackup';
  static const String backupFolderName = 'Adeghe_Backups';

  // How long after unlock before the once-per-24h auto-backup may run. Deferred
  // so a cold start is not slowed by a multi-MB disk write racing the database
  // providers that are still initializing at unlock.
  static const Duration autoBackupDelay = Duration(seconds: 15);

  // Formats / locale defaults
  static const String dateFormatDisplay = 'dd MMM yyyy';
  static const String dateFormatApi = 'yyyy-MM-dd';
  static const String dateTimeFormatDisplay = 'dd MMM yyyy, hh:mm a';
  static const String defaultCurrencySymbol = '\u20A6';
  static const String defaultCurrencyCode = 'NGN';
  static const String defaultLocale = 'en_NG';
}
