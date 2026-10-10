#!/usr/bin/env bash
#
# test-apk-fcm-default.sh — FCM is the default in both APK scripts; --no-fcm opts out
# (row 58ec8260).
#
# Runs the REAL scripts through their dry-run hooks (APK_BUILD_DRY_RUN, APK_DEPLOY_DRY_RUN),
# which print the build command and stop. No Gradle, no ssh, no adb, no device.
#
#   src/scripts/test-apk-fcm-default.sh
#
# Exit 0 = all passed, 1 = a failure (the count is printed either way).

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD="$SCRIPT_DIR/build-apk-on-server.sh"
DEPLOY="$SCRIPT_DIR/deploy-apk-to-device.sh"
DEFINE="--dart-define=ENABLE_FCM=true"

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

contains() {   # contains <what> <needle> <haystack>
    case "$3" in
        *"$2"*) passed=$(( passed + 1 )); printf '  ok   %s\n' "$1" ;;
        *)      failed=$(( failed + 1 )); printf '  FAIL %s\n         [%s] not in [%s]\n' "$1" "$2" "$3" ;;
    esac
}

lacks() {   # lacks <what> <needle> <haystack>
    case "$3" in
        *"$2"*) failed=$(( failed + 1 )); printf '  FAIL %s\n         [%s] found in [%s]\n' "$1" "$2" "$3" ;;
        *)      passed=$(( passed + 1 )); printf '  ok   %s\n' "$1" ;;
    esac
}

build() { APK_BUILD_DRY_RUN=1 "$BUILD" "$@" 2>&1; }
deploy() { APK_DEPLOY_DRY_RUN=1 "$DEPLOY" "$@" 2>&1; }

echo "build-apk-on-server.sh"
out="$( build )"
contains "no flag: the build carries the define"   "$DEFINE" "$out"
contains "no flag: FCM is reported true"           "FCM: true" "$out"
out="$( build --fcm )"
contains "--fcm still works and keeps the define"  "$DEFINE" "$out"
out="$( build --no-fcm )"
lacks    "--no-fcm drops the define"               "$DEFINE" "$out"
contains "--no-fcm reports FCM false"              "FCM: false" "$out"
check    "--fcm with --no-fcm is refused (exit 2)" "2" "$( APK_BUILD_DRY_RUN=1 "$BUILD" --fcm --no-fcm >/dev/null 2>&1; echo $? )"
check    "an unknown flag is still refused"        "2" "$( APK_BUILD_DRY_RUN=1 "$BUILD" --bogus >/dev/null 2>&1; echo $? )"

# The stamp is what deploy-apk-to-device.sh prints as "FCM: ON/OFF". It must say what the
# build did: a stamp that always says one thing would leave every check above green.
echo "build line defines (shown in the app drawer)"
out="$( build )"
contains "the build carries a build time"    "--dart-define=BUILD_TIME=20"   "$out"
contains "the build carries the time zone"   "--dart-define=BUILD_TZ="       "$out"
contains "the build carries a commit sha"    "--dart-define=BUILD_SHA="      "$out"
contains "the build says dirty or clean"     "--dart-define=BUILD_DIRTY="    "$out"
expected_version="$( sed -n 's/^version:[[:space:]]*//p' "$SCRIPT_DIR/../../pubspec.yaml" | head -n 1 | tr -d '[:space:]' )"
contains "the version comes from pubspec.yaml" "--dart-define=BUILD_VERSION=$expected_version" "$out"
contains "the FCM define is still there"     "$DEFINE"                       "$out"
out="$( build --no-fcm )"
contains "--no-fcm still stamps the build"   "--dart-define=BUILD_TIME=20"   "$out"

echo "build stamp agrees with the build"
# shellcheck source=src/scripts/lib/apk-build-stamp.sh
source "$SCRIPT_DIR/lib/apk-build-stamp.sh"
TMP="$( mktemp -d "${TMPDIR:-/tmp}/apk-fcm-default-test.XXXXXX" )"
trap 'rm -rf "$TMP"' EXIT
stamped() {   # stamped <build args...>: dry-run, stamp a fresh APK path, print what the stamp says
    local apk="$TMP/app-debug.apk"
    rm -f "$apk" "$( apk_stamp_path "$apk" )"
    touch "$apk"
    APK_BUILD_DRY_RUN=1 APK_STAMP_TEST_APK="$apk" "$BUILD" "$@" >/dev/null 2>&1
    apk_fcm_state "$apk"
}
check "no flag: the stamp says fcm on"         "on"  "$( stamped )"
check "--fcm: the stamp says fcm on"           "on"  "$( stamped --fcm )"
check "--no-fcm: the stamp says fcm off"       "off" "$( stamped --no-fcm )"

echo "deploy-apk-to-device.sh"
out="$( deploy --build )"
lacks    "--build alone passes no opt-out (server default is FCM on)" "--no-fcm" "$out"
contains "--build alone targets the build script"  "build-apk-on-server.sh" "$out"
out="$( deploy --build --fcm )"
lacks    "--build --fcm passes no opt-out"         "--no-fcm" "$out"
out="$( deploy --build --no-fcm )"
contains "--build --no-fcm passes the opt-out on"  "build-apk-on-server.sh --no-fcm" "$out"
check    "--fcm with --no-fcm is refused (exit 2)" "2" "$( APK_DEPLOY_DRY_RUN=1 "$DEPLOY" --build --fcm --no-fcm >/dev/null 2>&1; echo $? )"
check    "--no-fcm without --build is refused"     "2" "$( APK_DEPLOY_DRY_RUN=1 "$DEPLOY" --no-fcm >/dev/null 2>&1; echo $? )"
check    "--fcm without --build is still refused"  "2" "$( APK_DEPLOY_DRY_RUN=1 "$DEPLOY" --fcm >/dev/null 2>&1; echo $? )"

echo ""
if [ "$failed" -eq 0 ]; then
    echo "$passed passed, 0 failed"
    exit 0
fi
echo "$passed passed, $failed FAILED"
exit 1
