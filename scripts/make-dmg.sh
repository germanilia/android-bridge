#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "DMG packaging requires macOS."
[ "$(uname -m)" = "arm64" ] || fail "DMG packaging supports Apple Silicon only."
[ "$#" -eq 3 ] || fail "Usage: scripts/make-dmg.sh APP_PATH OUTPUT_DMG EXPECTED_REQUIREMENT_FILE"

APP_PATH="$1"
OUTPUT_DMG="$2"
EXPECTED_REQUIREMENT_FILE="$3"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(python3 "$ROOT/scripts/release.py" version --root "$ROOT" --field version)"
VERSION_CODE="$(python3 "$ROOT/scripts/release.py" version --root "$ROOT" --field code)"
EXPECTED_REQUIREMENT="$(cat "$EXPECTED_REQUIREMENT_FILE")"
[ -n "$EXPECTED_REQUIREMENT" ] || fail "Expected signing requirement is empty."

requirement() {
    codesign -dr - "$1" 2>&1 | awk '/^designated =>/{sub(/^designated => /, ""); print}'
}

validate_app() {
    local app="$1"
    [ -d "$app" ] || fail "App bundle is missing: $app"
    local executable="$app/Contents/MacOS/AndroidBridge"
    [ -x "$executable" ] || fail "App executable is missing: $executable"
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = "com.androidbridge.mac" ] || fail "App bundle identifier is invalid."
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" = "$VERSION" ] || fail "App short version is invalid."
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" = "$VERSION_CODE" ] || fail "App build version is invalid."
    lipo -archs "$executable" | grep -qx 'arm64' || fail "App executable is not arm64-only."
    codesign --verify --deep --strict --verbose=2 "$app" || fail "App signature verification failed."
    [ "$(requirement "$app")" = "$EXPECTED_REQUIREMENT" ] || fail "App designated requirement does not match distribution requirement."
}

validate_app "$APP_PATH"
TMP_DIR="$(mktemp -d)"
MOUNT_POINT="$TMP_DIR/mount"
ATTACHED=0
cleanup() {
    local status="$?"
    local cleanup_failed=0
    if [ "$ATTACHED" -eq 1 ]; then
        hdiutil detach "$MOUNT_POINT" >/dev/null || cleanup_failed=1
    fi
    rm -rf "$TMP_DIR" || cleanup_failed=1
    if [ "$cleanup_failed" -ne 0 ]; then
        printf 'Error: DMG cleanup failed.\n' >&2
        [ "$status" -eq 0 ] && exit 1
    fi
    exit "$status"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR/image"
ditto "$APP_PATH" "$TMP_DIR/image/AndroidBridge.app"
ln -s /Applications "$TMP_DIR/image/Applications"
rm -f "$OUTPUT_DMG"
hdiutil create -volname "Android Bridge" -srcfolder "$TMP_DIR/image" -format UDZO -ov "$OUTPUT_DMG" >/dev/null

mkdir -p "$MOUNT_POINT"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$OUTPUT_DMG" >/dev/null
ATTACHED=1
[ -d "$MOUNT_POINT" ] || fail "DMG mount point is unavailable."

ROOT_ENTRIES="$(find "$MOUNT_POINT" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort | paste -sd ' ' -)"
[ "$ROOT_ENTRIES" = "AndroidBridge.app Applications" ] || fail "DMG contains unexpected root entries."
[ -L "$MOUNT_POINT/Applications" ] || fail "DMG Applications entry is not a symlink."
[ "$(readlink "$MOUNT_POINT/Applications")" = "/Applications" ] || fail "DMG Applications link target is invalid."
validate_app "$MOUNT_POINT/AndroidBridge.app"

hdiutil detach "$MOUNT_POINT" >/dev/null
ATTACHED=0
printf 'Created and verified %s\n' "$OUTPUT_DMG"
