import 'package:flutter_test/flutter_test.dart';

import 'package:loantrack/features/documents/data/models/document_entity.dart';

void main() {
  Map<String, Object?> validDocument() => {
        'id': 'doc-1',
        'customer_id': 'customer-1',
        'loan_id': null,
        'doc_type': 'passport',
        'file_path': '/secure/doc.enc',
        'original_name': 'passport.jpg',
        'mime_type': 'image/jpeg',
        'uploaded_at': '2026-09-05T12:00:00.000Z',
      };

  test('parses valid document metadata', () {
    final document = CustomerDocument.fromMap(validDocument());
    expect(document.id, 'doc-1');
    expect(document.type, CustomerDocumentType.passport);
    expect(document.isImage, isTrue);
  });

  test('rejects unknown document type', () {
    final row = validDocument()..['doc_type'] = 'unknown';
    expect(() => CustomerDocument.fromMap(row), throwsFormatException);
  });

  test('rejects empty encrypted path', () {
    final row = validDocument()..['file_path'] = '';
    expect(() => CustomerDocument.fromMap(row), throwsFormatException);
  });

  test('rejects malformed upload date', () {
    final row = validDocument()..['uploaded_at'] = 'not-a-date';
    expect(() => CustomerDocument.fromMap(row), throwsFormatException);
  });

  test('rejects unsupported MIME type', () {
    final row = validDocument()..['mime_type'] = 'application/octet-stream';
    expect(() => CustomerDocument.fromMap(row), throwsFormatException);
  });
}
