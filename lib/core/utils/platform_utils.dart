import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// True when running on a desktop OS (Windows, Linux, macOS). Desktop targets
/// have no camera hardware, so features that rely on `ImageSource.camera`
/// (image_picker throws on desktop) must be hidden rather than crash.
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// True when the current platform can capture photos from a camera.
bool get canUseCamera => !isDesktopPlatform;
