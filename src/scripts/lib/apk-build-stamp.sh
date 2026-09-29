#!/usr/bin/env bash
#
# apk-build-stamp.sh — what was compiled into this APK, written down next to it.
#
# Sourced by build-apk-on-server.sh (writes the stamp) and deploy-apk-to-device.sh
# (reads it and reports). ONE implementation on purpose: a test that re-implemented the
# parser would pass while the script it is supposed to guard was broken.
#
# ─────────────────────────────────────────────────────────────────────────────────────
# WHY A STAMP EXISTS AT ALL (row 8ff78c69, review finding F3)
#
# --fcm is a compile-time define (--dart-define=ENABLE_FCM=true). `kEnableFcm` is read in
# exactly one place — the init gate in fcm_bootstrap.dart — and is never logged, never
# shown in the UI, and leaves no trace in the binary. So an APK with background wake
# compiled OUT is indistinguishable from one with it in: not on the phone, not in logcat,
# and not to the deploy script, whose staleness gate compares mtimes and cannot see flags.
#
# The way that bites: the standing rule is to rebuild after every client change, and it
# says nothing about --fcm. One routine rebuild ships FCM off, the deploy passes cleanly
# because the APK really is newer than lib/, and background wake vanishes with no
# diagnostic separating it from a server problem or a revoked notification permission.
# ─────────────────────────────────────────────────────────────────────────────────────

# Path of the stamp belonging to an APK.
apk_stamp_path() { echo "$1.build-info"; }

# write_apk_stamp <apk> <sha> <branch> <fcm:true|false> <dirty:true|false>
write_apk_stamp() {
    local apk="$1" sha="$2" branch="$3" fcm="$4" dirty="$5"
    cat > "$( apk_stamp_path "$apk" )" <<EOF
sha=$sha
branch=$branch
fcm=$fcm
dirty=$dirty
built_at=$( date -Is )
built_on=$( hostname )
EOF
}

# read_apk_stamp_field <apk> <field> — empty when absent or unset.
read_apk_stamp_field() {
    local stamp; stamp="$( apk_stamp_path "$1" )"
    [ -f "$stamp" ] || return 0
    sed -n "s/^$2=//p" "$stamp"
}

# apk_fcm_state <apk> — echoes exactly one of: on | off | unknown
#
# `unknown` is its own answer and NOT folded into `off`: an APK built before the stamp
# existed, or by the other build script, genuinely might have FCM either way, and
# reporting a guess as a fact is the thing this whole mechanism is against.
apk_fcm_state() {
    case "$( read_apk_stamp_field "$1" fcm )" in
        true)  echo "on" ;;
        false) echo "off" ;;
        *)     echo "unknown" ;;
    esac
}
