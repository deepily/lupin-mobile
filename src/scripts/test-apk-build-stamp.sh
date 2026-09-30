#!/usr/bin/env bash
#
# test-apk-build-stamp.sh — tests for lib/apk-build-stamp.sh (row 8ff78c69, F3).
#
# Sources the REAL helper the two scripts use, so this cannot pass against a broken
# parser. Runs anywhere, touches nothing outside its own temp dir, needs no device.
#
#   src/scripts/test-apk-build-stamp.sh
#
# Exit 0 = all passed, 1 = a failure (the count is printed either way).

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=src/scripts/lib/apk-build-stamp.sh
source "$SCRIPT_DIR/lib/apk-build-stamp.sh"

passed=0
failed=0

check() {   # check <what> <expected> <actual>
    if [ "$2" = "$3" ]; then
        passed=$(( passed + 1 ))
        printf '  ok   %s\n' "$1"
    else
        failed=$(( failed + 1 ))
        printf '  FAIL %s\n         expected [%s]\n         actual   [%s]\n' "$1" "$2" "$3"
    fi
}

TMP="$( mktemp -d "${TMPDIR:-/tmp}/apk-stamp-test.XXXXXX" )"
trap 'rm -rf "$TMP"' EXIT
APK="$TMP/app-debug.apk"
touch "$APK"

echo "apk-build-stamp.sh"

# ── an --fcm build says so ───────────────────────────────────────────────────────────
write_apk_stamp "$APK" "abc1234" "fix/fcm-review-findings" "true" "false"
check "an --fcm build reports on"            "on"                      "$( apk_fcm_state "$APK" )"
check "the sha round-trips"                  "abc1234"                 "$( read_apk_stamp_field "$APK" sha )"
check "a branch with a slash round-trips"    "fix/fcm-review-findings"  "$( read_apk_stamp_field "$APK" branch )"
check "dirty round-trips"                    "false"                   "$( read_apk_stamp_field "$APK" dirty )"

# ── THE CASE THE WHOLE MECHANISM EXISTS FOR ─────────────────────────────────────────
# A routine rebuild with no --fcm, over the top of an --fcm build. This is the silent
# regression: the APK is genuinely newer than lib/, so the staleness gate passes it, and
# nothing else anywhere can tell that background wake just disappeared.
write_apk_stamp "$APK" "def5678" "main" "false" "false"
check "a rebuild without --fcm reports off"  "off"                     "$( apk_fcm_state "$APK" )"
check "the stamp is overwritten, not appended" "def5678"               "$( read_apk_stamp_field "$APK" sha )"

# ── no stamp is UNKNOWN, never guessed ──────────────────────────────────────────────
# An APK from before the stamp existed, or built by the other script, might have FCM
# either way. Reporting a guess as a fact is the defect this is against.
rm -f "$( apk_stamp_path "$APK" )"
check "a missing stamp reports unknown"      "unknown"                 "$( apk_fcm_state "$APK" )"
check "a missing stamp yields no sha"        ""                        "$( read_apk_stamp_field "$APK" sha )"

# ── C3: A STAMP OLDER THAN ITS APK DESCRIBES A DIFFERENT BINARY ─────────────────────
# Only build-apk-on-server.sh writes a stamp. A bare `flutter build apk`, the sibling
# deploy script, or an IDE run leaves the PREVIOUS stamp beside the NEW binary — and
# reading it then is worse than having none, because it reports a confident on/off about
# a build it never saw.
write_apk_stamp "$APK" "aaa1111" "main" "true" "false"
sleep 0.01
touch "$APK"                                   # a rebuild that wrote no stamp
check "an APK newer than its stamp is unknown" "unknown" "$( apk_fcm_state "$APK" )"

# The reverse must NOT trip it: re-stamping without touching the APK is the normal
# order build-apk-on-server.sh writes in, and has to keep reading as the truth.
write_apk_stamp "$APK" "bbb2222" "main" "true" "false"
check "a stamp newer than its APK is trusted"  "on"      "$( apk_fcm_state "$APK" )"

# ── a corrupt stamp is unknown too, not off ─────────────────────────────────────────
printf 'sha=x\nfcm=banana\n' > "$( apk_stamp_path "$APK" )"
check "an unparseable fcm reports unknown"   "unknown"                 "$( apk_fcm_state "$APK" )"
printf 'sha=x\n' > "$( apk_stamp_path "$APK" )"
check "an absent fcm line reports unknown"   "unknown"                 "$( apk_fcm_state "$APK" )"

echo ""
if [ "$failed" -eq 0 ]; then
    echo "$passed passed, 0 failed"
    exit 0
fi
echo "$passed passed, $failed FAILED"
exit 1
