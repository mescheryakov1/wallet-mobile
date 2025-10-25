#!/usr/bin/env bash
set -euxo pipefail

# Ensure Flutter iOS artifacts are available on the runner.
flutter precache --ios

# Fetch Dart and Flutter dependencies.
flutter pub get

# Build an unsigned IPA that can be signed later by CI.
# Flutter will produce an .xcarchive but will skip creating .ipa because of --no-codesign.
flutter build ipa --release --no-codesign

# Manually package unsigned IPA from the generated .xcarchive.
WORK_DIR="build/ios"
ARCHIVE_PATH="$WORK_DIR/archive/Runner.xcarchive"
IPA_DIR="$WORK_DIR/ipa"

mkdir -p "$IPA_DIR/Payload"

# Копируем собранное приложение в Payload
cp -R "$ARCHIVE_PATH/Products/Applications/Runner.app" "$IPA_DIR/Payload/Runner.app"

# Создаем ipa (это обычный zip с корнем Payload)
pushd "$IPA_DIR" >/dev/null
zip -r Runner-unsigned.ipa Payload
popd >/dev/null

# Print cache summary to help CI job configure persistence.
echo ""
echo "Cache directories for CI persistence:"
echo " - $HOME/.pub-cache"
echo " - $HOME/.gradle"
echo " - $HOME/.cache/flutter"
echo " - $HOME/Library/Caches/CocoaPods"
echo " - $HOME/Library/Developer/Xcode/DerivedData"
