import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/document_repository.dart';
import '../../data/models/document_entity.dart';
import '../providers/document_providers.dart';

class DocumentUploadScreen extends ConsumerStatefulWidget {
  const DocumentUploadScreen({
    super.key,
    required this.customerId,
    this.loanId,
  });

  final String customerId;
  final String? loanId;

  @override
  ConsumerState<DocumentUploadScreen> createState() =>
      _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends ConsumerState<DocumentUploadScreen> {
  CustomerDocumentType? _selectedType;
  File? _selectedFile;
  bool _uploading = false;

  Future<void> _pickFile() async {
    final source = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Choose image or PDF'),
            onTap: () => Navigator.pop(context, false),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Scan with camera'),
            onTap: () => Navigator.pop(context, true),
          ),
        ]),
      ),
    );
    if (source == null) return;

    if (source) {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        maxWidth: 1600,
      );
      if (image != null) setState(() => _selectedFile = File(image.path));
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      );
      final path = result?.files.single.path;
      if (path != null) setState(() => _selectedFile = File(path));
    }
  }

  Future<void> _upload() async {
    if (_selectedType == null || _selectedFile == null) return;
    setState(() => _uploading = true);
    try {
      await ref.read(documentRepositoryProvider).add(
            customerId: widget.customerId,
            type: _selectedType!,
            source: _selectedFile!,
            loanId: widget.loanId,
          );
      ref.invalidate(customerDocumentsProvider(widget.customerId));
      if (mounted) Navigator.of(context).pop(true);
    } on DocumentFileException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Upload failed. Please try again.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Upload document')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<CustomerDocumentType>(
              value: _selectedType,
              decoration: const InputDecoration(
                labelText: 'Document type',
                border: OutlineInputBorder(),
              ),
              items: CustomerDocumentType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: _uploading
                  ? null
                  : (value) => setState(() => _selectedType = value),
            ),
            const SizedBox(height: 16),
            Card(
              child: InkWell(
                onTap: _uploading ? null : _pickFile,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 40),
                  child: Column(
                    children: [
                      Icon(
                        _selectedFile != null
                            ? Icons.check_circle_outline
                            : Icons.add_circle_outline,
                        size: 48,
                        color: _selectedFile != null
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _selectedFile != null
                            ? _selectedFile!.path.split(Platform.pathSeparator).last
                            : 'Tap to select a file',
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'PDF, PNG, JPG, or JPEG \u2022 Max 20 MB',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_selectedFile != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _uploading ? null : () => setState(() => _selectedFile = null),
                icon: const Icon(Icons.close),
                label: const Text('Clear selection'),
              ),
            ],
            const SizedBox(height: 24),
            if (_uploading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: (_selectedType != null && _selectedFile != null && !_uploading)
                  ? _upload
                  : null,
              icon: _uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(_uploading ? 'Encrypting & uploading...' : 'Upload'),
            ),
          ],
        ),
      ),
    );
  }
}
