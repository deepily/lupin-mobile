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
  8. comments   (--comments-only) every changed .dart file is identical once comments are stripped, and
                no other file changed at all

The start of the range is measured WITHOUT touching the checkout: `git archive` exports lib/, test/ and
the pubspec files of that commit into a scratch directory, and the analyzer runs there. No stash, no
worktree, no checkout. Files that are gitignored and absent from the export (a missing google-services
style file) can only add errors to the start, which makes the comparison more lenient, never stricter.

Run it from the real checkout, not from a copy under a scratch directory: three AC-G2 tests skip there and
check 7 reports them missing.

Refused with exit 2 (CANNOT RUN): a range that does not end at HEAD, an empty range, modified tracked files,
any untracked, non-ignored file outside src/rnd/, src/docs/, history/, todo-archive/, io/ and .claude/ (the checks
read the working tree, so an untracked file can satisfy an import or an asset that the commit cannot), a missing
dart, flutter.sh or tool script.

A range that edits any analysis_options.yaml fails check 1 (a commit could exclude its own errors); pass
--allow-analyzer-config to accept it. A range that adds a line containing `ignore:` or `ignore_for_file:` to any
.dart file fails check 1 too (such a comment silences analyzer errors; the public_member_api_docs form is not
exempt); pass --allow-ignores to accept it. Either flag makes the verdict line say so.
The analyzer runs over the top-level directories of the tracked .dart files (lib, test, integration_test, ...),
at the head and, separately, at the start of the range.

Output: one verdict line, one line per check with its exit code, the log directory. Verdicts:
  PASS               every check ran and passed                                    exit 0
  PASS-WITH-WARNING  as PASS, but the range changes the gate's own inputs (this script, tool/check_*.py,
                     pre_commit_gate.py, doc_coverage.py, tool/data/, the AC-G2 baseline); a human must read that diff   exit 0
  QUICK              nothing failed but --skip-suite left checks 6 and 7 unrun        exit 3
  FAIL               a check that ran failed                                          exit 1
Exit 2 = could not run. PASS-WITH-WARNING exits 0, so a caller must read the verdict word and the warning line,
not only the exit code.

Known limits, left as they are: no check has a timeout, so a hung check hangs the gate (never a PASS);
an unterminated /* comment runs to the end of the file in strip_dart (such a file fails to compile, so check 1 fails).
"""
import argparse, collections, json, os, re, shlex, shutil, subprocess, sys, tempfile

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
        """
        Add one space to the output unless it is empty or already ends in one.

        Requires:
            - out is the output list of the enclosing strip_dart call
        Ensures:
            - never leaves two spaces in a row or a leading space
        """
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
    """
    Read a file's text at a commit.

    Requires:
        - rev is a commit in root; path is repo-relative
    Ensures:
        - returns the text, or "" when the file does not exist at that commit
    """
    p = subprocess.run( [ "git", "show", f"{rev}:{path}" ], cwd=root, capture_output=True, text=True )
    return p.stdout if p.returncode == 0 else ""


def range_commits( start, end, root=ROOT ):
    """
    Count the commits in a range.

    Requires:
        - start and end are commits in root
    Ensures:
        - returns the number of commits reachable from end and not from start; 0 means an empty range
    """
    return len( git( [ "rev-list", f"{start}..{end}" ], root ).split() )


ALLOWED_UNTRACKED = ( "src/rnd/", "src/docs/", "history/", "todo-archive/", "io/", ".claude/" )


def untracked_inputs( root=ROOT ):
    """
    List untracked, non-ignored files that the checks could read.

    Requires:
        - root is a git checkout
    Ensures:
        - returns sorted repo-relative paths of every untracked file that .gitignore does not cover,
          except those under src/rnd/, src/docs/, history/, todo-archive/, io/ and .claude/
        - a test may read any path (an asset, a fixture), so no other directory is exempt
    """
    names = git( [ "ls-files", "--others", "--exclude-standard" ], root ).splitlines()
    return sorted( n for n in names if not n.startswith( ALLOWED_UNTRACKED ) )


def limited( names, limit=10 ):
    """
    Format a file list for a message, at most limit entries.

    Requires:
        - names is a list of strings; limit is a positive integer
    Ensures:
        - returns one indented line per name up to limit, then "...and N more" when names are left out
    """
    lines = [ f"  {n}" for n in names[ :limit ] ]
    if len( names ) > limit: lines.append( f"  ...and {len( names ) - limit} more" )
    return "\n".join( lines )


IGNORE_LINE = re.compile( r"\bignore(?:_for_file)?:\s*(?P<codes>.*)$" )


def count_ignore_lines( text ):
    """
    Count the lines of a source file that carry an analyzer ignore.

    Requires:
        - text is the contents of a .dart file
    Ensures:
        - returns the number of lines containing `ignore:` or `ignore_for_file:` as a word
        - a line with several codes counts once; a line that merely says "ignore" does not count
    """
    return sum( 1 for line in text.splitlines() if IGNORE_LINE.search( line ) )


def ignore_additions( start, end, root=ROOT ):
    """
    List the ignore comments a range adds, per .dart file.

    Requires:
        - start and end are commits in root
    Ensures:
        - returns sorted ( file, codes ) pairs for each changed .dart file whose count of ignore lines rose
          between start and end; codes is the text after `ignore:` on each added line, joined with "; "
        - a line that only moves within a file, or a removed ignore, is not an addition
        - the public_member_api_docs form is counted like any other
    """
    found = []
    for path in changed_dart_files( start, end, root )[ 0 ]:
        old, new = show( start, path, root ), show( end, path, root )
        if count_ignore_lines( new ) <= count_ignore_lines( old ): continue
        grab  = lambda t: collections.Counter( l.strip() for l in t.splitlines() if IGNORE_LINE.search( l ) )
        added = ( grab( new ) - grab( old ) ).elements()
        found.append( ( path, "; ".join( IGNORE_LINE.search( l ).group( "codes" ).strip() for l in sorted( added ) ) ) )
    return sorted( found )


def dart_roots( paths ):
    """
    Pick the analyzer targets out of a list of tracked paths.

    Requires:
        - paths is a list of repo-relative paths
    Ensures:
        - returns the sorted, de-duplicated top-level directory of each .dart file, or the file itself when it sits at the repo root
        - non-.dart paths are ignored
    """
    return sorted( { p.split( "/" )[ 0 ] if "/" in p else p for p in paths if p.endswith( ".dart" ) } )


def dart_roots_at( rev, root=ROOT ):
    """
    List the analyzer targets of a commit.

    Requires:
        - rev is a commit in root
    Ensures:
        - returns dart_roots of every file tracked at rev
    """
    return dart_roots( git( [ "ls-tree", "-r", "--name-only", rev ], root ).splitlines() )


def analyzer_config_files( names ):
    """
    Pick the analyzer option files out of a list of changed paths.

    Requires:
        - names is a list of repo-relative paths
    Ensures:
        - returns sorted paths whose file name is exactly analysis_options.yaml, at any depth
    """
    return sorted( n for n in names if os.path.basename( n ) == "analysis_options.yaml" )


GATE_FILES = ( "tool/merge_gate.py", "tool/test_merge_gate.py", "tool/pre_commit_gate.py", "tool/doc_coverage.py", "tool/lint_dart_docs.py",
               "tool/conftest.py", "test/fixtures/ac_g2_passing_baseline.json", "flutter.sh", "dart_test.yaml", "pytest.ini",
               "pubspec.yaml", "pubspec.lock" )


def gate_input_files( names ):
    """
    Pick out the changed paths that feed the gate itself.

    Requires:
        - names is a list of repo-relative paths
    Ensures:
        - returns sorted paths that decide what a check runs or accepts: this script and its test, tool/check_*.py,
          pre_commit_gate.py, doc_coverage.py, lint_dart_docs.py, tool/conftest.py, anything under tool/data/ or
          .github/workflows/, the AC-G2 baseline, flutter.sh, dart_test.yaml, pytest.ini, pubspec.yaml, pubspec.lock
        - every other file is not listed
    """
    def feeds( n ):
        base = os.path.basename( n )
        return ( n in GATE_FILES or n.startswith( ( "tool/data/", ".github/workflows/" ) )
                 or ( n.startswith( "tool/" ) and "/" not in n[ 5: ] and base.startswith( "check_" ) and base.endswith( ".py" ) ) )
    return sorted( n for n in names if feeds( n ) )


def missing_tools( root=ROOT, skip_suite=False ):
    """
    List what the gate needs and cannot find.

    Requires:
        - root is the checkout the gate will run in
    Ensures:
        - returns one message per missing item: the dart binary, flutter/bin/flutter, flutter.sh (unless skip_suite)
          and each tool/ script the gate calls
        - returns [] when everything is present
    """
    missing = []
    dart = pcg.dart_cmd( ROOT )
    if not ( shutil.which( dart ) if os.sep not in dart else os.path.isfile( dart ) ): missing.append( f"dart binary {dart}" )
    needed = [ "flutter/bin/flutter", "tool/pre_commit_gate.py", "tool/check_doc_ignores.py", "tool/doc_coverage.py" ]
    if not skip_suite: needed += [ "flutter.sh", "tool/check_test_failures.py", "tool/check_ac_g2.py" ]
    return missing + [ f"{n} missing under {root}" for n in needed if not os.path.exists( os.path.join( root, n ) ) ]


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


def analyze_machine( root, logdir, name, targets ):
    """
    Run `dart analyze --format=machine` over the targets in root; return ( exit_code, stdout ).

    Requires:
        - targets is a non-empty list of directories or files that exist under root; logdir exists; name is a log file stem
    Ensures:
        - exit codes 0 to 3 (clean, infos, warnings, errors) are all a finished run
        - the output is saved as <logdir>/<name>.log
    """
    p = subprocess.run( [ pcg.dart_cmd( ROOT ), "analyze", "--format=machine", *targets ],
                        cwd=root, capture_output=True, text=True )
    with open( os.path.join( logdir, name + ".log" ), "w" ) as f: f.write( p.stdout + p.stderr )
    return p.returncode, p.stdout


def analyzer_failure( code, errors, where ):
    """
    Say whether an analyzer run counts as unfinished or unbelievable.

    Requires:
        - code is the analyzer's exit code; errors is the Counter parse_errors made from its output; where names the run
    Ensures:
        - returns a message when the exit code is outside 0 to 3 (the run did not finish)
        - returns a message when the exit code is 3 (errors exist) but no ERROR line was parsed (the output format
          changed or was cut short), so "no new errors" cannot be believed
        - returns None otherwise
    """
    if code not in ( 0, 1, 2, 3 ): return f"analyzer did not finish at {where} (exit {code})"
    if code == 3 and not errors: return f"analyzer exited 3 at {where} but no ERROR line was parsed"
    return None


def range_label( start, end, count, comments_only, config_allowed, ignores_allowed=False ):
    """
    Build the short text after the verdict word.

    Requires:
        - start and end are full shas; count is the number of commits
    Ensures:
        - returns "start..end (N commits)", with " comments-only", " analyzer-config-allowed" and " ignores-allowed" appended when set
    """
    label = f"{start[:7]}..{end[:7]} ({count} commit{'' if count == 1 else 's'})"
    return label + ( " comments-only" if comments_only else "" ) + ( " analyzer-config-allowed" if config_allowed else "" ) + ( " ignores-allowed" if ignores_allowed else "" )


def check_analyzer( start, logdir, root=ROOT, allow_config=False, allow_ignores=False ):
    """
    Fail on any analyzer ERROR that the start of the range does not also have.

    Requires:
        - start is a commit in root; the working tree is the end of the range

    Ensures:
        - returns 1, without running the analyzer, when the range edits any analysis_options.yaml and
          allow_config is not set: the head is analyzed with its own options, so a commit could exclude its own errors
        - returns 1, likewise, when the range adds an ignore comment to a .dart file and allow_ignores is not set;
          the detail names each file and the codes
        - analyzes the top-level directories of the tracked .dart files at the head, and those at the start for the start
        - returns ( exit_code, detail ); 0 only when the head has no error beyond the start's
        - returns 1 when either analyzer run did not finish, or the start could not be exported
        - leaves the checkout untouched: the start is exported with git archive into a scratch directory
    """
    touched = analyzer_config_files( git( [ "diff", "--name-only", "--no-renames", f"{start}..HEAD" ], root ).splitlines() )
    ignored = ignore_additions( start, "HEAD", root )
    refusals = []
    if touched and not allow_config:
        refusals.append( f"range edits analyzer config: {', '.join( touched )} (pass --allow-analyzer-config after reading that diff)" )
    if ignored and not allow_ignores:
        refusals.append( "range adds ignore comments: " + "; ".join( f"{f} [{c}]" for f, c in ignored ) + " (pass --allow-ignores after reading that diff)" )
    if refusals: return 1, " | ".join( refusals )
    head_targets, base_targets = dart_roots_at( "HEAD", root ), dart_roots_at( start, root )
    head = collections.Counter()
    if head_targets:
        print( "== analyzer (head)", file=sys.stderr, flush=True )
        code, head_text = analyze_machine( root, logdir, "1-analyzer-head", head_targets )
        head = parse_errors( head_text, ( root + "/", ) )
        if analyzer_failure( code, head, "head" ): return 1, analyzer_failure( code, head, "head" )
    base = collections.Counter()
    if base_targets:
        print( "== analyzer (start of range)", file=sys.stderr, flush=True )
        with tempfile.TemporaryDirectory( prefix="merge-gate-base-" ) as d:
            arc = subprocess.run( "git archive " + " ".join( shlex.quote( x ) for x in ( start, *base_targets, "pubspec.yaml", "pubspec.lock", "analysis_options.yaml" ) )
                                  + f" | tar -x -C {shlex.quote( d )}", shell=True, cwd=root, capture_output=True, text=True )
            if arc.returncode != 0: return 1, f"could not export {start[:7]}: {arc.stderr.strip()}"
            flutter = os.path.join( ROOT, "flutter", "bin", "flutter" )
            pub = subprocess.run( [ flutter, "pub", "get", "--offline" ], cwd=d, capture_output=True, text=True )
            if pub.returncode != 0: return 1, f"pub get failed for the start of the range: {pub.stderr.strip()[:200]}"
            code, base_text = analyze_machine( d, logdir, "1-analyzer-base", base_targets )
            base = parse_errors( base_text, ( d + "/", ) )
            if analyzer_failure( code, base, "start" ): return 1, analyzer_failure( code, base, "start" )
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
          and no other file changed
        - a .dart file added or deleted counts as changed text, unless it holds nothing but comments and whitespace:
          such a file strips to "" and so passes, whether it was added or deleted
        - any changed file that is not .dart fails the check, and the detail names it
        - a range that changes no .dart file fails rather than passing for nothing
    """
    dart, other = changed_dart_files( start, end, root )
    bad = [ p for p in dart if comments_differ( show( start, p, root ), show( end, p, root ) ) ]
    for p in bad: print( f"  not comments-only: {p}", file=sys.stderr )
    note = f"{len( dart )} .dart file(s)"
    if other: return 1, f"changes non-.dart file(s): {', '.join( other )} ({note})"
    if not dart: return 1, f"no .dart file changed; nothing to call comments-only ({note})"
    return ( 1, f"{len( bad )} file(s) change more than comments ({note})" ) if bad else ( 0, f"comments only ({note})" )


def check_suite( logdir, root=ROOT ):
    """
    Run the full suite and judge it with tool/check_test_failures.py; run it twice only if that script asks.

    Requires:
        - root holds flutter.sh and tool/check_test_failures.py; logdir exists
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
    with open( os.path.join( logdir, last + ".log" ) ) as f: lines = f.read().strip().splitlines()
    return code, ( lines[ 0 ] if lines else "no output" ), run1


# ---------------------------------------------------------------- verdict

def verdict( results, warnings=() ):
    """
    Combine the check results into one word and an exit code.

    Requires:
        - results is a list of ( name, exit_code_or_None, detail ); None means the check was skipped
        - warnings is the list of changed gate-input files, empty when none

    Ensures:
        - returns ( "FAIL", 1 ) when any check that ran exited non-zero
        - else ( "QUICK", 3 ) when any check was skipped: a skipped suite never earns PASS
        - else ( "PASS-WITH-WARNING", 0 ) when warnings is not empty
        - else ( "PASS", 0 )
        - a warning never turns FAIL or QUICK into anything else
    """
    if any( c is not None and c != 0 for _n, c, _d in results ): return "FAIL", FAIL
    if any( c is None for _n, c, _d in results ): return "QUICK", QUICK
    return ( "PASS-WITH-WARNING", PASS ) if warnings else ( "PASS", PASS )


def report( word, results, rng, logdir, warnings=() ):
    """
    Format the verdict line, one line per check, and the log directory.

    Requires:
        - word is the verdict word; results as in verdict(); rng is a short "start..end" text
        - warnings is the list of changed gate-input files, empty when none

    Ensures:
        - the first line starts with the verdict word; each check line carries its exit code, or SKIPPED
        - when warnings is not empty, the second line is the WARNING line naming them
    """
    lines = [ f"{word} {rng}" ]
    if warnings: lines.append( f"WARNING: this range changes the gate's own inputs: {', '.join( warnings )}. A human must read that diff." )
    for name, code, detail in results:
        lines.append( f"  {name:<13} {'SKIPPED' if code is None else 'exit ' + str( code ):<8} {detail}" )
    lines.append( f"logs: {logdir}" )
    return "\n".join( lines )


def main( argv=None, root=ROOT ):
    """
    Run the gate.

    Requires:
        - run inside the checkout that holds the commits, range ending at HEAD, tracked files unmodified
        - root is that checkout (the tests pass a throwaway repo)

    Ensures:
        - returns 0 for PASS and PASS-WITH-WARNING, 1 for FAIL, 2 when the gate could not start, 3 for QUICK
        - exit 2 for: a bad revision, a range not ending at HEAD, an empty range, modified tracked files,
          untracked input files, a missing tool
        - runs every check even after one fails, so one run shows every failure
    """
    ap = argparse.ArgumentParser( description="Run the merge gate on a commit or range. Run it from the real checkout, not a scratch copy." )
    ap.add_argument( "rev", nargs="?", help="a commit, or A..B ending at HEAD; default: the merge-base of --base and HEAD, to HEAD" )
    ap.add_argument( "--base", default="main", help="branch the work will merge into (default main)" )
    ap.add_argument( "--skip-suite", action="store_true", help="skip the full suite and ac-g2; the verdict says QUICK" )
    ap.add_argument( "--comments-only", action="store_true", help="also require that the range changes only comments in .dart files" )
    ap.add_argument( "--allow-analyzer-config", action="store_true", help="accept a range that edits analysis_options.yaml (the verdict line says so)" )
    ap.add_argument( "--allow-ignores", action="store_true", help="accept a range that adds `ignore:` / `ignore_for_file:` comments (the verdict line says so)" )
    ap.add_argument( "--log-dir", help="keep logs here (default: a new directory under the system temp)" )
    args = ap.parse_args( argv )
    def refuse( msg ):
        print( f"CANNOT RUN — {msg}", file=sys.stderr ); return UNRUNNABLE
    try:
        start, end = resolve_range( args.rev, args.base, root )
        head  = git( [ "rev-parse", "HEAD" ], root ).strip()
        dirty = git( [ "status", "--porcelain", "--untracked-files=no" ], root ).strip()
        count = range_commits( start, end, root )
        loose = untracked_inputs( root )
    except RuntimeError as ex:
        return refuse( str( ex ) )
    if end != head: return refuse( f"the range ends at {end[:7]} but HEAD is {head[:7]}; check out the end of the range first" )
    if count == 0:  return refuse( f"the range {start[:7]}..{end[:7]} is empty; there is nothing to gate" )
    if dirty:       return refuse( f"tracked files are modified:\n{dirty}" )
    if loose:       return refuse( f"{len( loose )} untracked file(s) the checks would read (git add them, delete them, or add them to .gitignore):\n" + limited( loose ) )
    absent = missing_tools( root, args.skip_suite )
    if absent:      return refuse( "; ".join( absent ) )
    logdir = args.log_dir or tempfile.mkdtemp( prefix="merge-gate-" )
    os.makedirs( logdir, exist_ok=True )
    names    = git( [ "diff", "--name-only", "--no-renames", f"{start}..{end}" ], root ).splitlines()
    warnings = gate_input_files( names )
    rng      = range_label( start, end, count, args.comments_only, bool( analyzer_config_files( names ) ) and args.allow_analyzer_config,
                           bool( ignore_additions( start, end, root ) ) and args.allow_ignores )

    results = []
    code, detail = check_analyzer( start, logdir, root, args.allow_analyzer_config, args.allow_ignores );  results.append( ( "analyzer", code, detail ) )
    for name, cmd in ( ( "docs-gate",   [ sys.executable, "tool/pre_commit_gate.py", "--docs-all" ] ),
                       ( "ignores",     [ sys.executable, "tool/check_doc_ignores.py" ] ),
                       ( "coverage",    [ sys.executable, "tool/doc_coverage.py" ] ),
                       ( "tool-tests",  [ sys.executable, "-m", "pytest", "tool/", "-q" ] ) ):
        code = run_logged( f"{len( results ) + 1}-{name}", cmd, logdir, root )
        results.append( ( name, code, " ".join( cmd[ 1: ] ) ) )
    if args.skip_suite:
        results += [ ( "suite", None, "skipped by --skip-suite" ), ( "ac-g2", None, "skipped by --skip-suite" ) ]
    else:
        code, detail, run1 = check_suite( logdir, root );  results.append( ( "suite", code, detail ) )
        code = run_logged( "7-ac-g2", [ sys.executable, "tool/check_ac_g2.py", run1 ], logdir, root )
        results.append( ( "ac-g2", code, "tool/check_ac_g2.py" ) )
    if args.comments_only:
        code, detail = check_comments_only( start, end, root );  results.append( ( "comments-only", code, detail ) )
    word, exit_code = verdict( results, warnings )
    print( report( word, results, rng, logdir, warnings ) )
    return exit_code


if __name__ == "__main__":
    sys.exit( main() )
