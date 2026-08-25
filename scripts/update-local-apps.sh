#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Updating local Mac app..."
"$ROOT/mac/scripts/make-macos-app.sh"

update_android() {
    if ! command -v adb >/dev/null 2>&1; then
        echo "Skipping Android update: adb is not available."
        return
    fi

    local devices authorized_devices authorized_count serial
    if ! devices="$(adb devices)"; then
        echo "Skipping Android update: adb devices failed."
        return
    fi

    authorized_devices="$(printf '%s\n' "$devices" | awk '$2 == "device" { print $1 }')"
    authorized_count="$(printf '%s\n' "$authorized_devices" | awk 'NF { count++ } END { print count + 0 }')"
    serial="${ANDROID_SERIAL:-}"

    if [ -n "$serial" ] && ! printf '%s\n' "$authorized_devices" | grep -Fx "$serial" >/dev/null; then
        echo "Skipping Android update: ANDROID_SERIAL is not an authorized device."
        return
    fi
    if [ -z "$serial" ] && [ "$authorized_count" -eq 1 ]; then
        serial="$authorized_devices"
    fi
    if [ -z "$serial" ]; then
        echo "Skipping Android update: select exactly one authorized device or set ANDROID_SERIAL."
        return
    fi

    echo "Updating Android app on $serial..."
    (
        cd "$ROOT/android"
        ./gradlew :app:assembleDebug --no-daemon
    )

    local apk="$ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
    if [ ! -f "$apk" ] || [ ! -s "$apk" ]; then
        echo "Android build did not produce a usable APK: $apk" >&2
        return 1
    fi

    adb -s "$serial" install -r "$apk"
    adb -s "$serial" shell am start -n com.androidbridge/.MainActivity >/dev/null
    echo "Updated and relaunched Android app on $serial."
}

update_android

echo "Updating homeserver relay..."
"$ROOT/relay/scripts/deploy-homeserver.sh"
echo "Updated homeserver relay."
