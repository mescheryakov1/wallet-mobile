#!/usr/bin/env bash
set -euo pipefail

ADB_BIN="${ADB_BIN:-adb}"

if ! command -v "${ADB_BIN}" >/dev/null 2>&1; then
  echo "${ADB_BIN} is required but not available in PATH." >&2
  exit 1
fi

: "${APK_PATH:?APK_PATH must point to the APK file to install}"
: "${APP_PACKAGE:?APP_PACKAGE must be provided (e.g. com.example.app)}"

LAUNCH_ACTIVITY="${LAUNCH_ACTIVITY:-}"
WAIT_SECONDS="${APP_LAUNCH_WAIT_SECONDS:-15}"

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
