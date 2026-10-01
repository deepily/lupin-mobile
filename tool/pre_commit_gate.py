#!/usr/bin/env python3
"""Blocking pre-commit gate for the documentation standard.

  python3 tool/pre_commit_gate.py            # gate the staged changes (what the hook runs)
  python3 tool/pre_commit_gate.py --list     # print the swept directories and stop

Runs three checks and blocks the commit when any one fails:
  1. tool/lint_dart_docs.py --staged --strict   (Dart doc linter, staged lines only)
  2. tool/check_doc_ignores.py                  (ignore gate, whole of lib/)
  3. flutter analyze --fatal-infos <dir>        (one run per swept directory the commit touches)

A swept directory is a lib/ directory that holds its own analysis_options.yaml. Set FLUTTER to
use another flutter binary; the default is `flutter` on PATH, then ./flutter.sh.
Bypass with `git commit --no-verify`; the CI step in .github/workflows/flutter-ci.yml catches that.

Exit 0 = every check passed · 1 = at least one check failed.
"""
import argparse, os, shutil, subprocess, sys

ROOT    = os.path.dirname( os.path.dirname( os.path.abspath( __file__ ) ) )
OPTIONS = "analysis_options.yaml"


def swept_dirs( root=ROOT ):
    """
    List the swept directories: every directory under lib/ with its own analysis_options.yaml.

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


def flutter_cmd( root=ROOT ):
    """
    Choose the flutter binary the analyze check uses.

    Ensures:
        - returns $FLUTTER when set, else `flutter` on PATH, else the repo's flutter.sh wrapper
    """
    if os.environ.get( "FLUTTER" ): return os.environ["FLUTTER"]
    return "flutter" if shutil.which( "flutter" ) else os.path.join( root, "flutter.sh" )


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
    ap.add_argument( "--list", action="store_true", help="print the swept directories and stop" )
    args = ap.parse_args( argv )
    swept = swept_dirs( root )
    if args.list:
        print( "\n".join( swept ) )
        return 0
    staged  = staged_paths( root )
    results = [
        run_check( "doc linter (staged lines)",
                   [ sys.executable, "tool/lint_dart_docs.py", "--staged", "--strict" ], root ),
        run_check( "ignore checker",
                   [ sys.executable, "tool/check_doc_ignores.py" ], root ),
    ]
    for d in touched_dirs( staged, swept ):
        results.append( run_check( f"analyze --fatal-infos {d}",
                                   [ flutter_cmd( root ), "analyze", "--fatal-infos", d ], root ) )
    if all( results ): return 0
    print( "\nBLOCKED: fix the failures above, or bypass once with `git commit --no-verify` (CI still checks).",
           file=sys.stderr )
    return 1


if __name__ == "__main__":
    sys.exit( main() )
