import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/cloud/cloud_sync_service.dart';

/// Guards the cloud-sync hardening contract:
///  * regulated identifiers (bvn/nin) are stripped before any row is pushed
///  * the strip leaves other columns (including explicit NULLs) untouched
///  * remote tombstone `deleted_at` values must be well-formed, non-future
///    `syncTimestamp()` strings before they can force a local delete
void main() {
  group('cloudSensitiveColumns', () {
    test('only customers carries regulated identifiers', () {
      expect(cloudSensitiveColumns, {
        'customers': {'bvn', 'nin'},
      });
    });
  });

  group('stripSensitiveColumns', () {
    test('removes bvn and nin from a customer row', () {
      final row = stripSensitiveColumns('customers', {
        'id': 'c1',
        'full_name': 'Ada',
        'phone': '08000000000',
        'bvn': '22111111111',
        'nin': '12345678901',
        'residential_address': 'Lagos',
        'group_id': null,
      });
      expect(row.containsKey('bvn'), isFalse);
      expect(row.containsKey('nin'), isFalse);
      expect(row['full_name'], 'Ada');
      expect(row['phone'], '08000000000');
    });

    test('keeps other columns and explicit NULLs intact', () {
      final row = stripSensitiveColumns('customers', {
        'id': 'c1',
        'group_id': null,
        'bvn': null,
      });
      // F6 contract: nullable values survive so field-clearing writes push.
      expect(row['group_id'], isNull);
      expect(row['bvn'], isNull);
      expect(row['id'], 'c1');
    });

    test('leaves non-sensitive tables untouched', () {
      final row = {'id': 'l1', 'customer_id': 'c1', 'amount': 1000.0};
      expect(stripSensitiveColumns('loans', row), same(row));
    });
  });

  group('isValidSyncTimestamp', () {
    test('accepts a well-formed syncTimestamp() string', () {
      expect(isValidSyncTimestamp('2026-08-04T10:00:00.000Z'), isTrue);
    });

    test('rejects non-timestamp garbage', () {
      expect(isValidSyncTimestamp(null), isFalse);
      expect(isValidSyncTimestamp(''), isFalse);
      expect(isValidSyncTimestamp('not-a-date'), isFalse);
      expect(isValidSyncTimestamp('2026-08-04'), isFalse);
    });

    test('rejects toIso8601String() microsecond format', () {
      // LWW ordering requires 3-digit millis; 6-digit micros must not pass.
      expect(isValidSyncTimestamp('2026-08-04T10:00:00.123456Z'), isFalse);
    });

    test('rejects future-dated timestamps beyond clock skew', () {
      final future =
          _syncFormat(DateTime.now().toUtc().add(const Duration(days: 1)));
      expect(isValidSyncTimestamp(future), isFalse);
    });

    test('accepts timestamps within clock-skew tolerance of now', () {
      final recent =
          _syncFormat(DateTime.now().toUtc().add(const Duration(seconds: 30)));
      expect(isValidSyncTimestamp(recent), isTrue);
    });
  });

  group('isSaneCloudRow', () {
    Map<String, Object?> loanRow(
        [String updatedAt = '2026-08-04T10:00:00.000Z']) {
      return {
        'id': 'l1',
        'customer_id': 'c1',
        'loan_type': 'daily',
        'amount': 1000.0,
        'interest_rate': 10.0,
        'total_repayment': 1100.0,
        'outstanding_balance': 1100.0,
        'status': 'active',
        'updated_at': updatedAt,
      };
    }

    test('accepts a well-formed row', () {
      expect(isSaneCloudRow('loans', loanRow(), 'id'), isTrue);
    });

    test('rejects a future-dated updated_at (API-3 LWW poisoning)', () {
      final future = _syncFormat(
          DateTime.now().toUtc().add(const Duration(days: 365)));
      expect(isSaneCloudRow('loans', loanRow(future), 'id'), isFalse);
    });

    test('rejects a malformed updated_at', () {
      expect(isSaneCloudRow('loans', loanRow('2026-08-04'), 'id'), isFalse);
      expect(isSaneCloudRow('loans', loanRow('garbage'), 'id'), isFalse);
    });

    test('rejects a missing primary key', () {
      final row = loanRow()..remove('id');
      expect(isSaneCloudRow('loans', row, 'id'), isFalse);
    });

    test('rejects a string where a number belongs (API-4 cast crash)', () {
      final row = loanRow()..['amount'] = 'abc';
      expect(isSaneCloudRow('loans', row, 'id'), isFalse);
    });

    test('rejects non-finite numbers (Infinity/NaN poison the local DB)', () {
      // Infinity/NaN are `num` and Infinity even passes the Postgres >= 0
      // CHECK, but would be stored as NULL / corrupt aggregates locally.
      final inf = loanRow()..['amount'] = double.infinity;
      expect(isSaneCloudRow('loans', inf, 'id'), isFalse);
      final negInf = loanRow()..['amount'] = double.negativeInfinity;
      expect(isSaneCloudRow('loans', negInf, 'id'), isFalse);
      final nan = loanRow()..['amount'] = double.nan;
      expect(isSaneCloudRow('loans', nan, 'id'), isFalse);
    });

    test('rejects negative numeric values (server CHECK is >= 0)', () {
      final row = loanRow()..['outstanding_balance'] = -50.0;
      expect(isSaneCloudRow('loans', row, 'id'), isFalse);
    });

    test('rejects a non-integer installment_number', () {
      final row = {
        'id': 'r1',
        'loan_id': 'l1',
        'installment_number': 3.0, // must be a whole int for `as int`
        'due_date': '2026-08-05',
        'amount': 100.0,
        'status': 'pending',
        'paid_amount': 0.0,
        'updated_at': '2026-08-04T10:00:00.000Z',
      };
      expect(isSaneCloudRow('repayment_schedule', row, 'id'), isFalse);
    });

    test('rejects an unknown enum value', () {
      final row = loanRow()..['status'] = 'x';
      expect(isSaneCloudRow('loans', row, 'id'), isFalse);
    });

    test('rejects a payments row with an unknown type', () {
      final row = {
        'id': 'p1',
        'loan_id': 'l1',
        'customer_id': 'c1',
        'amount': 500.0,
        'payment_date': '2026-08-01',
        'payment_method': 'cash',
        'receipt_no': 'R1',
        'collector': 'Me',
        'type': 'settlement',
        'status': 'completed',
        'updated_at': '2026-08-04T10:00:00.000Z',
      };
      expect(isSaneCloudRow('payments', row, 'id'), isFalse);
    });

    test('rejects a customers row with an unknown status', () {
      final row = {
        'id': 'c1',
        'full_name': 'Ada',
        'phone': '08000000000',
        'date_registered': '2026-01-01',
        'status': 'zombie',
        'updated_at': '2026-08-04T10:00:00.000Z',
      };
      expect(isSaneCloudRow('customers', row, 'id'), isFalse);
    });

    test('accepts every loan status the app writes', () {
      for (final status in [
        'active',
        'completed',
        'defaulted',
        'pending',
        'cancelled',
      ]) {
        expect(isSaneCloudRow('loans', loanRow()..['status'] = status, 'id'),
            isTrue,
            reason: status);
      }
    });

    test('allows NULLs in numeric, int, and enum columns', () {
      final row = loanRow()
        ..['daily_payment'] = null
        ..['installment_number'] = null
        ..['status'] = null;
      expect(isSaneCloudRow('loans', row, 'id'), isTrue);
    });

    test('rejects a customers row with an empty full_name (empty-name crash)', () {
      final row = {
        'id': 'c1',
        'full_name': '',
        'phone': '08000000000',
        'date_registered': '2026-01-01',
        'status': 'active',
        'updated_at': '2026-08-04T10:00:00.000Z',
      };
      expect(isSaneCloudRow('customers', row, 'id'), isFalse);
    });

    test('rejects a customers row with a blank-only full_name', () {
      final row = {
        'id': 'c1',
        'full_name': '   ',
        'phone': '08000000000',
        'date_registered': '2026-01-01',
        'status': 'active',
        'updated_at': '2026-08-04T10:00:00.000Z',
      };
      expect(isSaneCloudRow('customers', row, 'id'), isFalse);
    });

    test('rejects a customer_groups row with an empty name', () {
      final row = {
        'id': 'g1',
        'name': '',
        'created_at': '2026-01-01',
        'updated_at': '2026-08-04T10:00:00.000Z',
      };
      expect(isSaneCloudRow('customer_groups', row, 'id'), isFalse);
    });

    test('rejects a customers row missing a required text column', () {
      final row = {
        'id': 'c1',
        'full_name': 'Ada',
        // 'date_registered' missing — NOT NULL in the schema
        'phone': '08000000000',
        'status': 'active',
        'updated_at': '2026-08-04T10:00:00.000Z',
      };
      expect(isSaneCloudRow('customers', row, 'id'), isFalse);
    });

    test('accepts a well-formed customers row with non-empty required text', () {
      final row = {
        'id': 'c1',
        'full_name': 'Ada',
        'phone': '08000000000',
        'date_registered': '2026-01-01',
        'status': 'active',
        'updated_at': '2026-08-04T10:00:00.000Z',
      };
      expect(isSaneCloudRow('customers', row, 'id'), isTrue);
    });
  });
}

/// Formats a UTC instant as a fixed-width `yyyy-MM-ddTHH:mm:ss.SSSZ` string,
/// matching the syncTimestamp() shape (3-digit millis).
String _syncFormat(DateTime utc) {
  final y = utc.year.toString().padLeft(4, '0');
  final m = utc.month.toString().padLeft(2, '0');
  final d = utc.day.toString().padLeft(2, '0');
  final hh = utc.hour.toString().padLeft(2, '0');
  final mm = utc.minute.toString().padLeft(2, '0');
  final ss = utc.second.toString().padLeft(2, '0');
  final ms = utc.millisecond.toString().padLeft(3, '0');
  return '$y-$m-${d}T$hh:$mm:$ss.$ms' 'Z';
}
