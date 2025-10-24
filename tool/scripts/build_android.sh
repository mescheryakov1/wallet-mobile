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

RESOLVED_FLUTTER_VERSION="$(
  MIN_DART_VERSION="${MIN_DART_VERSION}" \
  MIN_FLUTTER_VERSION="${MIN_FLUTTER_VERSION}" \
  python - <<'PY'
import json
import os
import re
import sys
import urllib.request

min_dart = os.environ.get("MIN_DART_VERSION", "").strip()
if not min_dart:
    sys.exit(0)

min_flutter = os.environ.get("MIN_FLUTTER_VERSION", "").strip()


def parse_version(value: str):
    parts = [int(piece) for piece in re.split(r"[^0-9]+", value) if piece]
    return tuple(parts)


min_dart_tuple = parse_version(min_dart)
min_flutter_tuple = parse_version(min_flutter) if min_flutter else ()

try:
    with urllib.request.urlopen(
        "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json",
        timeout=10,
    ) as response:
        release_data = json.load(response)
except Exception:
    sys.exit(0)

best_version = ""
best_tuple = ()

for release in release_data.get("releases", []):
    if release.get("channel") != "stable":
        continue
    version = release.get("version") or ""
    dart_version = release.get("dart_sdk_version") or ""
    if not version or not dart_version:
        continue
    dart_tuple = parse_version(dart_version)
    if not dart_tuple:
        continue
    if min_dart_tuple and dart_tuple < min_dart_tuple:
        continue
    flutter_tuple = parse_version(version)
    if min_flutter_tuple and flutter_tuple < min_flutter_tuple:
        continue
    if not best_tuple or flutter_tuple > best_tuple:
        best_tuple = flutter_tuple
        best_version = version

if best_version:
    sys.stdout.write(best_version)
PY
)"
RESOLVED_FLUTTER_VERSION="${RESOLVED_FLUTTER_VERSION//$'\n'/}"

TARGET_FLUTTER_VERSION="${FLUTTER_VERSION_OVERRIDE:-${RESOLVED_FLUTTER_VERSION:-${MIN_FLUTTER_VERSION}}}"

if [[ -n "${RESOLVED_FLUTTER_VERSION}" ]]; then
  log "Resolved stable Flutter version with Dart >= ${MIN_DART_VERSION}: ${RESOLVED_FLUTTER_VERSION}"
fi
if [[ -n "${TARGET_FLUTTER_VERSION}" ]]; then
  log "Using Flutter target version ${TARGET_FLUTTER_VERSION}"
fi

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
  local machine_output=""
  if machine_output="$(flutter --version --machine 2>/dev/null)" && [[ -n "${machine_output}" ]]; then
    FLUTTER_MACHINE_JSON="${machine_output}" python - <<'PY'
import json
import os

info = json.loads(os.environ["FLUTTER_MACHINE_JSON"])
print(info.get("frameworkVersion", ""))
print(info.get("dartSdkVersion", "").split()[0])
PY
    return
  fi

  local human_output=""
  if human_output="$(flutter --version 2>/dev/null)" && [[ -n "${human_output}" ]]; then
    FLUTTER_HUMAN_READABLE="${human_output}" python - <<'PY'
import os
import re

text = os.environ["FLUTTER_HUMAN_READABLE"]
framework = re.search(r"Flutter\s+([0-9.]+)", text)
dart = re.search(r"Dart\s+([0-9.]+)", text)
print(framework.group(1) if framework else "")
print(dart.group(1) if dart else "")
PY
    return
  fi

  printf '\n\n'
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

function install_flutter_from_archive() {
  local desired_version="$1"
  local channel="${FLUTTER_CHANNEL:-stable}"

  if [[ -z "${desired_version}" ]]; then
    return 1
  fi

  local platform=""
  case "$(uname -s)" in
    Linux*) platform="linux" ;;
    Darwin*) platform="macos" ;;
    *)
      log "Unsupported platform $(uname -s) for Flutter archive installation."
      return 1
      ;;
  esac

  local cache_dir="${PROJECT_ROOT}/.tool-cache/flutter/${channel}-${desired_version}"
  local sdk_root="${cache_dir}/flutter"

  if [[ ! -x "${sdk_root}/bin/flutter" ]]; then
    if ! command -v curl >/dev/null 2>&1; then
      log "curl is required to download Flutter ${desired_version}"
      return 1
    fi

    log "Downloading Flutter ${desired_version}-${channel} SDK"
    rm -rf "${cache_dir}"
    mkdir -p "${cache_dir}"

    local archive=""
    local url=""
    if [[ "${platform}" == "linux" ]]; then
      archive="flutter_linux_${desired_version}-${channel}.tar.xz"
      url="https://storage.googleapis.com/flutter_infra_release/releases/${channel}/${platform}/${archive}"
    else
      archive="flutter_macos_${desired_version}-${channel}.zip"
      url="https://storage.googleapis.com/flutter_infra_release/releases/${channel}/${platform}/${archive}"
    fi

    if ! curl -L --retry 3 --retry-connrefused --retry-delay 2 -o "${cache_dir}/${archive}" "${url}"; then
      log "Failed to download Flutter archive from ${url}"
      return 1
    fi

    if [[ "${archive}" == *.zip ]]; then
      if ! command -v unzip >/dev/null 2>&1; then
        log "unzip is required to extract Flutter ${desired_version}"
        return 1
      fi
      if ! unzip -q "${cache_dir}/${archive}" -d "${cache_dir}"; then
        log "Failed to extract Flutter archive ${archive}"
        return 1
      fi
    else
      local tar_flags="-xf"
      [[ "${archive}" == *.tar.xz ]] && tar_flags="-xJf"

      if ! tar ${tar_flags} "${cache_dir}/${archive}" -C "${cache_dir}"; then
        log "Failed to extract Flutter archive ${archive}"
        return 1
      fi
    fi

    rm -f "${cache_dir}/${archive}"
  fi

  export FLUTTER_ROOT="${sdk_root}"
  export PATH="${FLUTTER_ROOT}/bin:${PATH}"
  hash -r

  log "Using Flutter SDK from ${FLUTTER_ROOT}"
  return 0
}

function upgrade_flutter() {
  local desired_version="$1"
  log "Upgrading Flutter SDK${desired_version:+ to ${desired_version}}"
  if install_flutter_from_archive "${desired_version}"; then
    flutter --version
    return
  fi

  if [[ -n "${desired_version}" ]]; then
    log "Falling back to in-place Flutter upgrade after archive installation failure"
  fi

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
