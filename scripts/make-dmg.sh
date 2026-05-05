#!/usr/bin/env bash
set -euo pipefail

# Build a Release ChungHwa.app and pack it into ChungHwa-<version>.dmg.
# Self-use: ad-hoc code signature ("-"). Distributed binaries will be
# Gatekeeper-quarantined on first open; users either run
#   xattr -dr com.apple.quarantine /Applications/ChungHwa.app
# or right-click → Open from Finder.
#
# Usage:
#   ./scripts/make-dmg.sh                    # auto-version from CFBundleShortVersionString
#   ./scripts/make-dmg.sh 1.2.3              # override version
#   OUTPUT_DIR=./dist ./scripts/make-dmg.sh  # write into ./dist/ instead of ./build/

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/build}"
DERIVED="$OUTPUT_DIR/derived"
RELEASE_DIR="$DERIVED/Build/Products/Release"
APP="$RELEASE_DIR/ChungHwa.app"

# Version: arg > Info.plist's CFBundleShortVersionString > "0.0".
if [[ $# -ge 1 ]]; then
  VERSION="$1"
else
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$ROOT/ChungHwa/Info.plist" 2>/dev/null || true)"
  VERSION="${VERSION:-0.0}"
fi

DMG="$OUTPUT_DIR/ChungHwa-$VERSION.dmg"
echo "==> output dmg: $DMG"

mkdir -p "$OUTPUT_DIR"

# Vendor mihomo. The Xcode build phase also runs this, but doing it
# here too means a CI box without DerivedData state can run xcodebuild
# cleanly on first try.
echo "==> fetching mihomo binary"
"$ROOT/scripts/fetch-mihomo.sh"

# Build Release. Ad-hoc sign so we don't need a Developer ID cert
# or a provisioning profile. Override anything inherited from the
# project file.
echo "==> xcodebuild Release"
xcodebuild \
  -project "$ROOT/ChungHwa.xcodeproj" \
  -scheme ChungHwa \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  PROVISIONING_PROFILE_SPECIFIER="" \
  ONLY_ACTIVE_ARCH=NO \
  build

if [[ ! -d "$APP" ]]; then
  echo "build did not produce $APP" >&2
  exit 1
fi

# Re-sign deeply so the embedded mihomo binary is also ad-hoc signed
# consistently. Xcode usually does this; belt-and-braces.
echo "==> codesign --deep -"
codesign --force --deep --sign - "$APP"

# Stage the app + an Applications symlink so drop-to-install works
# in the mounted DMG.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Create a UDZO-compressed read-only DMG.
rm -f "$DMG"
hdiutil create \
  -volname "ChungHwa $VERSION" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$DMG" >/dev/null

# Sign the DMG itself (ad-hoc again).
codesign --force --sign - "$DMG"

echo "==> done"
ls -lh "$DMG"
