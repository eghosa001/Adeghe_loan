import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/documents/data/models/document_entity.dart';

void main() {
  test('document mapping preserves encryption metadata', () {
    final document = CustomerDocument(
      id: 'DOC-1',
      customerId: 'CUS-1',
      type: CustomerDocumentType.ninSlip,
      encryptedPath: '/secure/DOC-1.enc',
      originalName: 'nin.pdf',
      mimeType: 'application/pdf',
      uploadedAt: DateTime.utc(2026, 7, 18),
    );

    final restored = CustomerDocument.fromMap(document.toMap());

    expect(restored.type, CustomerDocumentType.ninSlip);
    expect(restored.isPdf, isTrue);
    expect(restored.encryptedPath, document.encryptedPath);
  });

  test(
      'document mapping falls back to the epoch for a malformed uploaded_at '
      '(cloud-tamper guard)', () {
    final restored = CustomerDocument.fromMap({
      'id': 'DOC-1',
      'customer_id': 'CUS-1',
      'loan_id': null,
      'doc_type': 'other',
      'file_path': '/secure/DOC-1.enc',
      'original_name': 'x.pdf',
      'mime_type': 'application/pdf',
      'uploaded_at': 'not-a-date',
    });

    expect(restored.uploadedAt, DateTime.fromMillisecondsSinceEpoch(0));
  });
}
