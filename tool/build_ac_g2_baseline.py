#!/usr/bin/env python3
"""AC-G2 baseline builder — the SET of passing test ids, not a count.

Why a set: a rising count cannot detect a deletion masked by additions, and the
gate the whole build rests on could be passed by deleting the tests that were
failing (Chloé + Tiffany, 2026-08-29).

Reads `flutter test --reporter json` on stdin-path, writes the fixture.
Ids are "<repo-relative suite path>::<full test name>" so a rename reads as one
removal plus one addition rather than silently as nothing.
"""
import json, subprocess, sys, os, collections

src, out = sys.argv[1], sys.argv[2]
suites, tests, ok, failed = {}, {}, set(), set()

for line in open( src ):
    line = line.strip()
    if not line.startswith( "{" ): continue
    try: e = json.loads( line )
    except json.JSONDecodeError: continue
    t = e.get( "type" )
    if t == "suite":  suites[ e["suite"]["id"] ] = e["suite"]["path"]
    elif t == "testStart":
        n = e["test"]
        if n.get( "name", "" ).startswith( "loading " ): continue
        tests[ n["id"] ] = ( n.get( "suiteID" ), n.get( "name" ) )
    elif t == "testDone":
        if e.get( "hidden" ): continue
        # A SKIPPED test reports result "success" with skipped:true. Counting it
        # put this fixture ONE ahead of the runner's own summary (753 vs +752,
        # 2026-08-29) — a baseline whose count disagrees with the runner is the
        # shape that has bitten this build repeatedly. Skips are not passes.
        if e.get( "skipped" ): continue
        ( ok if e.get( "result" ) == "success" else failed ).add( e[ "testID" ] )

root = os.path.abspath( "." )
def rel( p ): return os.path.relpath( p, root ) if p else "?"

def ids( s ):
    return sorted( f"{rel( suites.get( tests[i][0] ) )}::{tests[i][1]}" for i in s if i in tests )

passing = ids( ok )
# Which suites are NOT under version control — a baseline that pins an untracked
# test is pinning something no other checkout has.
paths    = sorted( { p.split( "::" )[0] for p in passing } )
untracked = set()
if paths:
    r = subprocess.run( [ "git", "ls-files", "--error-unmatch", "--" ] + paths,
                        capture_output=True, text=True )
    tracked = set( r.stdout.split() )
    untracked = { p for p in paths if p not in tracked }

# The sha is HEAD *at build time*, not necessarily the tree the capture ran on.
# Measured 2026-08-29: a build minutes after its capture stamped a sha two commits
# ahead and the fixture then claimed a tree it had never measured. Pass the sha
# explicitly as argv[3] when capture and build are not back-to-back.
sha = sys.argv[ 3 ] if len( sys.argv ) > 3 else subprocess.run(
    [ "git", "rev-parse", "--short", "HEAD" ], capture_output=True, text=True ).stdout.strip()

json.dump( {
    "_ac"        : "AC-G2 — no previously-passing test id may disappear.",
    "_why_a_set" : "A rising COUNT cannot detect a deletion masked by additions; "
                   "the old predicate could be satisfied by deleting the failing tests.",
    "_captured_at_sha" : sha,
    "_sha_caveat" : (
        "HEAD at BUILD time unless passed explicitly as argv[3]. Run the capture and "
        "this builder back-to-back, or pass the sha — a build minutes after its capture "
        "will stamp a tree it never measured."
    ),
    "_how_to_refresh"  : "./flutter.sh test --reporter json > /tmp/t.json && "
                         "python3 build_ac_g2_baseline.py /tmp/t.json "
                         "test/fixtures/ac_g2_passing_baseline.json",
    "_untracked_suites_at_capture" : sorted( untracked ),
    "_untracked_warning" : "Ids from these suites are NOT in any commit — another "
                           "checkout cannot reproduce them. Re-capture once they land.",
    "_count_reconciliation" : (
        "Matches the runner's own summary line. Three numbers exist for one tree and "
        "they are NOT interchangeable: ALL testDone successes = 916 (includes 163 "
        "hidden group/suite-level events); non-hidden = 753; non-hidden AND non-skipped "
        "= 752, which is what `flutter test` prints and what this fixture stores. "
        "A skipped test reports result 'success' with skipped:true."
    ),
    "passing_count" : len( passing ),
    "failing_count" : len( failed ),
    "passing"       : passing,
}, open( out, "w" ), indent=2 )
print( f"sha={sha} passing={len(passing)} failing={len(failed)} untracked_suites={len(untracked)}" )
