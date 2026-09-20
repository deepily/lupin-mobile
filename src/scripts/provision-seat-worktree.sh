#!/usr/bin/env bash
#
# Give a spawned SEAT its own private worktree of lupin-mobile, so two seats can never
# be mid-edit in one working tree.
#
# THE DEFECT THIS CLOSES (row 133f34ea, found live 2026-09-19 while staffing the
# fleet-panes cascade). `spawn_sessions( project="lupin-mobile" )` places the child in
# the MAIN CHECKOUT and reports `worktree_status: "script_absent"`, because this repo has
# none of the three provisioning scripts lupin has. The spawner degrades to the main tree
# rather than refusing, so the failure is silent unless someone reads `worktree_status`.
#
# Measured that evening: two review seats sat in the live tree while the manager held
# uncommitted changes in it and committed from it. It had happened before — 2026-09-14,
# this repo, "the spawn dropped both into the main tree", and two builders had to be moved
# by hand before they could work.
#
# ⚠️ THIS IS A NEAR-VERBATIM PORT of lupin's `src/scripts/provision-seat-worktree.sh`, and
# that is deliberate. The script is entirely project-agnostic — git worktree mechanics,
# a seat-name slug, a janitor lock and four output keys. NOTHING in it is Python, and
# nothing in it needed to become Flutter. The two things that DID need porting are its
# siblings, `link-worktree-venv.sh` and `link-worktree-artifacts.sh`, which is where every
# Flutter-specific decision lives. Keeping this one identical means a fix to the shared
# hazard lands in both repos as the same diff.
#
# ⚠️ WHAT THIS DOES NOT DO: it never removes a worktree. Teardown belongs to the reap
# path and to the arbiter's worktree janitor.
#
# 🔴 WHERE THE TREE GOES, AND WHY IT IS LOCKED. Seat trees live in the sanctioned lane,
# `<main>/.claude/worktrees/seat-<seat>` — gitignored here by `.claude/*` (.gitignore:2),
# out of sight, and swept by the janitor. The janitor drains any tree there idle past its
# threshold and a LIVE seat can easily sit idle that long, so the tree is locked with
# reason `lupin-seat:<seat>`. A seat-locked tree is swept only once the seat is provably
# gone.
#
# Usage:
#   provision-seat-worktree.sh <main-repo-root> <seat-name>
#   provision-seat-worktree.sh --check <path>     # report, change nothing
#
# Machine-readable output — the caller parses these keys, one per line, never the prose:
#   WORKTREE=<absolute path>
#   DRIFT_BEHIND=<commits this tree is behind the main checkout's HEAD>
#   STATUS=created|reused|already_seat_tree
#
# Exit codes:
#   0  the seat has a private worktree (created or already there)
#   2  bad arguments, missing directory, or not a git repository
#   4  the target already exists and is NOT a worktree — not ours to touch
#   5  git worktree add failed
#   6  created it but it does not verify — never report success on an unverified tree

set -euo pipefail

if [[ "${1:-}" == "--check" ]]; then
    TARGET="${2:-$PWD}"
    if [[ ! -d "$TARGET" ]]; then
        echo "ERROR: not a directory: $TARGET" >&2
        exit 2
    fi
    # No pipe into a short-circuiting reader — see the SIGPIPE note in
    # link-worktree-venv.sh.
    if ! LIST="$( git -C "$TARGET" worktree list --porcelain 2>/dev/null )"; then LIST=""; fi
    MAIN=""
    while IFS= read -r line; do
        if [[ "$line" == "worktree "* ]]; then MAIN="${line#worktree }"; break; fi
    done <<< "$LIST"
    if [[ -z "$MAIN" ]]; then
        echo "ERROR: $TARGET is not inside a git repository" >&2
        exit 2
    fi
    if [[ "$( cd "$TARGET" && pwd -P )" == "$( cd "$MAIN" && pwd -P )" ]]; then
        echo "SHARED: $TARGET is the MAIN checkout — a peer's uncommitted work can be here" >&2
        exit 1
    fi
    echo "PRIVATE: $TARGET is its own worktree"
    exit 0
fi

MAIN_ROOT="${1:-}"
SEAT_NAME="${2:-}"

if [[ -z "$MAIN_ROOT" || -z "$SEAT_NAME" ]]; then
    echo "ERROR: usage: provision-seat-worktree.sh <main-repo-root> <seat-name>" >&2
    exit 2
fi
if [[ ! -d "$MAIN_ROOT" ]]; then
    echo "ERROR: not a directory: $MAIN_ROOT" >&2
    exit 2
fi

if ! LIST="$( git -C "$MAIN_ROOT" worktree list --porcelain 2>/dev/null )"; then LIST=""; fi
MAIN=""
while IFS= read -r line; do
    if [[ "$line" == "worktree "* ]]; then MAIN="${line#worktree }"; break; fi
done <<< "$LIST"
if [[ -z "$MAIN" ]]; then
    echo "ERROR: $MAIN_ROOT is not inside a git repository" >&2
    exit 2
fi

# ⚠️ RESOLVE THE MAIN CHECKOUT RATHER THAN TRUSTING THE ARGUMENT. A manager standing in
# its own worktree hands us that worktree; nesting a worktree inside one is not what the
# ruling asks for, and `git worktree list` already names the primary tree for us.
MAIN="$( cd "$MAIN" && pwd -P )"

# Sanitize the seat name into a path segment. A seat name reaches us from a spawn
# record; it is not a path and must never be able to become one.
SLUG="$( printf '%s' "$SEAT_NAME" | tr -c 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//' )"
if [[ -z "$SLUG" ]]; then
    echo "ERROR: seat name sanitizes to nothing: $SEAT_NAME" >&2
    exit 2
fi

SEAT_LANE="$MAIN/.claude/worktrees"
TARGET="$SEAT_LANE/seat-${SLUG}"
LOCK_REASON="lupin-seat:${SEAT_NAME}"

# Lock the seat's tree so the janitor leaves it alone while the seat lives. Idempotent:
# git refuses to lock a tree that is already locked, and that is not a failure here.
lock_seat_tree() {
    git -C "$MAIN" worktree lock --reason "$LOCK_REASON" "$TARGET" >/dev/null 2>&1 || true
}

# 🔴 THE SHORT-CIRCUIT ASKS "AM I THIS SEAT'S OWN TREE", NOT "AM I SOMEWHERE OTHER THAN
# THE MAIN CHECKOUT" — and it is computed AFTER `TARGET` for exactly that reason. The
# earlier shape tested `MAIN_ROOT != MAIN` and had a measured hole: a manager standing in
# its OWN worktree hands us that worktree, the test passed, the seat name was IGNORED, and
# every seat of the batch shared one tree with every alarm silent. "Not the main checkout"
# is not "private to me".
if [[ "$( cd "$MAIN_ROOT" && pwd -P )" == "$TARGET" ]]; then
    echo "STATUS=already_seat_tree"
    echo "WORKTREE=$TARGET"
    echo "DRIFT_BEHIND=$( git -C "$MAIN_ROOT" rev-list --count HEAD.."$( git -C "$MAIN" rev-parse HEAD )" 2>/dev/null || echo 0 )"
    echo "Already this seat's own worktree — nothing to provision."
    exit 0
fi

# Idempotent: a registered worktree at that path is REUSED, never recreated. A seat that
# is re-spun under the same name comes back to its own tree with its work still in it.
IS_REGISTERED=0
while IFS= read -r line; do
    if [[ "$line" == "worktree "* ]]; then
        if [[ "${line#worktree }" == "$TARGET" ]]; then IS_REGISTERED=1; break; fi
    fi
done <<< "$LIST"

if [[ $IS_REGISTERED -eq 1 && -d "$TARGET" ]]; then
    lock_seat_tree
    echo "STATUS=reused"
    echo "WORKTREE=$TARGET"
    echo "DRIFT_BEHIND=$( git -C "$TARGET" rev-list --count HEAD.."$( git -C "$MAIN" rev-parse HEAD )" 2>/dev/null || echo 0 )"
    echo "Reusing the existing worktree for seat $SEAT_NAME"
    exit 0
fi

if [[ -e "$TARGET" ]]; then
    echo "ERROR: $TARGET exists and is not a registered worktree — not mine to touch" >&2
    exit 4
fi

mkdir -p "$SEAT_LANE"
if ! git -C "$MAIN" worktree add --detach "$TARGET" HEAD >/dev/null 2>&1; then
    echo "ERROR: git worktree add failed for $TARGET" >&2
    exit 5
fi

# Verify rather than assume — a directory that exists is not a working tree.
if [[ ! -d "$TARGET" ]] || ! git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: created $TARGET but it is not a usable worktree" >&2
    exit 6
fi
lock_seat_tree

echo "STATUS=created"
echo "WORKTREE=$TARGET"
echo "DRIFT_BEHIND=$( git -C "$TARGET" rev-list --count HEAD.."$( git -C "$MAIN" rev-parse HEAD )" 2>/dev/null || echo 0 )"
