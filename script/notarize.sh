#!/usr/bin/env bash
# 仅使用已有钥匙串 profile；不在脚本或命令参数中传递密码。
set -euo pipefail
cd "$(dirname "$0")/.."
: "${PATHBRIDGE_NOTARY_PROFILE:?请设置已有的 notarytool 钥匙串 profile 名称}"
APP="dist/PathBridge.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
mkdir -p build/notarization
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" build/notarization/PathBridge-submit.zip
xcrun notarytool submit build/notarization/PathBridge-submit.zip --keychain-profile "$PATHBRIDGE_NOTARY_PROFILE" --wait --output-format json > build/notarization/app-result.json
python3 -c 'import json; r=json.load(open("build/notarization/app-result.json")); print(r); assert r["status"] == "Accepted", "App 公证未通过"'
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
./script/create_dmg.sh
DMG="dist/PathBridge-$VERSION.dmg"
xcrun notarytool submit "$DMG" --keychain-profile "$PATHBRIDGE_NOTARY_PROFILE" --wait --output-format json > build/notarization/dmg-result.json
python3 -c 'import json; r=json.load(open("build/notarization/dmg-result.json")); print(r); assert r["status"] == "Accepted", "DMG 公证未通过"'
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo "App 与 DMG 公证及验证完成：$DMG"
