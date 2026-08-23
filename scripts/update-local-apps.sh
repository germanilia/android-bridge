#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Updating local Mac app..."
"$ROOT/mac/scripts/make-macos-app.sh"

if ! command -v adb >/dev/null 2>&1; then
    echo "Skipping Android update: adb is not available."
    exit 0
fi

if ! devices="$(adb devices)"; then
    echo "Skipping Android update: adb devices failed."
    exit 0
fi

authorized_devices="$(printf '%s\n' "$devices" | awk '$2 == "device" { print $1 }')"
authorized_count="$(printf '%s\n' "$authorized_devices" | awk 'NF { count++ } END { print count + 0 }')"

if [ -n "${ANDROID_SERIAL:-}" ]; then
    serial=""
    while IFS= read -r candidate; do
        if [ "$candidate" = "$ANDROID_SERIAL" ]; then
            serial="$candidate"
            break
        fi
    done <<EOF
$authorized_devices
EOF
    if [ -z "$serial" ]; then
        echo "Skipping Android update: ANDROID_SERIAL is not an authorized device."
        exit 0
    fi
elif [ "$authorized_count" -eq 1 ]; then
    serial="$authorized_devices"
else
    echo "Skipping Android update: select exactly one authorized device or set ANDROID_SERIAL."
    exit 0
fi

echo "Updating Android app on $serial..."
(
    cd "$ROOT/android"
    ./gradlew :app:assembleDebug --no-daemon
)

apk="$ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
if [ ! -f "$apk" ] || [ ! -s "$apk" ]; then
    echo "Android build did not produce a usable APK: $apk" >&2
    exit 1
fi

adb -s "$serial" install -r "$apk"
echo "Updated Android app on $serial."
