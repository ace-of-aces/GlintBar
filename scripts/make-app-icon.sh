#!/usr/bin/env bash
# Renders Design/Icons/app.svg into Resources/AppIcon.icns.
# Needs rsvg-convert (brew install librsvg); only run it after changing the artwork.
set -euo pipefail
cd "$(dirname "$0")/.."

SVG=Design/Icons/app.svg
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"

# Each size is rendered from the vector source rather than scaled down from one big image.
for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" "$SVG" -o "$ICONSET/icon_${size}x${size}.png"
    rsvg-convert -w $((size * 2)) -h $((size * 2)) "$SVG" -o "$ICONSET/icon_${size}x${size}@2x.png"
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
rm -rf "$(dirname "$ICONSET")"
echo "Wrote Resources/AppIcon.icns"
