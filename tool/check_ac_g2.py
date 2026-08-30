#!/usr/bin/env python3
"""AC-G2 gate — no previously-passing test id may disappear.

  ./flutter.sh test --reporter json > /tmp/now.json
  python3 tool/check_ac_g2.py /tmp/now.json

Exit 0 = PASS · 1 = REGRESSION · 2 = BASELINE INCOMPLETE.

🔴 WHY EXIT 2 EXISTS, AND WHY IT IS NOT A WARNING.
A baseline captured while some suites were untracked pins ids no other checkout
has: the gate would fail elsewhere on tests that never existed there, or pass
here on tests nobody else runs. Annotating that in the file is not enough — a
check that stays green while the thing it checks is untrue is exactly the shape
of the four control defects found on 2026-08-29 (a pointer counted as a
discharge; a duplicate definition counted as a discharge; a rising count counted
as no-regression; a stale id list reporting clean). Every one was informative
and non-blocking, and that is precisely why each survived.

So a non-empty `_untracked_suites_at_capture` is NOT a clean pass. Green requires
an empty list, and the only way to get one is to re-capture after the suites land:

  python3 tool/build_ac_g2_baseline.py /tmp/now.json test/fixtures/ac_g2_passing_baseline.json
"""
import json, sys, os

BASE = "test/fixtures/ac_g2_passing_baseline.json"
if not os.path.exists( BASE ):
    print( f"BASELINE MISSING — {BASE} does not exist. Capture it first." ); sys.exit( 2 )

base = json.load( open( BASE ) )
src  = sys.argv[ 1 ] if len( sys.argv ) > 1 else None
if not src:
    print( __doc__ ); sys.exit( 2 )

suites, tests, ok = {}, {}, set()
for line in open( src ):
    line = line.strip()
    if not line.startswith( "{" ): continue
    try: e = json.loads( line )
    except json.JSONDecodeError: continue
    t = e.get( "type" )
    if   t == "suite":     suites[ e["suite"]["id"] ] = e["suite"]["path"]
    elif t == "testStart":
        n = e[ "test" ]
        if n.get( "name", "" ).startswith( "loading " ): continue
        tests[ n["id"] ] = ( n.get( "suiteID" ), n.get( "name" ) )
    elif t == "testDone" and not e.get( "hidden" ) and e.get( "result" ) == "success":
        ok.add( e[ "testID" ] )

root = os.path.abspath( "." )
now  = { f"{os.path.relpath( suites.get( tests[i][0] ), root )}::{tests[i][1]}"
         for i in ok if i in tests and suites.get( tests[i][0] ) }

missing = sorted( set( base[ "passing" ] ) - now )

# REGRESSION is reported before INCOMPLETE: a real disappearance is the more
# serious answer, and an incomplete baseline must never mask one.
if missing:
    print( f"REGRESSION — {len( missing )} previously-passing test id(s) MISSING "
           f"(baseline sha {base[ '_captured_at_sha' ]}):" )
    for m in missing[ :40 ]: print( f"  - {m}" )
    if len( missing ) > 40: print( f"  … and {len( missing ) - 40} more" )
    sys.exit( 1 )

untracked = base.get( "_untracked_suites_at_capture", [] )
if untracked:
    print( f"BASELINE INCOMPLETE — captured at {base[ '_captured_at_sha' ]} while "
           f"{len( untracked )} suite(s) were UNTRACKED. This is NOT a clean pass." )
    for u in untracked: print( f"  - {u}" )
    print( "Re-capture once they are committed:\n"
           "  python3 tool/build_ac_g2_baseline.py <json> " + BASE )
    sys.exit( 2 )

print( f"PASS — all {len( base[ 'passing' ] )} baseline ids still passing "
       f"(baseline sha {base[ '_captured_at_sha' ]})." )
sys.exit( 0 )
