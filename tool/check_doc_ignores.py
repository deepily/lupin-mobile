#!/usr/bin/env python3
"""public_member_api_docs ignore gate — no file-wide ignores, no ignore without a reason.

  python3 tool/check_doc_ignores.py                 # every .dart file under lib/
  python3 tool/check_doc_ignores.py lib/features    # one directory or file
  python3 tool/check_doc_ignores.py --root DIR      # resolve lib/ under DIR instead of the repo

Rules (src/docs/docstring-standard.md, "Ignores"; decision D8):
  - `// ignore_for_file: public_member_api_docs` is never allowed.
  - `// ignore: public_member_api_docs` needs a reason on the same line, after " - ":
        // ignore: public_member_api_docs - generated override, see x.dart
    A reason names a fact, so "TODO", "obvious" and "later" are refused.

Prints each violation as `path:line: message`, then the allowed ignores per directory.

Exit 0 = no violations · 1 = at least one violation · 2 = nothing to scan (bad path or no .dart files).
"""
import argparse, os, re, sys

RULE      = "public_member_api_docs"
FOR_FILE  = re.compile( r"(?<!/)//(?!/)\s*ignore_for_file:\s*(?P<body>.*)$" )
FOR_LINE  = re.compile( r"(?<!/)//(?!/)\s*ignore:\s*(?P<body>.*)$" )
SEPARATOR = re.compile( r"\s+--?\s+" )
WEAK      = { "todo", "fixme", "tbd", "wip", "obvious", "later", "because", "temporary", "n/a", "na" }

ROOT = os.path.dirname( os.path.dirname( os.path.abspath( __file__ ) ) )


def names_rule( rule_list ):
    """
    Say whether a comma-separated lint list names the rule this gate guards.

    Requires:
        - rule_list is a string such as "public_member_api_docs, unused_element"

    Ensures:
        - returns True only for an exact rule-name match, not a substring
    """
    return RULE in [ r.strip() for r in rule_list.split( "," ) ]


def reason_problem( reason ):
    """
    Judge the reason text that follows an ignore.

    Requires:
        - reason is a string, possibly empty

    Ensures:
        - returns None when the reason is acceptable
        - returns a short message when it is empty or only a placeholder word
    """
    words = [ w.strip( ".,;:!?()\"'`" ).lower() for w in reason.split() ]
    words = [ w for w in words if w ]
    if not words: return "ignore has no reason on the same line"
    if all( w in WEAK for w in words ): return f"reason '{reason.strip()}' names no fact"
    return None


def scan_file( path ):
    """
    Find every ignore of the guarded rule in one file.

    Requires:
        - path is a readable UTF-8 text file

    Ensures:
        - returns ( violations, allowed ) as lists of ( line_number, message ) and line numbers
        - an ignore_for_file that names the rule is always a violation, reason or not
        - an `ignore:` that names the rule is allowed only with an acceptable same-line reason
    """
    violations, allowed = [], []
    with open( path, encoding="utf-8" ) as f:
        for number, line in enumerate( f, start=1 ):
            m = FOR_FILE.search( line )
            if m and names_rule( SEPARATOR.split( m.group( "body" ), maxsplit=1 )[ 0 ] ):
                violations.append( ( number, f"ignore_for_file: {RULE} is never allowed" ) )
                continue
            m = FOR_LINE.search( line )
            if not m: continue
            parts = SEPARATOR.split( m.group( "body" ), maxsplit=1 )
            if not names_rule( parts[ 0 ] ): continue
            problem = reason_problem( parts[ 1 ] if len( parts ) > 1 else "" )
            if problem: violations.append( ( number, problem ) )
            else:       allowed.append( number )
    return violations, allowed


def dart_files( targets ):
    """
    List the .dart files under the given files and directories.

    Requires:
        - targets is a list of existing paths

    Ensures:
        - returns a sorted list of .dart file paths, skipping hidden directories
    """
    found = []
    for target in targets:
        if os.path.isfile( target ):
            if target.endswith( ".dart" ): found.append( target )
            continue
        for folder, subdirs, names in os.walk( target ):
            subdirs[ : ] = [ d for d in subdirs if not d.startswith( "." ) ]
            found.extend( os.path.join( folder, n ) for n in names if n.endswith( ".dart" ) )
    return sorted( found )


def main( argv=None ):
    """
    Run the gate and return its exit code.

    Requires:
        - argv is a list of command-line arguments, or None to read sys.argv

    Ensures:
        - returns 0, 1 or 2 as documented at the top of this file
        - prints violations first, then the allowed ignores per directory
    """
    ap = argparse.ArgumentParser( description=__doc__.split( "\n" )[ 0 ] )
    ap.add_argument( "paths", nargs="*", help="files or directories; default is lib/" )
    ap.add_argument( "--root", default=ROOT, help="directory that holds lib/ and relative paths" )
    args    = ap.parse_args( argv )
    root    = os.path.abspath( args.root )
    targets = [ os.path.join( root, p ) for p in args.paths ] or [ os.path.join( root, "lib" ) ]

    missing = [ t for t in targets if not os.path.exists( t ) ]
    if missing:
        print( f"INPUT BAD — no such path: {', '.join( missing )}" ); return 2
    files = dart_files( targets )
    if not files:
        print( "INPUT BAD — no .dart files under the given paths" ); return 2

    bad, per_dir = 0, {}
    for path in files:
        violations, allowed = scan_file( path )
        rel = os.path.relpath( path, root )
        for number, message in violations:
            print( f"{rel}:{number}: {message}" ); bad += 1
        if allowed:
            folder = os.path.dirname( rel ) or "."
            per_dir[ folder ] = per_dir.get( folder, 0 ) + len( allowed )

    print( f"Allowed {RULE} ignores per directory:" )
    if not per_dir: print( "  (none)" )
    for folder in sorted( per_dir ): print( f"  {per_dir[ folder ]:4d}  {folder}" )

    if bad:
        print( f"FAIL — {bad} violation(s) in {len( files )} file(s)." ); return 1
    print( f"PASS — {len( files )} file(s), {sum( per_dir.values() )} allowed ignore(s)." ); return 0


if __name__ == "__main__":
    sys.exit( main() )
