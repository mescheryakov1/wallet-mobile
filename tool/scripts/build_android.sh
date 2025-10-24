#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

function log() {
  printf '[build-android] %s\n' "$*"
}

pushd "${PROJECT_ROOT}" >/dev/null

SDK_PATH="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -n "${SDK_PATH}" ]]; then
  log "Configuring Flutter to use Android SDK at ${SDK_PATH}"
  flutter config --android-sdk "${SDK_PATH}"
fi

log "Pre-caching Android build artifacts"
flutter precache --android

log "Fetching pub dependencies"
flutter pub get

log "Building release APK"
flutter build apk --release "$@"

popd >/dev/null
