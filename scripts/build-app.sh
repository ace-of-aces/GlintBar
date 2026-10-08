#!/usr/bin/env bash
# Builds build/Glint.app. Pass --install to also copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP=build/Glint.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Glint" "$APP/Contents/MacOS/Glint"
# Loaded by /usr/bin/perl at runtime for now-playing state (see NowPlayingMonitor.swift).
cp "$BIN_DIR/libGlintNowPlaying.dylib" "$APP/Contents/Frameworks/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP/Contents/Frameworks/libGlintNowPlaying.dylib"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Glint 2>/dev/null && sleep 0.5 || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/Glint.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/Glint.app
    echo "Installed and launched ~/Applications/Glint.app"
fi
