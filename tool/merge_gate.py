#!/usr/bin/env python3
"""Manager's merge gate — the checks run before a worker's commits are merged, as one tracked script.

  python3 tool/merge_gate.py --base wip-v0.2.2-2026.09.30-tracking-lupin     # HEAD against the merge target
  python3 tool/merge_gate.py A..B                                            # an explicit range ending at HEAD
  python3 tool/merge_gate.py <commit>                                        # one commit: <commit>^..<commit>
  python3 tool/merge_gate.py --base BR --skip-suite                          # quick pass: verdict says QUICK, never PASS
  python3 tool/merge_gate.py --base BR --comments-only                       # also require a comments-only change

Run it in the checkout that holds the commits, with the range ending at HEAD and no uncommitted
changes to tracked files: every check reads the working tree, so a verdict about anything else
would be a verdict about the wrong code.

Checks, each an existing tool run as a subprocess, its output kept in a log directory named at the end:
  1. analyzer   dart analyze --format=machine lib test: no ERROR that the start of the range does not
                also have (compared on file, code and message, never on line or column)
  2. docs gate  tool/pre_commit_gate.py --docs-all
  3. ignores    tool/check_doc_ignores.py
  4. coverage   tool/doc_coverage.py
  5. tool tests python3 -m pytest tool/ -q
  6. suite      ./flutter.sh test --machine, judged by tool/check_test_failures.py (re-runs the suite
                once when that script asks for it)
  7. ac-g2      tool/check_ac_g2.py on the suite's output
  8. comments   (--comments-only) every changed .dart file is identical once comments are stripped

The start of the range is measured WITHOUT touching the checkout: `git archive` exports lib/, test/ and
the pubspec files of that commit into a scratch directory, and the analyzer runs there. No stash, no
worktree, no checkout. Files that are gitignored and absent from the export (a missing google-services
style file) can only add errors to the start, which makes the comparison more lenient, never stricter.

Output: one verdict line (PASS, FAIL or QUICK), one line per check with its exit code, the log directory.
Exit 0 = PASS · 1 = FAIL · 2 = could not run (bad range, dirty tree) · 3 = QUICK (clean, but the suite was skipped).
"""
import argparse, collections, json, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, HERE )
import pre_commit_gate as pcg

ROOT = os.path.dirname( HERE )

PASS, FAIL, UNRUNNABLE, QUICK = 0, 1, 2, 3
# One machine line: SEVERITY|TYPE|CODE|file|line|col|length|message, with a literal | escaped as \|
PIPE = re.compile( r"(?<!\\)\|" )


# ---------------------------------------------------------------- analyzer comparison

def parse_errors( machine_text, prefixes=() ):
    """
    Count the ERROR findings in `dart analyze --format=machine` output, keyed without line or column.

    Requires:
        - machine_text is the analyzer's stdout, one finding per line
        - prefixes is a sequence of directory prefixes (such as "/tmp/x/") to strip from file paths

    Ensures:
        - returns a Counter of ( file, code, message ) with one count per ERROR finding
        - ignores warnings, infos and every line that is not a finding
        - two findings that differ only in line, column or length are the same key
    """
    found = collections.Counter()
    for line in machine_text.splitlines():
        f = PIPE.split( line )
        if len( f ) < 8 or f[ 0 ].upper() != "ERROR": continue
        path = f[ 3 ].replace( "\\|", "|" )
        for p in prefixes:
            if p and path.startswith( p ): path = path[ len( p ): ]
        found[ ( path, f[ 2 ], "|".join( f[ 7: ] ) ) ] += 1
    return found


def new_errors( base, head ):
    """
    List the errors the head has that the base does not.

    Requires:
        - base and head are Counters from parse_errors

    Ensures:
        - returns sorted ( file, code, message ) keys, each repeated once per extra occurrence
        - an error present at the base the same number of times or more is not new
    """
    extra = head - base
    return sorted( extra.elements() )


# ---------------------------------------------------------------- comment stripping

def strip_dart( text ):
    """
    Reduce Dart source to its code and string text, with comments removed and whitespace collapsed.

    Requires:
        - text is the contents of a .dart file

    Ensures:
        - // and /* */ comments (nested block comments included, doc comments too) are dropped
        - outside strings, every run of whitespace and comments becomes one space; the result is trimmed
        - string contents are kept byte for byte: '//' inside a string is text, not a comment, and
          whitespace inside a string is not collapsed
        - ${ ... } interpolations are scanned as code, so a quote inside one does not end the string
        - two sources with the same result differ only in comments and code whitespace
    """
    out, i, n = [], 0, len( text )
    stack = [ [ "code", 0 ] ]          # ["code", brace depth] or ["str", quote, raw]
    def space():
        if out and out[ -1 ] != " ": out.append( " " )
    while i < n:
        top, c = stack[ -1 ], text[ i ]
        if top[ 0 ] == "code":
            two = text[ i:i + 2 ]
            if two == "//":
                j = text.find( "\n", i ); i = n if j < 0 else j; space(); continue
            if two == "/*":
                depth, i = 1, i + 2
                while i < n and depth:
                    if   text[ i:i + 2 ] == "/*": depth += 1; i += 2
                    elif text[ i:i + 2 ] == "*/": depth -= 1; i += 2
                    else: i += 1
                space(); continue
            if c.isspace(): space(); i += 1; continue
            if c in "'\"" or ( c == "r" and text[ i + 1:i + 2 ] in ( "'", '"' ) and ( not out or not ( out[ -1 ].isalnum() or out[ -1 ] == "_" ) ) ):
                raw = c == "r"
                if raw: out.append( "r" ); i += 1; c = text[ i ]
                q = c * 3 if text[ i:i + 3 ] == c * 3 else c
                out.append( q ); i += len( q )
                stack.append( [ "str", q, raw ] ); continue
            if len( stack ) > 1:       # inside ${ ... }: count braces to find the end of the interpolation
                if c == "{": top[ 1 ] += 1
                elif c == "}":
                    top[ 1 ] -= 1
                    if top[ 1 ] == 0: stack.pop(); out.append( c ); i += 1; continue
            out.append( c ); i += 1; continue
        _, q, raw = top
        if c == "\\" and not raw: out.append( text[ i:i + 2 ] ); i += 2; continue
        if text.startswith( q, i ): out.append( q ); i += len( q ); stack.pop(); continue
        if c == "$" and not raw and text[ i + 1:i + 2 ] == "{":
            out.append( "${" ); i += 2; stack.append( [ "code", 1 ] ); continue
        out.append( c ); i += 1
    return "".join( out ).strip()


def comments_differ( old, new ):
    """
    Say whether two versions of a .dart file differ in anything but comments and code whitespace.

    Requires:
        - old and new are file contents; "" stands for a file that does not exist at that end

    Ensures:
        - returns False when strip_dart gives the same text for both
        - returns True for any changed token, including an added or removed trailing comma
    """
    return strip_dart( old ) != strip_dart( new )


# ---------------------------------------------------------------- git helpers

def git( args, root=ROOT, check=True ):
    """
    Run git in root and return its stdout.

    Requires:
        - args is a list of git arguments

    Ensures:
        - returns stdout as text
        - raises RuntimeError with git's stderr when check is set and git fails
    """
    p = subprocess.run( [ "git", *args ], cwd=root, capture_output=True, text=True )
    if check and p.returncode != 0: raise RuntimeError( f"git {' '.join( args )}: {p.stderr.strip()}" )
    return p.stdout


def resolve_range( rev, base, root=ROOT ):
    """
    Turn the command-line choice into ( start_sha, end_sha ), end being the commit under review.

    Requires:
        - rev is None, "A..B", or a single commit; base is the branch the work will merge into

    Ensures:
        - rev None: start is the merge-base of base and HEAD, end is HEAD
        - rev "A..B": start is A, end is B
        - rev a commit C: start is C^, end is C
        - raises RuntimeError when a name does not resolve or a single commit has no parent
    """
    if rev is None:                      # the common case: HEAD against the branch it will merge into
        return git( [ "merge-base", base, "HEAD" ], root ).strip(), git( [ "rev-parse", "HEAD" ], root ).strip()
    if ".." in rev:
        a, b = rev.split( "..", 1 )
        return git( [ "rev-parse", a ], root ).strip(), git( [ "rev-parse", b or "HEAD" ], root ).strip()
    return git( [ "rev-parse", rev + "^" ], root ).strip(), git( [ "rev-parse", rev ], root ).strip()


def changed_dart_files( start, end, root=ROOT ):
    """
    List the paths a range changes, split into .dart files and others.

    Requires:
        - start and end are commits in root

    Ensures:
        - returns ( dart_paths, other_paths ), both sorted
        - renames are reported as a delete plus an add, so each side is compared on its own
    """
    names  = git( [ "diff", "--name-only", "--no-renames", f"{start}..{end}" ], root ).splitlines()
    dart   = sorted( p for p in names if p.endswith( ".dart" ) )
    return dart, sorted( p for p in names if not p.endswith( ".dart" ) )


def show( rev, path, root=ROOT ):
    """Return a file's text at a commit, or "" when it does not exist there."""
    p = subprocess.run( [ "git", "show", f"{rev}:{path}" ], cwd=root, capture_output=True, text=True )
    return p.stdout if p.returncode == 0 else ""


# ---------------------------------------------------------------- checks

def run_logged( name, cmd, logdir, root=ROOT, stdout_to=None ):
    """
    Run one command as a subprocess, keeping its output in the log directory.

    Requires:
        - cmd is an argument list; logdir exists

    Ensures:
        - writes <logdir>/<name>.log (stdout then stderr), or stdout to stdout_to when given
        - returns the exit code
    """
    print( f"== {name}", file=sys.stderr, flush=True )
    with open( os.path.join( logdir, name + ".log" ), "w" ) as log:
        if stdout_to:
            with open( stdout_to, "w" ) as out: return subprocess.run( cmd, cwd=root, stdout=out, stderr=log ).returncode
        return subprocess.run( cmd, cwd=root, stdout=log, stderr=subprocess.STDOUT ).returncode


def dart_dirs( root ):
    """Return the directories among lib and test that exist under root."""
    return [ d for d in ( "lib", "test" ) if os.path.isdir( os.path.join( root, d ) ) ]


def analyze_machine( root, logdir, name ):
    """
    Run `dart analyze --format=machine` over lib and test in root; return ( exit_code, stdout ).

    Ensures:
        - exit codes 0 to 3 (clean, infos, warnings, errors) are all a finished run
        - the output is saved as <logdir>/<name>.log
    """
    p = subprocess.run( [ pcg.dart_cmd( ROOT ), "analyze", "--format=machine", *dart_dirs( root ) ],
                        cwd=root, capture_output=True, text=True )
    open( os.path.join( logdir, name + ".log" ), "w" ).write( p.stdout + p.stderr )
    return p.returncode, p.stdout


def check_analyzer( start, logdir, root=ROOT ):
    """
    Fail on any analyzer ERROR that the start of the range does not also have.

    Requires:
        - start is a commit in root; the working tree is the end of the range

    Ensures:
        - returns ( exit_code, detail ); 0 only when the head has no error beyond the start's
        - returns 1 when either analyzer run did not finish, or the start could not be exported
        - leaves the checkout untouched: the start is exported with git archive into a scratch directory
    """
    print( "== analyzer (head)", file=sys.stderr, flush=True )
    code, head_text = analyze_machine( root, logdir, "1-analyzer-head" )
    if code not in ( 0, 1, 2, 3 ): return 1, f"analyzer did not finish at head (exit {code})"
    head = parse_errors( head_text, ( root + "/", ) )
    print( "== analyzer (start of range)", file=sys.stderr, flush=True )
    with tempfile.TemporaryDirectory( prefix="merge-gate-base-" ) as d:
        arc = subprocess.run( f"git archive {start} lib test pubspec.yaml pubspec.lock analysis_options.yaml | tar -x -C {d}",
                              shell=True, cwd=root, capture_output=True, text=True )
        if arc.returncode != 0: return 1, f"could not export {start[:7]}: {arc.stderr.strip()}"
        flutter = os.path.join( ROOT, "flutter", "bin", "flutter" )
        pub = subprocess.run( [ flutter, "pub", "get", "--offline" ], cwd=d, capture_output=True, text=True )
        if pub.returncode != 0: return 1, f"pub get failed for the start of the range: {pub.stderr.strip()[:200]}"
        code, base_text = analyze_machine( d, logdir, "1-analyzer-base" )
        if code not in ( 0, 1, 2, 3 ): return 1, f"analyzer did not finish at start (exit {code})"
        base = parse_errors( base_text, ( d + "/", ) )
    new = new_errors( base, head )
    if new:
        for f, c, m in new[ :20 ]: print( f"  new error: {f} {c}: {m}", file=sys.stderr )
        return 1, f"{len( new )} new error(s) (head {sum( head.values() )}, start {sum( base.values() )})"
    return 0, f"no new errors (head {sum( head.values() )}, start {sum( base.values() )})"


def check_comments_only( start, end, root=ROOT ):
    """
    Fail when any changed .dart file differs in more than comments.

    Requires:
        - start and end are commits in root

    Ensures:
        - returns ( exit_code, detail ); 0 only when every changed .dart file strips to the same text at both ends
        - a .dart file added or deleted by the range counts as changed text
        - non-.dart files are counted in the detail but do not fail the check
    """
    dart, other = changed_dart_files( start, end, root )
    bad = [ p for p in dart if comments_differ( show( start, p, root ), show( end, p, root ) ) ]
    for p in bad: print( f"  not comments-only: {p}", file=sys.stderr )
    note = f"{len( dart )} .dart file(s), {len( other )} other file(s) not checked"
    if not dart: return 1, f"no .dart file changed; nothing to call comments-only ({note})"
    return ( 1, f"{len( bad )} file(s) change more than comments ({note})" ) if bad else ( 0, f"comments only ({note})" )


def check_suite( logdir, root=ROOT ):
    """
    Run the full suite and judge it with tool/check_test_failures.py; run it twice only if that script asks.

    Ensures:
        - returns ( exit_code, detail, json_path ); exit_code is check_test_failures' own verdict
        - the suite's own exit code is never read: it is non-zero whenever any test fails
        - json_path is the first run's event stream, for check_ac_g2
    """
    run1 = os.path.join( logdir, "6-suite-run1.json" )
    run_logged( "6-suite-run1-stderr", [ os.path.join( root, "flutter.sh" ), "test", "--machine" ], logdir, root, stdout_to=run1 )
    code, last = run_logged( "6-verdict", [ sys.executable, "tool/check_test_failures.py", run1 ], logdir, root ), "6-verdict"
    if code == 3:
        run2 = os.path.join( logdir, "6-suite-run2.json" )
        run_logged( "6-suite-run2-stderr", [ os.path.join( root, "flutter.sh" ), "test", "--machine" ], logdir, root, stdout_to=run2 )
        code, last = run_logged( "6-verdict-rerun", [ sys.executable, "tool/check_test_failures.py", run1, run2 ], logdir, root ), "6-verdict-rerun"
    lines = open( os.path.join( logdir, last + ".log" ) ).read().strip().splitlines()
    return code, ( lines[ 0 ] if lines else "no output" ), run1


# ---------------------------------------------------------------- verdict

def verdict( results ):
    """
    Combine the check results into one word and an exit code.

    Requires:
        - results is a list of ( name, exit_code_or_None, detail ); None means the check was skipped

    Ensures:
        - returns ( "FAIL", 1 ) when any check that ran exited non-zero
        - else ( "QUICK", 3 ) when any check was skipped: a skipped suite never earns PASS
        - else ( "PASS", 0 )
    """
    if any( c is not None and c != 0 for _n, c, _d in results ): return "FAIL", FAIL
    if any( c is None for _n, c, _d in results ): return "QUICK", QUICK
    return "PASS", PASS


def report( word, results, rng, logdir ):
    """
    Format the verdict line, one line per check, and the log directory.

    Requires:
        - word is the verdict word; results as in verdict(); rng is a short "start..end" text

    Ensures:
        - the first line starts with the verdict word; each check line carries its exit code, or SKIPPED
    """
    lines = [ f"{word} {rng}" ]
    for name, code, detail in results:
        lines.append( f"  {name:<13} {'SKIPPED' if code is None else 'exit ' + str( code ):<8} {detail}" )
    lines.append( f"logs: {logdir}" )
    return "\n".join( lines )


def main( argv=None ):
    """
    Run the gate.

    Requires:
        - run inside the checkout that holds the commits, range ending at HEAD, tracked files unmodified

    Ensures:
        - returns 0 for PASS, 1 for FAIL, 2 when the gate could not start, 3 for QUICK
        - runs every check even after one fails, so one run shows every failure
    """
    ap = argparse.ArgumentParser( description="Run the merge gate on a commit or range." )
    ap.add_argument( "rev", nargs="?", help="a commit, or A..B ending at HEAD; default: the merge-base of --base and HEAD, to HEAD" )
    ap.add_argument( "--base", default="main", help="branch the work will merge into (default main)" )
    ap.add_argument( "--skip-suite", action="store_true", help="skip the full suite and ac-g2; the verdict says QUICK" )
    ap.add_argument( "--comments-only", action="store_true", help="also require that the range changes only comments in .dart files" )
    ap.add_argument( "--log-dir", help="keep logs here (default: a new directory under the system temp)" )
    args = ap.parse_args( argv )
    try:
        start, end = resolve_range( args.rev, args.base )
        head = git( [ "rev-parse", "HEAD" ] ).strip()
        dirty = git( [ "status", "--porcelain", "--untracked-files=no" ] ).strip()
    except RuntimeError as ex:
        print( f"CANNOT RUN — {ex}", file=sys.stderr ); return UNRUNNABLE
    if end != head: print( f"CANNOT RUN — the range ends at {end[:7]} but HEAD is {head[:7]}; check out the end of the range first", file=sys.stderr ); return UNRUNNABLE
    if dirty: print( f"CANNOT RUN — tracked files are modified:\n{dirty}", file=sys.stderr ); return UNRUNNABLE
    logdir = args.log_dir or tempfile.mkdtemp( prefix="merge-gate-" )
    os.makedirs( logdir, exist_ok=True )
    count  = len( git( [ "rev-list", f"{start}..{end}" ] ).split() )
    rng    = f"{start[:7]}..{end[:7]} ({count} commit{'' if count == 1 else 's'})" + ( " comments-only" if args.comments_only else "" )

    results = []
    code, detail = check_analyzer( start, logdir );  results.append( ( "analyzer", code, detail ) )
    for name, cmd in ( ( "docs-gate",   [ sys.executable, "tool/pre_commit_gate.py", "--docs-all" ] ),
                       ( "ignores",     [ sys.executable, "tool/check_doc_ignores.py" ] ),
                       ( "coverage",    [ sys.executable, "tool/doc_coverage.py" ] ),
                       ( "tool-tests",  [ sys.executable, "-m", "pytest", "tool/", "-q" ] ) ):
        code = run_logged( f"{len( results ) + 1}-{name}", cmd, logdir )
        results.append( ( name, code, " ".join( cmd[ 1: ] ) ) )
    if args.skip_suite:
        results += [ ( "suite", None, "skipped by --skip-suite" ), ( "ac-g2", None, "skipped by --skip-suite" ) ]
    else:
        code, detail, run1 = check_suite( logdir );  results.append( ( "suite", code, detail ) )
        code = run_logged( "7-ac-g2", [ sys.executable, "tool/check_ac_g2.py", run1 ], logdir )
        results.append( ( "ac-g2", code, "tool/check_ac_g2.py" ) )
    if args.comments_only:
        code, detail = check_comments_only( start, end );  results.append( ( "comments-only", code, detail ) )
    word, exit_code = verdict( results )
    print( report( word, results, rng, logdir ) )
    return exit_code


if __name__ == "__main__":
    sys.exit( main() )
