#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Universal by default: a plain `swift build` produces a host-only binary, so
# building on Apple Silicon shipped an arm64 slice that Intel Macs cannot run at
# all. Set TOKENISLAND_HOST_ONLY=1 for a faster host-arch build while iterating.
if [ "${TOKENISLAND_HOST_ONLY:-0}" = "1" ]; then
  ARCH_FLAGS=()
  echo "Building host-arch only (TOKENISLAND_HOST_ONLY=1) — not for release."
else
  ARCH_FLAGS=(--arch x86_64 --arch arm64)
fi

swift build -c release "${ARCH_FLAGS[@]}"
BUILD_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

APP_DIR="$ROOT_DIR/.build/TokenIsland.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/TokenIsland" "$MACOS_DIR/TokenIsland"
if [ -d "$BUILD_DIR/TokenIsland_TokenIslandKit.bundle" ]; then
  cp -R "$BUILD_DIR/TokenIsland_TokenIslandKit.bundle" "$RESOURCES_DIR/"
fi
if [ -d "$ROOT_DIR/Docs" ]; then
  cp -R "$ROOT_DIR/Docs" "$RESOURCES_DIR/Docs"
fi

# App icon (pixel-pet crab). Tolerate failure — the bundle works without it.
if ! swift "$ROOT_DIR/Scripts/generate_app_icon.swift"; then
  echo "warning: app icon generation failed; bundling without AppIcon.icns" >&2
fi
if [ -f "$ROOT_DIR/.build/AppIcon.icns" ]; then
  cp "$ROOT_DIR/.build/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>TokenIsland</string>
  <key>CFBundleIdentifier</key>
  <string>com.tokenisland.app</string>
  <key>CFBundleName</key>
  <string>TokenIsland</string>
  <key>CFBundleDisplayName</key>
  <string>TokenIsland</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <!-- Must match Package.swift's .macOS(.v14); 14.6 here silently locked out
       every 14.0–14.5 Mac the package itself claims to support. -->
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright 2026 TokenIsland</string>
</dict>
</plist>
PLIST

# macOS ties Keychain "Always Allow" grants and TCC permissions (Accessibility,
# Automation) to the app's code identity. An ad-hoc signature has none, so every
# rebuild looks like a different app and every grant is asked for again. Sign
# with a real identity when there is one — see Scripts/create_signing_identity.sh.
IDENTITY="${TOKENISLAND_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "TokenIsland Dev"; then
  IDENTITY="TokenIsland Dev"
fi

if [ -n "$IDENTITY" ]; then
  codesign --force --deep --sign "$IDENTITY" --identifier com.tokenisland.app "$APP_DIR"
  echo "Signed with identity: $IDENTITY (permission grants persist across rebuilds)"
else
  codesign --force --deep --sign - --identifier com.tokenisland.app "$APP_DIR"
  echo "Signed ad-hoc — macOS will re-ask for Keychain/Accessibility after every rebuild."
  echo "Run  bash Scripts/create_signing_identity.sh  once to stop that."
fi

echo "Created $APP_DIR"
echo "Run it with:  open '$APP_DIR'"
echo "(Grant Accessibility once: System Settings → Privacy & Security → Accessibility → TokenIsland)"
