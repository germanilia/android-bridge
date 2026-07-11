#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="germanilia/android-bridge"
APP_NAME="AndroidBridge.app"
ARCHIVE_NAME="AndroidBridge-macOS-arm64.zip"
CHECKSUM_NAME="${ARCHIVE_NAME}.sha256"
INSTALL_PATH="/Applications/${APP_NAME}"

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "Android Bridge requires macOS."
[ "$(uname -m)" = "arm64" ] || fail "This release supports Apple Silicon Macs only."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RELEASE_TAG="latest-build"
ASSET_BASE="https://github.com/${REPOSITORY}/releases/download/${RELEASE_TAG}"
printf 'Downloading the latest Android Bridge build…\n'
curl -fL --proto '=https' --tlsv1.2 -o "$TMP_DIR/$ARCHIVE_NAME" "$ASSET_BASE/$ARCHIVE_NAME"
curl -fL --proto '=https' --tlsv1.2 -o "$TMP_DIR/$CHECKSUM_NAME" "$ASSET_BASE/$CHECKSUM_NAME"

(
    cd "$TMP_DIR"
    shasum -a 256 -c "$CHECKSUM_NAME"
)

unzip -q "$TMP_DIR/$ARCHIVE_NAME" -d "$TMP_DIR/app"
[ -d "$TMP_DIR/app/$APP_NAME" ] || fail "Release archive does not contain $APP_NAME."

printf 'Installing to %s…\n' "$INSTALL_PATH"
osascript -e 'quit app "AndroidBridge"' >/dev/null 2>&1 || true
if [ -w /Applications ]; then
    rm -rf "$INSTALL_PATH"
    cp -R "$TMP_DIR/app/$APP_NAME" "$INSTALL_PATH"
else
    sudo rm -rf "$INSTALL_PATH"
    sudo cp -R "$TMP_DIR/app/$APP_NAME" "$INSTALL_PATH"
fi

open "$INSTALL_PATH"
printf 'Installed the latest Android Bridge build.\n'
