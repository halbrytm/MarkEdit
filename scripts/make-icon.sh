#!/bin/zsh
# Generuje build/AppIcon.icns z scripts/make_icon.swift
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -O scripts/make_icon.swift -o build/make_icon
build/make_icon build/icon_1024.png
ICONSET=build/AppIcon.iconset
rm -rf $ICONSET && mkdir -p $ICONSET
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon_1024.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/icon_1024.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o build/AppIcon.icns
echo "Zapisano build/AppIcon.icns"
