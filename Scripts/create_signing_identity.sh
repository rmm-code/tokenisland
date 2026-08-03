#!/bin/bash
# One-time: create a local code-signing identity for TokenIsland dev builds.
#
# Why: macOS attaches Keychain "Always Allow" grants and TCC permissions
# (Accessibility, Automation) to an app's code identity. Ad-hoc signatures have
# no stable identity, so every rebuild reads as a brand-new app and macOS asks
# for every permission again. A self-signed certificate fixes that — the
# identity stays the same across rebuilds, so you grant each permission once.
#
# This is a local development certificate. It is NOT for distribution; shipping
# needs a Developer ID from Apple.
#
# macOS will ask for your login password when the certificate is added to your
# keychain and when codesign first uses it. That prompt is macOS talking to you
# directly — nothing here reads or stores your password.

set -euo pipefail

NAME="TokenIsland Dev"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "Identity \"$NAME\" already exists — nothing to do."
  echo "Rebuild with:  bash Scripts/build_app_bundle.sh"
  exit 0
fi

echo "Creating a self-signed code-signing certificate: $NAME"

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" \
  -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

openssl pkcs12 -export -inkey "$WORK_DIR/key.pem" -in "$WORK_DIR/cert.pem" \
  -out "$WORK_DIR/identity.p12" -passout pass:

# -T /usr/bin/codesign lets codesign use the key without a prompt per build.
security import "$WORK_DIR/identity.p12" \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  -T /usr/bin/codesign -P ""

echo
echo "Done. Two things left, both one-time:"
echo "  1. Open Keychain Access → login → Certificates → \"$NAME\" → Get Info →"
echo "     Trust → Code Signing: Always Trust. (macOS will ask for your password.)"
echo "  2. Rebuild:  bash Scripts/build_app_bundle.sh"
echo
echo "After that, grant Accessibility/Automation and Keychain access once and"
echo "they will stick across rebuilds."
