#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

pushd "${PROJECT_ROOT}" >/dev/null
flutter config --enable-android
flutter pub get
flutter build apk --release "$@"
popd >/dev/null
