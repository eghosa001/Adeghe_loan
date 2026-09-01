from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

def edit(rel, fn):
    p = ROOT / rel
    s = p.read_text(encoding='utf-8-sig')
    n = fn(s)
    if n == s:
        raise RuntimeError(f'No change made to {rel}')
    p.write_text(n, encoding='utf-8')

def replace_once(s, old, new, label):
    if old not in s:
        raise RuntimeError(f'Missing expected block: {label}')
    return s.replace(old, new, 1)

# 1. Never delete a live financial database after SQLCipher error 26.
def dbfix(s):
    old = '''      // Sqlite error 26 = "file is not a database". This happens when the\n      // encryption key doesn't match the one used to create the database\n      // (e.g. after a secure storage reset but the DB file remains).\n      // The data is unrecoverable with the wrong key, so we delete the corrupt\n      // file and let the next open create a fresh database.\n      final message = e.toString();\n      if (message.contains('SqliteException(26)') ||\n          message.contains('file is not a database')) {\n        final file = File(path);\n        if (await file.exists()) {\n          await file.delete();\n        }\n        return databaseFactoryFfi.openDatabase(\n          path,\n          options: OpenDatabaseOptions(\n            version: _databaseVersion,\n            onCreate: _onCreate,\n            onConfigure: (db) async {\n              await db.execute(_cipherKeySql(encryptionKey));\n              await _onConfigure(db);\n            },\n            onUpgrade: _onUpgrade,\n            onOpen: _onOpen,\n          ),\n        );\n      }'''
    new = '''      // Error 26 is a recovery condition, never permission to destroy the\n      // operator's financial history. Preserve the original file and stop.\n      final message = e.toString();\n      if (message.contains('SqliteException(26)') ||\n          message.contains('file is not a database')) {\n        final file = File(path);\n        String recoveryPath = path;\n        if (await file.exists()) {\n          final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');\n          final recovery = File('$path.recovery-$stamp');\n          try {\n            await file.copy(recovery.path);\n            recoveryPath = recovery.path;\n          } catch (_) {}\n        }\n        throw DatabaseRecoveryException(\n          'The Adeghe Loan database could not be opened safely. No data was deleted. Recovery copy: $recoveryPath',\n          recoveryPath,\n        );\n      }'''
    s = replace_once(s, old, new, 'windows database deletion')
    marker = '''  static String _cipherKeySql(String encryptionKey) {'''
    exc = '''  /// Signals that opening the encrypted database requires operator recovery.\n  class DatabaseRecoveryException implements Exception {\n    const DatabaseRecoveryException(this.message, this.recoveryPath);\n    final String message;\n    final String recoveryPath;\n    @override\n    String toString() => message;\n  }\n\n'''
    return replace_once(s, marker, exc + marker, 'recovery exception')
edit('lib/core/database/database_service.dart', dbfix)

# 2. Remove committed cloud defaults; require build-time configuration.
def configfix(s):
    s = re.sub(r"static const String supabaseUrl = String.fromEnvironment\(\n    'SUPABASE_URL',\n    defaultValue: 'https://[^']+',\n  \);", "static const String supabaseUrl = String.fromEnvironment(\n    'SUPABASE_URL',\n    defaultValue: '',\n  );", s, count=1)
    s = re.sub(r"static const String anonKey = String.fromEnvironment\(\n    'SUPABASE_ANON_KEY',\n    defaultValue:\n        '[^']+', // nosemgrep: generic.secrets.security.detected-jwt-token.detected-jwt-token\n  \);", "static const String anonKey = String.fromEnvironment(\n    'SUPABASE_ANON_KEY',\n    defaultValue: '',\n  );", s, count=1)
    s = s.replace('static const int anonKeyExpiresAtEpochSeconds = 2101185634;', 'static const int anonKeyExpiresAtEpochSeconds = 0;')
    s = s.replace('static int anonKeySecondsToExpiry() =>\n      anonKeyExpiresAtEpochSeconds -', "static int anonKeySecondsToExpiry() =>\n      anonKeyExpiresAtEpochSeconds == 0 ? 0 : anonKeyExpiresAtEpochSeconds -")
    return s
edit('lib/core/cloud/supabase_config.dart', configfix)

# 3. Exact integer-minor-unit helpers; existing DB doubles remain compatible at boundaries.
def currencyfix(s):
    marker = '''  /// Parses [text] as a finite, non-negative number, or returns null.'''
    add = '''  /// Exact currency arithmetic boundary: naira -> kobo/cents.\n  static int toMinorUnits(num amount) {\n    if (!amount.isFinite) throw ArgumentError.value(amount, 'amount');\n    final scaled = amount * 100;\n    if (!scaled.isFinite) throw ArgumentError.value(amount, 'amount');\n    return scaled.round();\n  }\n\n  static double fromMinorUnits(int amount) => amount / 100.0;\n\n  static int? tryParseMinorUnits(String? text) {\n    final value = tryParseAmount(text);\n    return value == null ? null : toMinorUnits(value);\n  }\n\n'''
    return replace_once(s, marker, add + marker, 'currency minor-unit helpers')
edit('lib/core/utils/currency_utils.dart', currencyfix)

# 4. Loan calculator computes monetary components in integer minor units.
def loancalc(s):
    old = '''    final interestAmount = principal * (interestRatePercent / 100);\n    final insuranceFeeAmount = principal * (insuranceFeePercent / 100);\n    final commissionAmount = principal * (commissionPercent / 100);\n    final totalCharges = insuranceFeeAmount + commissionAmount + processingFee + administrativeFee + otherCharges;\n    final totalRepayment = principal + interestAmount + totalCharges;\n    final installmentAmount = totalRepayment / duration;\n\n    return LoanCalculationResult(\n      principal: principal,\n      interestAmount: CurrencyUtils.roundToCents(interestAmount),\n      insuranceFeeAmount: CurrencyUtils.roundToCents(insuranceFeeAmount),\n      commissionAmount: CurrencyUtils.roundToCents(commissionAmount),\n      totalCharges: CurrencyUtils.roundToCents(totalCharges),\n      totalRepayment: CurrencyUtils.roundToCents(totalRepayment),\n      installmentAmount: CurrencyUtils.roundToCents(installmentAmount),\n    );'''
    new = '''    final principalCents = CurrencyUtils.toMinorUnits(principal);\n    int percentOfPrincipal(double percent) =>\n        (principalCents * percent / 100).round();\n    final interestCents = percentOfPrincipal(interestRatePercent);\n    final insuranceCents = percentOfPrincipal(insuranceFeePercent);\n    final commissionCents = percentOfPrincipal(commissionPercent);\n    final chargesCents = insuranceCents + commissionCents +\n        CurrencyUtils.toMinorUnits(processingFee) +\n        CurrencyUtils.toMinorUnits(administrativeFee) +\n        CurrencyUtils.toMinorUnits(otherCharges);\n    final totalCents = principalCents + interestCents + chargesCents;\n    final installmentCents = totalCents ~/ duration;\n\n    return LoanCalculationResult(\n      principal: CurrencyUtils.fromMinorUnits(principalCents),\n      interestAmount: CurrencyUtils.fromMinorUnits(interestCents),\n      insuranceFeeAmount: CurrencyUtils.fromMinorUnits(insuranceCents),\n      commissionAmount: CurrencyUtils.fromMinorUnits(commissionCents),\n      totalCharges: CurrencyUtils.fromMinorUnits(chargesCents),\n      totalRepayment: CurrencyUtils.fromMinorUnits(totalCents),\n      installmentAmount: CurrencyUtils.fromMinorUnits(installmentCents),\n    );'''
    return replace_once(s, old, new, 'loan integer arithmetic')
edit('lib/features/loans/domain/loan_calculator.dart', loancalc)

# 5. Payment split uses integer kobo/cents for all balance arithmetic.
def paymentfix(s):
    old = '''  final cap = (installmentDue != null && installmentDue > 0)\n      ? min(installmentDue, outstandingBalance)\n      : outstandingBalance;\n  final rawLoanPaid = min(paymentAmount, cap);\n  // Round to cents so floating-point dust (e.g. 0.001 surpluses) never lands\n  // in the savings balance or the loan balance.\n  final loanPaid = CurrencyUtils.roundToCents(rawLoanPaid);\n  final surplus = CurrencyUtils.roundToCents(paymentAmount - rawLoanPaid);\n  final newBalance =\n      CurrencyUtils.roundToCents(max(0.0, outstandingBalance - loanPaid));'''
    new = '''  final paymentCents = CurrencyUtils.toMinorUnits(paymentAmount);\n  final balanceCents = CurrencyUtils.toMinorUnits(outstandingBalance);\n  final installmentCents = installmentDue != null && installmentDue > 0\n      ? CurrencyUtils.toMinorUnits(installmentDue)\n      : 0;\n  final capCents = installmentCents > 0\n      ? min(installmentCents, balanceCents)\n      : balanceCents;\n  final loanPaidCents = min(paymentCents, capCents);\n  final surplusCents = max(0, paymentCents - loanPaidCents);\n  final newBalanceCents = max(0, balanceCents - loanPaidCents);\n  final loanPaid = CurrencyUtils.fromMinorUnits(loanPaidCents);\n  final surplus = CurrencyUtils.fromMinorUnits(surplusCents);\n  final newBalance = CurrencyUtils.fromMinorUnits(newBalanceCents);'''
    s = replace_once(s, old, new, 'payment split integer arithmetic')
    s = replace_once(s, '  return paymentAmount - overpaymentSurplus;', "  final paymentCents = CurrencyUtils.toMinorUnits(paymentAmount);\n  final surplusCents = CurrencyUtils.toMinorUnits(overpaymentSurplus);\n  return CurrencyUtils.fromMinorUnits(paymentCents - surplusCents);", 'reversal integer arithmetic')
    old2 = '''  final toDeduct = min(overpaymentSurplus, balance);\n  return (balance - toDeduct, toDeduct);'''
    new2 = '''  final balanceCents = CurrencyUtils.toMinorUnits(balance);\n  final surplusCents = CurrencyUtils.toMinorUnits(overpaymentSurplus);\n  final toDeductCents = min(surplusCents, balanceCents);\n  return (CurrencyUtils.fromMinorUnits(balanceCents - toDeductCents),\n      CurrencyUtils.fromMinorUnits(toDeductCents));'''
    return replace_once(s, old2, new2, 'savings reversal integer arithmetic')
edit('lib/features/payments/data/payment_logic.dart', paymentfix)

# 6. Avoid N+1 schedule rebuild queries by preloading holidays and payment totals.
def schedulefix(s):
    old = '''  Future<void> rebuildAllSchedules() async {\n    final db = await _db;\n    final loanRows = await db.query('loans');\n    for (final row in loanRows) {\n      await _rebuild(db, Loan.fromMap(row));\n    }\n    _versionNotifier.bump();\n  }'''
    new = '''  Future<void> rebuildAllSchedules() async {\n    final db = await _db;\n    final loanRows = await db.query('loans');\n    if (loanRows.isEmpty) { _versionNotifier.bump(); return; }\n    final holidays = (await db.query('holidays'))\n        .map((row) => Holiday.fromMap(row)).toList(growable: false);\n    final paymentRows = await db.rawQuery('''\n      SELECT p.loan_id, COALESCE(SUM(p.amount - COALESCE((\n        SELECT st.amount FROM savings_transactions st\n        WHERE st.reference_loan_payment_id = p.id AND st.type = 'overpayment'\n        LIMIT 1), 0.0)), 0.0) AS applied\n      FROM payments p WHERE p.status = 'completed' GROUP BY p.loan_id\n    ''');\n    final totals = <String, double>{};\n    for (final row in paymentRows) {\n      final id = row['loan_id'] as String?;\n      if (id != null) totals[id] = (row['applied'] as num?)?.toDouble() ?? 0.0;\n    }\n    for (final row in loanRows) {\n      await _rebuild(db, Loan.fromMap(row), holidays: holidays,\n          totalAppliedToLoan: totals[row['id']] ?? 0.0);\n    }\n    _versionNotifier.bump();\n  }'''
    s = replace_once(s, old, new, 'schedule batch preload')
    start = '''  Future<void> _rebuild(Database db, Loan loan) async {'''
    end = '''    final result = LoanScheduleCalculator.build('''
    i = s.index(start); j = s.index(end, i)
    replacement = '''  Future<void> _rebuild(Database db, Loan loan, {\n    List<Holiday>? holidays,\n    double? totalAppliedToLoan,\n  }) async {\n    final effectiveHolidays = holidays ?? (await db.query('holidays'))\n        .map((row) => Holiday.fromMap(row)).toList(growable: false);\n    final effectiveApplied = totalAppliedToLoan ?? await _loadApplied(db, loan.id);\n\n'''
    s = s[:i] + replacement + s[j:]
    # Remove old source blocks now left between replacement and result call.
    pattern = re.compile(r"    // Source 1: holidays.*?    var totalApplied = 0\.0;\n    for \(final row in paymentRows\) \{.*?      totalApplied \+= amount - surplus;\n    \}\n\n", re.S)
    s, count = pattern.subn('', s, count=1)
    if count != 1: raise RuntimeError('old schedule source block not removed')
    s = s.replace('      holidays: holidays,\n      totalAppliedToLoan: totalApplied,', '      holidays: effectiveHolidays,\n      totalAppliedToLoan: effectiveApplied,', 1)
    marker = '''}\n\n/// Watch this from any provider'''
    helper = '''  Future<double> _loadApplied(Database db, String loanId) async {\n    final rows = await db.rawQuery('''\n      SELECT COALESCE(SUM(p.amount - COALESCE((\n        SELECT st.amount FROM savings_transactions st\n        WHERE st.reference_loan_payment_id = p.id AND st.type = 'overpayment'\n        LIMIT 1), 0.0)), 0.0) AS applied\n      FROM payments p WHERE p.loan_id = ? AND p.status = 'completed'\n    ''', [loanId]);\n    return (rows.first['applied'] as num?)?.toDouble() ?? 0.0;\n  }\n'''
    return s.replace(marker, helper + marker, 1)
edit('lib/features/loans/data/loan_schedule_service.dart', schedulefix)

# 7. Add CI and production configuration documentation.
ci = ROOT / '.github/workflows/ci.yml'
ci.parent.mkdir(parents=True, exist_ok=True)
ci.write_text('''name: Flutter CI\n\non:\n  push:\n    branches: [main]\n  pull_request:\n\npermissions:\n  contents: read\n\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n      - uses: subosito/flutter-action@v2\n        with:\n          flutter-version: 3.44.6\n          channel: stable\n          cache: true\n      - run: flutter pub get\n      - run: flutter analyze\n      - run: flutter test\n''')
(ROOT / 'CLOUD_BUILD.md').write_text('''# Adeghe Loan cloud configuration\n\nCloud configuration is injected at build time. The repository intentionally\ncontains no Supabase project URL or client key.\n\n```text\nflutter build windows --release --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR-PUBLISHABLE-ANON-KEY\n```\n\nNever put a Supabase service-role key in the application.\n''')
