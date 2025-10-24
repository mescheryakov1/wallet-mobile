#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

function log() {
  printf '[build-android] %s\n' "$*"
}

pushd "${PROJECT_ROOT}" >/dev/null

PUBSPEC_PATH="${PROJECT_ROOT}/pubspec.yaml"
if [[ ! -f "${PUBSPEC_PATH}" ]]; then
  log "Unable to locate pubspec.yaml at ${PUBSPEC_PATH}"
  log "Ensure the repository is checked out before invoking this script."
  exit 1
fi

MIN_DART_VERSION="$(PROJECT_ROOT="${PROJECT_ROOT}" python - <<'PY'
import os
import re
from pathlib import Path

pubspec = Path(os.environ["PROJECT_ROOT"]) / "pubspec.yaml"
match = re.search(r"sdk:\s*>=\s*([0-9.]+)", pubspec.read_text())
print(match.group(1) if match else "0.0.0")
PY
)"
TARGET_FLUTTER_VERSION="${FLUTTER_VERSION_OVERRIDE:-3.35.7}"

function version_lt() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" != "$2" ]]
}

if command -v dart >/dev/null 2>&1; then
  CURRENT_DART_VERSION="$(dart --version 2>&1 | awk '{print $4}')"
  if version_lt "${CURRENT_DART_VERSION}" "${MIN_DART_VERSION}"; then
    log "Detected Dart ${CURRENT_DART_VERSION}, but project requires >= ${MIN_DART_VERSION}."
    log "Switching Flutter SDK to ${TARGET_FLUTTER_VERSION} to satisfy Dart constraint."
    yes | flutter version "${TARGET_FLUTTER_VERSION}"
    flutter --version
  fi
fi

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
