#!/usr/bin/env python3
"""
Blocking markdown gate: refuse a markdown page that breaks the documentation standard.

    python3 tool/markdown_gate.py --staged        the commit hook: the staged markdown files
    python3 tool/markdown_gate.py --base <ref>    the merge gate: every tracked page, and the lines changed since <ref>
    python3 tool/markdown_gate.py                 every tracked page, whole-file classes only

Each page has a class, listed in tool/data/markdown_scope.txt. The class decides which rules apply and
whether the whole file or only the changed lines are checked. A page with no entry is a reference page.

Exit 0 = nothing refused · 1 = at least one refused finding · 2 = the scope file is wrong.
"""
import argparse, os, subprocess, sys

sys.path.insert( 0, os.path.dirname( os.path.abspath( __file__ ) ) )
from doc_lint.changed_ranges import changed_line_ranges, filter_findings
from doc_lint.md_lint import lint_source
from doc_lint.text_rules import Finding

ROOT       = os.path.dirname( os.path.dirname( os.path.abspath( __file__ ) ) )
SCOPE_PATH = "tool/data/markdown_scope.txt"
CLASSES    = ( "reference", "record", "record-lines", "warn", "exempt" )
DEFAULT    = "reference"
# A record exists to hold dates and ticket ids, and it is not a reference page with a word limit.
RECORD_ALLOWS = frozenset( { "iso-date", "bare-ref", "dated-banner", "reference-length" } )
RECORDS       = frozenset( { "record", "record-lines" } )
WHOLE_FILE    = frozenset( { "reference", "record" } )


class ScopeError( Exception ):
    """The scope file cannot be read as a list of classes."""


def parse_scope( text ):
    """
    Read the scope file's text into entries.

    Requires:
        - text is the content of the scope file

    Ensures:
        - returns a list of ( pattern, class ) pairs in file order
        - blank lines and lines that start with # are skipped

    Raises:
        - ScopeError naming the line when a line is not a known class followed by one path, or a path is listed twice
    """
    entries = []
    seen    = set()
    for number, line in enumerate( text.split( "\n" ), 1 ):
        line = line.strip()
        if not line or line.startswith( "#" ): continue
        parts = line.split()
        if len( parts ) != 2 or parts[ 0 ] not in CLASSES:
            raise ScopeError( f"{SCOPE_PATH}:{number}: expected a class ({', '.join( CLASSES )}) and one path, got: {line}" )
        if parts[ 1 ] in seen: raise ScopeError( f"{SCOPE_PATH}:{number}: {parts[ 1 ]} is listed twice" )
        seen.add( parts[ 1 ] )
        entries.append( ( parts[ 1 ], parts[ 0 ] ) )
    return entries


def load_scope( root=ROOT ):
    """
    Read the scope file from the working tree.

    Requires:
        - root is the repo working tree

    Ensures:
        - returns the entries from parse_scope

    Raises:
        - ScopeError when the file is missing or malformed
    """
    try:
        with open( os.path.join( root, SCOPE_PATH ), encoding="utf-8" ) as handle: return parse_scope( handle.read() )
    except OSError as err:
        raise ScopeError( f"{SCOPE_PATH} could not be read: {err}" )


def class_of( path, entries ):
    """
    Say which class a page belongs to.

    Requires:
        - path is a repo-relative posix path
        - entries is the list from parse_scope

    Ensures:
        - an entry that ends in a slash matches every path under that folder; any other entry matches that one file
        - the longest matching entry wins
        - returns DEFAULT when no entry matches

    Raises:
        - nothing
    """
    best = None
    for pattern, cls in entries:
        hit = path.startswith( pattern ) if pattern.endswith( "/" ) else path == pattern
        if hit and ( best is None or len( pattern ) > len( best[ 0 ] ) ): best = ( pattern, cls )
    return best[ 1 ] if best is not None else DEFAULT


def apply_class( cls, findings, ranges ):
    """
    Keep the findings a page's class is held to.

    Requires:
        - cls is one of CLASSES
        - findings are the linter's findings for one page
        - ranges is the dict of changed line ranges per path

    Ensures:
        - exempt keeps nothing
        - a record class drops the rules in RECORD_ALLOWS
        - a class outside WHOLE_FILE keeps only findings on changed lines

    Raises:
        - nothing
    """
    if cls == "exempt": return []
    if cls in RECORDS: findings = [ f for f in findings if f.rule not in RECORD_ALLOWS ]
    if cls not in WHOLE_FILE: findings = filter_findings( findings, ranges )
    return findings


def git( root, *args ):
    """
    Run one git command in the working tree and return its output.

    Requires:
        - root is a git working tree

    Ensures:
        - returns stdout as text

    Raises:
        - RuntimeError naming the command and git's error when git exits non-zero
    """
    res = subprocess.run( [ "git", "-C", root, *args ], capture_output=True, text=True, encoding="utf-8", errors="replace" )
    if res.returncode != 0: raise RuntimeError( f"git {' '.join( args )} failed: {res.stderr.strip()}" )
    return res.stdout


def markdown_paths( root, staged ):
    """
    List the markdown files to check.

    Requires:
        - root is a git working tree

    Ensures:
        - staged=True returns the staged files that are added, copied, modified or renamed
        - staged=False returns every tracked file
        - only paths that end in .md are returned, sorted

    Raises:
        - RuntimeError from git
    """
    out = git( root, "diff", "--cached", "--name-only", "--diff-filter=ACMR" ) if staged else git( root, "ls-files" )
    return sorted( p for p in out.split( "\n" ) if p.endswith( ".md" ) )


def read_page( root, path, staged ):
    """
    Read one page as the check should see it.

    Requires:
        - path is a repo-relative posix path

    Ensures:
        - staged=True returns the staged content, so an unstaged edit cannot hide a staged finding
        - staged=False returns the working tree's content

    Raises:
        - RuntimeError from git, OSError or UnicodeDecodeError from the read
    """
    if staged: return git( root, "show", f":{path}" )
    with open( os.path.join( root, path ), encoding="utf-8" ) as handle: return handle.read()


def collect( root, staged, base ):
    """
    Gather the refused and the warned findings.

    Requires:
        - root is a git working tree
        - base is a revision, or None

    Ensures:
        - returns ( refused, warned, checked ): two lists of ( class, Finding ) and the number of pages read
        - with staged=False and base=None, the classes that check changed lines have no lines to check and add nothing
        - a page that cannot be read is refused, whatever its class, unless the class is exempt

    Raises:
        - ScopeError from the scope file, RuntimeError from git
    """
    entries = load_scope( root )
    if staged:           ranges = changed_line_ranges( root, None, cached=True )
    elif base is not None: ranges = changed_line_ranges( root, base )
    else:                ranges = {}
    refused, warned, checked = [], [], 0
    for path in markdown_paths( root, staged ):
        cls = class_of( path, entries )
        if cls == "exempt": continue
        if cls not in WHOLE_FILE and path not in ranges: continue
        checked += 1
        try:
            source = read_page( root, path, staged )
        except ( OSError, UnicodeDecodeError, RuntimeError ) as err:
            refused.append( ( cls, Finding( path, 1, "unreadable", f"could not read: {err}" ) ) )
            continue
        kept = apply_class( cls, lint_source( path, source, root ), ranges )
        ( warned if cls == "warn" else refused ).extend( ( cls, f ) for f in kept )
    return refused, warned, checked


def main( argv=None, root=ROOT, out=None ):
    """
    Run the gate and print what it found.

    Requires:
        - argv is a list of arguments, or None for sys.argv

    Ensures:
        - prints one line per finding with its class, then one summary line
        - returns 1 when any finding is refused, 2 when the scope file is wrong, else 0
        - a warned finding is printed and never changes the exit code

    Raises:
        - RuntimeError from git
    """
    out = out if out is not None else sys.stdout
    ap  = argparse.ArgumentParser( description="Blocking markdown gate for the documentation standard." )
    ap.add_argument( "--staged", action="store_true", help="check the staged markdown files (the commit hook)" )
    ap.add_argument( "--base", metavar="REF", help="check every tracked page, and the lines changed since REF (the merge gate)" )
    ap.add_argument( "--repo-root", default=root, help="git working tree to read" )
    args = ap.parse_args( argv )
    if args.staged and args.base: ap.error( "--staged and --base cannot be used together" )
    try:
        refused, warned, checked = collect( args.repo_root, args.staged, args.base )
    except ScopeError as err:
        print( f"BLOCKED: {err}", file=sys.stderr )
        return 2
    for cls, f in warned:  out.write( f"WARN    {f.path}:{f.line}: {f.rule}: {f.message}  [{cls}]\n" )
    for cls, f in refused: out.write( f"REFUSED {f.path}:{f.line}: {f.rule}: {f.message}  [{cls}]\n" )
    out.write( f"{len( refused )} refused, {len( warned )} warned, {checked} pages checked\n" )
    if refused:
        print( f"BLOCKED: {len( refused )} markdown finding(s). The class of each page is in {SCOPE_PATH}.", file=sys.stderr )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit( main() )
