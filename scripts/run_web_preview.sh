#!/usr/bin/env bash
set -euo pipefail

export PATH="/tmp/flutter/bin:$PATH"
export ANDROID_HOME="/tmp/android-sdk"
export JAVA_HOME="/nix/store/xad649j61kwkh0id5wvyiab5rliprp4d-openjdk-17.0.15+6/lib/openjdk"
export PUB_CACHE="/tmp/pub-cache"
export GRADLE_USER_HOME="/tmp/gradle-cache"
export CHROME_EXECUTABLE=""

flutter pub get
flutter build web --release

cd build/web
python3 -m http.server 5000
