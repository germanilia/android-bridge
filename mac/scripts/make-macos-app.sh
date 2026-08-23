#!/usr/bin/env bash
# Assembles a runnable AndroidBridge.app from the SwiftPM `AndroidBridge` executable.
# Usage: mac/scripts/make-macos-app.sh   (run from anywhere; paths are resolved relative to this script)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_DIR="$(cd "$HERE/.." && pwd)"
ROOT_DIR="$(cd "$MAC_DIR/.." && pwd)"
APP="$MAC_DIR/dist/AndroidBridge.app"
VERSION="$(python3 "$ROOT_DIR/scripts/release.py" version --root "$ROOT_DIR" --field version)"
VERSION_CODE="$(python3 "$ROOT_DIR/scripts/release.py" version --root "$ROOT_DIR" --field code)"

echo "› Building release executable…"
swift build -c release --package-path "$MAC_DIR" >/dev/null
BIN="$(swift build -c release --package-path "$MAC_DIR" --show-bin-path)/AndroidBridge"

echo "› Assembling bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AndroidBridge"
[ -f "$MAC_DIR/AppIcon.icns" ] && cp "$MAC_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
if [ -d "$MAC_DIR/Tools" ]; then
    cp -R "$MAC_DIR/Tools" "$APP/Contents/Resources/Tools"
    if [ "${EXCLUDE_LOCAL_TOOL_ENV:-0}" = "1" ]; then
        rm -rf "$APP/Contents/Resources/Tools/mlx_whisper/.venv"
    fi
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Android Bridge</string>
    <key>CFBundleDisplayName</key><string>Android Bridge</string>
    <key>CFBundleIdentifier</key><string>com.androidbridge.mac</string>
    <key>CFBundleExecutable</key><string>AndroidBridge</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION_CODE</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Android Bridge discovers and connects to your paired phone on the local network.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Android Bridge records meeting audio locally when you start Mac recording.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>Android Bridge reads calendar events to add meeting titles, participants, and customer suggestions to local meeting notes.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Android Bridge reads calendar events to add meeting titles, participants, and customer suggestions to local meeting notes.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Android Bridge captures system meeting audio locally so remote speakers can be transcribed separately.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_androidbridge._tcp</string>
    </array>
</dict>
</plist>
PLIST

# TCC binds privacy grants to the designated code requirement. Never pick the
# first keychain identity: its order can change when another certificate is
# added. This fingerprint is the existing Android Bridge identity whose grants
# must survive updates. Other machines can provide CODESIGN_IDENTITY explicitly.
DEFAULT_CODESIGN_IDENTITY="A0B15CA62926F788FFFC550CA7A7737AA64C7699"
IDENTITY="${CODESIGN_IDENTITY:-$DEFAULT_CODESIGN_IDENTITY}"
if ! security find-identity -v -p codesigning | grep -qi "$IDENTITY"; then
    echo "✗ Required code-signing identity is unavailable: $IDENTITY" >&2
    echo "  Set CODESIGN_IDENTITY to the stable identity previously used for this app." >&2
    exit 1
fi

echo "› Code-signing with stable identity: $IDENTITY"
codesign --force --deep --sign "$IDENTITY" "$APP"
codesign --verify --deep --verbose=2 "$APP"

requirement() {
    codesign -dr - "$1" 2>&1 | awk '/^designated =>/{sub(/^designated => /, ""); print}'
}

BUILT_REQUIREMENT="$(requirement "$APP")"
test -n "$BUILT_REQUIREMENT"
if [ -n "${EXPECTED_CODESIGN_REQUIREMENT_FILE:-}" ]; then
    [ -f "$EXPECTED_CODESIGN_REQUIREMENT_FILE" ] || {
        echo "✗ Expected code-signing requirement file is missing: $EXPECTED_CODESIGN_REQUIREMENT_FILE" >&2
        exit 1
    }
    EXPECTED_REQUIREMENT="$(cat "$EXPECTED_CODESIGN_REQUIREMENT_FILE")"
    [ "$BUILT_REQUIREMENT" = "$EXPECTED_REQUIREMENT" ] || {
        echo "✗ Built designated requirement does not match the expected distribution requirement." >&2
        exit 1
    }
fi

echo "› Designated requirement: $BUILT_REQUIREMENT"
echo "✓ Built $APP"

# Stage and verify the complete bundle before replacing the running app. Refuse
# an identity change by default because it would invalidate Calendar,
# Microphone, Screen Recording, and Accessibility grants.
if [ "${NO_INSTALL:-0}" != "1" ]; then
    INSTALLED="/Applications/AndroidBridge.app"
    STAGED="/Applications/.AndroidBridge.app.installing"
    if [ -d "$INSTALLED" ]; then
        INSTALLED_REQUIREMENT="$(requirement "$INSTALLED")"
        if [ "$INSTALLED_REQUIREMENT" != "$BUILT_REQUIREMENT" ] && [ "${ALLOW_SIGNATURE_CHANGE:-0}" != "1" ]; then
            echo "✗ Refusing update because the designated requirement changed." >&2
            echo "  Installed: $INSTALLED_REQUIREMENT" >&2
            echo "  New:       $BUILT_REQUIREMENT" >&2
            echo "  This would invalidate macOS privacy grants." >&2
            exit 1
        fi
    fi

    echo "› Staging verified update for $INSTALLED"
    rm -rf "$STAGED"
    ditto "$APP" "$STAGED"
    codesign --verify --deep --verbose=2 "$STAGED"
    test "$(requirement "$STAGED")" = "$BUILT_REQUIREMENT"

    osascript -e 'quit app "AndroidBridge"' >/dev/null 2>&1 || true
    sleep 1
    pkill -f "$INSTALLED/Contents/MacOS/AndroidBridge" >/dev/null 2>&1 || true
    rm -rf "$INSTALLED"
    mv "$STAGED" "$INSTALLED"
    codesign --verify --deep --verbose=2 "$INSTALLED"
    test "$(requirement "$INSTALLED")" = "$BUILT_REQUIREMENT"
    open "$INSTALLED"
    echo "✓ Installed with unchanged identity and relaunched $INSTALLED"
fi
