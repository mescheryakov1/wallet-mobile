#!/usr/bin/env bash
set -euo pipefail

# Reproduction harness for WalletConnect pairing on Android.
# Usage:
#   WC_URI="wc:..." DEVICE_ID="emulator-5554" ./tool/pairing_repro.sh
# The script will push the deeplink into the Android activity and stream logs
# from Flutter (WC:*), the Kotlin bridge (MainActivity), and the WalletConnect
# Dart service.

if [[ -z "${WC_URI:-}" ]]; then
  echo "WC_URI must be set to a valid WalletConnect URI (wc:...)" >&2
  exit 1
fi

DEVICE_ID=${DEVICE_ID:-}
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID=$(adb devices | awk 'NR==2 {print $1}')
fi

if [[ -z "$DEVICE_ID" || "$DEVICE_ID" == "List" ]]; then
  echo "No Android device/emulator detected; start one and re-run." >&2
  exit 1
fi

echo "Using device $DEVICE_ID"

echo "Launching WalletConnect intent..."
adb -s "$DEVICE_ID" shell am start \
  -a android.intent.action.VIEW \
  -d "$WC_URI" \
  com.example.wallet_mobile/.MainActivity

echo "Tailing logs (press Ctrl+C to stop)..."
adb -s "$DEVICE_ID" logcat -v time \
  MainActivity:D flutter:D WalletConnect:D WalletConnectService:D WC:D *:S
