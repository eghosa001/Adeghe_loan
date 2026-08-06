import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/documents/data/document_repository.dart';

void main() {
  group('detectDocumentMimeType', () {
    test('recognizes a PDF by its %PDF- signature', () {
      final bytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E]);
      expect(detectDocumentMimeType(bytes), 'application/pdf');
    });

    test('recognizes a PNG by its 8-byte signature', () {
      final bytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      ]);
      expect(detectDocumentMimeType(bytes), 'image/png');
    });

    test('recognizes a JPEG by its FF D8 FF signature', () {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      expect(detectDocumentMimeType(bytes), 'image/jpeg');
    });

    test('rejects a renamed executable (.exe bytes as loan.pdf)', () {
      // MZ header of a Windows PE binary — passed a renamed extension but must
      // be rejected by content.
      final exe = Uint8List.fromList([
        0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00,
      ]);
      expect(detectDocumentMimeType(exe), isNull);
    });

    test('rejects an HTML payload', () {
      final html = Uint8List.fromList(
          '<html><script>alert(1)</script></html>'.codeUnits);
      expect(detectDocumentMimeType(html), isNull);
    });

    test('rejects empty and too-short buffers', () {
      expect(detectDocumentMimeType(Uint8List(0)), isNull);
      expect(detectDocumentMimeType(Uint8List.fromList([0x25, 0x50])), isNull);
    });

    test('rejects a plain shell/batch script', () {
      final bat = Uint8List.fromList('@ECHO OFF'.codeUnits);
      expect(detectDocumentMimeType(bat), isNull);
    });
  });
}