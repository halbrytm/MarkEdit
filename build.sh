#!/bin/zsh
# Buduje MarkEdit.app.   ./build.sh            → build/MarkEdit.app
#                        ./build.sh --install  → dodatkowo kopiuje do /Applications
set -euo pipefail
cd "$(dirname "$0")"

[[ -f Resources/web/vendor/markdown-it.min.js ]] || ./scripts/fetch-vendor.sh
[[ -f build/AppIcon.icns ]] || ./scripts/make-icon.sh

swift build -c release

APP=build/MarkEdit.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources/pl.lproj
cp .build/release/MarkEdit $APP/Contents/MacOS/
cp Resources/Info.plist $APP/Contents/
cp build/AppIcon.icns $APP/Contents/Resources/
rsync -a --exclude demo.md Resources/web $APP/Contents/Resources/
codesign --force --deep --sign - $APP
echo "Zbudowano $APP"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'quit app "MarkEdit"' 2>/dev/null || true
  rm -rf /Applications/MarkEdit.app
  cp -R $APP /Applications/
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/MarkEdit.app
  echo "Zainstalowano w /Applications/MarkEdit.app"
fi
