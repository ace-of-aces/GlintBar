#!/usr/bin/env bash
# Packages build/GlintBar.app (from build-app.sh) into build/GlintBar.dmg, with an
# Applications link to drag it onto.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/GlintBar.app
DMG=build/GlintBar.dmg
STAGING=build/dmg

[[ -d "$APP" ]] || { echo "Missing $APP, run scripts/build-app.sh first" >&2; exit 1; }

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname GlintBar -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGING"
echo "Built $DMG"
