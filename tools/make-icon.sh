#!/bin/zsh
# Redraws Resources/AppIcon.icns from IconArt.swift (Saku --make-icon) with iconutil.
set -euo pipefail
cd "${0:A:h}/.."
swift build
tmp=$(mktemp -d)
.build/debug/Saku --make-icon "$tmp"
iconutil -c icns "$tmp/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$tmp/AppIcon.iconset/icon_512x512@2x.png" docs/icon.png
rm -rf "$tmp"
echo "wrote Resources/AppIcon.icns and docs/icon.png"
