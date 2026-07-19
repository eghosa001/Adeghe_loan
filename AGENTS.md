# AGENTS.md — LoanTrack

## Project overview

Offline-first Flutter loan/microfinance management app targeting the Nigerian market. Encrypted local SQLite database, PIN + biometric auth, no backend server.

**Package name:** `loantrack` (directory is `flutter_application_1`)

## Commands

```bash
flutter run                        # Run the app
flutter test                       # Run all tests
flutter test test/widget_test.dart # Run a single test file
flutter analyze                    # Static analysis
flutter build apk                  # Android release build
dart run build_runner build --delete-conflicting-outputs  # Codegen (currently unused — see below)
```

No Makefile, scripts, or CI workflows exist. No custom lint rules beyond default `flutter_lints`.

## Architecture

**Pattern:** Feature-first folder structure with Riverpod for state/DI, GoRouter for navigation.

```
lib/
  main.dart                        # Entry point: ProviderScope -> MyApp
  core/
    constant/app_constants.dart
    database/database_service.dart  # Encrypted SQLite (sqflite_sqlcipher), 9 tables, migrations v1-v5
    di/providers.dart               # Central Riverpod providers
    router/app_router.dart          # GoRouter config; some screens defined inline
    security/                       # Biometric, file encryption, secure storage
    services/                       # Backup, document, export services
    theme/app_theme.dart
    utils/                          # Currency, date, inactivity wrapper
  features/
    auth/       # PIN-based auth + biometrics; auth_provider.dart is the StateNotifier
    business/   # Business profile, financial settings, backup
    customers/  # CRUD with search
    documents/  # Encrypted customer documents (AES-GCM)
    holidays/   # Holiday management for schedule generation
    loans/      # Loan creation, schedule generation, calculator
    payments/   # Payment recording
```

**Routing:** GoRouter in `lib/core/router/app_router.dart`. Initial route `/splash`. Uses `state.params['id']` for path params, `state.extra` for objects.

**State management:** Riverpod v2 — `Provider`, `FutureProvider`, `StateProvider`, `StateNotifierProvider`. Screens use `ConsumerWidget`/`ConsumerStatefulWidget`.

**Database:** `sqflite_sqlcipher` — encrypted SQLite. DB file: `loantrack.db`. Key stored in FlutterSecureStorage. Schema version 5 with manual ALTER TABLE migrations in `database_service.dart`. **Note:** `PRAGMA foreign_keys = ON` is enforced.

**Auth:** Local-only. PIN (SHA-256 hashed in secure storage) + optional biometrics. 5-minute auto-lock via `InactivityWrapper`. `databaseServiceProvider` polls `authProvider` until unlocked before initializing DB.

**Document encryption:** `FileEncryptionService` — `[LTD1 header][12-byte IV][AES-GCM ciphertext]`. Max 20 MB. Supported: PDF, PNG, JPG.

**Error handling:** Sealed `Result<T>` type (`Success<T>` / `ResultError<T>`) with 11 `Failure` subtypes. No exceptions across repository boundaries.

**Entities:** Hand-written `toMap()`/`fromMap()` methods. No code-generated serialization despite dev dependencies.

## Code generation

`build_runner`, `freezed`, `json_serializable` are declared in `pubspec.yaml` but **completely unused**. No `.g.dart` or `.freezed.dart` files exist. No `build.yaml`. All serialization is manual.

## Testing

Tests in `test/`. Currently minimal (4 test files). Uses `flutter_test`. `mocktail` is a dev dependency but unused.

```bash
flutter test test/widget_test.dart                              # Single file
flutter test test/business/financial_defaults_screen_test.dart  # Single test
```

## Gotchas and known issues

- **Table name bug:** `LoanRepository.getScheduleForLoan()` queries `'repayment_installments'` but the actual table is `'repayment_schedule'` (`lib/features/loans/data/loan_repository.dart`). Will cause runtime SQL error.
- **Currency mismatch:** `AppConstants.defaultCurrencySymbol` = `$` (USD) but `FinancialSettings` default = `₦` (Naira). App targets Nigerian market.
- **PIN constant unused:** `AppConstants.pinLength = 4` but UI allows 4–8 digits. The constant is not referenced by PIN screens.
- **Inactivity timeout mismatch:** Widget defaults to 5 min but `AppConstants.defaultInactivityTimeout` = 3 min. Widget does not read the constant.
- **Orphaned root file:** `loan_entity.dart` exists in project root (not in `lib/`). Stale copy.
- **Debug log in root:** `flutter_01.log` should be gitignored.
- **Unused packages:** `flex_color_scheme`, `flutter_local_notifications` are dependencies but never imported in source.
- **No iOS directory:** Only `android/` platform files exist.
- **DI inconsistency:** Some repositories take `Ref`, others take `DatabaseService` directly. No uniform pattern.
