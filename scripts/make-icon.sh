#!/bin/bash
# Regenerates Resources/AppIcon.icns and docs/icon.png from the drawing in
# Sources/BudsBar/Artwork.swift (the same one the panel and the menu bar use).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/BudsBar"
SET="$(mktemp -d)/BudsBar.iconset"
mkdir -p "$SET" docs
"$BIN" --icon "$SET/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
    sips -z $size $size "$SET/icon_512x512@2x.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
    [ $size = 512 ] || sips -z $((size * 2)) $((size * 2)) "$SET/icon_512x512@2x.png" \
        --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
cp "$SET/icon_512x512.png" docs/icon.png
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns and docs/icon.png"
