#!/usr/bin/env python3
"""Known-failures gate — "no NEW failing test", from parsed `flutter test` JSON.

  ./flutter.sh test --reporter json > /tmp/now.json
  python3 tool/check_test_failures.py /tmp/now.json              # first look
  python3 tool/check_test_failures.py /tmp/now.json /tmp/again.json   # after re-running once

  python3 tool/check_test_failures.py --build run1.json run2.json run3.json   # (re)capture baseline

Exit 0 NO_NEW_FAILURE · 1 NEW_FAILURE (confirmed by the re-run) · 2 BASELINE_OR_INPUT_BAD ·
     3 RERUN_REQUIRED (a failure outside the known set was seen once; re-run before it counts).

The baseline (tool/data/test_failures_baseline.json) splits failures seen across N serial
full runs at one sha into ALWAYS_FAIL (failed in every run) and SOMETIMES_FAIL (failed in
some). A failing id in either set is known; anything else is new. A new failure must fail in
BOTH the first run and the re-run to count (exit 1) — a one-off is exit 3 -> re-run, not blame.

Like tool/check_ac_g2.py this reads the testDone event stream, never `flutter test`'s own exit
code (non-zero whenever anything failed). Ids are `<path relative to repo root>::<test name>`.
A suite that fails to load is a failure too, id `<path>::(loading)`.
"""
import json, os, subprocess, sys

ROOT     = os.path.dirname( os.path.dirname( os.path.abspath( __file__ ) ) )
BASELINE = os.path.join( ROOT, "tool", "data", "test_failures_baseline.json" )

NO_NEW_FAILURE, NEW_FAILURE, BASELINE_OR_INPUT_BAD, RERUN_REQUIRED = 0, 1, 2, 3


def read_run( path ):
    """
    Parse one `flutter test --reporter json` file.

    Requires:
        - path is a JSON-lines file from `flutter test --reporter json`

    Ensures:
        - returns ( failed_ids, passed_count ); skipped tests are neither
        - raises ValueError if the file holds no testDone events (a crashed run proves nothing)
    """
    suites, tests, failed, passed, done = {}, {}, set(), 0, 0
    for line in open( path ):
        line = line.strip()
        if not line.startswith( "{" ): continue
        try: e = json.loads( line )
        except json.JSONDecodeError: continue
        t = e.get( "type" )
        if   t == "suite":     suites[ e[ "suite" ][ "id" ] ] = e[ "suite" ][ "path" ]
        elif t == "testStart": tests[ e[ "test" ][ "id" ] ] = ( e[ "test" ].get( "suiteID" ), e[ "test" ].get( "name" ) )
        elif t == "testDone":
            done += 1
            if e.get( "skipped" ): continue
            suite_id, name = tests.get( e[ "testID" ], ( None, None ) )
            sp = suites.get( suite_id )
            rel = os.path.relpath( sp, ROOT ) if sp else "(unknown suite)"
            if e.get( "result" ) in ( "failure", "error" ):
                failed.add( f"{rel}::{name}".replace( "::loading " + str( sp ), "::(loading)" ) if name and name.startswith( "loading " ) else f"{rel}::{name}" )
            elif not e.get( "hidden" ): passed += 1
    if done == 0: raise ValueError( f"{path}: no testDone events — the run crashed or is not JSON" )
    return failed, passed


def sha():
    return subprocess.run( [ "git", "rev-parse", "--short", "HEAD" ], cwd=ROOT, capture_output=True, text=True ).stdout.strip()


def build( paths ):
    runs   = [ read_run( p ) for p in paths ]
    sets   = [ r[ 0 ] for r in runs ]
    always = set.intersection( *sets )
    some   = set.union( *sets ) - always
    data   = { "_captured_at_sha": sha(), "runs": len( runs ), "passed_per_run": [ r[ 1 ] for r in runs ],
               "failed_per_run": [ len( s ) for s in sets ],
               "always_fail": sorted( always ), "sometimes_fail": sorted( some ) }
    os.makedirs( os.path.dirname( BASELINE ), exist_ok=True )
    json.dump( data, open( BASELINE, "w" ), indent=2 )
    print( f"WROTE {BASELINE} — always {len( always )}, sometimes {len( some )}, runs {len( runs )} at {data[ '_captured_at_sha' ]}" )
    return NO_NEW_FAILURE


def check( now_path, again_path=None ):
    if not os.path.exists( BASELINE ): print( f"BASELINE_OR_INPUT_BAD — {BASELINE} missing; run --build" ); return BASELINE_OR_INPUT_BAD
    base  = json.load( open( BASELINE ) )
    known = set( base[ "always_fail" ] ) | set( base[ "sometimes_fail" ] )
    try:
        now = read_run( now_path )[ 0 ]
        new = now - known
        if new and again_path: new = new & read_run( again_path )[ 0 ]
    except ( ValueError, OSError ) as ex:
        print( f"BASELINE_OR_INPUT_BAD — {ex}" ); return BASELINE_OR_INPUT_BAD
    if new and not again_path:
        print( f"RERUN_REQUIRED — {len( new )} failure(s) outside the known set (baseline {base[ '_captured_at_sha' ]}); re-run once and pass both files:" )
        for n in sorted( new )[ :40 ]: print( f"  - {n}" )
        return RERUN_REQUIRED
    if new:
        print( f"NEW_FAILURE — {len( new )} failure(s) outside the known set, confirmed by the re-run:" )
        for n in sorted( new )[ :40 ]: print( f"  - {n}" )
        return NEW_FAILURE
    gone = set( base[ "always_fail" ] ) - now
    print( f"NO_NEW_FAILURE — {len( now )} failing, all known (always {len( base[ 'always_fail' ] )}, sometimes {len( base[ 'sometimes_fail' ] )})."
           + ( f" {len( gone )} always-fail test(s) now pass: refresh the baseline." if gone else "" ) )
    return NO_NEW_FAILURE


if __name__ == "__main__":
    a = sys.argv[ 1: ]
    if not a: print( __doc__ ); sys.exit( BASELINE_OR_INPUT_BAD )
    sys.exit( build( a[ 1: ] ) if a[ 0 ] == "--build" else check( a[ 0 ], a[ 1 ] if len( a ) > 1 else None ) )
