#!/usr/bin/env bash
set -euo pipefail
SIGNING_ARGS=("CODE_SIGN_STYLE=Manual")
if [[ -n "${PATHBRIDGE_SIGNING_IDENTITY:-}" ]]; then
  SIGNING_ARGS+=("CODE_SIGN_IDENTITY=$PATHBRIDGE_SIGNING_IDENTITY" "DEVELOPMENT_TEAM=${PATHBRIDGE_DEVELOPMENT_TEAM:-}")
fi
cd "$(dirname "$0")/.."
xcodebuild -project PathBridge.xcodeproj -scheme PathBridge -configuration Debug \
  -derivedDataPath build -destination 'platform=macOS' \
  -resultBundlePath "build/Tests-$(date +%Y%m%d-%H%M%S).xcresult" "${SIGNING_ARGS[@]}" test
