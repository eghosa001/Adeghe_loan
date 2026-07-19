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
}
