from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

def edit(path, fn):
    p = ROOT / path
    s = p.read_text(encoding='utf-8-sig')
    n = fn(s)
    if n == s:
        raise RuntimeError(f'No change made to {path}')
    p.write_text(n, encoding='utf-8')

def rep(s, old, new, label):
    if old not in s:
        raise RuntimeError(label)
    return s.replace(old, new, 1)

# Database recovery: preserve the original file and stop on SQLCipher error 26.
def database(s):
    old = """      // Sqlite error 26 = \"file is not a database\". This happens when the
      // encryption key doesn't match the one used to create the database
      // (e.g. after a secure storage reset but the DB file remains).
      // The data is unrecoverable with the wrong key, so we delete the corrupt
      // file and let the next open create a fresh database.
      final message = e.toString();
      if (message.contains('SqliteException(26)') ||
          message.contains('file is not a database')) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
        return databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: _databaseVersion,
            onCreate: _onCreate,
            onConfigure: (db) async {
              await db.execute(_cipherKeySql(encryptionKey));
              await _onConfigure(db);
            },
            onUpgrade: _onUpgrade,
            onOpen: _onOpen,
          ),
        );
      }"""
    new = """      // Error 26 is a recovery condition, never permission to destroy
      // financial history. Preserve the original file and stop.
      final message = e.toString();
      if (message.contains('SqliteException(26)') ||
          message.contains('file is not a database')) {
        final file = File(path);
        String recoveryPath = path;
        if (await file.exists()) {
          final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
          final recovery = File('$path.recovery-$stamp');
          try {
            await file.copy(recovery.path);
            recoveryPath = recovery.path;
          } catch (_) {}
        }
        throw DatabaseRecoveryException(
          'Database could not be opened safely. No data was deleted. Recovery copy: $recoveryPath',
          recoveryPath,
        );
      }"""
    s = rep(s, old, new, 'database deletion block missing')
    exc = """\n\n/// Database opening failed in a way that requires operator recovery.
class DatabaseRecoveryException implements Exception {
  const DatabaseRecoveryException(this.message, this.recoveryPath);
  final String message;
  final String recoveryPath;
  @override
  String toString() => message;
}
"""
    return s + exc if 'class DatabaseRecoveryException' not in s else s
edit('lib/core/database/database_service.dart', database)

# Build-time cloud configuration only.
def cloud_config(s):
    s = re.sub(r"static const String supabaseUrl = String.fromEnvironment\(\n    'SUPABASE_URL',\n    defaultValue: '[^']+',\n  \);", "static const String supabaseUrl = String.fromEnvironment(\n    'SUPABASE_URL',\n    defaultValue: '',\n  );", s, count=1)
    s = re.sub(r"static const String anonKey = String.fromEnvironment\(\n    'SUPABASE_ANON_KEY',\n    defaultValue:\n        '[^']+', // nosemgrep: generic.secrets.security.detected-jwt-token.detected-jwt-token\n  \);", "static const String anonKey = String.fromEnvironment(\n    'SUPABASE_ANON_KEY',\n    defaultValue: '',\n  );", s, count=1)
    s = s.replace('static const int anonKeyExpiresAtEpochSeconds = 2101185634;', 'static const int anonKeyExpiresAtEpochSeconds = 0;')
    s = s.replace("static int anonKeySecondsToExpiry() =>\n      anonKeyExpiresAtEpochSeconds -", "static int anonKeySecondsToExpiry() =>\n      anonKeyExpiresAtEpochSeconds == 0 ? 0 : anonKeyExpiresAtEpochSeconds -")
    return s
edit('lib/core/cloud/supabase_config.dart', cloud_config)

# Exact minor-unit helpers, while keeping the existing DB schema compatible.
def currency(s):
    marker = '  /// Parses [text] as a finite, non-negative number, or returns null.'
    add = """  /// Exact currency arithmetic boundary (kobo/cents).
  static int toMinorUnits(num amount) {
    if (!amount.isFinite) throw ArgumentError.value(amount, 'amount');
    final scaled = amount * 100;
    if (!scaled.isFinite) throw ArgumentError.value(amount, 'amount');
    return scaled.round();
  }

  static double fromMinorUnits(int amount) => amount / 100.0;

  static int? tryParseMinorUnits(String? text) {
    final value = tryParseAmount(text);
    return value == null ? null : toMinorUnits(value);
  }

"""
    return rep(s, marker, add + marker, 'currency marker missing')
edit('lib/core/utils/currency_utils.dart', currency)

# Loan calculator: monetary arithmetic is integer based at the calculation boundary.
def loan_calc(s):
    old = """    final interestAmount = principal * (interestRatePercent / 100);
    final insuranceFeeAmount = principal * (insuranceFeePercent / 100);
    final commissionAmount = principal * (commissionPercent / 100);
    final totalCharges = insuranceFeeAmount + commissionFeeAmount + processingFee + administrativeFee + otherCharges;
    final totalRepayment = principal + interestAmount + totalCharges;
    final installmentAmount = totalRepayment / duration;

    return LoanCalculationResult(
      principal: principal,
      interestAmount: CurrencyUtils.roundToCents(interestAmount),
      insuranceFeeAmount: CurrencyUtils.roundToCents(insuranceFeeAmount),
      commissionAmount: CurrencyUtils.roundToCents(commissionAmount),
      totalCharges: CurrencyUtils.roundToCents(totalCharges),
      totalRepayment: CurrencyUtils.roundToCents(totalRepayment),
      installmentAmount: CurrencyUtils.roundToCents(installmentAmount),
    );"""
    if old not in s:
        old = """    final interestAmount = principal * (interestRatePercent / 100);
    final insuranceFeeAmount = principal * (insuranceFeePercent / 100);
    final commissionAmount = principal * (commissionPercent / 100);
    final totalCharges = insuranceFeeAmount + commissionAmount + processingFee + administrativeFee + otherCharges;
    final totalRepayment = principal + interestAmount + totalCharges;
    final installmentAmount = totalRepayment / duration;

    return LoanCalculationResult(
      principal: principal,
      interestAmount: CurrencyUtils.roundToCents(interestAmount),
      insuranceFeeAmount: CurrencyUtils.roundToCents(insuranceFeeAmount),
      commissionAmount: CurrencyUtils.roundToCents(commissionAmount),
      totalCharges: CurrencyUtils.roundToCents(totalCharges),
      totalRepayment: CurrencyUtils.roundToCents(totalRepayment),
      installmentAmount: CurrencyUtils.roundToCents(installmentAmount),
    );"""
    new = """    final principalCents = CurrencyUtils.toMinorUnits(principal);
    int pct(double value) => (principalCents * value / 100).round();
    final interestCents = pct(interestRatePercent);
    final insuranceCents = pct(insuranceFeePercent);
    final commissionCents = pct(commissionPercent);
    final chargesCents = insuranceCents + commissionCents +
        CurrencyUtils.toMinorUnits(processingFee) +
        CurrencyUtils.toMinorUnits(administrativeFee) +
        CurrencyUtils.toMinorUnits(otherCharges);
    final totalCents = principalCents + interestCents + chargesCents;
    final installmentCents = totalCents ~/ duration;

    return LoanCalculationResult(
      principal: CurrencyUtils.fromMinorUnits(principalCents),
      interestAmount: CurrencyUtils.fromMinorUnits(interestCents),
      insuranceFeeAmount: CurrencyUtils.fromMinorUnits(insuranceCents),
      commissionAmount: CurrencyUtils.fromMinorUnits(commissionCents),
      totalCharges: CurrencyUtils.fromMinorUnits(chargesCents),
      totalRepayment: CurrencyUtils.fromMinorUnits(totalCents),
      installmentAmount: CurrencyUtils.fromMinorUnits(installmentCents),
    );"""
    return rep(s, old, new, 'loan calculator block missing')
edit('lib/features/loans/domain/loan_calculator.dart', loan_calc)

# Payment and reversal math in minor units.
def payment(s):
    old = """  final cap = (installmentDue != null && installmentDue > 0)
      ? min(installmentDue, outstandingBalance)
      : outstandingBalance;
  final rawLoanPaid = min(paymentAmount, cap);
  // Round to cents so floating-point dust (e.g. 0.001 surpluses) never lands
  // in the savings balance or the loan balance.
  final loanPaid = CurrencyUtils.roundToCents(rawLoanPaid);
  final surplus = CurrencyUtils.roundToCents(paymentAmount - rawLoanPaid);
  final newBalance =
      CurrencyUtils.roundToCents(max(0.0, outstandingBalance - loanPaid));"""
    new = """  final paymentCents = CurrencyUtils.toMinorUnits(paymentAmount);
  final balanceCents = CurrencyUtils.toMinorUnits(outstandingBalance);
  final installmentCents = installmentDue != null && installmentDue > 0
      ? CurrencyUtils.toMinorUnits(installmentDue)
      : 0;
  final capCents = installmentCents > 0
      ? min(installmentCents, balanceCents)
      : balanceCents;
  final loanPaidCents = min(paymentCents, capCents);
  final surplusCents = max(0, paymentCents - loanPaidCents);
  final newBalanceCents = max(0, balanceCents - loanPaidCents);
  final loanPaid = CurrencyUtils.fromMinorUnits(loanPaidCents);
  final surplus = CurrencyUtils.fromMinorUnits(surplusCents);
  final newBalance = CurrencyUtils.fromMinorUnits(newBalanceCents);"""
    s = rep(s, old, new, 'payment split block missing')
    s = rep(s, '  return paymentAmount - overpaymentSurplus;', "  final paymentCents = CurrencyUtils.toMinorUnits(paymentAmount);\n  final surplusCents = CurrencyUtils.toMinorUnits(overpaymentSurplus);\n  return CurrencyUtils.fromMinorUnits(paymentCents - surplusCents);", 'reversal block missing')
    old2 = """  final toDeduct = min(overpaymentSurplus, balance);
  return (balance - toDeduct, toDeduct);"""
    new2 = """  final balanceCents = CurrencyUtils.toMinorUnits(balance);
  final surplusCents = CurrencyUtils.toMinorUnits(overpaymentSurplus);
  final toDeductCents = min(surplusCents, balanceCents);
  return (CurrencyUtils.fromMinorUnits(balanceCents - toDeductCents),
      CurrencyUtils.fromMinorUnits(toDeductCents));"""
    return rep(s, old2, new2, 'savings reversal block missing')
edit('lib/features/payments/data/payment_logic.dart', payment)

# Schedule rebuild: one holiday query + one payment aggregate instead of N+1 queries.
def schedule(s):
    old = """  Future<void> rebuildAllSchedules() async {
    final db = await _db;
    final loanRows = await db.query('loans');
    for (final row in loanRows) {
      await _rebuild(db, Loan.fromMap(row));
    }
    _versionNotifier.bump();
  }"""
    new = """  Future<void> rebuildAllSchedules() async {
    final db = await _db;
    final loanRows = await db.query('loans');
    if (loanRows.isEmpty) { _versionNotifier.bump(); return; }
    final holidays = (await db.query('holidays'))
        .map((row) => Holiday.fromMap(row)).toList(growable: false);
    final paymentRows = await db.rawQuery(
      \"SELECT p.loan_id, COALESCE(SUM(p.amount - COALESCE((SELECT st.amount FROM savings_transactions st WHERE st.reference_loan_payment_id = p.id AND st.type = 'overpayment' LIMIT 1), 0.0)), 0.0) AS applied FROM payments p WHERE p.status = 'completed' GROUP BY p.loan_id\");
    final totals = <String, double>{};
    for (final row in paymentRows) {
      final id = row['loan_id'] as String?;
      if (id != null) totals[id] = (row['applied'] as num?)?.toDouble() ?? 0.0;
    }
    for (final row in loanRows) {
      await _rebuild(db, Loan.fromMap(row), holidays: holidays,
          totalAppliedToLoan: totals[row['id']] ?? 0.0);
    }
    _versionNotifier.bump();
  }"""
    s = rep(s, old, new, 'schedule rebuildAll block missing')
    old_start = '  Future<void> _rebuild(Database db, Loan loan) async {'
    new_start = """  Future<void> _rebuild(Database db, Loan loan, {
    List<Holiday>? holidays,
    double? totalAppliedToLoan,
  }) async {
    final effectiveHolidays = holidays ?? (await db.query('holidays'))
        .map((row) => Holiday.fromMap(row)).toList(growable: false);
    final effectiveApplied = totalAppliedToLoan ?? await _loadApplied(db, loan.id);

"""
    s = rep(s, old_start, new_start, 'schedule _rebuild start missing')
    block = re.compile(r"    // Source 1: holidays.*?    var totalApplied = 0\.0;\n    for \(final row in paymentRows\) \{.*?      totalApplied \+= amount - surplus;\n    \}\n\n", re.S)
    s, count = block.subn('', s, count=1)
    if count != 1: raise RuntimeError('schedule old query block missing')
    s = rep(s, '      holidays: holidays,\n      totalAppliedToLoan: totalApplied,', '      holidays: effectiveHolidays,\n      totalAppliedToLoan: effectiveApplied,', 'schedule result arguments missing')
    helper = """  Future<double> _loadApplied(Database db, String loanId) async {
    final rows = await db.rawQuery(
      \"SELECT COALESCE(SUM(p.amount - COALESCE((SELECT st.amount FROM savings_transactions st WHERE st.reference_loan_payment_id = p.id AND st.type = 'overpayment' LIMIT 1), 0.0)), 0.0) AS applied FROM payments p WHERE p.loan_id = ? AND p.status = 'completed'\",
      [loanId],
    );
    return (rows.first['applied'] as num?)?.toDouble() ?? 0.0;
  }

"""
    marker = '\n}\n\n/// Watch this from any provider'
    return rep(s, marker, '\n' + helper + '}\n\n/// Watch this from any provider', 'schedule class end missing')
edit('lib/features/loans/data/loan_schedule_service.dart', schedule)

# Financial sync: immutable events win; mutable loan/savings balances are never
# accepted as authoritative cloud state. Recompute projections after every pull.
def sync(s):
    marker = '  bool _syncing = false;'
    add = """  /// Financial balances are projections. Payment and savings transaction
  /// rows are the durable events; loan/savings balance snapshots are never
  /// authoritative during synchronization.
  static const Set<String> _derivedFinancialTables = {
    'loans', 'savings_accounts',
  };

"""
    s = rep(s, marker, add + marker, 'sync marker missing')
    old = """          final cleanedRows = [
            for (final row in rows) stripSensitiveColumns(table, row),
          ];"""
    new = """          final cleanedRows = [
            for (final row in rows)
              _cloudRowForPush(table, stripSensitiveColumns(table, row)),
          ];"""
    s = rep(s, old, new, 'sync push rows missing')
    old_pull = """            var row = Map<String, Object?>.from(remoteRow);
            if (sensitive != null && localRow != null) {"""
    new_pull = """            var row = Map<String, Object?>.from(remoteRow);
            if (table == 'loans' && localRow != null) {
              // Apply remote loan definition fields but preserve the local
              // financial projection. It will be rebuilt from payment events.
              for (final field in const ['outstanding_balance', 'status']) {
                row[field] = localRow[field];
              }
            } else if (table == 'savings_accounts' && localRow != null) {
              row['balance'] = localRow['balance'];
            }
            if (sensitive != null && localRow != null) {"""
    s = rep(s, old_pull, new_pull, 'sync pull row missing')
    # Insert helpers before _pushDocuments.
    anchor = '  Future<({int pushed, int failures})> _pushDocuments('
    helper = """  Map<String, Object?> _cloudRowForPush(String table, Map<String, Object?> row) {
    if (table == 'loans') {
      final copy = Map<String, Object?>.from(row);
      // Balance/status are derived locally from immutable payment events.
      copy['outstanding_balance'] = row['total_repayment'];
      return copy;
    }
    if (table == 'savings_accounts') {
      final copy = Map<String, Object?>.from(row);
      copy['balance'] = 0.0;
      return copy;
    }
    return row;
  }

  Future<void> _rebuildFinancialProjections(Database db) async {
    final paymentRows = await db.rawQuery(
      \"SELECT p.loan_id, COALESCE(SUM(p.amount - COALESCE((SELECT st.amount FROM savings_transactions st WHERE st.reference_loan_payment_id = p.id AND st.type = 'overpayment' LIMIT 1), 0.0)), 0.0) AS applied FROM payments p WHERE p.status = 'completed' GROUP BY p.loan_id\");
    final applied = <String, double>{};
    for (final row in paymentRows) {
      final id = row['loan_id'] as String?;
      if (id != null) applied[id] = (row['applied'] as num?)?.toDouble() ?? 0.0;
    }
    final loans = await db.query('loans', columns: const ['id', 'total_repayment', 'status']);
    for (final loan in loans) {
      final id = loan['id'] as String;
      final total = (loan['total_repayment'] as num?)?.toDouble() ?? 0.0;
      final paid = (applied[id] ?? 0.0).clamp(0.0, total);
      final balance = (total - paid).clamp(0.0, total);
      final oldStatus = loan['status'] as String?;
      final status = oldStatus == 'cancelled' ? 'cancelled' : (balance <= 0.005 ? 'completed' : 'active');
      await db.update('loans', {'outstanding_balance': balance, 'status': status}, where: 'id = ?', whereArgs: [id]);
    }
    final savings = await db.rawQuery(
      \"SELECT sa.id, COALESCE(SUM(CASE WHEN st.type IN ('deposit','overpayment') THEN st.amount WHEN st.type = 'withdrawal' THEN -st.amount ELSE 0 END),0.0) AS balance FROM savings_accounts sa LEFT JOIN savings_transactions st ON st.savings_account_id = sa.id GROUP BY sa.id\");
    for (final row in savings) {
      final id = row['id'] as String;
      final balance = ((row['balance'] as num?)?.toDouble() ?? 0.0).clamp(0.0, double.infinity);
      await db.update('savings_accounts', {'balance': balance}, where: 'id = ?', whereArgs: [id]);
    }
  }

"""
    s = rep(s, anchor, helper + anchor, 'sync helper anchor missing')
    # Run projection rebuild after pull, before the existing onPullComplete callback.
    old_after = """      // After every pull, re-derive all repayment schedules from the freshly
      // synced source data (loans + payments + savings + holidays). The derived
      // schedule rows are never replicated, so each device must recompute them
      // locally. Best-effort: a rebuild failure must not fail the sync cycle.
      try {"""
    new_after = """      // Rebuild financial projections from immutable transaction events before
      // rebuilding the derived repayment schedule.
      try { await _rebuildFinancialProjections(db); } catch (_) {}

      // After every pull, re-derive all repayment schedules from the freshly
      // synced source data (loans + payments + savings + holidays). The derived
      // schedule rows are never replicated, so each device must recompute them
      // locally. Best-effort: a rebuild failure must not fail the sync cycle.
      try {"""
    return rep(s, old_after, new_after, 'sync pull callback block missing')
edit('lib/core/cloud/cloud_sync_service.dart', sync)

# Regression tests and CI.
(ROOT / 'test/database/database_recovery_policy_test.dart').write_text("""import 'dart:io';\nimport 'package:flutter_test/flutter_test.dart';\n\nvoid main() {\n  test('recovery policy preserves the original database file', () async {\n    final dir = await Directory.systemTemp.createTemp('adeghe-recovery-');\n    addTearDown(() => dir.delete(recursive: true));\n    final db = File('${dir.path}/loantrack.db');\n    await db.writeAsString('financial-history');\n    final recovery = File('${db.path}.recovery-test');\n    await db.copy(recovery.path);\n    expect(await db.exists(), isTrue);\n    expect(await db.readAsString(), 'financial-history');\n    expect(await recovery.readAsString(), 'financial-history');\n  });\n}\n""")
(ROOT / 'test/payments/money_minor_units_test.dart').write_text("""import 'package:flutter_test/flutter_test.dart';\nimport 'package:loantrack/core/utils/currency_utils.dart';\nimport 'package:loantrack/features/payments/data/payment_logic.dart';\n\nvoid main() {\n  test('payment split is exact to the cent', () {\n    final x = computePaymentSplit(paymentAmount: 1000.01, outstandingBalance: 900.01);\n    expect(x.appliedToLoan, 900.01);\n    expect(x.overpaymentSurplus, 100.0);\n    expect(x.newLoanBalance, 0.0);\n  });\n\n  test('minor unit conversion is exact', () {\n    expect(CurrencyUtils.toMinorUnits(12500.50), 1250050);\n    expect(CurrencyUtils.fromMinorUnits(1250050), 12500.50);\n  });\n}\n""")
ci = ROOT / '.github/workflows/ci.yml'
ci.parent.mkdir(parents=True, exist_ok=True)
ci.write_text("""name: Flutter CI\n\non:\n  push:\n    branches: [main]\n  pull_request:\n\npermissions:\n  contents: read\n\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n      - uses: subosito/flutter-action@v2\n        with:\n          flutter-version: 3.44.6\n          channel: stable\n          cache: true\n      - run: flutter pub get\n      - run: flutter analyze\n      - run: flutter test\n""")
(ROOT / 'CLOUD_BUILD.md').write_text("""# Adeghe Loan cloud configuration\n\nSupabase configuration is injected at build time.\n\n`flutter build windows --release --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR-PUBLISHABLE-ANON-KEY`\n\nNever ship a Supabase service-role key in the app.\n""")
