#!/usr/bin/env bash
# Builds a release NoHands.app into build/. Set CODESIGN_IDENTITY to a stable identity to keep
# macOS permission grants across rebuilds (default: ad-hoc "-").
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/NoHands.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NoHands" "$APP/Contents/MacOS/NoHands"
cp Resources/Info.plist "$APP/Contents/Info.plist"
for b in "$BIN_DIR"/*.bundle; do
    [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" "$APP"
echo "$(pwd)/$APP"
