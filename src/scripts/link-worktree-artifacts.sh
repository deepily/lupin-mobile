#!/usr/bin/env bash
#
# Give a linked worktree the UNTRACKED artifacts it needs to run a whole tier, by
# borrowing the main checkout's — the same move `link-worktree-venv.sh` makes for the
# Flutter SDK, for the members that script does not cover.
#
# THE DEFECT THIS CLOSES (row 133f34ea). A fresh worktree holds exactly the tracked files
# at its sha, so what git does not track is BY CONSTRUCTION what a worktree lacks:
#     git ls-files --others --ignored --exclude-standard --directory
# The enumeration is arithmetic. The FILTER below is where the judgement lives, and it is
# deliberately short — this script does not try to provision the whole ignored set.
#
# ⚠️ AN SDK AND A TIER-CAPABLE TREE ARE DIFFERENT CLAIMS. `link-worktree-venv.sh` makes
# the first; without this script the second is still false, and the failure reads as a
# broken test rather than a missing tree.
#
# ─────────────────────────────────────────────────────────────────────────────────
# 🔴 THE DENY SIDE IS THE LOAD-BEARING HALF. Three rules, and the middle one is specific
# to Flutter and is the reason this script is not a copy of lupin's.
#
# 1. NEVER A SECRET. Not `android/app/google-services.json` (Firebase client config,
#    untracked here), not `CLAUDE.local.md`, not anything under a keys directory. A
#    symlink puts a live credential inside a throwaway tree that gets rm -rf'd, copied and
#    shared, and the SDK precedent makes it look sanctioned. A key-dependent test SKIPS
#    when its key is absent — that is the remedy for that family, and it is not this
#    script.
#
# 2. 🔴 NEVER `.dart_tool/`, AND THIS ONE IS NOT OBVIOUS. It is untracked, it is 126 MB,
#    and borrowing it looks exactly like borrowing `node_modules`. It is not.
#    `.dart_tool/` is WRITTEN — `flutter pub get` and `flutter test` both rewrite
#    `package_config.json` and the build stamps inside it. Through a symlink those writes
#    land in the MAIN CHECKOUT's `.dart_tool/`, so two seats running tests at once corrupt
#    each other's package resolution and the main tree's with it. That is the
#    "a copy does not merge" hazard wearing a symlink.
#
#    ⇒ Regenerate instead. `flutter test` runs `pub get` itself when
#    `package_config.json` is missing, so the tree self-heals on first use at no cost to
#    provisioning. Measured on the main checkout 2026-09-19: `lupin_mobile -> ../` is
#    RELATIVE (so the self-package would survive a copy), but `flutterRoot` is ABSOLUTE
#    and the 208 dependency roots point at the user-global `~/.pub-cache` — which is why
#    regeneration is cheap and correct, and copying is merely expensive and fragile.
#
# 3. NEVER A BUILD OUTPUT. `build/` is 138 MB and untracked and it is out for the same
#    reason lupin keeps `dist/` out: a symlinked output directory means a build run in a
#    throwaway tree writes into the SHARED checkout.
#
# ─────────────────────────────────────────────────────────────────────────────────
# ⚠️ ONE MEMBER IS COPIED, NOT LINKED, AND THE DISTINCTION IS THE POINT. `pubspec.lock` is
# gitignored in this repo, so a worktree has none. Two wrong answers:
#   · LINK it — then `flutter pub get` in the worktree rewrites the MAIN tree's lock file.
#     A throwaway tree silently re-pins the shared checkout's dependency versions.
#   · LEAVE it — then the worktree resolves fresh and may pin DIFFERENT versions than the
#     main tree. A suite that passes there and fails here, or worse passes both while
#     testing different code, is a false green with no visible cause.
# ⇒ COPY it. The worktree gets the same pinned versions and owns its own file, so its
#   `pub get` writes stay inside it.
#
# ⚠️ THIS SCRIPT RUNS NO TOOLCHAIN. The spawn path allows 30 SECONDS
# (`worktree_artifacts.py:51`); a 208-package resolve does not fit and a timeout is
# reported as `failed`. Every operation here is a symlink or a small file copy.
#
# Usage:
#   src/scripts/link-worktree-artifacts.sh            # provision the tree you are in
#   src/scripts/link-worktree-artifacts.sh <path>     # provision another worktree
#   src/scripts/link-worktree-artifacts.sh --check    # report, change nothing
#
# Machine-readable output — the caller parses these keys, one per line, never the prose:
#   LINKED=<rel>          a symlink was created and verified
#   COPIED=<rel>          a file was copied (see the pubspec.lock note above)
#   ALREADY=<rel>         something is already there and resolves — left alone
#   SOURCE_ABSENT=<rel>   the MAIN checkout does not have it either — nothing to borrow
#   REFUSED=<rel>         the link could not be created
#
# ⚠️ `COPIED=` IS NOT IN `worktree_artifacts.py:55`'s `_OUTCOME_KEYS` and is therefore
# ignored by today's parser. It is emitted anyway rather than reported as `LINKED=`,
# because a machine-readable channel that calls a copy a link is lying in the one place a
# reader cannot check. Add it to `_OUTCOME_KEYS` lupin-side if the count ever matters.
#
# Exit codes:
#   0  every borrowable artifact is now present (or the main checkout has none to lend)
#   2  bad arguments, missing directory, or not a git repository
#   3  the target IS the main checkout — a correct no-op, it owns the real artifacts
#   5  a link could not be created (permissions, a racing writer)
#   6  a link was created but does not resolve — never report success on an unverified tree

set -euo pipefail

# ── THE BORROW LIST ───────────────────────────────────────────────────────────────
#
# Relative paths, borrowed from the main checkout by SYMLINK. Read the DENY notes above
# before adding a line here. Each entry must be (a) untracked, (b) not a secret, (c) not
# a build output the worktree itself would write to, (d) not written by the toolchain at
# all, and (e) genuinely reached by code from inside a worktree.
LINK_LIST=(
    # The Gradle wrapper. Untracked (.gitignore), and `android/gradlew` is the entry point
    # for every Android build and instrumentation run. Read-only at run time — Gradle
    # writes to ~/.gradle and to build/, never back into the wrapper.
    "android/gradlew"
    "android/gradle/wrapper/gradle-wrapper.jar"
)

# ── THE COPY LIST ─────────────────────────────────────────────────────────────────
#
# Small files the worktree must OWN rather than share, because the toolchain writes them.
COPY_LIST=(
    "pubspec.lock"
)

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

# 🔴 NO PIPE HERE, DELIBERATELY — the same SIGPIPE race documented at length in
# `link-worktree-venv.sh`: a short-circuiting reader closes the pipe while git is still
# writing a long worktree list, git takes SIGPIPE, and `pipefail` + `set -e` turn that
# into a silent exit 141 that reads like success.
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

if [[ "$( cd "$TARGET" && pwd -P )" == "$( cd "$MAIN_REPO" && pwd -P )" ]]; then
    if [[ $CHECK_ONLY -eq 1 ]]; then
        echo "MAIN: $TARGET is the main checkout - it owns the real artifacts"
        exit 0
    fi
    echo "REFUSING: $TARGET is the MAIN repo, which owns the real artifacts."
    echo "  Linking them to themselves would replace real files with loops."
    exit 3
fi

if [[ $CHECK_ONLY -eq 1 ]]; then
    MISSING=0
    for rel in "${LINK_LIST[@]}" "${COPY_LIST[@]}"; do
        if [[ -e "$TARGET/$rel" ]]; then
            echo "OK: $rel"
        elif [[ ! -e "$MAIN_REPO/$rel" ]]; then
            echo "SOURCE_ABSENT=$rel"
        else
            echo "MISSING: $rel" >&2
            MISSING=1
        fi
    done
    exit $MISSING
fi

# ── Symlinked members ─────────────────────────────────────────────────────────────
for rel in "${LINK_LIST[@]}"; do
    SRC="$MAIN_REPO/$rel"
    DST="$TARGET/$rel"

    if [[ ! -e "$SRC" ]]; then
        echo "SOURCE_ABSENT=$rel"
        continue
    fi
    # Something already there and resolving is left alone, whether it is our symlink or a
    # real file the seat put there itself.
    if [[ -e "$DST" ]]; then
        echo "ALREADY=$rel"
        continue
    fi
    # A dangling symlink is ours and broken — the one case worth clearing.
    if [[ -L "$DST" ]]; then
        rm "$DST"
    fi

    mkdir -p "$( dirname "$DST" )"
    if ! ln -s "$SRC" "$DST" 2>/dev/null; then
        echo "REFUSED=$rel"
        echo "ERROR: could not link $DST -> $SRC" >&2
        exit 5
    fi
    # Verify rather than assume: a symlink resolving to nothing looks identical to success.
    if [[ ! -e "$DST" ]]; then
        echo "REFUSED=$rel"
        echo "ERROR: created $DST but it does not resolve" >&2
        exit 6
    fi
    echo "LINKED=$rel"
done

# ── Copied members ────────────────────────────────────────────────────────────────
for rel in "${COPY_LIST[@]}"; do
    SRC="$MAIN_REPO/$rel"
    DST="$TARGET/$rel"

    if [[ ! -e "$SRC" ]]; then
        echo "SOURCE_ABSENT=$rel"
        continue
    fi
    if [[ -e "$DST" ]]; then
        echo "ALREADY=$rel"
        continue
    fi

    mkdir -p "$( dirname "$DST" )"
    if ! cp "$SRC" "$DST" 2>/dev/null; then
        echo "REFUSED=$rel"
        echo "ERROR: could not copy $SRC -> $DST" >&2
        exit 5
    fi
    if [[ ! -s "$DST" ]]; then
        echo "REFUSED=$rel"
        echo "ERROR: copied $DST but it is empty" >&2
        exit 6
    fi
    echo "COPIED=$rel"
done
