#!/bin/bash
# Report the newest GitHub Actions run of each workflow; exit 1 if any is red.
#
# Why: CI sat red from 30 Sep to 9 Nov with nobody reading it (row 23c5580e).
# Run it at session start, or from cron:
#   17 */4 * * * /path/to/src/scripts/ci-status-check.sh --quiet >> ~/.lupin/logs/ci-status.log 2>&1
#
# Requires: gh (logged in), python3. Read-only: it never reruns or edits a run.
# Only runs on one branch (default main) and only finished runs count, so a run still
# in progress never hides an older red one.
# Usage: ci-status-check.sh [--quiet] [--limit N] [--branch NAME]
#   --quiet   print only when something is red (cron-friendly)
#   --limit N how many recent runs to look at (default 30; gh 2.4 cannot filter by branch, so raise it if main is busy)
#   --branch  branch to read (default main)
# Exit: 0 all newest runs green, 1 at least one red, 2 gh unavailable or failed.

set -u

QUIET=0
LIMIT=30
BRANCH=main
while [ $# -gt 0 ]; do
    case "$1" in
        --quiet) QUIET=1 ;;
        --limit)  [ $# -ge 2 ] || { echo "--limit needs a number" >&2; exit 2; }; shift; LIMIT="$1" ;;
        --branch) [ $# -ge 2 ] || { echo "--branch needs a name" >&2; exit 2; }; shift; BRANCH="$1" ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

RAW=$( gh run list --limit "$LIMIT" --json name,conclusion,status,headBranch,databaseId,createdAt 2>&1 ) || {
    echo "CI status: gh failed: $RAW" >&2
    exit 2
}

echo "$RAW" | QUIET=$QUIET BRANCH=$BRANCH python3 -I -c '
import json, os, sys
try:
    runs = json.load( sys.stdin )
except ValueError as e:
    print( f"CI status: gh returned malformed JSON: {e}", file=sys.stderr )
    sys.exit( 2 )
quiet  = os.environ[ "QUIET" ] == "1"
newest = {}
for r in runs:                                   # gh lists newest first
    if r[ "headBranch" ] != os.environ[ "BRANCH" ]: continue
    if r[ "status" ] != "completed": continue    # in progress or queued: not a verdict yet
    newest.setdefault( r[ "name" ], r )
red = [ r for r in newest.values() if r[ "conclusion" ] in ( "failure", "cancelled", "timed_out", "startup_failure" ) ]
if red or not quiet:
    for name, r in sorted( newest.items() ):
        state = r[ "conclusion" ] or r[ "status" ]
        flag  = "RED " if r in red else "ok  "
        branch = r[ "headBranch" ]
        day    = r[ "createdAt" ][:10]
        rid    = r[ "databaseId" ]
        print( f"{flag}{name:<16} {state:<10} {branch:<28} {day} run {rid}" )
if red: print( f"CI is RED: {len( red )} workflow(s). Inspect: gh run view <run> --log-failed" )
sys.exit( 1 if red else 0 )
'
