#!/usr/bin/env bash
# Builds build/GlintBar.app as a universal binary (Touch Bar Macs include Intel models).
# Pass --install to also copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"
APP=build/GlintBar.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/GlintBar" "$APP/Contents/MacOS/GlintBar"
# Loaded by /usr/bin/perl at runtime for now-playing state (see NowPlayingMonitor.swift).
cp "$BIN_DIR/libGlintBarNowPlaying.dylib" "$APP/Contents/Frameworks/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP/Contents/Frameworks/libGlintBarNowPlaying.dylib"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x GlintBar 2>/dev/null && sleep 0.5 || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/GlintBar.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/GlintBar.app
    echo "Installed and launched ~/Applications/GlintBar.app"
fi
