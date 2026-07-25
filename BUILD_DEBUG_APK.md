# Build Debug APK — VS Code Local Guide

Use this guide on your local machine (Windows, macOS, or Linux) to build a debug APK from this Flutter project. Replit cannot build APKs because Flutter is installed under `/tmp` and the Android SDK is not available there.

---

## 1. Prerequisites

Install these on your local machine before starting:

- **Flutter SDK** (stable channel) — https://docs.flutter.dev/get-started/install
- **Android Studio** or **Android SDK Command Line Tools**
- **VS Code** with the **Flutter** and **Dart** extensions
- **Git**

Verify Flutter after installation:

```bash
flutter doctor
```

Fix any issues reported by `flutter doctor` before continuing.

---

## 2. Clone the Project

```bash
git clone https://github.com/eghosa001/Adeghe_loan.git
cd Adeghe_loan
```

---

## 3. Install Dependencies

```bash
flutter pub get
```

---

## 4. Fix `android/local.properties`

The repository contains `android/local.properties` pointing to `/tmp` paths used by Replit. On your local machine you must update it to your own Flutter and Android SDK locations.

Open `android/local.properties` and replace the contents with the correct paths for your machine.

### Example (Windows)

```properties
sdk.dir=C:\\Users\\YOUR_USERNAME\\AppData\\Local\\Android\\Sdk
flutter.sdk=C:\\Users\\YOUR_USERNAME\\flutter
flutter.buildMode=debug
flutter.versionName=1.0.0
flutter.versionCode=1
```

### Example (macOS / Linux)

```properties
sdk.dir=/Users/YOUR_USERNAME/Library/Android/sdk
flutter.sdk=/Users/YOUR_USERNAME/flutter
flutter.buildMode=debug
flutter.versionName=1.0.0
flutter.versionCode=1
```

Find your SDK path with:

```bash
flutter config --android-sdk
# or
which flutter
```

> **Do not commit `android/local.properties`** — it is machine-specific. The file is already in `.gitignore` in most Flutter projects.

---

## 5. Build the Debug APK

### Option A — From VS Code

1. Open the project folder in VS Code.
2. Connect an Android device or start an emulator.
3. Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac).
4. Run: **Flutter: Build APK** or select **Debug > Start Debugging** to run on a device.

### Option B — From Terminal

```bash
flutter build apk --debug
```

The APK will be created at:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

---

## 6. Install the APK on a Device

```bash
flutter install
```

Or manually install the APK:

```bash
adb install build/app/outputs/flutter-apk/app-debug.apk
```

---

## 7. Common Issues

### Issue: `ANDROID_SDK_ROOT` not found

Set the environment variable:

```bash
export ANDROID_SDK_ROOT=/Users/YOUR_USERNAME/Library/Android/sdk
```

On Windows, set it via System Environment Variables.

### Issue: Gradle fails or Java version mismatch

Make sure you are using a Java version compatible with the Gradle version in `android/gradle/wrapper/gradle-wrapper.properties`. Flutter 3.x usually needs Java 17.

```bash
flutter doctor --android-licenses
```

Accept all licenses.

### Issue: `local.properties` keeps resetting

Delete it and let Flutter regenerate it:

```bash
rm android/local.properties
flutter build apk --debug
```

---

## 8. Quick Checklist

- [ ] `flutter doctor` shows all green ticks
- [ ] `android/local.properties` points to your local SDKs
- [ ] `flutter pub get` ran successfully
- [ ] Device/emulator is connected or `adb devices` shows it
- [ ] Ran `flutter build apk --debug`
- [ ] APK found at `build/app/outputs/flutter-apk/app-debug.apk`

---

## Notes

- The Replit preview only supports **web preview**. APK builds must be done locally.
- The database is encrypted with SQLCipher; the app will create the encrypted database on first run on the device.
- If you need a **release APK** later, run `flutter build apk --release` instead.
