#!/usr/bin/env bash
#
# build-apk-on-server.sh
#
# Build the debug APK on the DEV SERVER, in the MAIN checkout, with the memory settings
# that survive a worker seat's 8 GiB cap. Run it on the server directly, or from the
# laptop through `deploy-apk-to-device.sh --build`, which calls it over ssh and then
# installs the result.
#
#   ./build-apk-on-server.sh
#
# ─────────────────────────────────────────────────────────────────────────────────────
# WHY THE SETTINGS LIVE HERE AND NOT IN SOMEONE'S HEAD (row f681440d)
#
# The build is one long command (CLAUDE.md § DEVELOPMENT COMMANDS). Without the GRADLE_OPTS
# override, android/gradle.properties asks Gradle for -Xmx8G plus 4G metaspace, the seat's
# cap kills it, and all Gradle says is "Gradle build daemon disappeared unexpectedly". That
# is not a message anyone connects to memory, so the override belongs in a script.
#
# WHY THE MAIN CHECKOUT ONLY
#
# android/app/google-services.json is gitignored, so a worktree does not have it and the
# build fails deep inside Gradle. The laptop also installs from the main checkout's
# build/ directory over the SMB mount, so an APK built anywhere else would never reach it.
# ─────────────────────────────────────────────────────────────────────────────────────
#
# EXIT CODES
#   0  built; the APK is newer than the moment this script started
#   1  the build failed, or finished without producing a new APK
#   2  bad arguments
#   3  wrong place: a worktree, no google-services.json, or no JDK
#   4  another build is already running
#
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

print_step()    { echo -e "${BLUE}=== $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}" >&2; }
print_info()    { echo -e "${YELLOW}ℹ $1${NC}"; }

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
APK="$REPO_ROOT/build/app/outputs/flutter-apk/app-debug.apk"

# Same values as CLAUDE.md § DEVELOPMENT COMMANDS. Overridable, but the defaults are the
# ones that are known to fit under 8 GiB.
JAVA_HOME="${JAVA_HOME_OVERRIDE:-$HOME/opt/jdk-21}"
GRADLE_OPTS="${GRADLE_OPTS:--Dorg.gradle.jvmargs=-Xmx4g\ -XX:MaxMetaspaceSize=1g\ -XX:ReservedCodeCacheSize=256m -Dkotlin.daemon.jvmargs=-Xmx1500m -Dorg.gradle.workers.max=6}"
export JAVA_HOME GRADLE_OPTS

usage() {
    cat <<'EOF'
build-apk-on-server.sh — build the debug APK on the dev server, main checkout only

  (no arguments)   Build. Prints the commit it built and where the APK is.
  --fcm            Compile in FCM push wake-ups (--dart-define=ENABLE_FCM=true). Opt-in
                   until the wake path is proven on a device (row 8ff78c69, slice 1).
  --help, -h       This text.

Environment:
  JAVA_HOME_OVERRIDE   JDK to use (default ~/opt/jdk-21)
  GRADLE_OPTS          Gradle memory settings (default: the 8 GiB-safe values)

From the laptop, `deploy-apk-to-device.sh --build` runs this over ssh, then installs.
EOF
}

FCM=false
while [ $# -gt 0 ]; do
    case "$1" in
        --fcm)     FCM=true ;;
        --help|-h) usage; exit 0 ;;
        *) print_error "Unknown argument: $1"; echo ""; usage; exit 2 ;;
    esac
    shift
done

# ════════════════════════════════════════════════════════════════════════════════════
# Right place?
# ════════════════════════════════════════════════════════════════════════════════════
# In a worktree, --git-dir points under the main repo's .git/worktrees/ and differs from
# --git-common-dir. In the main checkout they are the same directory.
git_dir="$(    cd "$REPO_ROOT" && cd "$( git rev-parse --git-dir )"        && pwd )"
common_dir="$( cd "$REPO_ROOT" && cd "$( git rev-parse --git-common-dir )" && pwd )"
if [ "$git_dir" != "$common_dir" ]; then
    print_error "This is a git worktree ($REPO_ROOT), not the main checkout."
    print_info "Worktrees have no android/app/google-services.json, and the laptop installs"
    print_info "from the main checkout's build/ directory. Run the main checkout's copy:"
    print_info "  $( dirname "$common_dir" )/src/scripts/build-apk-on-server.sh"
    exit 3
fi

if [ ! -f "$REPO_ROOT/android/app/google-services.json" ]; then
    print_error "android/app/google-services.json is missing."
    print_info "It is gitignored and has to be copied in by hand; the build cannot run without it."
    exit 3
fi

if [ ! -x "$JAVA_HOME/bin/java" ]; then
    print_error "No JDK at $JAVA_HOME"
    print_info "Set JAVA_HOME_OVERRIDE=/path/to/jdk-21, or see CLAUDE.md § DEVELOPMENT COMMANDS."
    exit 3
fi

# ════════════════════════════════════════════════════════════════════════════════════
# One build at a time
# ════════════════════════════════════════════════════════════════════════════════════
# Two builds in the same tree fight over build/ and Gradle's lock, and the loser fails
# with a lock-timeout message that looks like a broken build. Say so instead.
mkdir -p "$REPO_ROOT/build"
exec 9>"$REPO_ROOT/build/.build-apk.lock"
if ! flock -n 9; then
    print_error "Another APK build is already running in $REPO_ROOT."
    print_info "Wait for it to finish, then run this again (or just deploy what it produces)."
    exit 4
fi

# ════════════════════════════════════════════════════════════════════════════════════
# Build
# ════════════════════════════════════════════════════════════════════════════════════
cd "$REPO_ROOT"
sha="$( git rev-parse --short HEAD )"
branch="$( git branch --show-current )"
dirty=""
[ -n "$( git status --porcelain -- lib pubspec.yaml android )" ] && dirty=" (plus uncommitted changes under lib/, pubspec.yaml or android/)"

fcm_note=""
build_args=( build apk --debug )
if [ "$FCM" = true ]; then
    build_args+=( --dart-define=ENABLE_FCM=true )
    fcm_note=" (with FCM push wake-ups)"
fi

print_step "Building debug APK on $( hostname ): $branch @ $sha$dirty$fcm_note"
print_info "About 1 minute warm, about 7 minutes cold."

# A marker file stamped now: the APK must end up newer than this, or the build did not
# actually replace it (Flutter can exit 0 in some failure modes and leave the old one).
marker="$( mktemp "${TMPDIR:-/tmp}/lupin-build-start.XXXXXX" )"
trap 'rm -f "$marker"' EXIT

started=$SECONDS
if ! ./flutter.sh "${build_args[@]}"; then
    print_error "flutter build apk failed."
    print_info "If it said \"Gradle build daemon disappeared unexpectedly\", it ran out of memory:"
    print_info "check GRADLE_OPTS was not overridden with larger values."
    exit 1
fi

if [ ! -f "$APK" ] || [ ! "$APK" -nt "$marker" ]; then
    print_error "The build reported success but did not produce a new APK at $APK"
    exit 1
fi

print_success "Built in $(( SECONDS - started ))s: $APK"
print_success "Commit: $branch @ $sha$dirty$fcm_note"
