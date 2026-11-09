#!/bin/bash
# Report the newest GitHub Actions run of each workflow; exit 1 if any is red.
#
# Why: CI sat red from 30 Sep to 9 Nov with nobody reading it (row 23c5580e).
# Run it at session start, or from cron:
#   17 */4 * * * /path/to/src/scripts/ci-status-check.sh --quiet >> ~/.lupin/logs/ci-status.log 2>&1
#
# Requires: gh (logged in), python3. Read-only: it never reruns or edits a run.
# Usage: ci-status-check.sh [--quiet] [--limit N]
#   --quiet   print only when something is red (cron-friendly)
#   --limit N how many recent runs to look at (default 30)
# Exit: 0 all newest runs green, 1 at least one red, 2 gh unavailable or failed.

set -u

QUIET=0
LIMIT=30
while [ $# -gt 0 ]; do
    case "$1" in
        --quiet) QUIET=1 ;;
        --limit) shift; LIMIT="$1" ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

RAW=$( gh run list --limit "$LIMIT" --json name,conclusion,status,headBranch,databaseId,createdAt 2>&1 ) || {
    echo "CI status: gh failed: $RAW" >&2
    exit 2
}

echo "$RAW" | QUIET=$QUIET python3 -I -c '
import json, os, sys
runs   = json.load( sys.stdin )
quiet  = os.environ[ "QUIET" ] == "1"
newest = {}
for r in runs:                                   # gh lists newest first
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
