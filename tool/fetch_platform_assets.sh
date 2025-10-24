#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required to generate platform assets." >&2
  exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

flutter create --platforms=android,ios,windows "$TEMP_DIR/template" >/dev/null 2>&1

cp -R "$TEMP_DIR/template/android/app/src/main/res/"mipmap-* "$PROJECT_ROOT/android/app/src/main/res/" 2>/dev/null || true
cp -R "$TEMP_DIR/template/ios/Runner/Assets.xcassets/AppIcon.appiconset" "$PROJECT_ROOT/ios/Runner/Assets.xcassets/" 2>/dev/null || true
cp -R "$TEMP_DIR/template/ios/Runner/Assets.xcassets/LaunchImage.imageset" "$PROJECT_ROOT/ios/Runner/Assets.xcassets/" 2>/dev/null || true
cp "$TEMP_DIR/template/windows/runner/resources/app_icon.ico" "$PROJECT_ROOT/windows/runner/resources/" 2>/dev/null || true

echo "Platform-specific binary assets restored."
