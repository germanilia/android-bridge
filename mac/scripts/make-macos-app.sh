#!/usr/bin/env bash
# Assembles a runnable AndroidBridge.app from the SwiftPM `AndroidBridge` executable.
# Usage: mac/scripts/make-macos-app.sh   (run from anywhere; paths are resolved relative to this script)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_DIR="$(cd "$HERE/.." && pwd)"
APP="$MAC_DIR/dist/AndroidBridge.app"

echo "› Building release executable…"
swift build -c release --package-path "$MAC_DIR" >/dev/null
BIN="$(swift build -c release --package-path "$MAC_DIR" --show-bin-path)/AndroidBridge"

echo "› Assembling bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AndroidBridge"
[ -f "$MAC_DIR/AppIcon.icns" ] && cp "$MAC_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
[ -d "$MAC_DIR/Tools" ] && cp -R "$MAC_DIR/Tools" "$APP/Contents/Resources/Tools"

cat > "$APP/Contents/Info.plist" <<'PLIST'
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
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Android Bridge discovers and connects to your paired phone on the local network.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Android Bridge records meeting audio locally when you start Mac recording.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Android Bridge captures system meeting audio locally so remote speakers can be transcribed separately.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_androidbridge._tcp</string>
    </array>
</dict>
</plist>
PLIST

# macOS ties privacy grants (Screen Recording, Microphone) to the app's code
# signature. Ad-hoc signatures change on every rebuild, so TCC treats each
# build as a new app and re-asks for permissions. Signing with a stable
# identity (any self-signed "Code Signing" cert in the keychain) keeps the
# grants across rebuilds.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' 'NR==1 {print $2}')}"
if [ -n "$IDENTITY" ]; then
    echo "› Code-signing with identity: $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"
else
    echo "› Ad-hoc code-signing… (permissions will be re-asked after every rebuild;"
    echo "  create a self-signed 'Code Signing' certificate in Keychain Access to fix)"
    codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"
fi

echo "✓ Built $APP"

# Install into /Applications and relaunch, so the app you actually run is always the fresh build.
# (Skip with NO_INSTALL=1.)
if [ "${NO_INSTALL:-0}" != "1" ]; then
    INSTALLED="/Applications/AndroidBridge.app"
    echo "› Installing to $INSTALLED and relaunching…"
    osascript -e 'quit app "AndroidBridge"' >/dev/null 2>&1 || true
    sleep 1
    pkill -f "$INSTALLED/Contents/MacOS/AndroidBridge" >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$INSTALLED"
    cp -R "$APP" "$INSTALLED"
    open "$INSTALLED"
    echo "✓ Installed and relaunched $INSTALLED"
fi
