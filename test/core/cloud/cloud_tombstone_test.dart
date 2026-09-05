import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/cloud/cloud_sync_service.dart';

void main() {
  group('shouldApplyRemoteTombstone', () {
    const deletedAt = '2026-09-05T10:00:00.000Z';

    test('applies when the local row is missing', () {
      expect(shouldApplyRemoteTombstone(null, deletedAt), isTrue);
    });

    test('applies when the local row is older than the tombstone', () {
      expect(
        shouldApplyRemoteTombstone('2026-09-05T09:59:59.999Z', deletedAt),
        isTrue,
      );
    });

    test('does not delete an equal-version local row', () {
      expect(shouldApplyRemoteTombstone(deletedAt, deletedAt), isFalse);
    });

    test('does not delete a newer local row', () {
      expect(
        shouldApplyRemoteTombstone('2026-09-05T10:00:00.001Z', deletedAt),
        isFalse,
      );
    });
  });
}
