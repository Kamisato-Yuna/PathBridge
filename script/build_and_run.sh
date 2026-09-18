#!/usr/bin/env bash
set -euo pipefail
SIGNING_ARGS=("CODE_SIGN_STYLE=Manual")
if [[ -n "${PATHBRIDGE_SIGNING_IDENTITY:-}" ]]; then
  SIGNING_ARGS+=("CODE_SIGN_IDENTITY=$PATHBRIDGE_SIGNING_IDENTITY" "DEVELOPMENT_TEAM=${PATHBRIDGE_DEVELOPMENT_TEAM:-}")
fi
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--debug|--logs|--telemetry|--verify|--build) ;; *) echo "usage: $0 [--build|--debug|--logs|--telemetry|--verify]" >&2; exit 2;; esac
if [[ "$MODE" != --build ]]; then pkill -x PathBridge >/dev/null 2>&1 || true; fi
xcodebuild -project PathBridge.xcodeproj -scheme PathBridge -configuration Debug -derivedDataPath build -destination 'platform=macOS' "${SIGNING_ARGS[@]}" build
APP_BUNDLE="$ROOT_DIR/build/Build/Products/Debug/PathBridge.app"
case "$MODE" in
  --build) ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/PathBridge" ;;
  --logs|--telemetry) open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "PathBridge"' ;;
  --verify) open -n "$APP_BUNDLE"; sleep 2; pgrep -x PathBridge >/dev/null ;;
  run) open -n "$APP_BUNDLE" ;;
esac
