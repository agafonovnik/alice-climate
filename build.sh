#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source scripts/swift-env.sh

swift build "${SWIFT_OPTIONS[@]}" -c release --product AliceClimate
BIN_DIR="$(swift build "${SWIFT_OPTIONS[@]}" -c release --show-bin-path)"
OUTPUT_DIR="${ALICE_OUTPUT_DIR:-$PWD/dist}"
APP="$OUTPUT_DIR/Алиса Климат.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AliceClimate" "$APP/Contents/MacOS/Алиса Климат"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "${SIGN_IDENTITY:--}" --identifier local.aliceclimate "$APP"
codesign --verify --deep --strict "$APP"
printf 'Готово: %s\n' "$APP"
