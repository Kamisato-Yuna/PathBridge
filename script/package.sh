#!/usr/bin/env bash
set -euo pipefail
SIGNING_ARGS=("CODE_SIGN_STYLE=Manual")
if [[ -n "${PATHBRIDGE_SIGNING_IDENTITY:-}" ]]; then
  SIGNING_ARGS+=("CODE_SIGN_IDENTITY=$PATHBRIDGE_SIGNING_IDENTITY" "DEVELOPMENT_TEAM=${PATHBRIDGE_DEVELOPMENT_TEAM:-}")
fi
cd "$(dirname "$0")/.."
xcodebuild -project PathBridge.xcodeproj -scheme PathBridge -configuration Release \
  -derivedDataPath build -destination 'generic/platform=macOS' ONLY_ACTIVE_ARCH=NO "${SIGNING_ARGS[@]}" build
mkdir -p dist
ditto build/Build/Products/Release/PathBridge.app dist/PathBridge.app
codesign --verify --deep --strict --verbose=2 dist/PathBridge.app
ditto -c -k --keepParent dist/PathBridge.app dist/PathBridge-macOS.zip
echo "签名构建产物：dist/PathBridge.app（未公证）"
