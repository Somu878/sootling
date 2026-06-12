#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
DIST_DIR="$ROOT_DIR/dist"
STAMP="$(date +%Y%m%d-%H%M%S)"
BUILD_DIR="$DIST_DIR/build-$STAMP"
APP="$BUILD_DIR/Sootling.app"
DMG="$DIST_DIR/Sootling-$STAMP.dmg"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$RELEASE_DIR/Sootling" "$APP/Contents/MacOS/Sootling"
cp "$ROOT_DIR/Sootling/App/Info.plist" "$APP/Contents/Info.plist"
cp -R "$RELEASE_DIR/Sootling_SootlingCore.bundle" "$APP/Contents/Resources/Sootling_SootlingCore.bundle"
cp "$ROOT_DIR/Sootling/App/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Sootling" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Sootling" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundlePackageType APPL" "$APP/Contents/Info.plist"

printf 'APPL????' > "$APP/Contents/PkgInfo"
chmod +x "$APP/Contents/MacOS/Sootling"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP/Contents/Resources/Sootling_SootlingCore.bundle" >/dev/null
  codesign --force --sign - "$APP" >/dev/null
fi

hdiutil create \
  -volname "Sootling" \
  -srcfolder "$APP" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

echo "$DMG"
