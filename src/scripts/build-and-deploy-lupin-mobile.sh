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
#   ./build-and-deploy-lupin-mobile.sh
#   (Press Ctrl+C to stop logcat)
#
# Recommended laptop alias:
#   alias bndm='cd /Volumes/data/include/www.deepily.ai/projects/lupin/src/lupin-mobile/src/scripts && ./build-and-deploy-lupin-mobile.sh'
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

# ============================================================================
# Step 1: Sync
# ============================================================================
print_step "Step 1/4: Syncing code (rsync)"

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
print_step "Step 2/4: Building debug APK (flutter build apk)"

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

print_info "Running: flutter build apk --debug"
if flutter build apk --debug; then
    print_success "APK built successfully"
else
    print_error "Flutter build failed"
    exit 1
fi

echo ""

# ============================================================================
# Step 3: Install to emulator
# ============================================================================
print_step "Step 3/4: Installing APK to emulator (adb)"

if [ ! -f "$APK_PATH" ]; then
    print_error "APK not found: $APK_PATH"
    exit 1
fi

print_info "APK location: $TARGET_DIR/$APK_PATH"

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
# Step 4: Logcat (filtered)
# ============================================================================
print_step "Step 4/4: Tailing logcat (Ctrl+C to stop)"

print_info "Filtering for: flutter | lupin_mobile | AndroidRuntime"
echo -e "${YELLOW}Press Ctrl+C to stop logcat when done${NC}"
echo ""

# Clear old logs and tail fresh output
adb logcat -c
sleep 1
adb logcat | grep --line-buffered -E "flutter|lupin_mobile|AndroidRuntime"
