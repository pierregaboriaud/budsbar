#!/bin/bash
# Builds BudsBar.app in ./build.
#
# Signing: macOS ties the Bluetooth permission to the code signature. With an ad-hoc signature
# it is asked again after every rebuild; set CODESIGN_IDENTITY (or have an "Apple Development"
# certificate in the keychain) to keep it across builds.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/BudsBar"

APP=build/BudsBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BudsBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # made by scripts/make-icon.sh

IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null |
        sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)"
fi
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"
