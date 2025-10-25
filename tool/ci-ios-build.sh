#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS builds must run on macOS hosts." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is required but was not found in PATH." >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required but was not found in PATH." >&2
  exit 1
fi

if ! command -v pod >/dev/null 2>&1; then
  echo "CocoaPods (pod) is required but was not found in PATH." >&2
  exit 1
fi

# Important cache locations for faster incremental builds.
declare -ra CACHE_DIRS=(
  "$HOME/.pub-cache"
  "$HOME/.gradle"
  "$HOME/.cache/flutter"
  "$HOME/Library/Caches/CocoaPods"
  "$HOME/Library/Developer/Xcode/DerivedData"
)

for dir in "${CACHE_DIRS[@]}"; do
  mkdir -p "$dir"
  echo "Cache directory ready: $dir"
done

# Display environment information to help debugging CI failures.
flutter --version
xcodebuild -version
pod --version

# Ensure required Flutter artifacts are available ahead of time.
flutter precache --ios

# Fetch Dart and Flutter dependencies.
flutter pub get

# Build an unsigned IPA that can be signed later by CI.
# Flutter's build step will prepare Pods automatically if needed.
flutter build ipa --release --no-codesign

# Print cache summary to help CI job configure persistence.
echo "\nCache directories for CI persistence:" >&2
for dir in "${CACHE_DIRS[@]}"; do
  echo " - $dir" >&2
done
