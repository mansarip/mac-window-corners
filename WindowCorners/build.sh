#!/bin/bash
# Builds "build/Window Corners.app" (ad-hoc signed). Pass --install to copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Window Corners.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library -target arm64-apple-macos26.0 Sources/*.swift -o "$APP/Contents/MacOS/WindowCorners"
cp Info.plist "$APP/Contents/Info.plist"

if [ ! -f build/AppIcon.icns ]; then
  swift Scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/"Window Corners.app"
  cp -R "$APP" ~/Applications/
  echo "Installed to ~/Applications/Window Corners.app"
fi
