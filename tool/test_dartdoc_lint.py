"""
Tests for the vendored Dart doc linter (tool/doc_lint). Run: pytest tool/test_dartdoc_lint.py

The positive control is a block that must yield a named finding; the clean block must yield none.
Neither test needs a lupin checkout or LUPIN_ROOT.
"""

import io
import json
import os
import subprocess
import sys

TOOL = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, TOOL )

from doc_lint.dartdoc_lint import lint_source, main
from doc_lint.word_list import WORD_LIST_PATH, default_words

BAD_BLOCK   = "/// Never call this twice.\n/// The value is NEVER cached.\nint f() => 1;\n"
CLEAN_BLOCK = "/// Returns the cached count.\n///\n/// The count resets when the queue is cleared.\nint g() => 1;\n"


def test_word_list_lives_in_tool_tree():
    """The list is read from tool/data/, not from the linted tree."""
    assert os.path.abspath( WORD_LIST_PATH ).startswith( TOOL + os.sep )
    assert "never" in default_words()


def test_positive_control_names_caps_finding():
    """A lowercase-word in capitals must produce a finding named caps."""
    findings = lint_source( "lib/a.dart", BAD_BLOCK )
    assert [ f.rule for f in findings ] == [ "caps" ]
    assert findings[ 0 ].line == 2


def test_clean_block_yields_nothing():
    """The negative control: ordinary prose produces no finding."""
    assert lint_source( "lib/a.dart", CLEAN_BLOCK ) == []


def test_runs_in_bare_environment_on_repo_without_word_list( tmp_path ):
    """Whole entry point, LUPIN_ROOT unset, linted repo holds no word list."""
    repo = tmp_path / "r"
    ( repo / "lib" ).mkdir( parents=True )
    ( repo / "lib" / "bad.dart" ).write_text( BAD_BLOCK )
    ( repo / "lib" / "ok.dart" ).write_text( CLEAN_BLOCK )
    subprocess.run( [ "git", "-C", str( repo ), "init", "-q" ], check=True )
    subprocess.run( [ "git", "-C", str( repo ), "add", "." ], check=True )
    env = { k: v for k, v in os.environ.items() if k != "LUPIN_ROOT" }
    res = subprocess.run( [ sys.executable, os.path.join( TOOL, "lint_dart_docs.py" ), "--json", "--repo-root", str( repo ) ],
                          capture_output=True, text=True, env=env, cwd=str( tmp_path ) )
    assert res.returncode == 0, res.stderr
    found = json.loads( res.stdout )
    assert [ ( f[ "path" ], f[ "rule" ] ) for f in found ] == [ ( "lib/bad.dart", "caps" ) ]


def test_strict_exit_code( tmp_path ):
    """--strict returns 1 when a finding remains."""
    repo = tmp_path / "r"
    ( repo / "lib" ).mkdir( parents=True )
    ( repo / "lib" / "bad.dart" ).write_text( BAD_BLOCK )
    subprocess.run( [ "git", "-C", str( repo ), "init", "-q" ], check=True )
    subprocess.run( [ "git", "-C", str( repo ), "add", "." ], check=True )
    assert main( [ "--strict", "--repo-root", str( repo ) ], io.StringIO() ) == 1


def test_marker_baseline_buckets():
    """build_marker_baseline files paths under the same buckets as doc_coverage_baseline."""
    import build_marker_baseline as bm
    assert bm.bucket( "lib/features/queue/a.dart" ) == ( "features", "features/queue" )
    assert bm.bucket( "lib/main.dart" ) == ( "(lib root)", None )
    assert bm.bucket( "test/unit/a_test.dart" ) == ( "test", None )
    assert bm.bucket( "integration_test/a.dart" ) == ( "(other)", None )
