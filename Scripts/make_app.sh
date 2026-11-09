#!/bin/bash
# Assembles build/artMouse.app from the release build output.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${ARTMOUSE_SIGNING_IDENTITY:--}"   # default: ad-hoc signing
APP="build/artMouse.app"

swift build -c release
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/artMouse" "$APP/Contents/MacOS/artMouse"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>app.artmouse</string>
    <key>CFBundleName</key><string>artMouse</string>
    <key>CFBundleExecutable</key><string>artMouse</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP"
