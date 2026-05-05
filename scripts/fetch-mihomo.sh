#!/usr/bin/env bash
#
# Download mihomo release binaries for darwin/arm64 + darwin/amd64,
# lipo them into a universal binary, ad-hoc codesign,
# and place at ChungHwa/Resources/mihomo.
#
# Usage:
#   scripts/fetch-mihomo.sh              # latest release
#   scripts/fetch-mihomo.sh v1.19.24     # specific tag
#
set -euo pipefail

REPO="MetaCubeX/mihomo"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &>/dev/null && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." &>/dev/null && pwd )"
OUT_DIR="${MIHOMO_OUT_DIR:-$PROJECT_DIR/Vendor/mihomo}"
OUT_BIN="$OUT_DIR/mihomo"
OUT_VER="$OUT_DIR/version.txt"

# Authenticate API requests when a GitHub token is in env. CI runners
# share an outbound IP, so anonymous calls hit the 60/hr rate limit
# almost immediately and api.github.com starts returning 403. With
# GITHUB_TOKEN the limit jumps to 5000/hr.
CURL_AUTH=()
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -n "$TOKEN" ]]; then
  CURL_AUTH=(-H "Authorization: Bearer $TOKEN")
fi

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "→ querying latest mihomo release tag…"
  VERSION=$(curl -fsSL ${CURL_AUTH[@]+"${CURL_AUTH[@]}"} \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$REPO/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
  if [[ -z "$VERSION" ]]; then
    echo "✗ failed to resolve latest tag" >&2
    exit 1
  fi
fi
echo "→ target version: $VERSION"

if [[ -f "$OUT_VER" ]] && [[ "$(cat "$OUT_VER")" == "$VERSION" ]] && [[ -x "$OUT_BIN" ]]; then
  echo "✓ already at $VERSION, skip (delete $OUT_BIN to force re-download)"
  exit 0
fi

mkdir -p "$OUT_DIR"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

download_arch () {
  local arch="$1"
  local asset="mihomo-darwin-${arch}-${VERSION}.gz"
  local url="https://github.com/$REPO/releases/download/$VERSION/$asset"
  echo "→ downloading $asset"
  curl -fL --progress-bar ${CURL_AUTH[@]+"${CURL_AUTH[@]}"} -o "$TMP/$asset" "$url"
  gunzip -k "$TMP/$asset"
  mv "$TMP/mihomo-darwin-${arch}-${VERSION}" "$TMP/mihomo-${arch}"
  chmod +x "$TMP/mihomo-${arch}"
  file "$TMP/mihomo-${arch}"
}

download_arch arm64
download_arch amd64

echo "→ lipo → universal"
lipo -create \
  "$TMP/mihomo-arm64" \
  "$TMP/mihomo-amd64" \
  -output "$TMP/mihomo-universal"
file "$TMP/mihomo-universal"

echo "→ ad-hoc codesign"
codesign --force --sign - "$TMP/mihomo-universal"
codesign --verify --verbose=2 "$TMP/mihomo-universal"

mv "$TMP/mihomo-universal" "$OUT_BIN"
chmod +x "$OUT_BIN"
echo "$VERSION" > "$OUT_VER"

echo
echo "✓ done"
echo "  binary : $OUT_BIN"
echo "  version: $VERSION"
echo "  size   : $(stat -f%z "$OUT_BIN") bytes"
