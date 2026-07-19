import 'dart:io';
import 'package:path_provider/path_provider.dart';

class StorageService {
  Future<String> saveDocument(
      File file, String folderName, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final customDir = Directory('${directory.path}/$folderName');

    if (!(await customDir.exists())) {
      await customDir.create(recursive: true);
    }

    final newPath = '${customDir.path}/$fileName';
    final savedFile = await file.copy(newPath);
    return savedFile.path;
  }
}
