#!/bin/bash
# Build TrayFold (Debug) and (re)launch it. Output goes to ./build (git-ignored).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
xcodebuild -project TrayFold.xcodeproj -scheme TrayFold -configuration Debug \
  -derivedDataPath build build 2>&1 | grep -E "error:|warning:|BUILD" | grep -v appintentsmetadataprocessor || true
APP="build/Build/Products/Debug/TrayFold.app"
[ -d "$APP" ] || { echo "Build failed: $APP missing"; exit 1; }
pkill -x TrayFold 2>/dev/null && sleep 0.5 || true
open "$APP"
# Ad-hoc signatures have no Authority line, so awk prints nothing; fall back to "ad-hoc".
SIGNER="$(codesign -dvv "$APP" 2>&1 | awk -F= '/^Authority=/ && !seen {print $2; seen=1}')"
echo "Launched $APP (signed as: ${SIGNER:-ad-hoc})"
