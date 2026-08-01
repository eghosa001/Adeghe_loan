import 'dart:io';


import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:loantrack/core/security/file_encryption_service.dart';
import 'package:loantrack/core/widgets/empty_state.dart';

import '../../data/document_repository.dart';
import '../../data/models/document_entity.dart';
import '../providers/document_providers.dart';

class DocumentListScreen extends ConsumerStatefulWidget {
  const DocumentListScreen({super.key, required this.customerId});
  final String customerId;

  @override
  ConsumerState<DocumentListScreen> createState() =>
      _DocumentListScreenState();
}

class _DocumentListScreenState extends ConsumerState<DocumentListScreen> {
  bool _working = false;

  Future<void> _addDocument() async {
    final type = await showModalBottomSheet<CustomerDocumentType>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        children: CustomerDocumentType.values
            .map((type) => ListTile(
                title: Text(type.label),
                onTap: () => Navigator.pop(context, type)))
            .toList(),
      ),
    );
    if (type == null) return;
    final source = await _pickSource();
    if (source == null) return;
    await _withProgress(() => ref
        .read(documentRepositoryProvider)
        .add(customerId: widget.customerId, type: type, source: source));
  }

  Future<void> _replace(CustomerDocument document) async {
    final source = await _pickSource();
    if (source == null) return;
    await _withProgress(
        () => ref.read(documentRepositoryProvider).replace(document, source));
  }

  Future<File?> _pickSource() async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
          child: Wrap(children: [
        ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Choose image or PDF'),
            onTap: () => Navigator.pop(context, false)),
        ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Scan with camera'),
            onTap: () => Navigator.pop(context, true)),
      ])),
    );
    if (camera == null) return null;
    if (camera) {
      final image = await ImagePicker().pickImage(
          source: ImageSource.camera, imageQuality: 90, maxWidth: 1600);
      return image == null ? null : File(image.path);
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
    );
    if (result == null || result.files.isEmpty) return null;
    return File(result.files.single.path!);
  }

  Future<void> _withProgress(Future<Object?> Function() action) async {
    setState(() => _working = true);
    try {
      await action();
      ref.invalidate(customerDocumentsProvider(widget.customerId));
    } on DocumentFileException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on FileEncryptionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Unable to secure this document. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _delete(CustomerDocument document) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Delete document?'),
                content: const Text(
                    'The encrypted file and its record will be permanently deleted.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'))
                ]));
    if (confirmed != true) return;
    await _withProgress(
        () => ref.read(documentRepositoryProvider).delete(document));
  }

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(customerDocumentsProvider(widget.customerId));
    return Scaffold(
      appBar: AppBar(title: const Text('Customer documents')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _working ? null : _addDocument,
          icon: const Icon(Icons.upload_file),
          label: const Text('Upload')),
      body: documents.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Unable to load documents: $error')),
        data: (items) => items.isEmpty
            ? const EmptyState(
                icon: Icons.folder_open_outlined,
                title: 'No documents yet',
                subtitle: 'Upload an image or PDF to keep records safe.',
              )
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final document = items[index];
                  return Card(
                      child: ListTile(
                    leading: Icon(document.isPdf
                        ? Icons.picture_as_pdf
                        : Icons.image_outlined),
                    title: Text(document.type.label),
                    subtitle:
                        Text('${document.originalName}\nEncrypted on device'),
                    isThreeLine: true,
                    onTap: () => context.push('/documents/preview',
                        extra: document),
                    trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'replace') _replace(document);
                          if (action == 'delete') _delete(document);
                        },
                        itemBuilder: (context) => const [
                              PopupMenuItem(
                                  value: 'replace', child: Text('Replace')),
                              PopupMenuItem(
                                  value: 'delete', child: Text('Delete'))
                            ]),
                  ));
                },
              ),
      ),
    );
  }
}
