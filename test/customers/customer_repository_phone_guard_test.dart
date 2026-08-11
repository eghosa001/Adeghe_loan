import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/features/customers/data/customer_repository.dart';
import 'package:loantrack/features/customers/data/models/customer_entity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Guards the empty-phone sync black hole (fixed 2026-08-11): the cloud schema
/// declares `customers.phone` NOT NULL and the sync pull guard
/// (`cloudRequiredTextColumns`) rejects customers with an empty phone, so a
/// customer saved with no phone could never be received by the other device —
/// the row was rejected on pull and its loans failed FK with it (observed live:
/// Windows 127 loans, phone stuck at 126). `CustomerRepository.save` now
/// rejects empty/whitespace-only phones at the repository boundary so no save
/// path can create such a customer.
void main() {
  sqfliteFfiInit();

  Future<CustomerRepository> openRepo() async {
    final service = DatabaseService.withOpenOverride(
      SecureStorageService(),
      () async {
        final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
        await db.execute('''
          CREATE TABLE customers (
            id TEXT PRIMARY KEY,
            passport_path TEXT,
            full_name TEXT NOT NULL,
            gender TEXT,
            dob TEXT,
            phone TEXT NOT NULL,
            alt_phone TEXT,
            email TEXT,
            residential_address TEXT,
            business_address TEXT,
            occupation TEXT,
            employer TEXT,
            marital_status TEXT,
            nationality TEXT,
            state TEXT,
            lga TEXT,
            next_of_kin TEXT,
            next_of_kin_relation TEXT,
            next_of_kin_phone TEXT,
            guarantor_1_name TEXT,
            guarantor_1_phone TEXT,
            guarantor_1_address TEXT,
            guarantor_2_name TEXT,
            guarantor_2_phone TEXT,
            guarantor_2_address TEXT,
            guarantor_passport_path TEXT,
            nin TEXT,
            bvn TEXT,
            id_type TEXT,
            id_number TEXT,
            signature_path TEXT,
            date_registered TEXT NOT NULL,
            notes TEXT,
            status TEXT NOT NULL,
            credit_score REAL DEFAULT 0.0,
            group_id TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE savings_accounts (
            id TEXT PRIMARY KEY,
            customer_id TEXT NOT NULL,
            balance REAL NOT NULL DEFAULT 0.0,
            created_at TEXT NOT NULL
          )
        ''');
        return db;
      },
    );
    addTearDown(service.close);
    return CustomerRepository(service);
  }

  Customer customerWith({required String phone}) => Customer(
        id: 'CUS-test',
        fullName: 'TEST CUSTOMER',
        phone: phone,
        dateRegistered: '2026-08-11',
      );

  test('save rejects an empty phone (the sync black-hole bug)', () async {
    final repo = await openRepo();
    await expectLater(
      repo.save(customerWith(phone: '')),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('save rejects a whitespace-only phone', () async {
    final repo = await openRepo();
    await expectLater(
      repo.save(customerWith(phone: '   ')),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('save accepts a customer with a phone', () async {
    final repo = await openRepo();
    await repo.save(customerWith(phone: '08012345678'));
  });
}
