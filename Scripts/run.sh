#!/bin/bash
# Build and (re)launch the app the only way that keeps macOS permissions.
#
#   bash Scripts/run.sh
#
# Use this instead of `swift run TokenIsland`. That command launches
# .build/debug/TokenIsland, which is ad-hoc signed with a per-build identifier
# — macOS sees a brand-new app every single time, so Keychain "Always Allow",
# Accessibility and Automation grants can never stick. The bundle is signed
# with a stable identity, so you grant each permission once.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/.build/TokenIsland.app"

bash "$ROOT_DIR/Scripts/build_app_bundle.sh"

if pgrep -f "TokenIsland.app/Contents/MacOS/TokenIsland" >/dev/null; then
  echo "Quitting the running instance…"
  pkill -f "TokenIsland.app/Contents/MacOS/TokenIsland" || true
  sleep 1
fi

open "$APP"
echo "Launched $APP"
