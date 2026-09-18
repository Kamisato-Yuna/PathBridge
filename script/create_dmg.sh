#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/PathBridge.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/pathbridge-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/PathBridge.app"
ln -s /Applications "$STAGING/Applications"
DMG="dist/PathBridge-$VERSION.dmg"
hdiutil create -volname "PathBridge $VERSION" -srcfolder "$STAGING" -format UDZO -ov "$DMG"
codesign --force --timestamp --sign "${PATHBRIDGE_SIGNING_IDENTITY:-Developer ID Application: Yuna Kamisato (852H844JG2)}" "$DMG"
hdiutil verify "$DMG"
echo "DMG：$DMG"
