#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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

MIN_FLUTTER_VERSION="$(PROJECT_ROOT="${PROJECT_ROOT}" python - <<'PY'
import os
import re
from pathlib import Path

lock_file = Path(os.environ["PROJECT_ROOT"]) / "pubspec.lock"
if lock_file.exists():
    match = re.search(r"flutter:\s*>=\s*([0-9.]+)", lock_file.read_text())
    if match:
        print(match.group(1))
        raise SystemExit
print("")
PY
)"

TARGET_FLUTTER_VERSION="${FLUTTER_VERSION_OVERRIDE:-${MIN_FLUTTER_VERSION}}"

function version_lt() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" != "$2" ]]
}

function flutter_root_dir() {
  if [[ -n "${FLUTTER_ROOT:-}" && -d "${FLUTTER_ROOT}" ]]; then
    printf '%s\n' "${FLUTTER_ROOT}"
    return
  fi
  local flutter_bin
  flutter_bin="$(command -v flutter)"
  if [[ -z "${flutter_bin}" ]]; then
    return 1
  fi
  (cd "$(dirname "${flutter_bin}")/.." && pwd)
}

function parse_flutter_versions() {
  flutter --version --machine | python - <<'PY'
import json
import sys

info = json.loads(sys.stdin.read())
print(info.get("frameworkVersion", ""))
print(info.get("dartSdkVersion", "").split()[0])
PY
}

function ensure_flutter_version() {
  local min_flutter="$1"
  local min_dart="$2"
  local target="$3"

  local versions
  IFS=$'\n' read -r current_flutter current_dart < <(parse_flutter_versions)

  if [[ -n "${current_flutter}" ]]; then
    log "Current Flutter version: ${current_flutter}"
  fi
  if [[ -n "${current_dart}" ]]; then
    log "Current Dart version: ${current_dart}"
  fi

  if [[ -n "${min_flutter}" && -n "${current_flutter}" ]]; then
    if version_lt "${current_flutter}" "${min_flutter}"; then
      log "Flutter ${current_flutter} is older than required ${min_flutter}."
      upgrade_flutter "${target:-${min_flutter}}"
      IFS=$'\n' read -r current_flutter current_dart < <(parse_flutter_versions)
      if [[ -n "${current_flutter}" ]] && version_lt "${current_flutter}" "${min_flutter}"; then
        log "Flutter ${current_flutter} remains below required ${min_flutter}. Set FLUTTER_VERSION_OVERRIDE to a newer stable release."
        exit 1
      fi
    fi
  fi

  if [[ -n "${min_dart}" && -n "${current_dart}" ]]; then
    if version_lt "${current_dart}" "${min_dart}"; then
      log "Dart ${current_dart} is older than required ${min_dart}."
      upgrade_flutter "${target:-}" "${min_dart}"
      IFS=$'\n' read -r current_flutter current_dart < <(parse_flutter_versions)
      if [[ -n "${current_dart}" ]] && version_lt "${current_dart}" "${min_dart}"; then
        log "Dart ${current_dart} is still below ${min_dart}. Set FLUTTER_VERSION_OVERRIDE to a release with Dart >= ${min_dart}."
        exit 1
      fi
    fi
  fi
}

function upgrade_flutter() {
  local desired_version="$1"
  log "Upgrading Flutter SDK${desired_version:+ to ${desired_version}}"
  flutter channel stable

  local root
  if ! root="$(flutter_root_dir)" || [[ -z "${root}" ]]; then
    log "Unable to determine Flutter SDK root. Falling back to \"flutter upgrade --force\"."
    flutter upgrade --force
    flutter --version
    return
  fi

  if [[ ! -d "${root}/.git" ]]; then
    log "Flutter SDK at ${root} is not a git checkout. Using \"flutter upgrade --force\"."
    flutter upgrade --force
    flutter --version
    return
  fi

  if [[ -n "${desired_version}" ]]; then
    if ! git -C "${root}" fetch --tags origin; then
      log "Failed to fetch Flutter tags. Falling back to \"flutter upgrade --force\"."
      flutter upgrade --force
      flutter --version
      return
    fi
    if git -C "${root}" rev-parse "refs/tags/${desired_version}" >/dev/null 2>&1; then
      git -C "${root}" checkout "tags/${desired_version}"
      git -C "${root}" clean -xfd
      flutter --version
      return
    else
      log "Tag ${desired_version} not found. Falling back to \"flutter upgrade --force\"."
    fi
  fi

  flutter upgrade --force
  flutter --version
}

ensure_flutter_version "${MIN_FLUTTER_VERSION}" "${MIN_DART_VERSION}" "${TARGET_FLUTTER_VERSION}"

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
