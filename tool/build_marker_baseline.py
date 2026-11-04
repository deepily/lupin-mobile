#!/usr/bin/env python3
"""
Capture the doc-marker baseline: findings of the vendored Dart doc linter per directory and rule.

Run from the repo root: python3 tool/build_marker_baseline.py [--write]
Without --write it prints the totals; with --write it replaces tool/data/doc_marker_baseline.json.
The shape follows doc_coverage_baseline.json, plus by_rule and a files_with_findings count.
"""

import io
import json
import os
import subprocess
import sys

TOOL = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, TOOL )

from doc_lint.dartdoc_lint import main as lint_main

ROOT     = os.path.dirname( TOOL )
BASELINE = os.path.join( TOOL, "data", "doc_marker_baseline.json" )


def bucket( path ):
    """
    Return ( top, feature_or_None ) for a repo-relative Dart path.

    Requires:
        - path is a posix path such as lib/features/queue/a.dart or test/unit/a_test.dart

    Ensures:
        - top is the first directory under lib/, "(lib root)" for a file directly in lib/,
          "test" for anything under test/, and "(other)" for the rest
        - feature is "features/<name>" for files under lib/features/<name>/, otherwise None

    Raises:
        - nothing
    """
    parts = path.split( "/" )
    if parts[ 0 ] == "test": return "test", None
    if parts[ 0 ] != "lib": return "(other)", None
    rel  = parts[ 1 : ]
    top  = rel[ 0 ] if len( rel ) > 1 else "(lib root)"
    feat = f"features/{rel[ 1 ]}" if top == "features" and len( rel ) > 2 else None
    return top, feat


def measure():
    """
    Lint every tracked Dart file and tally the findings.

    Requires:
        - the working directory tree at ROOT is a git checkout

    Ensures:
        - returns { total, files_with_findings, by_top, by_feature, by_rule }, keys sorted

    Raises:
        - ValueError when the linter's JSON cannot be parsed
    """
    out = io.StringIO()
    lint_main( [ "--json", "--repo-root", ROOT ], out )
    found = json.loads( out.getvalue() )
    tops, feats, rules = {}, {}, {}
    for f in found:
        top, feat = bucket( f[ "path" ] )
        tops[ top ]       = tops.get( top, 0 ) + 1
        rules[ f[ "rule" ] ] = rules.get( f[ "rule" ], 0 ) + 1
        if feat: feats[ feat ] = feats.get( feat, 0 ) + 1
    return {
        "total"               : len( found ),
        "files_with_findings" : len( { f[ "path" ] for f in found } ),
        "by_top"              : dict( sorted( tops.items() ) ),
        "by_feature"          : dict( sorted( feats.items() ) ),
        "by_rule"             : dict( sorted( rules.items(), key=lambda kv: -kv[ 1 ] ) ),
    }


def main( argv ):
    """
    Print the totals, or write the baseline file with --write.

    Requires:
        - argv is the argument list after the program name

    Ensures:
        - returns 0

    Raises:
        - RuntimeError when git cannot name the current sha
    """
    res = subprocess.run( [ "git", "-C", ROOT, "rev-parse", "--short", "HEAD" ], capture_output=True, text=True )
    if res.returncode != 0: raise RuntimeError( f"git rev-parse failed: {res.stderr.strip()}" )
    now = measure()
    if "--write" in argv:
        with open( BASELINE, "w" ) as handle: json.dump( { "_captured_at_sha": res.stdout.strip(), "tool": "doc_lint (lupin f4637ecee)", **now }, handle, indent=2 )
        print( f"WROTE {BASELINE}" )
    print( json.dumps( now, indent=2 ) )
    return 0


if __name__ == "__main__":
    sys.exit( main( sys.argv[ 1: ] ) )
