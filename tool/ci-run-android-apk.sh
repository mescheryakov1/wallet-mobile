#!/usr/bin/env bash
set -euo pipefail

ADB_BIN="${ADB_BIN:-adb}"

if ! command -v "${ADB_BIN}" >/dev/null 2>&1; then
  echo "${ADB_BIN} is required but not available in PATH." >&2
  exit 1
fi

if [[ -z "${APK_PATH:-}" ]]; then
  nullglob_was_set=0
  if shopt -q nullglob; then
    nullglob_was_set=1
  else
    shopt -s nullglob
  fi

  DEFAULT_APK_CANDIDATES=(
    downloaded-android-artifact/app-release.apk
    downloaded-android-artifact/app-debug.apk
    downloaded-android-artifact/*.apk
    build/app/outputs/flutter-apk/app-release.apk
    build/app/outputs/flutter-apk/app-profile.apk
    build/app/outputs/flutter-apk/app-debug.apk
  )

  for candidate in "${DEFAULT_APK_CANDIDATES[@]}"; do
    if [[ -f "$candidate" ]]; then
      APK_PATH="$candidate"
      break
    fi
  done

  if [[ $nullglob_was_set -eq 0 ]]; then
    shopt -u nullglob
  fi
fi

: "${APK_PATH:?APK file could not be located automatically. Set APK_PATH manually.}"

APP_PACKAGE="${APP_PACKAGE:-com.example.wallet_mobile}"

LAUNCH_ACTIVITY="${LAUNCH_ACTIVITY:-}"
WAIT_SECONDS="${APP_LAUNCH_WAIT_SECONDS:-20}"

"${ADB_BIN}" wait-for-device
"${ADB_BIN}" uninstall "${APP_PACKAGE}" >/dev/null 2>&1 || true
"${ADB_BIN}" install -r "${APK_PATH}"

if [[ -n "${LAUNCH_ACTIVITY}" ]]; then
  COMPONENT="${APP_PACKAGE}/${LAUNCH_ACTIVITY}"
  "${ADB_BIN}" shell am start -n "${COMPONENT}"
else
  "${ADB_BIN}" shell monkey -p "${APP_PACKAGE}" -c android.intent.category.LAUNCHER 1
fi

sleep "${WAIT_SECONDS}"

if ! "${ADB_BIN}" shell pidof "${APP_PACKAGE}" >/dev/null 2>&1; then
  echo "Application ${APP_PACKAGE} did not remain running after launch." >&2
  exit 1
fi

"${ADB_BIN}" shell am force-stop "${APP_PACKAGE}"

sleep 5

if "${ADB_BIN}" shell pidof "${APP_PACKAGE}" >/dev/null 2>&1; then
  echo "Application ${APP_PACKAGE} is still running after being force-stopped." >&2
  exit 1
fi

echo "Application ${APP_PACKAGE} was launched and closed successfully."
