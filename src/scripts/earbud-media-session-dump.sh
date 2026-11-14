#!/usr/bin/env bash
#
# earbud-media-session-dump.sh — record where Android sends an earbud tap (rows c643b1b0, bcc9cba3)
#
# Run it from the laptop, like deploy-apk-to-device.sh, with the phone on adb.
# Open Quick Ask on the phone with the earbuds in before you start.
# The script clears the phone's log, asks you to tap an earbud, then saves:
#   - dumpsys media_session: which app's session Android gives media buttons to
#   - dumpsys audio: which apps played audio most recently
#   - the phone's log around the tap: media-key and Bluetooth AVRCP lines
# The file goes to io/tmp/ in this checkout, which the dev server reads directly.
#
# Usage: src/scripts/earbud-media-session-dump.sh
# Exit: 0 saved, 2 adb not found or no device.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

ADB="${ADB:-}"
if [ -z "$ADB" ]; then
    if command -v adb >/dev/null 2>&1; then
        ADB="adb"
    elif [ -x "${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools/adb" ]; then
        ADB="${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools/adb"
    elif [ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]; then
        ADB="$HOME/Library/Android/sdk/platform-tools/adb"
    fi
fi
if [ -z "$ADB" ]; then
    echo "adb not found. Set ADB=/path/to/adb and run again." >&2
    exit 2
fi
if ! "$ADB" get-state >/dev/null 2>&1; then
    echo "adb sees no ready device. Connect the phone the way deploy-apk-to-device.sh does, then run again." >&2
    exit 2
fi

mkdir -p "$REPO_ROOT/io/tmp"
OUT="$REPO_ROOT/io/tmp/earbud-dump-$( date +%Y.%m.%d-%H%M%S ).txt"

"$ADB" logcat -c
echo "Quick Ask open on the phone, earbuds in?"
read -r -p "Tap ONE earbud once now, wait two seconds, then press Enter here... " _

{
    echo "=== earbud-media-session-dump $( date -u +%Y-%m-%dT%H:%M:%SZ ) ==="
    echo "=== device: $( "$ADB" shell getprop ro.product.model | tr -d '\r' ), Android $( "$ADB" shell getprop ro.build.version.release | tr -d '\r' ) ==="
    echo
    echo "=== dumpsys media_session ==="
    "$ADB" shell dumpsys media_session
    echo
    echo "=== dumpsys audio (playback) ==="
    "$ADB" shell dumpsys audio | grep -iE -A40 "playback activity|AudioPlaybackConfiguration|players:" | head -200
    echo
    echo "=== logcat around the tap ==="
    "$ADB" logcat -d -v time | grep -iE "media_?session|MediaButton|MediaKey|KeyEvent|avrcp|audioservice|EarbudTrace|lupin" | tail -400
} > "$OUT" 2>&1

echo "Saved: $OUT"
echo "Tell Tiffany \"dump saved\"."
