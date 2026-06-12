#!/bin/bash
# Builds Sootling.app, signs it, optionally notarizes, and packages as DMG.
# Usage:
#   ./scripts/distribute.sh                           # ad-hoc signed (Gatekeeper warning)
#   ./scripts/distribute.sh --notarize                # Developer ID + notarization
#
# Notarization requires:
#   1. Apple Developer ID certificate in your keychain
#   2. App Store Connect API key at ~/.private_keys/AuthKey_<key_id>.p8
#      (or set NOTARY_KEY, NOTARY_KEY_ID, NOTARY_ISSUER below)
#   3. Xcode 13.2+ for notarytool
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Sootling/App/Info.plist)
BUNDLE_ID="app.sootling.Sootling"
APP_NAME="Sootling"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGING="$DIST/dmg-staging"
NOTARIZE=false

for arg in "$@"; do
  case "$arg" in
    --notarize) NOTARIZE=true ;;
  esac
done

# ── Apple Developer credentials ──────────────────────────────────────
# Either set these env vars or the script autodetects from ~/.private_keys/
NOTARY_KEY="${NOTARY_KEY:-}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:-}"
NOTARY_ISSUER="${NOTARY_ISSUER:-}"
TEAM_ID="${TEAM_ID:-}"

# Auto-detect API key if NOTARY_KEY_ID not set
if [ -z "$NOTARY_KEY_ID" ]; then
  for f in "$HOME"/.private_keys/AuthKey_*.p8; do
    if [ -f "$f" ]; then
      basename="${f##*/}"
      NOTARY_KEY_ID="${basename#AuthKey_}"
      NOTARY_KEY_ID="${NOTARY_KEY_ID%.p8}"
      NOTARY_KEY="$f"
      break
    fi
  done
fi

# ── Step 1: Build ────────────────────────────────────────────────────
echo "▸ Building release binary..."
swift build -c release

# ── Step 2: Assemble .app bundle ─────────────────────────────────────
echo "▸ Assembling ${APP}..."
rm -rf "$APP" "$STAGING" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
if [ -d ".build/release/${APP_NAME}_SootlingCore.bundle" ]; then
  cp -R ".build/release/${APP_NAME}_SootlingCore.bundle" "$APP/Contents/Resources/"
fi
cp "Sootling/App/Info.plist" "$APP/Contents/Info.plist"
cp "Sootling/App/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# ── Step 3: Sign ─────────────────────────────────────────────────────
# Find Developer ID certificate if NOTARIZE requested
SIGN_IDENTITY="-"
if [ "$NOTARIZE" = true ]; then
  CERT=$(security find-identity -v -p basic 2>/dev/null | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)
  if [ -z "$CERT" ]; then
    echo "❌ --notarize requires a 'Developer ID Application' certificate in your keychain."
    echo "   Get one at https://developer.apple.com/account/resources/certificates/"
    exit 1
  fi
  SIGN_IDENTITY="$CERT"
  echo "▸ Signing with '${SIGN_IDENTITY}'..."
else
  echo "▸ Ad-hoc signing (Gatekeeper will warn users on download)..."
fi

codesign --force --deep --sign "$SIGN_IDENTITY" --options runtime "$APP"

# Verify signing
codesign -dvvv "$APP" 2>&1 | grep "Signed\." || true

# ── Step 4: Notarization ──────────────────────────────────────────────
if [ "$NOTARIZE" = true ]; then
  if [ -z "$NOTARY_KEY" ] || [ -z "$NOTARY_KEY_ID" ] || [ -z "$NOTARY_ISSUER" ]; then
    echo "❌ Notarization requires NOTARY_KEY, NOTARY_KEY_ID, and NOTARY_ISSUER."
    echo "   Set them as env vars or place an API key at ~/.private_keys/AuthKey_<key_id>.p8"
    echo "   Get one at https://appstoreconnect.apple.com/access/integrations/api"
    exit 1
  fi

  echo "▸ Zipping app for notarization..."
  ZIP="$DIST/$APP_NAME-$VERSION.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"

  echo "▸ Submitting to Apple for notarization..."
  SUBMISSION=$(xcrun notarytool submit "$ZIP" \
    --key "$NOTARY_KEY" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER" \
    --wait 2>&1 | tee /dev/stderr)
  SUBMISSION_ID=$(echo "$SUBMISSION" | grep -o "id: [a-f0-9-]*" | head -1 | cut -d' ' -f2 || true)

  if [ -n "$SUBMISSION_ID" ]; then
    echo "▸ Stapling notarization ticket..."
    xcrun stapler staple "$APP"
    echo "✓ Notarization complete"
  else
    echo "⚠ Notarization submission may have failed. Check the log above."
  fi
  rm -f "$ZIP"
fi

# ── Step 5: Package as DMG ──────────────────────────────────────────
echo "▸ Creating DMG..."
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

# If notarized, also staple to DMG
if [ "$NOTARIZE" = true ] && command -v xcrun stapler >/dev/null 2>&1; then
  xcrun stapler staple "$DMG" 2>/dev/null || true
fi

echo ""
echo "✓ $DMG"

# ── Summary ──────────────────────────────────────────────────────────
if [ "$NOTARIZE" = false ]; then
  SIGN_INFO=$(codesign -dvvv "$APP" 2>&1 | grep "Signed\." || true)
  if echo "$SIGN_INFO" | grep -q "adhoc"; then
    echo ""
    echo "⚠  AD-HOC SIGNED — downloaded copies will show 'not safe for Apple'."
    echo "   To fix: get an Apple Developer account and run with --notarize"
  fi
fi
