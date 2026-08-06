import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guard against the SQLCipher native-library shadowing bug (2026-08-05).
///
/// The sqlite3 package's native-assets hook (`hooks.user_defines.sqlite3.source:
/// sqlcipher` in pubspec, needed only for the Windows desktop build) also
/// downloads a raw `libsqlcipher.so` for the Android ABIs. sqflite_sqlcipher
/// bundles its own SQLCipher native library through the net.zetetic AAR whose
/// `libsqlcipher.so` carries the Zetetic JNI (`net.zetetic.database.sqlcipher.*`,
/// exported symbol `nativeOpen`) that the plugin calls. Both share the file name,
/// and if the raw sqlite3 build shadows the AAR's, the APK opens the encrypted
/// DB with `UnsatisfiedLinkError` right after PIN unlock.
///
/// `android/app/build.gradle.kts` already deletes the staged raw copy and fails
/// the build on a bad APK; this test is a second, durable net that runs with the
/// rest of the suite on whatever APK has been built.
void main() {
  final root = Directory.current.path;
  final outputDir = Directory('$root/build/app/outputs/flutter-apk');
  final apks = outputDir.existsSync()
      ? outputDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.apk'))
          .toList()
      : <File>[];

  if (apks.isEmpty) {
    // Nothing built yet — nothing to verify (e.g. `flutter test` on a clean
    // checkout before the first `flutter build`).
    return;
  }

  test('every built APK ships a libsqlcipher.so with the Zetetic JNI', () {
    final failures = <String>[];

    for (final apk in apks) {
      final archive = ZipDecoder().decodeBytes(apk.readAsBytesSync());
      final entries = archive.files
          .where((f) =>
              f.isFile && f.name.startsWith('lib/') && f.name.endsWith('/libsqlcipher.so'))
          .toList();

      if (entries.isEmpty) {
        failures.add(
            '${apk.path}: no libsqlcipher.so found under lib/*/. A raw sqlite3 '
            'build has either shadowed it or it was stripped entirely.');
        continue;
      }

      for (final entry in entries) {
        final text = latin1.decode(entry.content as List<int>);
        if (!text.contains('nativeOpen')) {
          failures.add(
              '${apk.path} -> ${entry.name}: missing the Zetetic JNI export '
              "'nativeOpen'. The sqlite3 native-assets hook is shadowing the "
              'net.zetetic AAR on Android; the app will crash with '
              'UnsatisfiedLinkError at database open.');
        }
      }
    }

    expect(failures, isEmpty,
        reason: failures.isEmpty ? null : failures.join('\n'));
  });
}
