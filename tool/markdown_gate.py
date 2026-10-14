#!/usr/bin/env python3
"""
Blocking markdown gate: refuse a markdown page that breaks the documentation standard.

    python3 tool/markdown_gate.py --staged        the commit hook: the staged markdown files
    python3 tool/markdown_gate.py --base <ref>    the merge gate: every tracked page, and the lines changed since <ref>
    python3 tool/markdown_gate.py                 every tracked page, whole-file classes only

Each page has a class, listed in tool/data/markdown_scope.txt. The class decides which rules apply and
whether the whole file or only the changed lines are checked. A page with no entry is a reference page.

A line that carries `<!-- doc-lint: waive <rule> -- <reason> -->` drops that one rule on that line; the reason needs a word
of three letters or more, and each honoured waiver is printed and counted.

Exit 0 = nothing refused · 1 = at least one refused finding · 2 = the scope file is wrong.
"""
import argparse, os, re, subprocess, sys

sys.path.insert( 0, os.path.dirname( os.path.abspath( __file__ ) ) )
from doc_lint.changed_ranges import HUNK_HEADER, PAGE_LEVEL_RULES, in_ranges
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
ALL_LINES     = [ ( 1, 10 ** 9 ) ]
# <!-- doc-lint: waive <rule> -- <reason> --> : drops that one rule on the line that carries it. The reason must hold
# a word of three letters or more; a marker without one waives nothing.
WAIVER        = re.compile( r"<!--\s*doc-lint:\s*waive\s+(?P<rule>[a-z0-9-]+)\s*--\s*(?P<reason>.*?)\s*-->" )
CODE_SPAN     = re.compile( r"(`+)(?:(?!\1).)+?\1" )
REASON_WORD   = re.compile( r"[A-Za-z]{3,}" )


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
        - ScopeError naming the line when a line is not a known class followed by one path, when the path neither
          ends in a slash nor in .md (a folder written without its slash would match nothing), or a path is listed twice
    """
    entries = []
    seen    = set()
    for number, line in enumerate( text.split( "\n" ), 1 ):
        line = line.strip()
        if not line or line.startswith( "#" ): continue
        parts = line.split()
        if len( parts ) != 2 or parts[ 0 ] not in CLASSES:
            raise ScopeError( f"{SCOPE_PATH}:{number}: expected a class ({', '.join( CLASSES )}) and one path, got: {line}" )
        if not parts[ 1 ].endswith( ( "/", ".md" ) ):
            raise ScopeError( f"{SCOPE_PATH}:{number}: {parts[ 1 ]} must be a .md file or a folder that ends in a slash" )
        if parts[ 1 ] in seen: raise ScopeError( f"{SCOPE_PATH}:{number}: {parts[ 1 ]} is listed twice" )
        seen.add( parts[ 1 ] )
        entries.append( ( parts[ 1 ], parts[ 0 ] ) )
    return entries


def load_scope( root=ROOT, staged=False, base=None ):
    """
    Read the scope file.

    Requires:
        - root is the repo working tree

    Ensures:
        - returns ( entries, notice ): the entries from parse_scope and a line to print, or None
        - staged=True reads the file as HEAD has it, and base reads it as it was at the merge base of HEAD and base, so
          neither a commit nor a run of commits can loosen the classes it is judged by
        - when the change touches the file, or the revision has none, notice says which version was used
        - with neither, reads the working tree's file and notice is None

    Raises:
        - ScopeError when the file is missing or malformed, or when base has no merge base with HEAD
    """
    notice, rev = None, None
    if staged:
        rev     = "HEAD"
        touched = git( root, "diff", "--cached", "--name-only", "-z", "--", SCOPE_PATH ).strip( "\0" )
        if touched: notice = f"NOTICE  {SCOPE_PATH} is changed in this commit; this commit is judged by the classes in HEAD"
    elif base is not None:
        proc = subprocess.run( [ "git", "-C", root, "merge-base", "HEAD", base ], capture_output=True, text=True )
        if proc.returncode != 0 or not proc.stdout.strip(): raise ScopeError( f"--base {base}: no merge base with HEAD" )
        rev = proc.stdout.strip()
        if git( root, "diff", "--name-only", "-z", rev, "--", SCOPE_PATH ).strip( "\0" ):
            notice = f"NOTICE  {SCOPE_PATH} is changed since the merge base {rev[ :7 ]}; the range is judged by the classes there"
    if rev is not None:
        try: return parse_scope( git( root, "show", f"{rev}:{SCOPE_PATH}" ) ), notice
        except RuntimeError: notice = f"NOTICE  {SCOPE_PATH} is not in {rev[ :7 ]}; judged by the working tree's copy"
    try:
        with open( os.path.join( root, SCOPE_PATH ), encoding="utf-8" ) as handle: return parse_scope( handle.read() ), notice
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
        - a class outside WHOLE_FILE keeps only findings on changed lines, and drops the page-level rules
          (length, runbook sections): one appended line must not be refused for the shape of the whole page

    Raises:
        - nothing
    """
    if cls == "exempt": return []
    if cls in RECORDS: findings = [ f for f in findings if f.rule not in RECORD_ALLOWS ]
    if cls not in WHOLE_FILE:
        findings = [ f for f in findings if f.rule not in PAGE_LEVEL_RULES and in_ranges( f.line, ranges.get( f.path, [] ) ) ]
    return findings


def waivers( source ):
    """
    Read the same-line waivers on a page.

    Requires:
        - source is the page's text

    Ensures:
        - returns { ( line, rule ): reason } for each marker whose reason holds a word of three letters or more
        - a marker with no such word is not returned, so it waives nothing
        - a marker covers its own line and its own rule, and nothing else
        - a marker inside a code span or a fenced block is text, not a waiver

    Raises:
        - nothing
    """
    found, fenced = {}, False
    for number, text in enumerate( source.split( "\n" ), 1 ):
        if text.lstrip().startswith( ( "```", "~~~" ) ):
            fenced = not fenced
            continue
        if fenced: continue
        text = CODE_SPAN.sub( lambda m: " " * len( m.group( 0 ) ), text )
        for m in WAIVER.finditer( text ):
            if REASON_WORD.search( m.group( "reason" ) ): found[ ( number, m.group( "rule" ) ) ] = m.group( "reason" )
    return found


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


def changed_pages( root, staged, base ):
    """
    Say which markdown pages changed, and on which lines.

    Requires:
        - root is a git working tree
        - exactly one of staged and base is set, or neither (then nothing is reported)

    Ensures:
        - returns ( ranges, origins ): ranges maps each added, copied, modified or renamed page to its list of
          ( first, last ) new-file lines, and origins maps a renamed page to its old path
        - names come from NUL-separated git output and each page is diffed alone by a literal pathspec, so a name with a
          space or a non-ASCII letter is the same key everywhere
        - staged=True reads the index against HEAD; base reads the working tree against that revision

    Raises:
        - RuntimeError from git
    """
    if not staged and base is None: return {}, {}
    where  = [ "--cached" ] if staged else [ base ]
    tokens = git( root, "diff", "--name-status", "-z", "-M", "--diff-filter=ACMR", *where ).split( "\0" )
    ranges, origins, i = {}, {}, 0
    while i < len( tokens ) and tokens[ i ]:
        if tokens[ i ][ 0 ] in "RC": old, new, i = tokens[ i + 1 ], tokens[ i + 2 ], i + 3
        else:                        old, new, i = None, tokens[ i + 1 ], i + 2
        if not new.endswith( ".md" ): continue
        specs = [ f":(literal){p}" for p in ( new, old ) if p is not None ]
        diff  = git( root, "diff", "-U0", "--no-color", "--no-ext-diff", "-M", *where, "--", *specs )
        ranges[ new ] = []
        if old is not None: origins[ new ] = old
        for raw in diff.split( "\n" ):
            m = HUNK_HEADER.match( raw )
            if m is None: continue
            start, count = int( m.group( 1 ) ), 1 if m.group( 2 ) is None else int( m.group( 2 ) )
            if count > 0: ranges[ new ].append( ( start, start + count - 1 ) )
    return ranges, origins


def markdown_paths( root, staged ):
    """
    List the markdown files to check.

    Requires:
        - root is a git working tree

    Ensures:
        - staged=True returns the staged files that are added, copied, modified or renamed
        - staged=False returns every tracked file that is still in the working tree, so a file deleted there is not read
        - names are read NUL-separated, so a name with a space or a non-ASCII letter is not quoted by git
        - only paths that end in .md are returned, sorted

    Raises:
        - RuntimeError from git
    """
    if staged: out = git( root, "diff", "--cached", "--name-only", "-z", "--diff-filter=ACMR" )
    else:      out = git( root, "ls-files", "-z" )
    paths = sorted( p for p in out.split( "\0" ) if p.endswith( ".md" ) )
    return paths if staged else [ p for p in paths if os.path.isfile( os.path.join( root, p ) ) ]


def read_page( root, path, staged ):
    """
    Read one page as the check should see it.

    Requires:
        - path is a repo-relative posix path

    Ensures:
        - staged=True returns the staged content, so an unstaged edit cannot hide a staged finding
        - content that is not valid UTF-8 raises, in both modes, so neither mode reads it with bytes replaced
        - staged=False returns the working tree's content

    Raises:
        - RuntimeError from git, OSError or UnicodeDecodeError from the read
    """
    if staged:
        res = subprocess.run( [ "git", "-C", root, "show", f":{path}" ], capture_output=True )
        if res.returncode != 0: raise RuntimeError( f"git show :{path} failed: {res.stderr.decode( 'utf-8', 'replace' ).strip()}" )
        return res.stdout.decode( "utf-8" )
    with open( os.path.join( root, path ), encoding="utf-8" ) as handle: return handle.read()


def collect( root, staged, base ):
    """
    Gather the refused and the warned findings.

    Requires:
        - root is a git working tree
        - base is a revision, or None

    Ensures:
        - returns ( refused, warned, checked, notice, waived ): two lists of ( class, Finding ), the number of pages read,
          the scope notice or None, and a list of ( Finding, reason ) for each finding a same-line waiver dropped
        - a waiver drops only a finding that the page's class would otherwise have refused or warned about
        - a page that enters a changed-lines class by rename from a page of another class is checked on every line
        - with staged=False and base=None, the classes that check changed lines have no lines to check and add nothing
        - a page that cannot be read is refused, whatever its class, unless the class is exempt

    Raises:
        - ScopeError from the scope file, RuntimeError from git
    """
    entries, notice = load_scope( root, staged, base )
    ranges, origins = changed_pages( root, staged, base )
    refused, warned, waived, checked = [], [], [], 0
    for path in markdown_paths( root, staged ):
        cls = class_of( path, entries )
        if cls == "exempt": continue
        if cls not in WHOLE_FILE and path in origins and class_of( origins[ path ], entries ) != cls: ranges[ path ] = ALL_LINES
        if cls not in WHOLE_FILE and not ranges.get( path ): continue
        checked += 1
        try:
            source = read_page( root, path, staged )
        except ( OSError, UnicodeDecodeError, RuntimeError ) as err:
            refused.append( ( cls, Finding( path, 1, "unreadable", f"could not read: {err}" ) ) )
            continue
        kept   = apply_class( cls, lint_source( path, source, root ), ranges )
        found  = waivers( source )
        waived.extend( ( f, found[ ( f.line, f.rule ) ] ) for f in kept if ( f.line, f.rule ) in found )
        kept   = [ f for f in kept if ( f.line, f.rule ) not in found ]
        ( warned if cls == "warn" else refused ).extend( ( cls, f ) for f in kept )
    return refused, warned, checked, notice, waived


def main( argv=None, root=ROOT, out=None ):
    """
    Run the gate and print what it found.

    Requires:
        - argv is a list of arguments, or None for sys.argv

    Ensures:
        - prints one line per finding with its class, one WAIVED line per honoured waiver, then one summary line
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
        refused, warned, checked, notice, waived = collect( args.repo_root, args.staged, args.base )
    except ScopeError as err:
        print( f"BLOCKED: {err}", file=sys.stderr )
        return 2
    if notice: out.write( notice + "\n" )
    for cls, f in warned:  out.write( f"WARN    {f.path}:{f.line}: {f.rule}: {f.message}  [{cls}]\n" )
    for cls, f in refused: out.write( f"REFUSED {f.path}:{f.line}: {f.rule}: {f.message}  [{cls}]\n" )
    for f, reason in waived: out.write( f"WAIVED  {f.path}:{f.line}: {f.rule} -- {reason}\n" )
    out.write( f"{len( refused )} refused, {len( warned )} warned, {checked} pages checked, {len( waived )} waived\n" )
    if refused:
        print( f"BLOCKED: {len( refused )} markdown finding(s). The class of each page is in {SCOPE_PATH}.", file=sys.stderr )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit( main() )
