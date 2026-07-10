#!/usr/bin/env bash
# Packages the HfpProbe as a signed .app bundle with a Bluetooth usage description, so macOS
# attributes Bluetooth/TCC to the bundle (a bare `swift run` CLI is silently denied classic
# HFP connections). This is the decisive test for whether the HFP audio route is blocked by
# packaging/permissions (fixable) or by a macOS framework wall (→ manual fallback).
#
# Usage:
#   mac/scripts/make-hfp-probe-app.sh
#   open mac/dist/HfpProbe.app          # approve the Bluetooth prompt, then place a call
#   cat ~/hfp-probe.log                 # read what the probe observed
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_DIR="$(cd "$HERE/.." && pwd)"
APP="$MAC_DIR/dist/HfpProbe.app"

echo "› Building release executable…"
swift build -c release --package-path "$MAC_DIR" --product HfpProbe >/dev/null
BIN="$(swift build -c release --package-path "$MAC_DIR" --show-bin-path)/HfpProbe"

echo "› Assembling bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/HfpProbe"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>HfpProbe</string>
    <key>CFBundleIdentifier</key><string>com.androidbridge.hfpprobe</string>
    <key>CFBundleExecutable</key><string>HfpProbe</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSBackgroundOnly</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>HfpProbe connects to your paired phone as a Bluetooth hands-free device to route call audio to this Mac.</string>
</dict>
</plist>
PLIST

cat > "$MAC_DIR/dist/hfpprobe.entitlements" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.bluetooth</key><true/>
</dict>
</plist>
ENT

echo "› Ad-hoc code-signing with hardened runtime + Bluetooth entitlement…"
codesign --force --options runtime \
    --entitlements "$MAC_DIR/dist/hfpprobe.entitlements" \
    --sign - "$APP"

echo "✓ Built $APP"
echo "  Run:  open \"$APP\"   then place a call, then:  cat ~/hfp-probe.log"
