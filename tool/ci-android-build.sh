#!/usr/bin/env bash
set -euo pipefail

# Ensure the android sdkmanager is available in PATH
declare -r DEFAULT_ANDROID_SDK_DIR="$ANDROID_HOME"
if [[ -z "${DEFAULT_ANDROID_SDK_DIR:-}" ]]; then
  echo "ANDROID_HOME is not set. Exiting." >&2
  exit 1
fi

# Show Flutter version for debugging
flutter --version

# Ensure all Flutter dependencies are ready
flutter pub get

# Build the release APK
flutter build apk --release
