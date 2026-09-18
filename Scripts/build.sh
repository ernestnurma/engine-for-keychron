#!/bin/bash
# Builds "Engine for Keychron.app" (Apple Silicon) and packages it into a DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Engine for Keychron"
VERSION="1.0.0"
BUILD="$ROOT/.build"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

cd "$ROOT"
swift build -c release --arch arm64 --product EngineForKeychron
BIN="$(swift build -c release --arch arm64 --show-bin-path)/EngineForKeychron"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/EngineForKeychron"

ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET"
swift "$ROOT/Scripts/make_icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>EngineForKeychron</string>
    <key>CFBundleIdentifier</key><string>io.github.engine-for-keychron</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key><string>Reads battery level and firmware version from your Keychron mouse while it is connected over Bluetooth.</string>
    <key>NSHumanReadableCopyright</key><string>Unofficial tool for Keychron M-series mice.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature (required to run on Apple Silicon).
codesign --force --deep --sign - "$APP"

STAGE="$BUILD/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DIST/EngineForKeychron-$VERSION.dmg" >/dev/null
echo "Built: $DIST/EngineForKeychron-$VERSION.dmg"
