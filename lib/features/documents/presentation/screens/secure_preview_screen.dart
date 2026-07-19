import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../data/models/document_entity.dart';
import '../providers/document_providers.dart';

class SecurePreviewScreen extends ConsumerWidget {
  const SecurePreviewScreen({super.key, required this.document});

  final CustomerDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(_decryptedDocumentProvider(document));
    return Scaffold(
      appBar: AppBar(
        title: Text(document.type.label),
        actions: [
          IconButton(
            onPressed: bytes.valueOrNull == null
                ? null
                : () => _export(context, bytes.value!),
            icon: const Icon(Icons.download),
            tooltip: 'Save decrypted copy',
          ),
        ],
      ),
      body: bytes.when(
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

  Widget _buildContent(BuildContext context, Uint8List data) {
    if (document.isPdf) {
      return PdfPreview(
        build: (format) async => data,
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: false,
      );
    }
    if (document.isImage) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(child: Image.memory(data)),
      );
    }
    return const Center(
      child: Text('This file type cannot be previewed.'),
    );
  }

  Future<void> _export(BuildContext context, Uint8List data) async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save decrypted document',
        fileName: document.originalName,
      );
      if (path != null) {
        final file = File(path);
        await file.writeAsBytes(data, flush: true);
      }
      if (context.mounted && path != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Document saved.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Unable to save a copy on this device.'),
        ));
      }
    }
  }
}

final _decryptedDocumentProvider =
    FutureProvider.family<Uint8List, CustomerDocument>((ref, document) {
  return ref.watch(documentRepositoryProvider).decrypt(document);
});
