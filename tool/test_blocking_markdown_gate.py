"""
Tests for the markdown step of tool/pre_commit_gate.py, which blocks the commit (lupin-mobile row 696b6744, plan step 5).

Run: python3 -m pytest tool/test_blocking_markdown_gate.py
A finding, a missing tool, a tool that cannot start, a tool that hangs and any non-zero exit each refuse the commit.
The repositories here are temporary and hold no src/conf/, so a linter that looked for its word list in the
linted tree would crash in them (the defect recorded on lupin row ec1854b7).
"""

import os
import shutil
import subprocess
import sys
import tempfile
import time

TOOL = os.path.dirname( os.path.abspath( __file__ ) )
ROOT = os.path.dirname( TOOL )
sys.path.insert( 0, TOOL )

import pre_commit_gate as gate

BAD_PAGE   = "# Notes\n\nThe value is NEVER cached.\n"
CLEAN_PAGE = "# Notes\n\nThe value is read once.\n"
GATE_TOOL  = "tool/markdown_gate.py"
STEP_NAME  = "markdown gate (staged pages)"


def make_repo( pages, with_gate=True ):
    """
    Create a temporary git repo that holds the markdown gate and the given staged pages.

    Requires:
        - pages maps a repo-relative path to its text

    Ensures:
        - returns the repo root, with every page staged
        - the scope file is empty, so every page is a reference page
        - with_gate False leaves tool/markdown_gate.py out
    """
    root = tempfile.mkdtemp()
    subprocess.run( [ "git", "init", "-q" ], cwd=root, check=True )
    os.makedirs( os.path.join( root, "tool", "data" ) )
    shutil.copytree( os.path.join( TOOL, "doc_lint" ), os.path.join( root, "tool", "doc_lint" ),
                     ignore=shutil.ignore_patterns( "__pycache__" ) )
    shutil.copy( os.path.join( TOOL, "data", "dm-tutor-lowercase-words.txt" ), os.path.join( root, "tool", "data" ) )
    if with_gate: shutil.copy( os.path.join( TOOL, "markdown_gate.py" ), os.path.join( root, "tool" ) )
    with open( os.path.join( root, "tool", "data", "markdown_scope.txt" ), "w", encoding="utf-8" ) as f: f.write( "" )
    for rel, text in pages.items():
        with open( os.path.join( root, rel ), "w", encoding="utf-8" ) as f: f.write( text )
    subprocess.run( [ "git", "add", "tool/data/markdown_scope.txt", *pages ], cwd=root, check=True )
    return root


def run_main_with_dart_checks_passing( root ):
    """
    Run the gate's main with every Dart check stubbed to pass, so only the markdown step is real.

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


def overwrite_tool( root, text ):
    """
    Replace the copied markdown gate with a stub.

    Requires:
        - root is a repo from make_repo
    """
    with open( os.path.join( root, "tool", "markdown_gate.py" ), "w", encoding="utf-8" ) as f: f.write( text )


def test_a_staged_page_with_findings_refuses_the_commit( capfd ):
    # Refuted if main returns 0: the staged page holds an ALL-CAPS word.
    root = make_repo( { "notes.md": BAD_PAGE } )
    code = run_main_with_dart_checks_passing( root )
    out, err = capfd.readouterr()
    assert code == 1
    assert "REFUSED notes.md:3: caps" in out
    assert f"BLOCKED: {STEP_NAME}: exited 1" in err


def test_a_clean_staged_page_passes( capfd ):
    # Refuted if main returns 1 or prints a BLOCKED line for a clean page.
    root = make_repo( { "notes.md": CLEAN_PAGE } )
    code = run_main_with_dart_checks_passing( root )
    out, err = capfd.readouterr()
    assert code == 0
    assert "0 refused" in out
    assert "BLOCKED" not in err


def test_a_missing_tool_refuses_the_commit_with_one_line_naming_the_cause( capfd ):
    # Refuted if main returns 0 when tool/markdown_gate.py is absent, or the line does not say "is missing".
    root = make_repo( { "notes.md": CLEAN_PAGE }, with_gate=False )
    code = run_main_with_dart_checks_passing( root )
    _, err = capfd.readouterr()
    assert code == 1
    assert f"BLOCKED: {STEP_NAME}: {GATE_TOOL} is missing, check NOT run" in err


def test_an_interpreter_that_cannot_start_refuses_the_commit( capfd ):
    # Refuted if block_check returns True for an interpreter that does not exist.
    root = make_repo( { "notes.md": CLEAN_PAGE } )
    assert gate.block_check( STEP_NAME, [ os.path.join( root, "no-such-python" ), GATE_TOOL ], root ) is False
    _, err = capfd.readouterr()
    assert "could not start" in err and "check NOT run" in err


def test_a_tool_that_crashes_refuses_the_commit( capfd ):
    # Refuted if main returns 0 when the tool raises: a crash exits 1 and must not read as a pass.
    root = make_repo( { "notes.md": CLEAN_PAGE } )
    overwrite_tool( root, "raise RuntimeError( 'boom' )\n" )
    code = run_main_with_dart_checks_passing( root )
    _, err = capfd.readouterr()
    assert code == 1
    assert "RuntimeError: boom" in err
    assert f"BLOCKED: {STEP_NAME}: exited 1" in err


def test_a_tool_that_exits_above_one_refuses_the_commit_and_names_the_code( capfd ):
    # Refuted if main returns 0, or the line names a different exit code.
    root = make_repo( { "notes.md": CLEAN_PAGE } )
    overwrite_tool( root, "raise SystemExit( 2 )\n" )
    code = run_main_with_dart_checks_passing( root )
    _, err = capfd.readouterr()
    assert code == 1
    assert f"BLOCKED: {STEP_NAME}: exited 2" in err


def test_a_tool_that_hangs_is_stopped_and_the_commit_is_refused( capfd ):
    # Refuted if main returns 0, or the run waits the whole 30 s the stub sleeps.
    root = make_repo( { "notes.md": CLEAN_PAGE } )
    overwrite_tool( root, "import time\ntime.sleep( 30 )\n" )
    orig = gate.MARKDOWN_TIMEOUT_SECONDS
    gate.MARKDOWN_TIMEOUT_SECONDS = 1
    began = time.time()
    try:
        code = run_main_with_dart_checks_passing( root )
    finally:
        gate.MARKDOWN_TIMEOUT_SECONDS = orig
    _, err = capfd.readouterr()
    assert code == 1
    assert time.time() - began < 20
    assert f"BLOCKED: {STEP_NAME}: still running after 1 s, stopped" in err


def test_a_hung_tool_is_stopped_together_with_the_processes_it_started( capfd ):
    # Refuted if the grandchild process is still alive 5 s after the refusal.
    root = make_repo( { "notes.md": CLEAN_PAGE } )
    overwrite_tool( root, ( "import subprocess, sys, time\n"
                            "child = subprocess.Popen( [ sys.executable, '-c', 'import time; time.sleep( 60 )' ] )\n"
                            "open( 'child.pid', 'w' ).write( str( child.pid ) )\n"
                            "time.sleep( 60 )\n" ) )
    orig = gate.MARKDOWN_TIMEOUT_SECONDS
    gate.MARKDOWN_TIMEOUT_SECONDS = 2
    try:
        code = run_main_with_dart_checks_passing( root )
    finally:
        gate.MARKDOWN_TIMEOUT_SECONDS = orig
    capfd.readouterr()
    assert code == 1
    with open( os.path.join( root, "child.pid" ), encoding="utf-8" ) as f: pid = int( f.read() )
    alive = True
    for _ in range( 50 ):
        try:
            with open( f"/proc/{pid}/stat", encoding="utf-8" ) as f: alive = f.read().split( ") ", 1 )[ 1 ][ 0 ] != "Z"
        except OSError:
            alive = False
        if not alive: break
        time.sleep( 0.1 )
    assert not alive


def test_the_markdown_step_blocks_on_its_own_when_the_dart_checks_pass():
    # Refuted if main's result ignores the markdown step's result (the step ran and its False was dropped).
    root = make_repo( { "notes.md": BAD_PAGE } )
    assert run_main_with_dart_checks_passing( root ) == 1


def test_a_dart_check_still_blocks_with_the_markdown_step_clean():
    # Refuted if main returns 0: check_docs fails while the markdown page is clean.
    root = make_repo( { "notes.md": CLEAN_PAGE } )
    names = ( "run_check", "check_docs", "check_strict", "staged_paths", "swept_dirs", "exempt_dirs", "listed_but_missing" )
    keep  = { n: getattr( gate, n ) for n in names }
    gate.run_check          = lambda name, cmd, root=None: True
    gate.check_docs         = lambda dirs, root=None: False
    gate.check_strict       = lambda dirs, root=None: True
    gate.staged_paths       = lambda root=None: [ "notes.md" ]
    gate.swept_dirs         = lambda root=None: []
    gate.exempt_dirs        = lambda root=None: []
    gate.listed_but_missing = lambda root=None: []
    try:
        assert gate.main( [], root=root ) == 1
    finally:
        for n in names: setattr( gate, n, keep[ n ] )


def test_only_staged_lines_of_a_record_lines_page_are_refused( capfd ):
    # Refuted if the commit is refused for the old bad line: history.md is listed record-lines in this repo.
    root = make_repo( { "history.md": BAD_PAGE } )
    with open( os.path.join( root, "tool", "data", "markdown_scope.txt" ), "w", encoding="utf-8" ) as f: f.write( "record-lines history.md\n" )
    subprocess.run( [ "git", "add", "tool/data/markdown_scope.txt" ], cwd=root, check=True )
    subprocess.run( [ "git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--no-verify", "-m", "base" ], cwd=root, check=True )
    with open( os.path.join( root, "history.md" ), "a", encoding="utf-8" ) as f: f.write( "\nA second line that is fine.\n" )
    subprocess.run( [ "git", "add", "history.md" ], cwd=root, check=True )
    code = run_main_with_dart_checks_passing( root )
    out, err = capfd.readouterr()
    assert code == 0
    assert "NEVER" not in out
    assert "BLOCKED" not in err


def test_the_gate_runs_with_this_repository_as_its_root():
    # Refuted if the gate crashes on the real scope file or the real linter files: it exits 2 or prints a traceback.
    done = subprocess.run( [ sys.executable, GATE_TOOL, "--staged" ], cwd=ROOT, capture_output=True, text=True )
    assert done.returncode in ( 0, 1 ), done.stderr
    assert "Traceback" not in done.stderr


def test_the_committed_hook_runs_the_gate():
    hook = os.path.join( TOOL, "hooks", "pre-commit" )
    assert os.access( hook, os.X_OK )
    with open( hook, encoding="utf-8" ) as f: assert "tool/pre_commit_gate.py" in f.read()
