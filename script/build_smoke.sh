#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/integration
xcrun swiftc -swift-version 6 -target "$(uname -m)-apple-macos15.7" \
  -I build/Build/Products/Debug \
  App/Models/*.swift App/Services/*.swift App/Stores/SettingsStore.swift \
  Tests/Integration/Smoke.swift build/Build/Products/Debug/PathBridgeCore.o \
  -o build/integration/pathbridge-smoke
codesign --force --options runtime --sign "${PATHBRIDGE_SIGNING_IDENTITY:-Developer ID Application: Yuna Kamisato (852H844JG2)}" \
  --identifier com.yuna.PathBridge build/integration/pathbridge-smoke
