import 'dart:io';
import 'package:path_provider/path_provider.dart';

class StorageService {
  Future<String> saveDocument(
      File file, String folderName, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final customDir = Directory(
        '${directory.path}/${_safeSegment(folderName)}');

    if (!(await customDir.exists())) {
      await customDir.create(recursive: true);
    }

    final newPath = '${customDir.path}/${_safeSegment(fileName)}';
    final savedFile = await file.copy(newPath);
    return savedFile.path;
  }

  /// Neutralizes path separators and parent-dir traversal so a crafted
  /// `folderName`/`fileName` can never escape the documents directory. All
  /// current callers pass fixed safe strings; this is defence-in-depth for
  /// any future caller that interpolates user input into a path segment.
  String _safeSegment(String value) {
    final cleaned = value
        .replaceAll('\\', '_')
        .replaceAll('/', '_')
        .replaceAll('..', '_');
    return cleaned.trim().isEmpty ? '_' : cleaned;
  }
}
