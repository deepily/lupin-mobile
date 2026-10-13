"""
The R&D ledger covers each document under src/rnd that was present at the ledger's sha.

Run: python3 -m pytest tool/test_rnd_ledger.py
The ledger is src/docs/rnd-ledger.tsv, in the shape of lupin's ledger: columns path, class, reason, date, sha.
It is the mobile half of the R&D triage exit gate in lupin's documentation rewrite plan.

The population comes from git and never from the ledger. The required set is the tracked files under src/rnd
that were also present at the sha the ledger names. A document added after that sha needs no row until the
next sweep, so this file stays green when a seat adds a document between sweeps. In the ledger itself the
class `new` marks a document that would be history but is still cited by a file that holds it.

Each check is also run against a broken ledger, so a green result on the real tree means the check can fail.
This file does not assert that any class in the ledger is right.
"""

import csv
import os
import re
import subprocess

TOOL       = os.path.dirname( os.path.abspath( __file__ ) )
ROOT       = os.path.dirname( TOOL )
LEDGER_REL = "src/docs/rnd-ledger.tsv"
RND_ROOT   = "src/rnd/"
COLUMNS    = [ "path", "class", "reason", "date", "sha" ]
CLASSES    = frozenset( { "in force", "superseded", "history", "new", "follows folder" } )
DATE       = re.compile( r"^\d{4}-\d{2}-\d{2}$" )


def git_lines( root, *args ):
    """
    Run one git command in a tree and return its output lines.

    Requires:
        - root is a git working tree

    Ensures:
        - returns the non-empty stdout lines

    Raises:
        - subprocess.CalledProcessError when git exits non-zero
    """
    out = subprocess.run( [ "git", *args ], cwd=root, capture_output=True, text=True, check=True ).stdout
    return [ line for line in out.split( "\n" ) if line ]


def read_ledger( path ):
    """
    Read the ledger into its header and its rows.

    Requires:
        - path is a tab-separated file with a header line

    Ensures:
        - returns ( header list, list of row dicts keyed by the header )
        - each row dict also carries _fields, the number of fields on its line

    Raises:
        - OSError when the file cannot be read
    """
    with open( path, encoding="utf-8", newline="" ) as f:
        reader = csv.reader( f, delimiter="\t", quoting=csv.QUOTE_NONE )
        header = next( reader )
        return header, [ dict( zip( header, row ), _fields=len( row ) ) for row in reader ]


def coverage_problems( rows, tracked_now, tracked_at_sha ):
    """
    List what is wrong with the ledger's coverage of the R&D documents.

    Requires:
        - rows is the ledger's row dicts
        - tracked_now and tracked_at_sha are the paths under src/rnd tracked today and at the ledger's sha

    Ensures:
        - names each required document with no row, each path with more than one row,
          each row whose path was not a tracked R&D document at the ledger's sha,
          and each row whose document is no longer tracked
        - returns an empty list when the coverage is exact

    Raises:
        - nothing
    """
    required = set( tracked_now ) & set( tracked_at_sha )
    counts   = {}
    for row in rows: counts[ row[ "path" ] ] = counts.get( row[ "path" ], 0 ) + 1
    problems  = [ f"no row: {p}" for p in sorted( required ) if p not in counts ]
    problems += [ f"{n} rows: {p}" for p, n in sorted( counts.items() ) if n > 1 ]
    problems += [ f"row for a path not under {RND_ROOT} at the ledger's sha: {p}" for p in sorted( counts ) if p not in set( tracked_at_sha ) ]
    problems += [ f"row for a document that is no longer tracked: {p}" for p in sorted( counts ) if p in set( tracked_at_sha ) and p not in set( tracked_now ) ]
    return problems


def row_problems( header, rows ):
    """
    List what is wrong with the ledger's columns and values.

    Requires:
        - header is the ledger's first line as a list, rows its row dicts

    Ensures:
        - names a wrong header, a row with a missing, empty or extra field, an unknown class,
          a date that is not yyyy-mm-dd and a second sha
        - returns an empty list when every row is well formed

    Raises:
        - nothing
    """
    if header != COLUMNS: return [ f"header is {header}, expected {COLUMNS}" ]
    problems = []
    for n, row in enumerate( rows, start=2 ):
        if row[ "_fields" ] != len( COLUMNS ) or any( not row.get( c ) for c in COLUMNS ): problems.append( f"line {n}: a field is missing, empty or extra" )
        elif row[ "class" ] not in CLASSES: problems.append( f"line {n}: unknown class '{row[ 'class' ]}'" )
        elif not DATE.match( row[ "date" ] ): problems.append( f"line {n}: date '{row[ 'date' ]}' is not yyyy-mm-dd" )
    shas = sorted( { row.get( "sha", "" ) for row in rows } )
    if len( shas ) != 1: problems.append( f"the ledger names {len( shas )} shas, expected 1" )
    return problems


def real_ledger():
    """
    Read the real ledger and the two git populations it is checked against.

    Requires:
        - the repository holds the ledger and the commit its rows name

    Ensures:
        - returns ( header, rows, tracked_now, tracked_at_sha )

    Raises:
        - subprocess.CalledProcessError when the ledger's sha is not in this repository
    """
    header, rows = read_ledger( os.path.join( ROOT, LEDGER_REL ) )
    sha          = rows[ 0 ][ "sha" ]
    return header, rows, git_lines( ROOT, "ls-files", RND_ROOT ), git_lines( ROOT, "ls-tree", "-r", "--name-only", sha, RND_ROOT )


def test_every_document_present_at_the_ledger_sha_has_exactly_one_row():
    header, rows, now, then = real_ledger()
    assert coverage_problems( rows, now, then ) == []


def test_every_row_is_well_formed_and_names_one_sha():
    header, rows, now, then = real_ledger()
    assert row_problems( header, rows ) == []


def test_the_population_is_not_empty():
    header, rows, now, then = real_ledger()
    assert len( set( now ) & set( then ) ) > 100


def test_a_removed_row_is_reported():
    header, rows, now, then = real_ledger()
    assert coverage_problems( rows[ 1: ], now, then ) == [ f"no row: {rows[ 0 ][ 'path' ]}" ]


def test_a_repeated_row_is_reported():
    header, rows, now, then = real_ledger()
    assert coverage_problems( rows + rows[ :1 ], now, then ) == [ f"2 rows: {rows[ 0 ][ 'path' ]}" ]


def test_a_row_for_a_file_outside_the_population_is_reported():
    header, rows, now, then = real_ledger()
    extra = dict( rows[ 0 ], path="lib/main.dart" )
    assert coverage_problems( rows + [ extra ], now, then ) == [ f"row for a path not under {RND_ROOT} at the ledger's sha: lib/main.dart" ]


def test_a_row_for_a_document_deleted_since_the_ledger_sha_is_reported():
    header, rows, now, then = real_ledger()
    gone = rows[ 0 ][ "path" ]
    assert coverage_problems( rows, [ p for p in now if p != gone ], then ) == [ f"row for a document that is no longer tracked: {gone}" ]


def test_a_document_added_after_the_ledger_sha_needs_no_row():
    header, rows, now, then = real_ledger()
    assert coverage_problems( rows, now + [ "src/rnd/2099.01.01-added-later.md" ], then ) == []


def test_an_unknown_class_an_empty_field_a_second_sha_and_a_wrong_header_are_reported():
    header, rows, now, then = real_ledger()
    assert row_problems( header, [ dict( rows[ 0 ], **{ "class": "archived" } ) ] ) == [ "line 2: unknown class 'archived'" ]
    assert row_problems( header, [ dict( rows[ 0 ], reason="" ) ] ) == [ "line 2: a field is missing, empty or extra" ]
    assert row_problems( header, [ dict( rows[ 0 ], _fields=6 ) ] ) == [ "line 2: a field is missing, empty or extra" ]
    assert row_problems( header, [ dict( rows[ 0 ], date="13 Oct" ) ] ) == [ "line 2: date '13 Oct' is not yyyy-mm-dd" ]
    assert row_problems( header, [ rows[ 0 ], dict( rows[ 1 ], sha="0" * 40 ) ] ) == [ "the ledger names 2 shas, expected 1" ]
    assert row_problems( header[ :4 ], rows ) == [ f"header is {header[ :4 ]}, expected {COLUMNS}" ]
