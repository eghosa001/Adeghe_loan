---
name: Google Fonts Flutter compatibility
description: How to keep google_fonts compiling when the Flutter SDK is upgraded to 3.44+.
---

Old versions of `google_fonts` (≤6.3.0) fail to compile on Flutter 3.44+ because the package uses a `const` map whose keys are `FontWeight` values, and newer Flutter/Dart no longer allows those as const keys.

**Why:** The Dart SDK version bundled with Flutter 3.44 changed how const objects are evaluated. The `google_fonts` maintainers fixed this in newer versions, but the old package requires an older Dart SDK constraint.

**How to apply:**
1. Upgrade `google_fonts` to `^8.0.0` (or the latest compatible version).
2. Update the `pubspec.yaml` environment constraint to `sdk: '>=3.12.0 <4.0.0'` so the resolver accepts the new package.
3. Run `flutter pub get` and `flutter build web` / `flutter build apk` to verify.

**Note:** The fix is coupled. Only upgrading the package without raising the SDK constraint will fail resolution. Only raising the SDK constraint without upgrading the package leaves the compile error.
