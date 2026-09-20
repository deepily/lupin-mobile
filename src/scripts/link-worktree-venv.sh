#!/usr/bin/env bash
#
# Give a linked worktree the Flutter SDK by symlinking the main checkout's, so the test
# tier answers the same question in every tree.
#
# 🔴 WHY A FLUTTER REPO HAS A SCRIPT CALLED "venv". THE NAME IS A CONTRACT, NOT A
# DESCRIPTION. `cosa/utils/worktree_venv.py:46` hard-codes the relative path
# `src/scripts/link-worktree-venv.sh` and the spawn path calls exactly that. A file named
# `link-worktree-flutter.sh` would be correct English and would never be invoked — the
# spawner would keep reporting `script_absent` and keep dropping seats in the main
# checkout, which is the whole defect (row 133f34ea). The name is lupin's; the CONTENT is
# this repo's answer to the same question: *what does a fresh worktree lack that makes it
# unable to run its own tier?*
#
# Here that is the vendored SDK at `flutter/` (2.3 GB, `.gitignore` — untracked, so
# `git worktree add` never produces one), not a Python `.venv`.
#
# THE DEFECT THIS CLOSES, MEASURED IN A BARE WORKTREE 2026-09-19:
#
#     $ ./flutter.sh test
#     Error: Flutter not found at <worktree>/flutter/bin/flutter
#     exit 1
#
# `flutter.sh` is TRACKED and resolves `$SCRIPT_DIR/flutter/bin/flutter` — relative to
# itself, so in a worktree it looks for the WORKTREE's SDK and finds nothing. The suite
# cannot start. Not one test fails; the runner never runs.
#
# 🔴 LINK, NEVER COPY — AND THE NUMBER IS WHY. The SDK is 2.3 GB. Eight seats copying it
# is 18 GB of duplicated toolchain, and every copy drifts from the main checkout's the
# moment anyone runs `flutter upgrade` in one of them. A symlink duplicates nothing and
# cannot drift, because there is only ever one SDK.
#
# ⚠️ THE SDK IS SHARED MUTABLE STATE, AND THAT IS ACCEPTED DELIBERATELY. `flutter` writes
# into its own tree — `flutter/bin/cache/`, version stamps, the Dart SDK download. Two
# seats running `flutter test` at once therefore write one cache. That is ALREADY TRUE
# today with a single checkout and a single SDK, so linking preserves the current
# behaviour rather than introducing a new hazard; it is named here so nobody discovers it
# and thinks the symlink caused it. The alternative — a private 2.3 GB SDK per seat —
# trades a benign shared cache for 18 GB and a drift surface.
#
# ⚠️ WHAT THIS SCRIPT DOES NOT DO: it does not run `flutter pub get`. The spawn path gives
# this script 30 SECONDS (`worktree_venv.py:54`) and a 208-package resolve does not fit in
# it; a timeout is reported as `failed`, which would turn provisioning into the thing that
# breaks the spawn. Provisioning is symlinks and nothing else — every operation here is
# O(milliseconds). `flutter test` runs `pub get` itself on first use, so the tree
# self-heals. See `link-worktree-artifacts.sh` for the `pubspec.lock` half of that.
#
# Usage:
#   src/scripts/link-worktree-venv.sh            # provision the tree you are standing in
#   src/scripts/link-worktree-venv.sh <path>     # provision another worktree
#   src/scripts/link-worktree-venv.sh --check    # report, change nothing (exit 1 if absent)
#
# Exit codes — these mirror lupin's, because `worktree_venv.py` reads them:
#   0  the tree has a usable SDK (linked now, or already there)
#   1  --check only: no usable SDK
#   2  bad arguments, missing directory, or not a git repository
#   3  the target IS the main checkout — a correct no-op, it owns the real SDK
#   4  the main checkout has no SDK to lend
#   5  something is already at the link path and is not a usable SDK — not ours to delete
#   6  created the link but it does not resolve — never report success unverified

set -euo pipefail

TARGET="${1:-$PWD}"
CHECK_ONLY=0
if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=1
    TARGET="${2:-$PWD}"
fi

if [[ ! -d "$TARGET" ]]; then
    echo "ERROR: not a directory: $TARGET" >&2
    exit 2
fi

# The main repo is the worktree list's first entry — git reports the primary tree first,
# which is the one that actually owns an SDK.
#
# 🔴 NO PIPE HERE, DELIBERATELY. This line is the shape that carried a SIGPIPE race in
# lupin (row f8f7d54b): `git worktree list --porcelain | awk '/^worktree /{print $2; exit}'`
# dies on a long worktree list because awk closes the pipe on its first match while git is
# still writing. git takes SIGPIPE, and `pipefail` + `set -e` turn that into a silent exit
# 141 before any of this script's own messages — which reads to a caller exactly like "ran
# fine, nothing to do" with no SDK. Reading the whole output into a variable first is the
# shape that CANNOT race: there is no reader to close early.
#
# Bonus: ${line#worktree } keeps worktree paths containing spaces, which awk '{print $2}'
# silently truncated at the first space.
if ! WORKTREE_LIST="$( git -C "$TARGET" worktree list --porcelain 2>/dev/null )"; then
    WORKTREE_LIST=""
fi

MAIN_REPO=""
while IFS= read -r line; do
    if [[ "$line" == "worktree "* ]]; then
        MAIN_REPO="${line#worktree }"
        break
    fi
done <<< "$WORKTREE_LIST"
if [[ -z "$MAIN_REPO" ]]; then
    echo "ERROR: $TARGET is not inside a git repository" >&2
    exit 2
fi

SOURCE_SDK="$MAIN_REPO/flutter"
LINK="$TARGET/flutter"

if [[ $CHECK_ONLY -eq 1 ]]; then
    if [[ -x "$LINK/bin/flutter" ]]; then
        echo "OK: $TARGET has a usable Flutter SDK ($( readlink "$LINK" 2>/dev/null || echo "real directory" ))"
        exit 0
    fi
    echo "MISSING: $TARGET has no usable flutter/bin/flutter" >&2
    echo "  ./flutter.sh test cannot start here — the runner never runs (row 133f34ea)." >&2
    echo "  Fix: src/scripts/link-worktree-venv.sh" >&2
    exit 1
fi

if [[ "$( cd "$TARGET" && pwd -P )" == "$( cd "$MAIN_REPO" && pwd -P )" ]]; then
    echo "REFUSING: $TARGET is the MAIN repo, which owns the real SDK."
    echo "  Linking it to itself would replace a real directory with a loop."
    exit 3
fi

if [[ ! -x "$SOURCE_SDK/bin/flutter" ]]; then
    echo "ERROR: the main checkout has no usable SDK to link: $SOURCE_SDK/bin/flutter" >&2
    echo "  Install it there first; this script only shares an existing one." >&2
    exit 4
fi

if [[ -e "$LINK" || -L "$LINK" ]]; then
    if [[ -x "$LINK/bin/flutter" ]]; then
        echo "ALREADY PROVISIONED: $LINK resolves to a usable SDK — leaving it alone."
        exit 0
    fi
    # A dangling symlink is the one case worth clearing: it is ours and it is broken.
    if [[ -L "$LINK" && ! -e "$LINK" ]]; then
        echo "Replacing a dangling symlink at $LINK"
        rm "$LINK"
    else
        echo "REFUSING: $LINK already exists and is not a usable SDK." >&2
        echo "  It is not mine to delete — inspect it and remove it yourself if it is stale." >&2
        exit 5
    fi
fi

ln -s "$SOURCE_SDK" "$LINK"

# Verify rather than assume: a symlink that resolves to nothing looks identical to success.
if [[ ! -x "$LINK/bin/flutter" ]]; then
    echo "ERROR: created $LINK but it does not resolve to an executable flutter" >&2
    exit 6
fi

echo "Linked: $LINK -> $SOURCE_SDK"
