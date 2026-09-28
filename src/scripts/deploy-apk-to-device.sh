#!/usr/bin/env bash
#
# deploy-apk-to-device.sh
#
# ONE command, no hand steps: install the debug APK the DEV SERVER already built onto
# whatever Android device this laptop can see.
#
#   ./deploy-apk-to-device.sh
#
# That is the whole interface. It pulls the APK over the SMB mount, picks a device,
# installs, launches, and exits.
#
# ─────────────────────────────────────────────────────────────────────────────────────
# WHY THIS IS A SIBLING OF build-and-deploy-lupin-mobile.sh RATHER THAN A FLAG ON IT
#
# That script's identity is rsync-the-source-then-build-on-the-laptop. The SDK now lives
# on the dev server and the laptop no longer builds (row 651e3956), so its first two
# steps are the two this job must not do. Adding a no-build default to it would leave its
# rsync-and-build machinery as a non-default path and make the file's own header lie
# about what running it does.
#
# Its `--push-only` flag is the nearest thing that already existed, and it is NOT this:
# it installs from a laptop-local build tree (`$HOME/Projects/lupin-mobile`), which on the
# new arrangement is a stale tree or no tree at all, and its device gate is written for an
# emulator (it advises "start the emulator first" and does not pass `-s`, so it dies on
# "more than one device/emulator" the moment a phone is attached alongside one).
#
# So: that script keeps the build workflow, this one owns the deploy. Neither duplicates
# the other. If the laptop ever builds again, that script is still there and still works.
# ─────────────────────────────────────────────────────────────────────────────────────
#
# WHERE THE APK COMES FROM — no configuration, on purpose.
#
# This script lives at <repo>/src/scripts/ inside the lupin-mobile repo, and the laptop
# reaches that repo over the SMB mount. So the script's OWN location is the answer: two
# directories up is the repo root, and the APK is at the standard Flutter output path
# under it. Nothing to configure, nothing to keep in sync with the dev server, and no
# hard-coded /Volumes path that breaks when the mount is named differently.
#
# WHICH DEVICE — the phone wins.
#
# Rick's rule: install to whatever adb sees; emulator if that is what is up, the phone if
# the phone is connected, and if BOTH are present prefer the phone and say so. A device
# whose serial starts with `emulator-` is an emulator; everything else is a phone, which
# is also true of a wireless phone (`192.168.1.50:5555`).
#
# 🔴 "adb sees it" IS NOT THE SAME AS "adb can install to it", AND THE DIFFERENCE IS
# SILENT. `adb devices` lists a phone in `unauthorized` (the on-screen "Allow USB
# debugging" prompt has not been tapped) and in `offline` (asleep, or a wireless link that
# dropped) exactly as prominently as a working one. A gate that greps for the serial and
# stops there reports success and then fails inside `adb install` with a message about the
# device state that reads like a bug. So each state is named here, with what to do about
# it, because the fix is different for each and neither is something a script can perform.
#
# EXIT CODES — for the caller, since this is meant to be run from an alias or a chain:
#   0  installed (and launched)
#   1  no usable device, or the install itself failed
#   2  bad arguments
#   3  the APK is missing, unreadable over the mount, or STALE (see --allow-stale)
#
set -euo pipefail

# ════════════════════════════════════════════════════════════════════════════════════
# Colors and printers — same vocabulary as build-and-deploy-lupin-mobile.sh, so the two
# scripts read alike in a terminal.
# ════════════════════════════════════════════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

print_step()    { echo -e "${BLUE}=== $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}" >&2; }
print_info()    { echo -e "${YELLOW}ℹ $1${NC}"; }

# Modification time and size, on either platform. The laptop is macOS (BSD stat), the dev
# server is Linux (GNU stat); `ls -l` is the last resort so this can never be the reason a
# deploy fails. Lifted deliberately from the sibling script rather than reinvented.
file_stamp() {
    stat -c '%y  (%s bytes)' "$1" 2>/dev/null \
        || stat -f '%Sm  (%z bytes)' "$1" 2>/dev/null \
        || ls -l "$1"
}

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
APK_REL="build/app/outputs/flutter-apk/app-debug.apk"
APK_SRC="$REPO_ROOT/$APK_REL"
PACKAGE_NAME="ai.deepily.lupin_mobile"

# How long to wait for `adb connect` before calling it dead. Ten seconds is generous for a
# LAN and far short of adb's own ~130 s silence against an unreachable address.
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-10}"
LAUNCH_ACTIVITY="$PACKAGE_NAME/$PACKAGE_NAME.MainActivity"

# ADB defaults to whatever is on PATH; ANDROID_HOME's copy is the fallback so this works
# on a laptop where platform-tools was never added to PATH.
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

usage() {
    cat <<'EOF'
deploy-apk-to-device.sh — install the dev server's debug APK to whatever adb sees

  (no arguments)     Pull the APK over the SMB mount, pick a device, install, launch, exit.
  --device SERIAL    Install to this adb serial instead of choosing one.
  -s SERIAL          Short form of --device.
  --connect ADDR     `adb connect ADDR` first, for a wireless phone on the LAN.
                     Port defaults to 5555, so --connect 192.168.1.50 is enough.
                     Bounded by CONNECT_TIMEOUT (default 10s): adb itself sits silent
                     for ~130s against an address that is simply not there.
  --pair ADDR CODE   `adb pair ADDR CODE` first — the ONE-TIME wireless pairing.
  --apk PATH         Install this APK instead of the one under the repo root.
  --allow-stale      Install even though lib/ has .dart files NEWER than the APK.
                     Without it, that is refused: the dev server builds, so a newer
                     source file means this binary does not contain it. Never silent.
  --no-launch        Install without starting the app.
  --logcat           After installing, tail filtered logcat (Ctrl+C to stop).
                     Off by default: a tail never returns, so "one command" would
                     never finish.
  --list             Show what adb sees, say which device would be chosen, install nothing.
  --help, -h         This text.

DEVICE CHOICE: a serial starting `emulator-` is an emulator, anything else is a phone
(including a wireless phone like 192.168.1.50:5555). With both attached the PHONE wins.
With neither, this fails rather than waiting.

THE TWO THINGS NO SCRIPT CAN DO FOR YOU — both one-time per phone, both survive reboots:
  1. USB: tap "Allow USB debugging" on the phone. Until then it shows `unauthorized`.
  2. Wireless: the pairing code is generated ON THE PHONE (Settings → Developer options →
     Wireless debugging → Pair device with pairing code) so a human reads it off the
     screen once. Note the PAIR port differs from the :5555 connect port:
       ./deploy-apk-to-device.sh --pair 192.168.1.50:41234 123456 --connect 192.168.1.50
     After that, plain `./deploy-apk-to-device.sh` is the whole command, forever.
EOF
}

# ════════════════════════════════════════════════════════════════════════════════════
# Arguments
# ════════════════════════════════════════════════════════════════════════════════════
DEVICE_SERIAL=""
CONNECT_ADDR=""
PAIR_ADDR=""
PAIR_CODE=""
APK_OVERRIDE=""
ALLOW_STALE=false
DO_LAUNCH=true
DO_LOGCAT=false
LIST_ONLY=false

while [ $# -gt 0 ]; do
    case "$1" in
        --device|-s)
            # A missing value would silently swallow the NEXT flag as a serial, so the
            # check is that a value exists and is not itself a flag.
            case "${2:-}" in ""|-*) print_error "--device needs an adb serial"; exit 2 ;; esac
            DEVICE_SERIAL="$2"; shift ;;
        --connect)
            case "${2:-}" in ""|-*) print_error "--connect needs an address, e.g. 192.168.1.50"; exit 2 ;; esac
            CONNECT_ADDR="$2"; shift ;;
        --pair)
            case "${2:-}" in ""|-*) print_error "--pair needs ADDR:PORT"; exit 2 ;; esac
            case "${3:-}" in ""|-*) print_error "--pair needs the code the phone is showing"; exit 2 ;; esac
            PAIR_ADDR="$2"; PAIR_CODE="$3"; shift 2 ;;
        --apk)
            case "${2:-}" in ""|-*) print_error "--apk needs a path"; exit 2 ;; esac
            APK_OVERRIDE="$2"; shift ;;
        --allow-stale) ALLOW_STALE=true ;;
        --no-launch) DO_LAUNCH=false ;;
        --logcat)    DO_LOGCAT=true ;;
        --list)      LIST_ONLY=true ;;
        --help|-h)   usage; exit 0 ;;
        *)
            # Fail loudly rather than ignoring it: a silently-dropped flag here means a
            # deploy that did something other than what was asked.
            print_error "Unknown argument: $1"; echo ""; usage; exit 2 ;;
    esac
    shift
done

[ -n "$APK_OVERRIDE" ] && APK_SRC="$APK_OVERRIDE"

if [ -z "$ADB" ]; then
    print_error "adb not found."
    print_info "Install Android platform-tools, or set ADB=/path/to/adb."
    exit 1
fi

# ════════════════════════════════════════════════════════════════════════════════════
# Wireless pair / connect, when asked
# ════════════════════════════════════════════════════════════════════════════════════
if [ -n "$PAIR_ADDR" ]; then
    print_step "Pairing with $PAIR_ADDR (one-time)"
    if "$ADB" pair "$PAIR_ADDR" "$PAIR_CODE"; then
        print_success "Paired"
    else
        print_error "Pairing failed."
        print_info "The code expires in seconds and the dialog issues a new one each time —"
        print_info "re-read it off the phone and try again. Check the PAIR port, not :5555."
        exit 1
    fi
fi

if [ -n "$CONNECT_ADDR" ]; then
    case "$CONNECT_ADDR" in *:*) ;; *) CONNECT_ADDR="$CONNECT_ADDR:5555" ;; esac
    print_step "Connecting to $CONNECT_ADDR"
    print_info "(up to ${CONNECT_TIMEOUT}s — an unreachable address answers slowly, if at all)"

    # 🔴 `adb connect` EXITS 0 ON FAILURE and says so only in its output, so the exit code
    # cannot be trusted here. MEASURED 2026-09-27 on platform-tools 37.0.1 (adb 1.0.41):
    #     adb connect 127.0.0.1:1  ->  "failed to connect to '127.0.0.1:1': Connection
    #                                   refused"   rc=0
    # Note the failure text says "connect to", never "connected to", so matching on
    # "connected to" cannot false-positive against it. Both halves of that were run, not
    # assumed — this comment used to assert the behaviour with no evidence behind it.
    #
    # 🔴 AND A REFUSED ADDRESS IS THE FAST CASE. An address that is simply NOT THERE —
    # a wrong octet, a phone asleep, wireless debugging switched off — drops the packets
    # instead of refusing them, and adb sits silent for ~130 s before printing anything
    # (measured by Pocholo, same toolchain). For a script whose whole pitch is "one
    # command", two minutes of no output is indistinguishable from a hang, and the user
    # concludes the tool is broken long before adb concludes anything. So the call is
    # bounded and the two failures are reported DIFFERENTLY, because their fixes differ:
    # something answered and said no, versus nothing is there at all.
    # ⚠️ `connect_rc=0` FIRST AND `|| connect_rc=$?` ON THE ASSIGNMENT, because `set -e` is
    # on: a bare `var=$( cmd )` whose command fails kills the script THERE, before the next
    # line can read `$?`. Caught by the suite — the first cut of this timeout exited 124
    # straight out of the script instead of printing the explanation it exists to print.
    connect_rc=0
    connect_out="$( timeout "$CONNECT_TIMEOUT" "$ADB" connect "$CONNECT_ADDR" 2>&1 )" \
        || connect_rc=$?
    [ -n "$connect_out" ] && echo "$connect_out"

    # `timeout` reports 124 when it had to kill the command. Anything else is adb's own.
    if [ "$connect_rc" = 124 ]; then
        print_error "No answer from $CONNECT_ADDR after ${CONNECT_TIMEOUT}s — giving up."
        print_info "Nothing at that address is even refusing the connection, which usually means:"
        print_info "  - the IP is wrong (check the phone: Settings → Developer options →"
        print_info "    Wireless debugging — it shows the current address AND port), or"
        print_info "  - wireless debugging is switched off, or the phone is asleep, or"
        print_info "  - the phone is on a different network from this laptop."
        print_info "Raise the wait with CONNECT_TIMEOUT=<seconds> if the LAN is genuinely slow."
        exit 1
    fi

    case "$connect_out" in
        *"connected to"*) print_success "Connected to $CONNECT_ADDR" ;;
        *)
            print_error "Could not connect to $CONNECT_ADDR"
            print_info "Something answered and refused — so the address is reachable but the"
            print_info "port is wrong or wireless debugging has been toggled since you read it."
            print_info "The port changes EVERY time wireless debugging is toggled — re-read it."
            print_info "If the phone was never paired with this laptop, use --pair first."
            exit 1 ;;
    esac
fi

# ════════════════════════════════════════════════════════════════════════════════════
# Choose a device
# ════════════════════════════════════════════════════════════════════════════════════
print_step "Looking for a device"

# `adb devices` first line is a header; every later non-blank line is "<serial>\t<state>".
device_lines="$( "$ADB" devices | tail -n +2 | grep -v '^[[:space:]]*$' || true )"

phones=()        # serials in state `device`, not emulators
emulators=()     # serials in state `device`, emulators
unauthorized=()
offline=()

# 🔴 COUNTED IN SCALARS, NOT WITH ${#arr[@]}, AND THAT IS NOT A STYLE CHOICE. The laptop's
# /bin/bash is 3.2, where `set -u` makes ${#arr[@]} on an EMPTY array an unbound-variable
# error rather than 0. Every no-device path reads at least one empty array, so the script
# would die with "unbound variable" at precisely the moment its job is to explain why no
# device was found. The shebang now prefers a newer bash from PATH, but `bash script.sh`
# ignores a shebang entirely, so the counters are the belt to that brace.
n_phones=0; n_emulators=0; n_unauthorized=0; n_offline=0

while IFS= read -r line; do
    [ -z "$line" ] && continue
    serial="$( printf '%s' "$line" | awk '{print $1}' )"
    state="$(  printf '%s' "$line" | awk '{print $2}' )"
    [ -z "$serial" ] && continue
    case "$state" in
        device)
            case "$serial" in
                emulator-*) emulators+=( "$serial" );    n_emulators=$(( n_emulators + 1 )) ;;
                *)          phones+=( "$serial" );       n_phones=$(( n_phones + 1 )) ;;
            esac ;;
        unauthorized) unauthorized+=( "$serial" ); n_unauthorized=$(( n_unauthorized + 1 )) ;;
        *)            offline+=( "$serial" );      n_offline=$(( n_offline + 1 )) ;;   # offline, bootloader, …
    esac
done <<< "$device_lines"

# Choose: the phone wins, and say so when the choice was between two.
CHOSEN=""
CHOSEN_KIND=""
if [ -n "$DEVICE_SERIAL" ]; then
    CHOSEN="$DEVICE_SERIAL"
    case "$CHOSEN" in emulator-*) CHOSEN_KIND="emulator" ;; *) CHOSEN_KIND="phone" ;; esac
    print_info "Using the serial you passed: $CHOSEN"
elif [ "$n_phones" -gt 0 ]; then
    CHOSEN="${phones[0]}"
    CHOSEN_KIND="phone"
    if [ "$n_emulators" -gt 0 ]; then
        print_info "Both a phone and an emulator are attached — PREFERRING THE PHONE."
        print_info "  phone:    $CHOSEN"
        print_info "  emulator: ${emulators[*]}  (pass --device to override)"
    fi
    if [ "$n_phones" -gt 1 ]; then
        print_info "More than one phone attached; using the first: $CHOSEN"
        print_info "  all phones: ${phones[*]}  (pass --device to pick another)"
    fi
elif [ "$n_emulators" -gt 0 ]; then
    CHOSEN="${emulators[0]}"
    CHOSEN_KIND="emulator"
    print_info "No phone attached; using the emulator: $CHOSEN"
fi

# Nothing usable: say which of the three situations this is, because the fix differs.
if [ -z "$CHOSEN" ]; then
    print_error "No device adb can install to."
    if [ "$n_unauthorized" -gt 0 ]; then
        print_info "UNAUTHORIZED: ${unauthorized[*]}"
        print_info "  The phone is plugged in and visible but has not trusted this laptop."
        print_info "  Unlock it and tap \"Allow USB debugging\" (tick \"Always allow\")."
        print_info "  This is a one-time on-device tap; no script can perform it."
    fi
    if [ "$n_offline" -gt 0 ]; then
        print_info "OFFLINE: ${offline[*]}"
        print_info "  Usually a sleeping phone or a dropped wireless link."
        print_info "  Wake it, then re-run; for wireless, re-run with --connect."
    fi
    if [ "$n_unauthorized" -eq 0 ] && [ "$n_offline" -eq 0 ]; then
        print_info "adb sees nothing at all. Either:"
        print_info "  - plug the phone in over USB (with USB debugging enabled), or"
        print_info "  - start it wirelessly:  --connect <phone-ip>   (--pair first, once), or"
        print_info "  - start the emulator."
    fi
    exit 1
fi

if [ "$LIST_ONLY" = true ]; then
    print_step "adb sees"
    printf '%s\n' "$device_lines"
    print_success "Would install to the $CHOSEN_KIND: $CHOSEN"
    exit 0
fi

# ════════════════════════════════════════════════════════════════════════════════════
# Pull the APK over the mount
# ════════════════════════════════════════════════════════════════════════════════════
print_step "Fetching the APK"

if [ ! -f "$APK_SRC" ]; then
    print_error "APK not found: $APK_SRC"
    print_info "The DEV SERVER builds it. Nothing here rebuilds, on purpose."
    print_info "On the dev server, in the MAIN checkout (not a worktree):"
    print_info "  JAVA_HOME=\$HOME/opt/jdk-21 GRADLE_OPTS=... ./flutter.sh build apk --debug"
    print_info "See CLAUDE.md § DEVELOPMENT COMMANDS for the full command with the override."
    print_info "If the path itself looks wrong, the SMB mount is probably not mounted."
    exit 3
fi

print_info "Source:    $APK_SRC"
print_info "Built:     $( file_stamp "$APK_SRC" )"

# 🔴 A TIMESTAMP IS A DISCLOSURE, NOT A CONTROL, AND THIS IS THE CONTROL.
# Printing when the APK was built puts a two-timestamp comparison in the reader's head at
# the worst possible moment, and the line scrolls past above the ✓ the eye actually lands
# on. So: if any .dart under lib/ is newer than the APK, REFUSE. The whole point of this
# script is that the dev server builds and the laptop installs — which makes "the source
# moved and nobody rebuilt" the single most likely way it hands over the wrong binary.
# --allow-stale exists because sometimes you do mean it, and it is never silent.
newer_dart="$( find "$REPO_ROOT/lib" -name '*.dart' -newer "$APK_SRC" -print -quit 2>/dev/null || true )"
if [ -n "$newer_dart" ]; then
    newer_count="$( find "$REPO_ROOT/lib" -name '*.dart' -newer "$APK_SRC" 2>/dev/null | wc -l | tr -d ' ' )"
    if [ "$ALLOW_STALE" = true ]; then
        print_info "STALE, and you passed --allow-stale: $newer_count .dart file(s) under lib/"
        print_info "are newer than this APK. Installing it anyway, as asked."
        print_info "  e.g. ${newer_dart#"$REPO_ROOT"/}"
    else
        print_error "STALE APK — refusing to install."
        print_info "$newer_count .dart file(s) under lib/ are newer than this build."
        print_info "  e.g. ${newer_dart#"$REPO_ROOT"/}"
        print_info "This APK does NOT contain those changes. Rebuild on the DEV SERVER, in the"
        print_info "MAIN checkout (see CLAUDE.md § DEVELOPMENT COMMANDS), then run this again."
        print_info "To install this build regardless:  --allow-stale"
        exit 3
    fi
fi

# 🔴 NOTHING HERE REBUILDS, SO THAT TIMESTAMP IS THE HONEST ANSWER TO "WHAT AM I
# INSTALLING?" A source change newer than it is NOT in this binary — the dev server has to
# build again first. This is the same hazard the sibling script's --push-only prints, and
# for this script it is not a mode, it is the whole design.

# Copy off the mount before installing. `adb install` streams the whole file, and doing
# that straight from SMB is both slow and the thing that fails halfway on a flaky mount —
# a local copy turns "the install broke" into "the copy broke", which is a much clearer
# failure and costs one cheap retry instead of a partial install.
TMP_DIR="$( mktemp -d "${TMPDIR:-/tmp}/lupin-apk.XXXXXX" )"
trap 'rm -rf "$TMP_DIR"' EXIT
APK_LOCAL="$TMP_DIR/app-debug.apk"

if ! cp "$APK_SRC" "$APK_LOCAL"; then
    print_error "Could not copy the APK off the mount."
    print_info "Check the SMB mount is up and readable: $REPO_ROOT"
    exit 3
fi

src_size="$( wc -c < "$APK_SRC" | tr -d ' ' )"
dst_size="$( wc -c < "$APK_LOCAL" | tr -d ' ' )"
if [ "$src_size" != "$dst_size" ]; then
    # A short copy off a network mount is the failure this catches: adb would then reject
    # a truncated archive with a parse error that says nothing about the mount.
    print_error "Short copy: $dst_size of $src_size bytes. The mount dropped mid-read."
    exit 3
fi
print_success "Fetched $dst_size bytes"

# ════════════════════════════════════════════════════════════════════════════════════
# Install
# ════════════════════════════════════════════════════════════════════════════════════
print_step "Installing to the $CHOSEN_KIND: $CHOSEN"

# `-r` reinstalls over the existing app and keeps its data. A signature change (a release
# build over a debug one, or a rebuilt debug keystore) makes it fail with
# INSTALL_FAILED_UPDATE_INCOMPATIBLE; that needs an uninstall, which this script does NOT
# do on its own because it would take the app's data with it. Named so the message is
# recognisable rather than mysterious.
# 🔴 THE EXIT CODE IS NOT THE ANSWER ON ITS OWN — THE SAME TRAP AS `adb connect` ABOVE,
# AND THIS SCRIPT FELL INTO IT ONCE. Older platform-tools print
# `Failure [INSTALL_FAILED_…]` and still exit 0, so a status-only check reports
# "✓ Installed" and then "✓ Done — the phone is running the APK built <T>" over a phone
# that is running last week's build. Pocholo demonstrated exactly that against a stub.
# Platform-tools ≥ 28 does exit non-zero, so on a current laptop this arm may never fire —
# which is an argument for keeping it, not for leaving it out: nothing else catches it,
# and nobody is checking the laptop's version before every deploy.
install_out="$( "$ADB" -s "$CHOSEN" install -r "$APK_LOCAL" 2>&1 )" && install_rc=0 || install_rc=$?
echo "$install_out"

install_failed=0
[ "$install_rc" != 0 ] && install_failed=1
case "$install_out" in
    *Failure*|*"adb: failed"*|*"Error:"*) install_failed=1 ;;
esac

if [ "$install_failed" = 0 ]; then
    print_success "Installed"
else
    print_error "adb install failed."
    [ "$install_rc" = 0 ] && print_info "(adb exited 0 but said so in its output — that is why this is checked.)"
    print_info "If it said INSTALL_FAILED_UPDATE_INCOMPATIBLE, the signature changed:"
    print_info "  $ADB -s $CHOSEN uninstall $PACKAGE_NAME   # ⚠️ ALSO DELETES THE APP'S DATA"
    print_info "then run this again. Not done automatically — that is your data to lose."
    print_info "If it said INSTALL_FAILED_INSUFFICIENT_STORAGE, free space on the phone:"
    print_info "  this debug APK is large (a debug build carries every ABI and no shrinking)."
    exit 1
fi

if [ "$DO_LAUNCH" = true ]; then
    print_step "Launching"
    if "$ADB" -s "$CHOSEN" shell am start -n "$LAUNCH_ACTIVITY" >/dev/null 2>&1; then
        print_success "Launched $PACKAGE_NAME"
    else
        # Not fatal: the install is what was asked for, and the launcher icon still works.
        print_info "Launch did not take — start it from the phone. The install succeeded."
    fi
fi

echo ""
print_success "Done — $CHOSEN_KIND $CHOSEN is running the APK built $( file_stamp "$APK_SRC" )"

if [ "$DO_LOGCAT" = true ]; then
    print_step "Tailing logcat (Ctrl+C to stop)"
    print_info "Filtering for: flutter | lupin_mobile | AndroidRuntime"
    "$ADB" -s "$CHOSEN" logcat -c
    sleep 1
    "$ADB" -s "$CHOSEN" logcat | grep --line-buffered -E "flutter|lupin_mobile|AndroidRuntime"
fi
