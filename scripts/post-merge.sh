#!/usr/bin/env bash
# Post-merge setup: runs after every task agent merge.
# Must be idempotent and non-interactive.
set -e

export PATH="/tmp/flutter/bin:$PATH"
export PUB_CACHE="/tmp/pub-cache"

# Restore flutter pub deps if pubspec changed
if command -v flutter &>/dev/null; then
  flutter pub get --no-example 2>/dev/null || true
fi

echo "Post-merge setup complete."
