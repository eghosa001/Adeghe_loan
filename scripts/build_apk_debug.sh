#!/usr/bin/env bash
set -euo pipefail

export PATH="/tmp/flutter/bin:$PATH"
export ANDROID_HOME="/tmp/android-sdk"
export JAVA_HOME="/nix/store/xad649j61kwkh0id5wvyiab5rliprp4d-openjdk-17.0.15+6/lib/openjdk"
export PUB_CACHE="/tmp/pub-cache"
export GRADLE_USER_HOME="/tmp/gradle-cache"

if ! command -v flutter &> /dev/null; then
  echo "Flutter not found on PATH. Install Flutter in /tmp and add /tmp/flutter/bin to PATH."
  exit 1
fi

if [ -z "${ANDROID_HOME:-}" ]; then
  echo "ANDROID_HOME is not set."
  exit 1
fi

flutter config --android-sdk "$ANDROID_HOME" > /dev/null 2>&1 || true
flutter config --jdk-dir "$JAVA_HOME" > /dev/null 2>&1 || true
yes | flutter doctor --android-licenses 2>/dev/null || true

flutter pub get
flutter build apk --debug

echo "APK location:"
ls -lh "build/app/outputs/flutter-apk/app-debug.apk"
