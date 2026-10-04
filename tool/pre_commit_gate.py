#!/usr/bin/env python3
"""Blocking pre-commit gate for the documentation standard.

  python3 tool/pre_commit_gate.py            # gate the staged changes (what the hook runs)
  python3 tool/pre_commit_gate.py --list     # print the swept directories and stop
  python3 tool/pre_commit_gate.py --docs-all # check 3 alone, over every gated directory (what CI runs)

Runs these checks and blocks the commit when any one fails:
  1. tool/lint_dart_docs.py --staged --strict   (Dart doc linter, staged lines only)
  2. tool/check_doc_ignores.py                  (ignore gate, whole of lib/)
  3. dart analyze --format=machine <dirs>       (the gated directories the commit touches; fails
                                                 ONLY on public_member_api_docs, every other finding
                                                 is ignored, errors included), for the directories
                                                 named in tool/data/strict_exempt.txt
  4. dart analyze --fatal-infos --format=machine <dirs>  (every other gated directory the commit touches:
                                                 ANY finding fails, every options file that applies must be
                                                 the plain template, and no unexplained ignore comment)

The gated directories are listed in tool/data/gated_dirs.txt: every swept directory. A gated directory is
strict (check 4) unless tool/data/strict_exempt.txt names it, with a reason and a row; the exempt ones keep
the docs-only check 3 while their other findings are cleaned up (Rick, 2026-10-02: "Docs now, code clean-up later"). Set DART to
use another dart binary; the default is `dart` on PATH, then flutter/bin/dart in the repo.
Bypass with `git commit --no-verify`; the CI step in .github/workflows/flutter-ci.yml catches that.

Exit 0 = every check passed · 1 = at least one check failed.
"""
import argparse, os, re, shutil, subprocess, sys

sys.path.insert( 0, os.path.dirname( os.path.abspath( __file__ ) ) )
import check_doc_ignores as ignores   # the weak-reason list lives there, once

ROOT    = os.path.dirname( os.path.dirname( os.path.abspath( __file__ ) ) )
OPTIONS    = "analysis_options.yaml"
GATED_LIST = "tool/data/gated_dirs.txt"
EXEMPT_LIST = "tool/data/strict_exempt.txt"
EXEMPT_LINE = re.compile( r"^(\S+)\s+#\s+(\S.*)\(row [0-9a-f]{8}\)\s*$" )
# The only content an options file that applies to a strict directory may have (comments and blank lines aside).
# An allow-list, not a list of bad keys: any other key, in map or list form, at any depth, is refused.
ROOT_TEMPLATE = [ "include: package:flutter_lints/flutter.yaml", "analyzer:", "  exclude:", "    - flutter/**",
                  "    - build/**", "linter:", "  rules:" ]
DIR_TEMPLATE  = [ "include: <root options file>", "linter:", "  rules:", "    public_member_api_docs: true" ]
# Measured 2026-10-03 with dart 3.8.0: the analyzer honours `//`, `///` and `////` comments, indented or trailing,
# with any spacing, `ignore: a, b`, `type=lint`, and ignore_for_file at any line; it does not honour /* */ forms.
# The gate refuses every form, block comments included, so it never depends on that list staying true.
IGNORE_CMT    = re.compile( r"\bignore(?P<file>_for_file)?\s*:(?P<body>.*)$", re.IGNORECASE )
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


def ref_list( rel, root=ROOT, ref="HEAD" ):
    """
    Read a list file as it is at a git ref.

    Requires:
        - root is a git working tree; rel is a repo-relative list file such as tool/data/gated_dirs.txt

    Ensures:
        - returns the directory names in that file at the ref, comments and annotations dropped
        - returns None when the ref has no such file (first commit, or the file is new)
    """
    proc = subprocess.run( [ "git", "show", f"{ref}:{rel}" ], cwd=root, capture_output=True, text=True )
    if proc.returncode != 0: return None
    return [ l.split()[0] for l in ( x.strip() for x in proc.stdout.splitlines() ) if l and not l.startswith( "#" ) ]


def effective_lists( root=ROOT, ref="HEAD" ):
    """
    Give the gated and exempt lists a check must use, so a change cannot loosen its own gate.

    Requires:
        - root holds both list files; ref is a git ref (HEAD for the hook, the merge base for CI)

    Ensures:
        - returns ( gated, exempt ) as lists of directories
        - gated is the working list plus any directory the ref gated that still exists on disk
        - exempt is the working list limited to what the ref already exempted; when the ref has no exempt file it is the working list
    """
    gated   = swept_dirs( root )
    exempt  = exempt_dirs( root )
    in_ref  = ref_list( GATED_LIST, root, ref )
    if in_ref: gated = gated + [ d for d in in_ref if d not in gated and os.path.isdir( os.path.join( root, d ) ) ]
    ex_ref  = ref_list( EXEMPT_LIST, root, ref )
    if ex_ref is not None: exempt = [ d for d in exempt if d in ex_ref ]
    return gated, exempt


def listed_but_missing( root=ROOT ):
    """
    Find gated directories that are on the list but no longer exist.

    Requires:
        - root holds tool/data/gated_dirs.txt

    Ensures:
        - returns one message per missing directory, naming it and the list it is in
        - returns [] when every listed directory exists
    """
    return [ f"{d} is listed in {GATED_LIST} but the directory does not exist; delete that line"
             f"{' and its line in ' + EXEMPT_LIST if d in exempt_dirs( root ) else ''}"
             for d in swept_dirs( root ) if not os.path.isdir( os.path.join( root, d ) ) ]


def merge_base( ref, root=ROOT ):
    """
    Resolve the commit a check must read the lists from.

    Requires:
        - ref names a commit that shares history with HEAD (a fetched base branch)

    Ensures:
        - returns the merge-base sha of HEAD and ref
        - raises RuntimeError saying so when git cannot find one (never falls back to the working lists)
    """
    proc = subprocess.run( [ "git", "merge-base", "HEAD", ref ], cwd=root, capture_output=True, text=True )
    if proc.returncode != 0 or not proc.stdout.strip():
        raise RuntimeError( f"--base {ref}: no merge base with HEAD; fetch it (actions/checkout fetch-depth: 0)" )
    return proc.stdout.strip()


def partition_touched( staged, root=ROOT ):
    """
    Split the gated directories a commit touches into the docs-only ones and the strict ones.

    Requires:
        - staged is a list of repo-relative paths; root holds both list files

    Ensures:
        - returns ( docs_only, strict ), each in gated-list order
        - a touched directory named in strict_exempt.txt goes to docs_only, every other touched gated one to strict
        - a directory the commit itself drops from gated_dirs.txt is still checked (and still exists on disk)
        - a directory the commit itself adds to strict_exempt.txt is still checked strictly: an exemption
          counts only once it is in HEAD, so a commit cannot excuse its own findings
        - staging a list file or any analysis_options.yaml makes every gated directory count as touched
    """
    swept, exempt = effective_lists( root, "HEAD" )
    config  = ( GATED_LIST, EXEMPT_LIST, OPTIONS )
    if any( p in config or ( p.startswith( "lib/" ) and p.endswith( "/" + OPTIONS ) ) for p in staged ):
        touched = list( swept )
    else:
        touched = touched_dirs( staged, swept )
    return [ d for d in touched if d in exempt ], [ d for d in touched if d not in exempt ]


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


def exempt_dirs( root=ROOT ):
    """
    Read tool/data/strict_exempt.txt: the gated directories that are not yet strict.

    Requires:
        - root holds tool/data/strict_exempt.txt, lines `<dir>  # <reason> (row <8 hex>)`, `#`-only lines are comments

    Ensures:
        - returns the exempt directories in file order
        - raises ValueError naming the line when an entry has no reason or no row
        - raises ValueError naming the directory when it is not in the gated list
    """
    path = os.path.join( root, EXEMPT_LIST )
    if not os.path.exists( path ): return []
    found = []
    with open( path, encoding="utf-8" ) as f:
        for n, raw in enumerate( f, 1 ):
            line = raw.strip()
            if not line or line.startswith( "#" ): continue
            m = EXEMPT_LINE.match( line )
            if not m: raise ValueError( f"{EXEMPT_LIST}:{n}: need `<dir>  # <reason> (row <8 hex>)`, got: {line}" )
            found.append( m.group( 1 ) )
    gated = swept_dirs( root )
    for d in found:
        if d not in gated: raise ValueError( f"{EXEMPT_LIST}: {d} is not in {GATED_LIST}" )
    return found


def strict_dirs( root=ROOT ):
    """
    List the strict directories: every gated directory except the exempt ones.

    Requires:
        - root holds both list files

    Ensures:
        - returns gated directories in gated-list order, minus those in strict_exempt.txt
    """
    exempt = exempt_dirs( root )
    return [ d for d in swept_dirs( root ) if d not in exempt ]


def comment_segments( text ):
    """
    Split Dart source into numbered comment texts: line comments and block comments, trailing ones included.

    Requires:
        - text is Dart source; strings are not parsed, so a `//` inside a string literal starts a segment too

    Ensures:
        - returns ( line_number, comment_text ) pairs in source order, one per comment per line
        - a block comment that spans lines yields one pair per line, ended where `*/` closes it
        - the comment marker itself (`//`, `///`, `/*`) is part of the text
    """
    out, in_block = [], False
    for n, line in enumerate( text.splitlines(), 1 ):
        pos = 0
        while pos < len( line ):
            if in_block:
                end = line.find( "*/", pos )
                out.append( ( n, line[pos:] if end < 0 else line[pos:end] ) )
                if end < 0: break
                in_block, pos = False, end + 2
                continue
            a, b = line.find( "//", pos ), line.find( "/*", pos )
            if a < 0 and b < 0: break
            if a >= 0 and ( b < 0 or a < b ):
                out.append( ( n, line[a:] ) )
                break
            in_block, pos = True, b + 2
            out.append( ( n, "" ) )
    return out


def options_lines( path ):
    """
    Read an analysis options file as its meaningful lines.

    Requires:
        - path is a readable text file

    Ensures:
        - returns the lines with indentation kept, trailing spaces and ` # comment` tails dropped
        - drops blank lines and whole-line comments
    """
    out = []
    with open( path, encoding="utf-8" ) as f:
        for raw in f:
            line = re.sub( r"\s+#.*$", "", raw.rstrip() ).rstrip()
            if line.strip() and not line.lstrip().startswith( "#" ): out.append( line )
    return out


def options_problems( path, root=ROOT ):
    """
    Say how an options file that applies to a strict directory differs from the one allowed shape.

    Requires:
        - path is an analysis_options.yaml under root

    Ensures:
        - returns [] when the file is the root template (at the root) or the directory template: an `include:`
          that resolves to the root options file, then `linter: rules: public_member_api_docs: true`, nothing else
        - otherwise returns one message naming the file and each unexpected or missing line
        - so a rule switched off, a severity lowered, an exclude, a language or plugins entry, a second rule list
          or an include of another file is refused wherever it sits in the file
    """
    rel   = os.path.relpath( path, root )
    lines = options_lines( path )
    if os.path.dirname( rel ) == "":
        want = ROOT_TEMPLATE
    else:
        inc = lines[0] if lines and lines[0].startswith( "include:" ) else ""
        target = os.path.normpath( os.path.join( os.path.dirname( path ), inc.split( ":", 1 )[1].strip() ) ) if inc else ""
        ok  = target == os.path.join( os.path.normpath( root ), OPTIONS )
        want = [ lines[0] if ok else DIR_TEMPLATE[0] ] + DIR_TEMPLATE[1:]
    extra   = [ l.strip() for l in lines if l not in want ]
    missing = [ l.strip() for l in want if l not in lines ]
    if lines == want: return []
    detail  = []
    if extra: detail.append( "unexpected `" + "`, `".join( extra ) + "`" )
    if missing: detail.append( "missing `" + "`, `".join( missing ) + "`" )
    if not detail: detail.append( "lines are in a different order or shape" )
    return [ f"{rel}: options file may differ from the template only by comments ({'; '.join( detail )}); it can hide findings in a strict directory" ]


def strict_config_problems( dirs, root=ROOT ):
    """
    Find the ways a strict directory could read clean without being clean, other than the analyzer itself.

    Requires:
        - dirs is a list of repo-relative strict directories

    Ensures:
        - returns one message per problem, empty when none
        - checks, with options_problems, the root options file, every options file in an ancestor directory
          of a strict directory, and every options file anywhere under it (nested ones included)
        - flags an `ignore_for_file` comment, and an `ignore` comment whose reason after " - " is missing or only
          placeholder words (the list in tool/check_doc_ignores.py, reused), in any comment form: `//`, `///`,
          `////`, `/* */`, trailing, indented, any spacing or case; this includes public_member_api_docs ignores
    """
    problems = []
    files    = set()
    if dirs: files.add( os.path.join( root, OPTIONS ) )
    for d in dirs:
        up = os.path.dirname( d )
        while up:
            files.add( os.path.join( root, up, OPTIONS ) )
            up = os.path.dirname( up )
        for here, _dirs, names in os.walk( os.path.join( root, d ) ):
            if OPTIONS in names: files.add( os.path.join( here, OPTIONS ) )
    for path in sorted( files ):
        if os.path.exists( path ): problems += options_problems( path, root )
    for d in dirs:
        for here, _dirs, names in os.walk( os.path.join( root, d ) ):
            for name in names:
                if not name.endswith( ".dart" ): continue
                full = os.path.join( here, name )
                with open( full, encoding="utf-8" ) as f: text = f.read()
                for n, comment in comment_segments( text ):
                    m = IGNORE_CMT.search( comment )
                    if not m: continue
                    where = f"{os.path.relpath( full, root )}:{n}"
                    if m.group( "file" ):
                        problems.append( f"{where}: ignore_for_file is refused in a strict directory" )
                        continue
                    parts  = ignores.SEPARATOR.split( m.group( "body" ), 1 )
                    reason = ignores.reason_problem( parts[1] if len( parts ) > 1 else "" )
                    if reason: problems.append( f"{where}: ignore comment in a strict directory needs a real reason after ' - ': {reason}" )
    return problems


def strict_findings( machine_output, dirs, root=ROOT ):
    """
    Turn `dart analyze --format=machine` output into one readable line per finding.

    Requires:
        - machine_output is the analyzer's stdout; dirs are the strict directories that were analyzed

    Ensures:
        - returns `<dir>: <RULE> <file>:<line> <message>` for every finding line, in input order
        - names the directory the file sits in, or "?" when it sits in none of dirs
        - ignores any line that is not a finding
    """
    out = []
    for line in machine_output.splitlines():
        f = PIPE.split( line )
        if len( f ) < 8: continue
        rel = os.path.relpath( f[3], root ) if os.path.isabs( f[3] ) else f[3]
        d   = next( ( x for x in dirs if rel.startswith( x + "/" ) ), "?" )
        out.append( f"{d}: {f[2].lower()} {rel}:{f[4]} {f[7].replace( chr( 92 ) + '|', '|' )}" )
    return out


def check_strict( dirs, root=ROOT ):
    """
    Run the analyzer over the strict directories and fail on ANY finding.

    Requires:
        - dirs is a list of repo-relative directories, each gated and not exempt

    Ensures:
        - returns True when the config checks pass and the analyzer reports nothing
        - returns False, after printing each problem, when a finding or a config problem exists
        - returns False when the analyzer exits 1 to 3 but no finding line could be read (never reads that as clean)
        - returns False when the analyzer did not run to completion (exit outside 0 to 3)
        - returns True without running anything when dirs is empty
    """
    if not dirs: return True
    print( f"== strict (any finding): {' '.join( dirs )}", flush=True )
    problems = strict_config_problems( dirs, root )
    for p in problems: print( f"STRICT config: {p}" )
    proc = subprocess.run( [ dart_cmd( root ), "analyze", "--fatal-infos", "--format=machine", *dirs ],
                           cwd=root, capture_output=True, text=True )
    if proc.returncode not in ( 0, 1, 2, 3 ):
        print( f"analyzer did not finish (exit {proc.returncode}):\n{proc.stdout}{proc.stderr}", file=sys.stderr )
        return False
    found = strict_findings( proc.stdout, dirs, root )
    for l in found: print( f"STRICT {l}" )
    if proc.returncode != 0 and not found:
        print( f"analyzer exited {proc.returncode} but no finding could be read:\n{proc.stdout}", file=sys.stderr )
        return False
    if found: print( f"{len( found )} finding(s) in strict directories", file=sys.stderr )
    return not found and not problems


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
                     help="run checks 3 and 4 over every gated directory, ignoring the staged changes (CI)" )
    ap.add_argument( "--base", metavar="REF",
                     help="with --docs-all: read the two lists as they were at the merge base with REF, so this change cannot loosen its own gate" )
    args = ap.parse_args( argv )
    swept = swept_dirs( root )
    missing = listed_but_missing( root )
    if missing and not args.list:
        for m in missing: print( f"BLOCKED: {m}", file=sys.stderr )
        return 1
    if args.list:
        print( "\n".join( swept ) )
        return 0
    if args.docs_all:
        if args.base:
            try: swept, exempt = effective_lists( root, merge_base( args.base, root ) )
            except RuntimeError as e:
                print( f"BLOCKED: {e}", file=sys.stderr )
                return 1
        else:
            exempt = exempt_dirs( root )
        docs   = check_docs( [ d for d in swept if d in exempt ], root )
        strict = check_strict( [ d for d in swept if d not in exempt ], root )
        return 0 if docs and strict else 1
    staged  = staged_paths( root )
    results = [
        run_check( "doc linter (staged lines)",
                   [ sys.executable, "tool/lint_dart_docs.py", "--staged", "--strict" ], root ),
        run_check( "ignore checker",
                   [ sys.executable, "tool/check_doc_ignores.py" ], root ),
    ]
    docs_only, strict = partition_touched( staged, root )
    results.append( check_docs( docs_only, root ) )
    results.append( check_strict( strict, root ) )
    if all( results ): return 0
    print( "\nBLOCKED: fix the failures above, or bypass once with `git commit --no-verify` (CI still checks).",
           file=sys.stderr )
    return 1


if __name__ == "__main__":
    sys.exit( main() )
