#!/bin/bash
# Cut a distributable release: build → sign → notarize → staple → zip → appcast.
#
#   bash Scripts/release.sh 0.2.0
#
# Every step that needs Apple credentials is done by Apple's own tools against
# a keychain profile you create once (see "First time" below). This script
# never sees your Apple ID or password.
#
# First time (you run these, once):
#   1. Create a Developer ID Application certificate
#      https://developer.apple.com/account/resources/certificates/add
#      (Xcode → Settings → Accounts → Manage Certificates → + is easiest.)
#   2. Store notarization credentials in your keychain:
#      xcrun notarytool store-credentials TokenIslandNotary \
#        --apple-id "<your apple id>" --team-id "<your team id>"
#      It asks for an app-specific password from appleid.apple.com.
#
# Then every release is just: bash Scripts/release.sh <version>

set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "usage: bash Scripts/release.sh <version>   e.g. 0.2.0" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/.build/release-artifacts"
APP_DIR="$ROOT_DIR/.build/TokenIsland.app"
ZIP_PATH="$DIST_DIR/TokenIsland-$VERSION.zip"
APPCAST_PATH="$DIST_DIR/appcast.xml"
NOTARY_PROFILE="${TOKENISLAND_NOTARY_PROFILE:-TokenIslandNotary}"
FEED_BASE="${TOKENISLAND_DOWNLOAD_BASE:-https://github.com/rmm-code/tokenisland/releases/download/v$VERSION}"

fail() { echo "✗ $1" >&2; exit 1; }

# --- 1. A distribution identity is not optional -----------------------------
IDENTITY="${TOKENISLAND_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -m1 "Developer ID Application" \
    | sed -E 's/^[^"]*"(.*)"$/\1/' || true)"
fi
if [ -z "$IDENTITY" ]; then
  cat >&2 <<'MISSING'
✗ No "Developer ID Application" certificate found.

  An Apple Development certificate signs builds for YOUR Macs only — Gatekeeper
  blocks it everywhere else, and notarization refuses it outright. Create one:

    Xcode → Settings → Accounts → your Apple ID → Manage Certificates →
    + → Developer ID Application

  then run this script again.
MISSING
  exit 1
fi

# --- 2. Build and sign with the hardened runtime -----------------------------
echo "→ Building $VERSION and signing with: $IDENTITY"
TOKENISLAND_VERSION="$VERSION" TOKENISLAND_SIGN_IDENTITY="$IDENTITY" \
  bash "$ROOT_DIR/Scripts/build_app_bundle.sh" >/dev/null

codesign --verify --deep --strict "$APP_DIR" || fail "signature verification failed"
codesign -d --entitlements - "$APP_DIR" 2>/dev/null | grep -q "apple-events" \
  || fail "the Apple Events entitlement is missing — click-to-jump would break"

mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"
# ditto preserves the bundle's symlinks and metadata; `zip` does not.
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

# --- 3. Notarize and staple --------------------------------------------------
if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "→ Notarizing (this takes a few minutes)…"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait \
    || fail "notarization failed — run 'xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE'"
  xcrun stapler staple "$APP_DIR" || fail "stapling failed"
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"   # re-zip WITH the staple
  echo "✓ Notarized and stapled"
else
  cat >&2 <<MISSING
⚠ No notary profile "$NOTARY_PROFILE" — shipping un-notarized.
  Users will see "cannot be opened because Apple cannot check it". Fix with:
    xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id "<id>" --team-id "<team>"
MISSING
fi

# --- 3b. Disk image (what people download from the web) ----------------------
# The zip is for Sparkle; the DMG is for humans. An app launched out of a
# downloaded zip is App-Translocated — macOS runs it from a random read-only
# path, which breaks in-place updates and loses its permissions. Dragging from
# a DMG to Applications avoids that entirely.
DMG_PATH="$DIST_DIR/TokenIsland-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP_DIR" "$STAGING/TokenIsland.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "TokenIsland $VERSION" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -quiet \
  "$DMG_PATH" || fail "could not build the disk image"

codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH" || fail "could not sign the disk image"

# The app inside is already notarized, but the DMG needs its own ticket or the
# first mount still warns.
if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "→ Notarizing the disk image…"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait \
    || fail "disk image notarization failed"
  xcrun stapler staple "$DMG_PATH" || fail "could not staple the disk image"
  echo "✓ Disk image notarized and stapled"
fi

# A second copy under a fixed name, so the website's download link never has to
# change: /releases/latest/download/<name> only resolves when the asset name is
# identical in every release. The staple travels with the copy.
STABLE_DMG_PATH="$DIST_DIR/TokenIsland.dmg"
cp "$DMG_PATH" "$STABLE_DMG_PATH"

# --- 4. Appcast --------------------------------------------------------------
# Sparkle refuses any download whose EdDSA signature does not match the
# SUPublicEDKey baked into the running app. The private half lives in this
# machine's keychain (Sparkle's generate_keys put it there) and never in git.
SIGN_UPDATE="$(/usr/bin/find "$ROOT_DIR/.build/artifacts" -name sign_update -perm +111 -type f 2>/dev/null | grep -v old_dsa | head -1)"
ED_ATTRS=""
if [ -n "$SIGN_UPDATE" ]; then
  ED_ATTRS="$("$SIGN_UPDATE" "$ZIP_PATH" 2>/dev/null || true)"
  [ -n "$ED_ATTRS" ] || fail "sign_update produced nothing — is the private key in this keychain? (Sparkle's generate_keys)"
  echo "✓ Signed the archive for Sparkle"
else
  echo "⚠ sign_update not found — the appcast will have no signature and Sparkle will refuse it." >&2
fi

# sign_update emits BOTH sparkle:edSignature and length. Emitting our own
# length alongside it produced a duplicate attribute, which is invalid XML —
# every parser (ours and Sparkle's) then read the feed as empty.
if [ -n "$ED_ATTRS" ]; then
  ENCLOSURE_ATTRS="$ED_ATTRS"
else
  ENCLOSURE_ATTRS="length=\"$(stat -f%z "$ZIP_PATH")\""
fi
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_DIR/Contents/Info.plist" 2>/dev/null || echo 14.0)"

cat > "$APPCAST_PATH" <<XML
<?xml version="1.0" standalone="yes"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>TokenIsland</title>
    <link>https://github.com/rmm-code/tokenisland</link>
    <description>Every AI coding session, in your notch.</description>
    <language>en</language>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/rmm-code/tokenisland/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="$FEED_BASE/TokenIsland-$VERSION.zip"
                 sparkle:version="$VERSION"
                 $ENCLOSURE_ATTRS
                 type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

echo
echo "✓ $STABLE_DMG_PATH   ← stable download link (never changes)"
echo "✓ $DMG_PATH   ← the same image, version-stamped"
echo "✓ $ZIP_PATH   ← what Sparkle installs"
echo "✓ $APPCAST_PATH"
echo
echo "Publish (all three must be assets on the SAME release, tagged v$VERSION):"
echo "  gh release create v$VERSION '$STABLE_DMG_PATH' '$DMG_PATH' '$ZIP_PATH' '$APPCAST_PATH' --title 'TokenIsland $VERSION' --generate-notes"
echo
echo "Download link for the site (stable across releases):"
echo "  https://github.com/rmm-code/tokenisland/releases/latest/download/TokenIsland.dmg"
echo
echo "The app checks:"
/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP_DIR/Contents/Info.plist" 2>/dev/null | sed 's/^/  /'
