#!/usr/bin/env python3
"""Blocking pre-commit gate for the documentation standard.

  python3 tool/pre_commit_gate.py            # gate the staged changes (what the hook runs)
  python3 tool/pre_commit_gate.py --list     # print the swept directories and stop
  python3 tool/pre_commit_gate.py --docs-all # check 3 alone, over every gated directory (what CI runs)

Runs three checks and blocks the commit when any one fails:
  1. tool/lint_dart_docs.py --staged --strict   (Dart doc linter, staged lines only)
  2. tool/check_doc_ignores.py                  (ignore gate, whole of lib/)
  3. dart analyze --format=machine <dirs>       (the gated directories the commit touches; fails
                                                 ONLY on public_member_api_docs, every other finding
                                                 is ignored, errors included)

The gated directories are listed in tool/data/gated_dirs.txt: every swept directory. Other analyzer
findings are a separate clean-up (Rick, 2026-10-02: "Docs now, code clean-up later"). Set DART to
use another dart binary; the default is `dart` on PATH, then flutter/bin/dart in the repo.
Bypass with `git commit --no-verify`; the CI step in .github/workflows/flutter-ci.yml catches that.

Exit 0 = every check passed · 1 = at least one check failed.
"""
import argparse, os, re, shutil, subprocess, sys

ROOT    = os.path.dirname( os.path.dirname( os.path.abspath( __file__ ) ) )
OPTIONS    = "analysis_options.yaml"
GATED_LIST = "tool/data/gated_dirs.txt"
LEFT_OUT   = re.compile( r"#\s*left out:\s*(\S+)\s+(\d+)\b" )
DOC_CODE   = "PUBLIC_MEMBER_API_DOCS"
# One machine line: SEVERITY|TYPE|CODE|file|line|col|length|message, with a literal | escaped as \|
PIPE       = re.compile( r"(?<!\\)\|" )


def all_swept_dirs( root=ROOT ):
    """
    List every swept directory: each directory under lib/ with its own analysis_options.yaml.

    Requires:
        - root is a directory that holds lib/

    Ensures:
        - returns sorted repo-relative paths such as "lib/features/auth"
        - returns an empty list when lib/ has no options file below it
    """
    found = []
    for here, _dirs, files in os.walk( os.path.join( root, "lib" ) ):
        if OPTIONS in files and here != os.path.join( root, "lib" ):
            found.append( os.path.relpath( here, root ) )
    return sorted( found )


def swept_dirs( root=ROOT ):
    """
    List the gated directories: the ones in tool/data/gated_dirs.txt, which pass analyze today.

    Requires:
        - root holds tool/data/gated_dirs.txt, one path per line, `#` starts a comment

    Ensures:
        - returns the listed paths in file order, blank and comment lines skipped
    """
    with open( os.path.join( root, GATED_LIST ), encoding="utf-8" ) as f:
        lines = [ l.strip() for l in f ]
    return [ l for l in lines if l and not l.startswith( "#" ) ]


def left_out_dirs( root=ROOT ):
    """
    Read the `# left out: <dir> <count>` comments next to the gated list.

    Requires:
        - root holds tool/data/gated_dirs.txt

    Ensures:
        - returns { directory: issue count } for every left-out line
    """
    out = {}
    with open( os.path.join( root, GATED_LIST ), encoding="utf-8" ) as f:
        for l in f:
            m = LEFT_OUT.match( l.strip() )
            if m: out[m.group( 1 )] = int( m.group( 2 ) )
    return out


def touched_dirs( staged, swept ):
    """
    Pick the swept directories that at least one staged path sits inside.

    Requires:
        - staged is a list of repo-relative paths
        - swept is a list of repo-relative directory paths

    Ensures:
        - returns the swept directories in their given order, each at most once
        - matches whole path segments, so lib/core does not match lib/core_extra/x.dart
    """
    return [ d for d in swept if any( p.startswith( d + "/" ) for p in staged ) ]


def staged_paths( root=ROOT ):
    """
    List the paths staged for this commit, deletions excluded.

    Requires:
        - root is a git working tree

    Ensures:
        - returns repo-relative paths with forward slashes
    """
    out = subprocess.run( [ "git", "diff", "--cached", "--name-only", "--diff-filter=d" ],
                          cwd=root, capture_output=True, text=True, check=True ).stdout
    return [ l for l in out.splitlines() if l ]


def dart_cmd( root=ROOT ):
    """
    Choose the dart binary the docs check uses.

    Ensures:
        - returns $DART when set, else `dart` on PATH, else the repo's flutter/bin/dart
    """
    if os.environ.get( "DART" ): return os.environ["DART"]
    return "dart" if shutil.which( "dart" ) else os.path.join( root, "flutter", "bin", "dart" )


def missing_doc_findings( machine_output ):
    """
    Pick the missing-doc findings out of `dart analyze --format=machine` output.

    Requires:
        - machine_output is the analyzer's stdout, one finding per line

    Ensures:
        - returns the lines whose diagnostic code is public_member_api_docs, in input order
        - ignores every other finding, errors and warnings included, and any line that is not a finding
    """
    found = []
    for line in machine_output.splitlines():
        fields = PIPE.split( line )
        if len( fields ) >= 8 and fields[2].upper() == DOC_CODE: found.append( line )
    return found


def check_docs( dirs, root=ROOT ):
    """
    Run the analyzer over the directories and fail only on missing doc comments.

    Requires:
        - dirs is a list of repo-relative directories, each with an options file enabling public_member_api_docs

    Ensures:
        - returns True when the analyzer ran and reported no missing doc comment
        - returns False, after printing each missing-doc finding, when it reported one
        - returns False when the analyzer did not run to completion (exit code outside 0 to 3: 1 infos, 2 warnings, 3 errors)
        - returns True without running anything when dirs is empty
    """
    if not dirs: return True
    print( f"== docs only (public_member_api_docs): {' '.join( dirs )}", flush=True )
    proc = subprocess.run( [ dart_cmd( root ), "analyze", "--format=machine", *dirs ],
                           cwd=root, capture_output=True, text=True )
    if proc.returncode not in ( 0, 1, 2, 3 ):
        print( f"analyzer did not finish (exit {proc.returncode}):\n{proc.stdout}{proc.stderr}", file=sys.stderr )
        return False
    bad = missing_doc_findings( proc.stdout )
    for line in bad: print( line )
    if bad: print( f"{len( bad )} missing doc comment(s)", file=sys.stderr )
    return not bad


def run_check( name, cmd, root=ROOT ):
    """
    Run one check, stream its output, and say whether it passed.

    Requires:
        - cmd is an argument list

    Ensures:
        - prints a one-line header naming the check
        - returns True only when the command exits 0
    """
    print( f"== {name}", flush=True )
    return subprocess.run( cmd, cwd=root ).returncode == 0


def main( argv=None, root=ROOT ):
    """
    Run the gate on the staged changes.

    Requires:
        - argv is a list of arguments, or None for sys.argv

    Ensures:
        - returns 0 when every check passes, 1 when any fails
        - runs every check even after one fails, so one commit attempt shows all failures
    """
    ap = argparse.ArgumentParser( description="Blocking pre-commit gate for the documentation standard." )
    ap.add_argument( "--list", action="store_true", help="print the gated directories and stop" )
    ap.add_argument( "--docs-all", action="store_true",
                     help="run check 3 alone over every gated directory, ignoring the staged changes (CI)" )
    args = ap.parse_args( argv )
    swept = swept_dirs( root )
    if args.list:
        print( "\n".join( swept ) )
        return 0
    if args.docs_all: return 0 if check_docs( swept, root ) else 1
    staged  = staged_paths( root )
    results = [
        run_check( "doc linter (staged lines)",
                   [ sys.executable, "tool/lint_dart_docs.py", "--staged", "--strict" ], root ),
        run_check( "ignore checker",
                   [ sys.executable, "tool/check_doc_ignores.py" ], root ),
    ]
    results.append( check_docs( touched_dirs( staged, swept ), root ) )
    if all( results ): return 0
    print( "\nBLOCKED: fix the failures above, or bypass once with `git commit --no-verify` (CI still checks).",
           file=sys.stderr )
    return 1


if __name__ == "__main__":
    sys.exit( main() )
