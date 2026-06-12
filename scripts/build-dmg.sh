#!/bin/bash
# Builds Sootling.app from the SwiftPM release binary and packages it as a DMG.
# Output: dist/Sootling-<version>.dmg
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Sootling/App/Info.plist)
APP_NAME="Sootling"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGING="$DIST/dmg-staging"

echo "▸ Building release binary..."
swift build -c release

echo "▸ Assembling ${APP}..."
rm -rf "$APP" "$STAGING" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
# SwiftPM resource bundle (model registry JSON); Bundle.module finds it in Resources.
if [ -d ".build/release/${APP_NAME}_SootlingCore.bundle" ]; then
  cp -R ".build/release/${APP_NAME}_SootlingCore.bundle" "$APP/Contents/Resources/"
fi
cp "Sootling/App/Info.plist" "$APP/Contents/Info.plist"
cp "Sootling/App/Sootling.icns" "$APP/Contents/Resources/Sootling.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Ad-hoc signing..."
codesign --force --deep --sign - "$APP"

echo "▸ Creating DMG..."
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "✓ $DMG"
du -h "$DMG" | cut -f1
