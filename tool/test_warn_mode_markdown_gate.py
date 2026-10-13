"""
Tests for the warn-mode markdown step of tool/pre_commit_gate.py (lupin plan 1, phase 1 step 10).

Run: python3 -m pytest tool/test_warn_mode_markdown_gate.py
Warn mode means the step reports what it finds and the commit goes on, also when the tool is missing or crashes.
The repositories here are temporary and hold no src/conf/, so a linter that looked for its word list in the
linted tree would crash in them (the defect recorded on lupin row ec1854b7).
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

TOOL = os.path.dirname( os.path.abspath( __file__ ) )
ROOT = os.path.dirname( TOOL )
sys.path.insert( 0, TOOL )

import pre_commit_gate as gate

BAD_PAGE   = "# Notes\n\nThe value is NEVER cached.\n"
CLEAN_PAGE = "# Notes\n\nThe value is read once.\n"


def make_repo( pages, with_linter=True ):
    """
    Create a temporary git repo that holds the vendored linter and the given staged pages.

    Requires:
        - pages maps a repo-relative path to its text

    Ensures:
        - returns the repo root, with every page staged
        - with_linter False leaves tool/lint_markdown.py out
    """
    root = tempfile.mkdtemp()
    subprocess.run( [ "git", "init", "-q" ], cwd=root, check=True )
    if with_linter:
        os.makedirs( os.path.join( root, "tool", "data" ) )
        shutil.copytree( os.path.join( TOOL, "doc_lint" ), os.path.join( root, "tool", "doc_lint" ),
                         ignore=shutil.ignore_patterns( "__pycache__" ) )
        shutil.copy( os.path.join( TOOL, "lint_markdown.py" ), os.path.join( root, "tool" ) )
        shutil.copy( os.path.join( TOOL, "data", "dm-tutor-lowercase-words.txt" ), os.path.join( root, "tool", "data" ) )
    for rel, text in pages.items():
        with open( os.path.join( root, rel ), "w", encoding="utf-8" ) as f: f.write( text )
    subprocess.run( [ "git", "add", *pages ], cwd=root, check=True )
    return root


def run_main_with_blocking_checks_passing( root ):
    """
    Run the gate's main with every blocking check stubbed to pass, so only the warn-mode step is real.

    Requires:
        - root is a repo from make_repo

    Ensures:
        - returns main's exit code
        - restores the stubbed functions
    """
    names = ( "run_check", "check_docs", "check_strict", "staged_paths", "swept_dirs", "exempt_dirs", "listed_but_missing" )
    orig  = { n: getattr( gate, n ) for n in names }
    gate.run_check          = lambda name, cmd, root=None: True
    gate.check_docs         = lambda dirs, root=None: True
    gate.check_strict       = lambda dirs, root=None: True
    gate.staged_paths       = lambda root=None: [ "notes.md" ]
    gate.swept_dirs         = lambda root=None: []
    gate.exempt_dirs        = lambda root=None: []
    gate.listed_but_missing = lambda root=None: []
    try:
        return gate.main( [], root=root )
    finally:
        for n in names: setattr( gate, n, orig[ n ] )


def test_a_staged_page_with_findings_is_reported_and_the_commit_goes_on( capfd ):
    root = make_repo( { "notes.md": BAD_PAGE } )
    code = run_main_with_blocking_checks_passing( root )
    out, err = capfd.readouterr()
    assert code == 0
    assert "notes.md:3: caps: ALL-CAPS word NEVER" in out
    assert "WARN: markdown linter (staged lines): exited 1, commit allowed (warn mode)" in err
    assert "FileNotFoundError" not in err


def test_a_clean_staged_page_prints_no_warn_line( capfd ):
    root = make_repo( { "notes.md": CLEAN_PAGE } )
    code = run_main_with_blocking_checks_passing( root )
    out, err = capfd.readouterr()
    assert code == 0
    assert "0 findings in 1 files" in out
    assert "WARN" not in err


def test_a_missing_linter_prints_a_loud_line_and_the_commit_goes_on( capfd ):
    root = make_repo( { "notes.md": BAD_PAGE }, with_linter=False )
    code = run_main_with_blocking_checks_passing( root )
    _, err = capfd.readouterr()
    assert code == 0
    assert "WARN: markdown linter (staged lines): tool/lint_markdown.py is missing, check NOT run, commit allowed" in err


def test_a_linter_that_crashes_leaves_the_commit_open( capfd ):
    root = make_repo( { "notes.md": BAD_PAGE } )
    with open( os.path.join( root, "tool", "lint_markdown.py" ), "w", encoding="utf-8" ) as f: f.write( "raise RuntimeError( 'boom' )\n" )
    code = run_main_with_blocking_checks_passing( root )
    _, err = capfd.readouterr()
    assert code == 0
    assert "RuntimeError: boom" in err
    assert "exited 1, commit allowed (warn mode)" in err


def test_an_interpreter_that_cannot_start_leaves_the_commit_open( capfd ):
    root = make_repo( { "notes.md": BAD_PAGE } )
    assert gate.warn_check( "markdown linter", [ os.path.join( root, "no-such-python" ), "tool/lint_markdown.py" ], root ) is True
    _, err = capfd.readouterr()
    assert "could not start" in err and "check NOT run, commit allowed" in err


def test_a_blocking_failure_still_blocks_with_the_warn_step_present():
    root = make_repo( { "notes.md": CLEAN_PAGE } )
    orig = gate.check_docs
    gate.check_docs = lambda dirs, root=None: False
    names = ( "run_check", "check_strict", "staged_paths", "swept_dirs", "exempt_dirs", "listed_but_missing" )
    keep  = { n: getattr( gate, n ) for n in names }
    gate.run_check          = lambda name, cmd, root=None: True
    gate.check_strict       = lambda dirs, root=None: True
    gate.staged_paths       = lambda root=None: [ "notes.md" ]
    gate.swept_dirs         = lambda root=None: []
    gate.exempt_dirs        = lambda root=None: []
    gate.listed_but_missing = lambda root=None: []
    try:
        assert gate.main( [], root=root ) == 1
    finally:
        gate.check_docs = orig
        for n in names: setattr( gate, n, keep[ n ] )


def test_only_staged_lines_are_reported( capfd ):
    root = make_repo( { "notes.md": BAD_PAGE } )
    subprocess.run( [ "git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--no-verify", "-m", "base" ], cwd=root, check=True )
    with open( os.path.join( root, "notes.md" ), "a", encoding="utf-8" ) as f: f.write( "\nA second line that is fine.\n" )
    subprocess.run( [ "git", "add", "notes.md" ], cwd=root, check=True )
    code = run_main_with_blocking_checks_passing( root )
    out, err = capfd.readouterr()
    assert code == 0
    assert "NEVER" not in out
    assert "WARN" not in err


def test_a_linter_that_exits_above_one_leaves_the_commit_open( capfd ):
    root = make_repo( { "notes.md": BAD_PAGE } )
    with open( os.path.join( root, "tool", "lint_markdown.py" ), "w", encoding="utf-8" ) as f: f.write( "raise SystemExit( 2 )\n" )
    code = run_main_with_blocking_checks_passing( root )
    _, err = capfd.readouterr()
    assert code == 0
    assert "exited 2, commit allowed (warn mode)" in err


def test_a_linter_that_hangs_is_stopped_and_the_commit_goes_on( capfd ):
    root = make_repo( { "notes.md": BAD_PAGE } )
    with open( os.path.join( root, "tool", "lint_markdown.py" ), "w", encoding="utf-8" ) as f: f.write( "import time\ntime.sleep( 30 )\n" )
    orig = gate.WARN_TIMEOUT_SECONDS
    gate.WARN_TIMEOUT_SECONDS = 1
    try:
        code = run_main_with_blocking_checks_passing( root )
    finally:
        gate.WARN_TIMEOUT_SECONDS = orig
    _, err = capfd.readouterr()
    assert code == 0
    assert "still running after 1 s, stopped, commit allowed" in err


def test_the_linter_runs_with_this_repository_as_its_root():
    assert os.path.isfile( os.path.join( ROOT, "CLAUDE.md" ) )
    done = subprocess.run( [ sys.executable, "tool/lint_markdown.py", "CLAUDE.md" ], cwd=ROOT, capture_output=True, text=True )
    assert done.returncode == 0, done.stderr
    assert re.search( r"^\d+ findings in 1 files$", done.stdout, re.MULTILINE )
    assert "Traceback" not in done.stderr


def test_the_committed_hook_runs_the_gate():
    hook = os.path.join( TOOL, "hooks", "pre-commit" )
    assert os.access( hook, os.X_OK )
    with open( hook, encoding="utf-8" ) as f: assert "tool/pre_commit_gate.py" in f.read()
