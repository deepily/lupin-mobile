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

# write_apk_stamp <apk> <sha> <branch> <fcm:true|false> <dirty:true|false> [build_date] [build_number]
# The last two are the date (yyyy.mm.dd) and that day's build number the drawer shows.
write_apk_stamp() {
    local apk="$1" sha="$2" branch="$3" fcm="$4" dirty="$5" bdate="${6:-}" bnum="${7:-}"
    cat > "$( apk_stamp_path "$apk" )" <<EOF
sha=$sha
branch=$branch
build_date=$bdate
build_number=$bnum
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
#
# 🔴 A STAMP OLDER THAN ITS APK DESCRIBES A DIFFERENT BINARY (Chloé's C3). The stamp is
# only written by build-apk-on-server.sh. Anything else that produces an APK in that
# tree — a bare `flutter build apk`, build-and-deploy-lupin-mobile.sh, an IDE run —
# leaves the PREVIOUS stamp sitting next to the NEW binary. Reading it then is worse
# than having no stamp at all: it reports a confident on/off about a build it never
# saw, which is precisely the false-confidence failure this file exists to prevent,
# one level up from where F3 found it. So compare mtimes and answer `unknown`.
apk_fcm_state() {
    local apk="$1" stamp
    stamp="$( apk_stamp_path "$apk" )"
    if [ -f "$apk" ] && [ -f "$stamp" ] && [ "$apk" -nt "$stamp" ]; then
        echo "unknown"; return 0
    fi
    case "$( read_apk_stamp_field "$apk" fcm )" in
        true)  echo "on" ;;
        false) echo "off" ;;
        *)     echo "unknown" ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────────────
# THE BUILD COUNTER (the "build N" in the drawer: how many builds were made that day)
#
# One line, "<yyyy.mm.dd> <N>", in a gitignored file under io/. Not build/: `flutter clean`
# deletes build/ and the count would silently restart at 1 mid-day. Keyed by date, so a
# new day starts again at 1 with no cleanup. Read to PREDICT the number, written only once
# the APK has been verified, so a failed build leaves the count where it was.
# ─────────────────────────────────────────────────────────────────────────────────────

# build_counter_next <file> <yyyy.mm.dd> — echoes the number this day's next build gets.
build_counter_next() {
    local file="$1" day="$2" saved_day="" saved_n=""
    if [ -f "$file" ]; then read -r saved_day saved_n < "$file" || true; fi
    # Digits only, and forced to base 10: "08" and "09" are invalid octal to bash arithmetic
    # and would abort the build, so they are read as 8 and 9.
    case "$saved_n" in
        ''|*[!0-9]*) echo 1; return 0 ;;
    esac
    if [ "$saved_day" = "$day" ]; then echo $(( 10#$saved_n + 1 )); else echo 1; fi
}

# build_counter_commit <file> <yyyy.mm.dd> <n> — records that build n of that day succeeded.
build_counter_commit() {
    local file="$1" day="$2" n="$3" tmp
    mkdir -p "$( dirname "$file" )" || return 1
    tmp="$file.tmp.$$"
    printf '%s %s\n' "$day" "$n" > "$tmp" && mv -f "$tmp" "$file"
}
