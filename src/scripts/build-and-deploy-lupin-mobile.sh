#!/bin/bash
#
# build-and-deploy-lupin-mobile.sh
#
# One-command build and deploy workflow for Lupin Mobile (Flutter → Android):
#   1. Sync code from SMB mount to laptop local dir (rsync)
#   2. Build debug APK (flutter build apk --debug)
#   3. Install to emulator (adb install -r)
#   4. Tail logcat (filtered)
#
# This script lives on the dev server but EXECUTES ON THE LAPTOP (via SMB).
# The dev server has no Android SDK / adb; the laptop runs the emulator.
#
# Usage:
#   ./build-and-deploy-lupin-mobile.sh              full run: sync → build → install → logcat
#   ./build-and-deploy-lupin-mobile.sh --push-only  skip sync AND build; install the APK
#                                                   already on disk, then logcat
#   ./build-and-deploy-lupin-mobile.sh --help
#
#   (Press Ctrl+C to stop logcat)
#
# --push-only exists for the re-push case: the APK is current but the install is not
# (emulator wiped, app uninstalled, a snapshot rolled back, or you just want the app
# restarted with fresh logcat). A full run costs a pub get and a Gradle build for a
# result you already have on disk.
#
# ⚠️ IT PUSHES WHATEVER IS THERE, WHICH IS THE POINT AND ALSO THE HAZARD. So it prints
# the APK's timestamp and size before installing, and refuses outright if no APK exists.
# "I re-pushed and my change isn't there" is the failure this guards: in push-only mode
# nothing rebuilds, so a source edit since that timestamp is NOT in the binary.
#
# Recommended laptop aliases:
#   alias bndm='cd /Volumes/data/include/www.deepily.ai/projects/lupin-mobile/src/scripts && ./build-and-deploy-lupin-mobile.sh'
#   alias bndmp='bndm --push-only'
#
# Modeled on build-and-deploy-kotlin-java-client.sh from the Gemini project.
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSYNC_SCRIPT="$SCRIPT_DIR/rsync-lupin-mobile.sh"
TARGET_DIR="$HOME/Projects/lupin-mobile"
APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
PACKAGE_NAME="ai.deepily.lupin_mobile"
LAUNCH_ACTIVITY="$PACKAGE_NAME/$PACKAGE_NAME.MainActivity"

# Helpers
print_step() {
    echo -e "${BLUE}===================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================${NC}"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }
print_info()    { echo -e "${YELLOW}ℹ $1${NC}"; }

# Modification time and size of a file, on either platform.
# The laptop is macOS (BSD stat); the dev server is Linux (GNU stat). Trying GNU first
# and falling back is cheaper than detecting the OS, and `ls -l` is the last resort so
# this can never be the reason a push fails.
file_stamp() {
    stat -c '%y  (%s bytes)' "$1" 2>/dev/null \
        || stat -f '%Sm  (%z bytes)' "$1" 2>/dev/null \
        || ls -l "$1"
}

usage() {
    cat <<'EOF'
build-and-deploy-lupin-mobile.sh — sync, build, install, logcat

  (no arguments)   Full run: rsync → flutter build apk --debug → adb install -r → logcat
  --push-only      Skip rsync AND build. Install the APK already on disk, then logcat.
  -p               Short form of --push-only.
  --help, -h       This text.

--push-only is for re-pushing a build you already have: emulator wiped, app uninstalled,
snapshot rolled back, or you just want a restart with clean logcat.

⚠️ It rebuilds NOTHING. Any source change made after the APK timestamp it prints is not
in the binary it installs. If your change is missing, you wanted a full run.
EOF
}

# ============================================================================
# Arguments
# ============================================================================
PUSH_ONLY=false

while [ $# -gt 0 ]; do
    case "$1" in
        --push-only|-p)
            PUSH_ONLY=true
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            # Fail loudly rather than ignoring it: a silently-dropped flag here means a
            # full rebuild the user thought they had skipped, or the reverse.
            print_error "Unknown argument: $1"
            echo ""
            usage
            exit 2
            ;;
    esac
    shift
done

if [ "$PUSH_ONLY" = true ]; then
    TOTAL_STEPS=2
else
    TOTAL_STEPS=4
fi

# ============================================================================
# Steps 1-2: Sync and build   (skipped entirely by --push-only)
# ============================================================================
if [ "$PUSH_ONLY" = true ]; then
    print_step "Push-only: skipping rsync and build"
    print_info "Nothing is being rebuilt — the APK on disk is what gets installed."

    if [ ! -d "$TARGET_DIR" ]; then
        print_error "Target directory not found: $TARGET_DIR"
        exit 1
    fi
    cd "$TARGET_DIR"
    print_info "Working directory: $(pwd)"
    echo ""
else

print_step "Step 1/$TOTAL_STEPS: Syncing code (rsync)"

if [ ! -f "$RSYNC_SCRIPT" ]; then
    print_error "Rsync script not found: $RSYNC_SCRIPT"
    exit 1
fi

print_info "Running: $RSYNC_SCRIPT --write --yes"
if "$RSYNC_SCRIPT" --write --yes; then
    print_success "Code synced successfully"
else
    print_error "Rsync failed"
    exit 1
fi

echo ""

# ============================================================================
# Step 2: Build APK (Flutter)
# ============================================================================
print_step "Step 2/$TOTAL_STEPS: Building debug APK (flutter build apk)"

if [ ! -d "$TARGET_DIR" ]; then
    print_error "Target directory not found: $TARGET_DIR"
    exit 1
fi

cd "$TARGET_DIR"
print_info "Working directory: $(pwd)"

print_info "Running: flutter pub get"
if flutter pub get; then
    print_success "pub get completed"
else
    print_error "pub get failed"
    exit 1
fi

# Build dart-define flags for debug-only pre-filled login credentials.
# Values flow shell env → --dart-define → compile time → baked into debug APK.
# Never committed to git; stripped in release builds (gated by kDebugMode in auth_gate.dart).
BUILD_DEFINES=()
if [ -n "$LUPIN_DEV_EMAIL" ]; then
    BUILD_DEFINES+=( --dart-define="LUPIN_DEV_EMAIL=$LUPIN_DEV_EMAIL" )
    print_info "Baking LUPIN_DEV_EMAIL into debug APK"
fi
if [ -n "$LUPIN_DEV_PASSWORD" ]; then
    BUILD_DEFINES+=( --dart-define="LUPIN_DEV_PASSWORD=$LUPIN_DEV_PASSWORD" )
    print_info "Baking LUPIN_DEV_PASSWORD into debug APK (debug-only, kDebugMode-gated)"
fi

print_info "Running: flutter build apk --debug ${BUILD_DEFINES[*]}"
if flutter build apk --debug "${BUILD_DEFINES[@]}"; then
    print_success "APK built successfully"
else
    print_error "Flutter build failed"
    exit 1
fi

echo ""

fi   # end of the sync-and-build block skipped by --push-only

# ============================================================================
# Install to emulator
# ============================================================================
if [ "$PUSH_ONLY" = true ]; then
    print_step "Step 1/$TOTAL_STEPS: Installing the EXISTING APK to emulator (adb)"
else
    print_step "Step 3/$TOTAL_STEPS: Installing APK to emulator (adb)"
fi

if [ ! -f "$APK_PATH" ]; then
    print_error "APK not found: $APK_PATH"
    if [ "$PUSH_ONLY" = true ]; then
        print_info "Nothing to push — there is no build on disk yet."
        print_info "Run without --push-only once to produce one."
    fi
    exit 1
fi

print_info "APK location: $TARGET_DIR/$APK_PATH"

# 🔴 The one thing push-only has to tell you. Nothing was rebuilt, so this timestamp is
# the honest answer to "what am I actually installing?" — a source edit newer than this
# is not in the binary.
if [ "$PUSH_ONLY" = true ]; then
    print_info "APK built:    $(file_stamp "$APK_PATH")"
    print_info "NOT rebuilt — any source change newer than that is NOT in this binary."
fi

# Verify an emulator/device is connected
if ! adb devices | grep -qE "^emulator|device$"; then
    print_error "No adb devices found. Start the emulator first:"
    print_info "  emu    (alias: emulator @Pixel_8a -no-boot-anim -no-snapshot)"
    exit 1
fi

print_info "Running: adb install -r $APK_PATH"
if adb install -r "$APK_PATH"; then
    print_success "APK installed"
else
    print_error "adb install failed"
    exit 1
fi

# Optionally launch
print_info "Launching app: $LAUNCH_ACTIVITY"
adb shell am start -n "$LAUNCH_ACTIVITY" >/dev/null 2>&1 || print_info "(launch skipped — start manually if needed)"

echo ""

# ============================================================================
# Logcat (filtered)
# ============================================================================
if [ "$PUSH_ONLY" = true ]; then
    print_step "Step 2/$TOTAL_STEPS: Tailing logcat (Ctrl+C to stop)"
else
    print_step "Step 4/$TOTAL_STEPS: Tailing logcat (Ctrl+C to stop)"
fi

print_info "Filtering for: flutter | lupin_mobile | AndroidRuntime"
echo -e "${YELLOW}Press Ctrl+C to stop logcat when done${NC}"
echo ""

# Clear old logs and tail fresh output
adb logcat -c
sleep 1
adb logcat | grep --line-buffered -E "flutter|lupin_mobile|AndroidRuntime"
