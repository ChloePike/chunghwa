#!/usr/bin/env bash
set -euo pipefail

# Build a Release ChungHwa.app and pack it into a DMG.
# Self-use: ad-hoc code signature ("-"). Distributed binaries will be
# Gatekeeper-quarantined on first open; users either run
#   xattr -dr com.apple.quarantine /Applications/ChungHwa.app
# or right-click → Open from Finder.
#
# Usage:
#   ./scripts/make-dmg.sh                     # universal (arm64 + x86_64)
#   ./scripts/make-dmg.sh 1.2.3               # explicit version, universal
#   ./scripts/make-dmg.sh 1.2.3 arm64         # arm64-only slice
#   ./scripts/make-dmg.sh 1.2.3 x86_64        # x86_64-only slice
#   OUTPUT_DIR=./dist ./scripts/make-dmg.sh   # write into ./dist/

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/build}"

# Args: $1 = version (optional), $2 = arch (optional: universal | arm64 | x86_64)
VERSION_ARG="${1:-}"
ARCH="${2:-universal}"

if [[ -n "$VERSION_ARG" ]]; then
  VERSION="$VERSION_ARG"
else
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$ROOT/ChungHwa/Info.plist" 2>/dev/null || true)"
  VERSION="${VERSION:-0.0}"
fi

case "$ARCH" in
  universal|arm64|x86_64) ;;
  *) echo "arch must be universal | arm64 | x86_64 (got: $ARCH)" >&2; exit 2 ;;
esac

# Per-arch derived data + DMG name so the three slices don't collide.
DERIVED="$OUTPUT_DIR/derived-$ARCH"
RELEASE_DIR="$DERIVED/Build/Products/Release"
APP="$RELEASE_DIR/ChungHwa.app"
DMG="$OUTPUT_DIR/ChungHwa-$VERSION-$ARCH.dmg"

echo "==> output dmg: $DMG  (arch=$ARCH)"
mkdir -p "$OUTPUT_DIR"

# Vendor mihomo. We always need the universal binary as the source —
# arch-specific builds lipo it down. fetch-mihomo.sh is idempotent.
# When the cached mihomo is already a thin slice (left over from a
# prior arch-specific run), force a fresh download.
if [[ -f "$ROOT/Vendor/mihomo/mihomo" ]]; then
  if ! lipo -info "$ROOT/Vendor/mihomo/mihomo" 2>/dev/null | grep -q "x86_64 arm64\|arm64 x86_64"; then
    echo "==> cached mihomo is not universal, re-fetching"
    rm -f "$ROOT/Vendor/mihomo/mihomo" "$ROOT/Vendor/mihomo/version.txt"
  fi
fi
echo "==> fetching mihomo binary"
"$ROOT/scripts/fetch-mihomo.sh"

# Arch-specific build: lipo the mihomo to a same-arch slice so the
# resulting .app's embedded kernel matches and we save ~40MB.
if [[ "$ARCH" != "universal" ]]; then
  echo "==> lipo -thin $ARCH on mihomo binary"
  TMP_MIHOMO="$(mktemp -d)/mihomo"
  lipo -thin "$ARCH" "$ROOT/Vendor/mihomo/mihomo" -output "$TMP_MIHOMO"
  cp "$TMP_MIHOMO" "$ROOT/Vendor/mihomo/mihomo"
  chmod +x "$ROOT/Vendor/mihomo/mihomo"
  codesign --force --sign - "$ROOT/Vendor/mihomo/mihomo"
fi

# Map our $ARCH to xcodebuild ARCHS values.
if [[ "$ARCH" == "universal" ]]; then
  XCODE_ARCHS="arm64 x86_64"
else
  XCODE_ARCHS="$ARCH"
fi

echo "==> xcodebuild Release ARCHS=\"$XCODE_ARCHS\""
xcodebuild \
  -project "$ROOT/ChungHwa.xcodeproj" \
  -scheme ChungHwa \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  ARCHS="$XCODE_ARCHS" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  PROVISIONING_PROFILE_SPECIFIER="" \
  build

if [[ ! -d "$APP" ]]; then
  echo "build did not produce $APP" >&2
  exit 1
fi

echo "==> codesign --deep -"
codesign --force --deep --sign - "$APP"

# Stage with /Applications symlink for drag-install.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
echo "==> staged at $STAGE:"
ls -la "$STAGE"

rm -f "$DMG"
echo "==> hdiutil create → $DMG"
# Default to APFS — HFS+ image creation is unreliable on macOS 26
# runners. APFS DMGs work as drag-install volumes the same way.
hdiutil create \
  -volname "ChungHwa $VERSION ($ARCH)" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

codesign --force --sign - "$DMG"

echo "==> done"
ls -lh "$DMG"
file "$APP/Contents/MacOS/ChungHwa"
