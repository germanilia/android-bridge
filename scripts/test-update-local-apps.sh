#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEMP_ROOT"' EXIT

TEST_ROOT="$TEMP_ROOT/repository"
FAKE_BIN="$TEMP_ROOT/bin"
LOG="$TEMP_ROOT/log"
mkdir -p "$TEST_ROOT/.githooks" "$TEST_ROOT/scripts" "$TEST_ROOT/mac/scripts" \
    "$TEST_ROOT/android" "$TEST_ROOT/relay/scripts" "$FAKE_BIN"
cp "$ROOT/.githooks/pre-push" "$TEST_ROOT/.githooks/pre-push"
cp "$ROOT/scripts/update-local-apps.sh" "$TEST_ROOT/scripts/update-local-apps.sh"

cat > "$TEST_ROOT/mac/scripts/make-macos-app.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'mac\n' >> "$TEST_LOG"
SCRIPT

cat > "$TEST_ROOT/android/gradlew" <<'SCRIPT'
#!/usr/bin/env bash
printf 'gradlew %s\n' "$*" >> "$TEST_LOG"
mkdir -p app/build/outputs/apk/debug
printf 'apk' > app/build/outputs/apk/debug/app-debug.apk
SCRIPT

cat > "$TEST_ROOT/relay/scripts/deploy-homeserver.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'relay\n' >> "$TEST_LOG"
SCRIPT

cat > "$FAKE_BIN/adb" <<'SCRIPT'
#!/usr/bin/env bash
if [ "$1" = devices ]; then
    printf 'List of devices attached\n%s\n' "${ADB_DEVICES:-}"
    exit 0
fi
printf 'adb %s\n' "$*" >> "$TEST_LOG"
SCRIPT
chmod +x "$TEST_ROOT/.githooks/pre-push" "$TEST_ROOT/scripts/update-local-apps.sh" \
    "$TEST_ROOT/mac/scripts/make-macos-app.sh" "$TEST_ROOT/android/gradlew" \
    "$TEST_ROOT/relay/scripts/deploy-homeserver.sh" "$FAKE_BIN/adb"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

count() {
    if [ -f "$LOG" ]; then
        grep -c "^$1" "$LOG" || true
    else
        printf '0\n'
    fi
}

reset_log() {
    : > "$LOG"
}

assert_count() {
    [ "$(count "$1")" = "$2" ] || fail "expected $2 $1 entries"
}

run_hook() {
    printf '%s\n' "$1" | TEST_LOG="$LOG" PATH="$FAKE_BIN:/usr/bin:/bin" /bin/bash "$TEST_ROOT/.githooks/pre-push"
}

run_updater() {
    TEST_LOG="$LOG" PATH="$1" ADB_DEVICES="${2:-}" ANDROID_SERIAL="${3:-}" /bin/bash "$TEST_ROOT/scripts/update-local-apps.sh"
}

ZERO_OID=0000000000000000000000000000000000000000
OID=1111111111111111111111111111111111111111

reset_log
run_hook "refs/heads/topic $OID refs/heads/topic $ZERO_OID"
assert_count mac 0
assert_count relay 0

reset_log
run_hook "refs/heads/topic $OID refs/heads/topic $ZERO_OID
refs/heads/main $OID refs/heads/main $ZERO_OID"
assert_count mac 1
assert_count relay 1

reset_log
run_hook "refs/heads/main $ZERO_OID refs/heads/main $OID"
assert_count mac 0
assert_count relay 0

reset_log
run_updater "/usr/bin:/bin"
assert_count mac 1
assert_count gradlew 0
assert_count relay 1

reset_log
run_updater "$FAKE_BIN:/usr/bin:/bin" "phone-1 device"
assert_count mac 1
assert_count gradlew 1
grep -Fx "gradlew :app:assembleDebug --no-daemon" "$LOG" >/dev/null || fail "expected debug build"
grep -Fx "adb -s phone-1 install -r $TEST_ROOT/android/app/build/outputs/apk/debug/app-debug.apk" "$LOG" >/dev/null || fail "expected selected-phone install"
grep -Fx "adb -s phone-1 shell am start -n com.androidbridge/.MainActivity" "$LOG" >/dev/null || fail "expected selected-phone relaunch"
assert_count relay 1

reset_log
run_updater "$FAKE_BIN:/usr/bin:/bin" $'phone-1 device\nphone-2 device'
assert_count gradlew 0
assert_count adb 0
assert_count relay 1

reset_log
run_updater "$FAKE_BIN:/usr/bin:/bin" $'phone-1 device\nphone-2 device' "phone-2"
assert_count gradlew 1
grep -Fx "adb -s phone-2 install -r $TEST_ROOT/android/app/build/outputs/apk/debug/app-debug.apk" "$LOG" >/dev/null || fail "expected ANDROID_SERIAL install"
grep -Fx "adb -s phone-2 shell am start -n com.androidbridge/.MainActivity" "$LOG" >/dev/null || fail "expected ANDROID_SERIAL relaunch"
assert_count relay 1

echo "update-local-apps tests passed"
