#!/bin/bash
# Builds BudsBar, installs it in /Applications and (re)starts it.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
osascript -e 'tell application id "io.github.pierregaboriaud.BudsBar" to quit' >/dev/null 2>&1 || true
pkill -x BudsBar 2>/dev/null || true
rm -rf /Applications/BudsBar.app
cp -R build/BudsBar.app /Applications/BudsBar.app
open /Applications/BudsBar.app
echo "Installed /Applications/BudsBar.app — look for the earbuds icon in the menu bar."
