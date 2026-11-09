#!/usr/bin/env bash
# Builds a release NoHands.app into build/. Set CODESIGN_IDENTITY to a stable identity to keep
# macOS permission grants across rebuilds (default: ad-hoc "-").
set -euo pipefail
cd "$(dirname "$0")/.."

# Best effort: warn (stderr only) when this checkout is behind origin/main, so a build never silently
# lacks merged features. Every command is guarded so `set -e` cannot stop the build.
if git rev-parse --git-dir >/dev/null 2>&1; then
    GIT_TERMINAL_PROMPT=0 git fetch --quiet origin main >/dev/null 2>&1 || true
    if git rev-parse --verify --quiet origin/main >/dev/null 2>&1 \
        && ! git merge-base --is-ancestor origin/main HEAD >/dev/null 2>&1; then
        behind="$(git rev-list --count HEAD..origin/main 2>/dev/null || echo '?')"
        branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
        echo "warning: building ${branch}, ${behind} commits behind origin/main. Features merged since then will be missing." >&2
    fi
fi

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/NoHands.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NoHands" "$APP/Contents/MacOS/NoHands"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
for b in "$BIN_DIR"/*.bundle; do
    [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" "$APP"
echo "$(pwd)/$APP"
