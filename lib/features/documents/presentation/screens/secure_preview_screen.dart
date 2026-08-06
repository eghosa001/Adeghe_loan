import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../../../../core/constants/app_constants.dart';
import '../../data/models/document_entity.dart';
import '../providers/document_providers.dart';

class SecurePreviewScreen extends ConsumerWidget {
  const SecurePreviewScreen({super.key, required this.document});

  final CustomerDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decrypted = ref.watch(_decryptedDocumentProvider(document));
    return Scaffold(
      appBar: AppBar(
        title: Text(document.type.label),
        actions: [
          IconButton(
            onPressed: decrypted.valueOrNull == null
                ? null
                : () => _export(context, decrypted.value!.bytes),
            icon: const Icon(Icons.download),
            tooltip: 'Save decrypted copy',
          ),
        ],
      ),
      body: decrypted.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Decrypting document...'),
            ],
          ),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Unable to open this encrypted document.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        data: (data) => _buildContent(context, data),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, ({Uint8List bytes, String mimeType}) data) {
    // Render with the MIME type detected from the decrypted *content*, never the
    // stored metadata, so a row whose metadata disagrees with its bytes is not
    // steered into the wrong parser.
    if (data.mimeType == 'application/pdf') {
      return PdfPreview(
        build: (format) async => data.bytes,
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: false,
      );
    }
    if (data.mimeType.startsWith('image/')) {
      // Decode at, and never wider than, maxDocumentImageDimension so a crafted
      // image with huge intrinsic dimensions cannot exhaust device memory.
      // Flutter hoists cacheWidth/cacheHeight into a scaled decode, so the
      // full-resolution buffer is never materialized.
      const cap = AppConstants.maxDocumentImageDimension;
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
            child: Image.memory(
          data.bytes,
          cacheWidth: cap,
          cacheHeight: cap,
          gaplessPlayback: true,
        )),
      );
    }
    return const Center(
      child: Text('This file type cannot be previewed.'),
    );
  }

  Future<void> _export(BuildContext context, Uint8List data) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save an unencrypted copy?'),
        content: const Text(
          'This copy is stored in plain text in the app Documents folder. '
          'It will NOT be encrypted, so anyone with access to this device or '
          'a backup of that folder could read it. The encrypted original '
          'stays protected on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save copy'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${_safeExportName(document.originalName)}');
      await file.writeAsBytes(data, flush: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Document saved to ${file.path}')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Unable to save a copy on this device.'),
        ));
      }
    }
  }

  /// Makes [name] safe to store on any filesystem (Windows, Android, iOS):
  /// keeps only the base name, replaces characters that are illegal on Windows
  /// (and control characters), trims trailing dots/spaces, and falls back to a
  /// generic name when nothing remains. Path separators cannot survive, so a
  /// crafted original name cannot escape the Documents folder.
  String _safeExportName(String name) {
    final base = path.basename(name);
    final sanitized = base
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'[.\s]+$'), '');
    if (sanitized.isEmpty || sanitized == '.') {
      final extension = path.extension(base).toLowerCase();
      return extension.isEmpty ? 'document' : 'document$extension';
    }
    return sanitized;
  }
}

final _decryptedDocumentProvider =
    FutureProvider.family<({Uint8List bytes, String mimeType}), CustomerDocument>(
        (ref, document) {
  return ref.watch(documentRepositoryProvider).decrypt(document);
});
