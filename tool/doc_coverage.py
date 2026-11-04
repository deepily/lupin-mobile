#!/usr/bin/env python3
"""Doc-coverage baseline — public_member_api_docs hits per lib/ directory.

  python3 tool/doc_coverage.py                    # analyze lib/ in a scratch copy, compare to baseline
  python3 tool/doc_coverage.py --machine m.txt    # compare a pre-captured `dart analyze --format=machine`
  python3 tool/doc_coverage.py --write            # (re)capture tool/data/doc_coverage_baseline.json

Exit 0 = NOT ABOVE BASELINE · 1 = A BUCKET GREW · 2 = BASELINE MISSING / ANALYZER FAILED.

The root analysis_options.yaml is NOT touched. The rule is switched on in a scratch
copy of lib/ + pubspec (so no config file is ever left in the real tree), and hits are
bucketed from the analyzer's own machine-format output, never from a hand-written
member counter.

The baseline is a frozen measurement at the sha it records (cf5be6f). It still lists
features/voice: 96, a directory deleted since (222e9a0). That is left as is: compare() only
reads buckets present in the current run, so a stale bucket can never fail the check, and
regenerating would erase the measurement it exists to preserve. Buckets: each top-level lib/ dir (core, services, shared, ui, ...),
plus one per features/<name>.
"""
import json, os, re, shutil, subprocess, sys, tempfile

ROOT     = os.path.dirname( os.path.dirname( os.path.abspath( __file__ ) ) )
BASELINE = os.path.join( ROOT, "tool", "data", "doc_coverage_baseline.json" )
RULE     = "PUBLIC_MEMBER_API_DOCS"
OPTIONS  = "include: package:flutter_lints/flutter.yaml\nlinter:\n  rules:\n    public_member_api_docs: true\n"


def parse_machine( text ):
    """
    Parse `dart analyze --format=machine` output into hit paths for RULE.

    Requires:
        - text is the full machine-format output (SEVERITY|TYPE|CODE|FILE|LINE|COL|LEN|MSG)

    Ensures:
        - returns a list of file paths (as printed by the analyzer), one per hit
        - pipes escaped as \\| inside fields do not shift columns
    """
    hits = []
    for line in text.splitlines():
        f = re.split( r"(?<!\\)\|", line )
        if len( f ) >= 8 and f[ 2 ] == RULE: hits.append( f[ 3 ].replace( "\\|", "|" ) )
    return hits


def bucket( path ):
    """Return ( top, feature_or_None ) for a path containing a lib/ segment."""
    path  = path.replace( "\\", "/" )
    path  = path[ 4: ] if path.startswith( "lib/" ) else path.split( "/lib/", 1 )[ -1 ]
    rel   = path.split( "/" )
    top   = rel[ 0 ] if len( rel ) > 1 else "(lib root)"
    feat  = f"features/{rel[ 1 ]}" if top == "features" and len( rel ) > 2 else None
    return top, feat


def tally( hits ):
    tops, feats = {}, {}
    for h in hits:
        top, feat = bucket( h )
        tops[ top ] = tops.get( top, 0 ) + 1
        if feat: feats[ feat ] = feats.get( feat, 0 ) + 1
    return { "total": len( hits ), "by_top": dict( sorted( tops.items() ) ), "by_feature": dict( sorted( feats.items() ) ) }


def run_analyzer():
    """Analyze lib/ in a scratch copy with the rule on; return machine output or None."""
    flutter = os.path.join( ROOT, "flutter", "bin", "flutter" )
    dart    = os.path.join( ROOT, "flutter", "bin", "dart" )
    if not os.path.exists( flutter ): print( f"ANALYZER UNAVAILABLE — {flutter} missing" ); return None
    with tempfile.TemporaryDirectory() as d:
        shutil.copytree( os.path.join( ROOT, "lib" ), os.path.join( d, "lib" ) )
        for f in ( "pubspec.yaml", "pubspec.lock" ): shutil.copy( os.path.join( ROOT, f ), d )
        open( os.path.join( d, "analysis_options.yaml" ), "w" ).write( OPTIONS )
        if subprocess.run( [ flutter, "pub", "get" ], cwd=d, capture_output=True ).returncode != 0:
            print( "ANALYZER UNAVAILABLE — pub get failed in scratch copy" ); return None
        r = subprocess.run( [ dart, "analyze", "--format=machine", "lib" ], cwd=d, capture_output=True, text=True )
        return r.stdout.replace( d + "/", "" )   # non-zero exit just means infos exist; the output is the verdict


def sha():
    return subprocess.run( [ "git", "rev-parse", "--short", "HEAD" ], cwd=ROOT, capture_output=True, text=True ).stdout.strip()


def compare( now, base ):
    """Return list of 'bucket: base -> now' strings for every bucket that grew."""
    grew = []
    if now[ "total" ] > base[ "total" ]: grew.append( f"total: {base[ 'total' ]} -> {now[ 'total' ]}" )
    for key in ( "by_top", "by_feature" ):
        for k, v in now[ key ].items():
            if v > base[ key ].get( k, 0 ): grew.append( f"{k}: {base[ key ].get( k, 0 )} -> {v}" )
    return grew


def main( argv ):
    write = "--write" in argv
    mach  = argv[ argv.index( "--machine" ) + 1 ] if "--machine" in argv else None
    text  = open( mach ).read() if mach else run_analyzer()
    if text is None: return 2
    now = tally( parse_machine( text ) )
    if now[ "total" ] == 0 and "|" not in text: print( "ANALYZER OUTPUT EMPTY OR UNPARSEABLE" ); return 2
    if write:
        os.makedirs( os.path.dirname( BASELINE ), exist_ok=True )
        json.dump( { "_captured_at_sha": sha(), "rule": "public_member_api_docs", **now }, open( BASELINE, "w" ), indent=2 )
        print( f"WROTE {BASELINE} — total {now[ 'total' ]} at {sha()}" ); return 0
    if not os.path.exists( BASELINE ): print( f"BASELINE MISSING — {BASELINE}. Run with --write." ); return 2
    base = json.load( open( BASELINE ) )
    grew = compare( now, base )
    if grew:
        print( f"GREW — {len( grew )} bucket(s) above baseline {base[ '_captured_at_sha' ]}:" )
        for g in grew: print( f"  - {g}" )
        return 1
    print( f"OK — total {now[ 'total' ]} (baseline {base[ 'total' ]} at {base[ '_captured_at_sha' ]}); no bucket grew." )
    return 0


if __name__ == "__main__":
    sys.exit( main( sys.argv[ 1: ] ) )
