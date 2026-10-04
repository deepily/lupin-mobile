#!/usr/bin/env python3
"""Unit test for tool/pre_commit_gate.py — run: python3 -m pytest tool/test_pre_commit_gate.py"""
import os, subprocess, sys, tempfile, unittest
sys.path.insert( 0, os.path.dirname( os.path.abspath( __file__ ) ) )
import pre_commit_gate as gate


def make_repo( files ):
    """Create a temp git repo holding { relative path: text } and return its root."""
    root = tempfile.mkdtemp()
    subprocess.run( [ "git", "init", "-q" ], cwd=root, check=True )
    for rel, text in files.items():
        path = os.path.join( root, rel )
        os.makedirs( os.path.dirname( path ), exist_ok=True )
        with open( path, "w", encoding="utf-8" ) as f: f.write( text )
    return root


class PreCommitGateTest( unittest.TestCase ):

    def test_all_swept_dirs_needs_own_options_file( self ):
        root = make_repo( { "lib/analysis_options.yaml": "", "lib/core/analysis_options.yaml": "",
                            "lib/core/a.dart": "", "lib/features/auth/analysis_options.yaml": "",
                            "lib/features/home/h.dart": "" } )
        self.assertEqual( gate.all_swept_dirs( root ), [ "lib/core", "lib/features/auth" ] )

    def test_gated_list_skips_comments_and_reads_left_out_counts( self ):
        root = make_repo( { "tool/data/gated_dirs.txt":
                            "# header\nlib/features/auth\n\n# left out: lib/core 374 (measured at x)\n" } )
        self.assertEqual( gate.swept_dirs( root ), [ "lib/features/auth" ] )
        self.assertEqual( gate.left_out_dirs( root ), { "lib/core": 374 } )

    def test_every_swept_dir_in_this_repo_is_gated( self ):
        self.assertEqual( set( gate.all_swept_dirs() ) - set( gate.swept_dirs() ), set() )
        self.assertEqual( gate.left_out_dirs(), {} )

    def test_every_gated_dir_enables_public_member_api_docs( self ):
        for d in gate.swept_dirs():
            with open( os.path.join( gate.ROOT, d, gate.OPTIONS ), encoding="utf-8" ) as f:
                self.assertIn( "public_member_api_docs", f.read(), d )

    def test_touched_dirs_matches_whole_segments( self ):
        swept = [ "lib/core", "lib/features/auth" ]
        self.assertEqual( gate.touched_dirs( [ "lib/core_extra/x.dart" ], swept ), [] )
        self.assertEqual( gate.touched_dirs( [ "lib/core/a.dart", "lib/core/b.dart" ], swept ), [ "lib/core" ] )
        self.assertEqual( gate.touched_dirs( [ "README.md" ], swept ), [] )

    def test_staged_paths_excludes_deletions( self ):
        root = make_repo( { "lib/core/a.dart": "x", "lib/core/b.dart": "y" } )
        subprocess.run( [ "git", "add", "." ], cwd=root, check=True )
        subprocess.run( [ "git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base" ], cwd=root, check=True )
        os.remove( os.path.join( root, "lib/core/b.dart" ) )
        with open( os.path.join( root, "lib/core/a.dart" ), "w" ) as f: f.write( "z" )
        subprocess.run( [ "git", "add", "-A" ], cwd=root, check=True )
        self.assertEqual( gate.staged_paths( root ), [ "lib/core/a.dart" ] )

    def test_run_check_reports_exit_code( self ):
        self.assertTrue( gate.run_check( "ok", [ sys.executable, "-c", "pass" ] ) )
        self.assertFalse( gate.run_check( "bad", [ sys.executable, "-c", "raise SystemExit(3)" ] ) )

    def test_main_blocks_when_any_check_fails_but_runs_all( self ):
        calls = []
        orig  = ( gate.run_check, gate.staged_paths, gate.swept_dirs, gate.exempt_dirs, gate.check_docs, gate.check_strict )
        gate.run_check    = lambda name, cmd, root=None: calls.append( name ) or name.startswith( "ignore" )
        gate.check_docs   = lambda dirs, root=None: calls.append( "docs" ) or True
        gate.check_strict = lambda dirs, root=None: calls.append( "strict" ) or True
        gate.staged_paths = lambda root=None: [ "lib/core/a.dart" ]
        gate.swept_dirs   = lambda root=None: [ "lib/core" ]
        gate.exempt_dirs  = lambda root=None: []
        try:
            code = gate.main( [] )
        finally:
            gate.run_check, gate.staged_paths, gate.swept_dirs, gate.exempt_dirs, gate.check_docs, gate.check_strict = orig
        self.assertEqual( code, 1 )
        self.assertEqual( calls, [ "doc linter (staged lines)", "ignore checker", "docs", "strict" ] )

    def test_main_passes_when_all_checks_pass_and_skips_untouched_dirs( self ):
        calls = []
        orig  = ( gate.run_check, gate.staged_paths, gate.swept_dirs, gate.exempt_dirs, gate.check_docs, gate.check_strict )
        gate.run_check    = lambda name, cmd, root=None: calls.append( name ) or True
        gate.check_docs   = lambda dirs, root=None: calls.append( f"docs {dirs}" ) or True
        gate.check_strict = lambda dirs, root=None: calls.append( f"strict {dirs}" ) or True
        gate.staged_paths = lambda root=None: [ "README.md" ]
        gate.swept_dirs   = lambda root=None: [ "lib/core" ]
        gate.exempt_dirs  = lambda root=None: []
        try:
            code = gate.main( [] )
        finally:
            gate.run_check, gate.staged_paths, gate.swept_dirs, gate.exempt_dirs, gate.check_docs, gate.check_strict = orig
        self.assertEqual( code, 0 )
        self.assertEqual( calls[2:], [ "docs []", "strict []" ] )

    def test_filter_ignores_everything_but_missing_docs( self ):
        out = ( "ERROR|COMPILE_TIME_ERROR|UNDEFINED_GETTER|/r/lib/core/a.dart|3|4|5|The getter 'x' isn't defined.\n"
                "WARNING|STATIC_WARNING|UNUSED_IMPORT|/r/lib/core/a.dart|1|1|9|Unused import.\n"
                "INFO|LINT|AVOID_PRINT|/r/lib/core/a.dart|7|1|5|Don't print.\n" )
        self.assertEqual( gate.missing_doc_findings( out ), [] )

    def test_filter_catches_a_missing_doc_among_other_findings( self ):
        doc = "INFO|LINT|PUBLIC_MEMBER_API_DOCS|/r/lib/core/a.dart|9|8|3|Missing documentation for a public member."
        out = "ERROR|COMPILE_TIME_ERROR|UNDEFINED_GETTER|/r/a.dart|3|4|5|bad \\| pipe\n" + doc + "\n"
        self.assertEqual( gate.missing_doc_findings( out ), [ doc ] )

    def test_check_docs_follows_the_filter_not_the_exit_code( self ):
        def fake( out, code ):
            return lambda *a, **k: subprocess.CompletedProcess( a, code, stdout=out, stderr="" )
        orig = subprocess.run
        try:
            subprocess.run = fake( "ERROR|COMPILE_TIME_ERROR|X|/f|1|1|1|m\n", 3 )
            self.assertTrue( gate.check_docs( [ "lib/core" ] ) )
            subprocess.run = fake( "INFO|LINT|PUBLIC_MEMBER_API_DOCS|/f|1|1|1|m\n", 1 )
            self.assertFalse( gate.check_docs( [ "lib/core" ] ) )
            subprocess.run = fake( "", 64 )
            self.assertFalse( gate.check_docs( [ "lib/core" ] ) )
        finally:
            subprocess.run = orig
        self.assertTrue( gate.check_docs( [] ) )


# --- strict directories (row 5a200e6c) -------------------------------------------------------

REAL_DART = gate.dart_cmd()
NOTE      = "void shout() {\n  print( 'x' );\n}\n"          # one avoid_print style note
CLEAN     = "void quiet() {}\n"
OPTIONS_PRINT = "linter:\n  rules:\n    avoid_print: true\n"


def make_strict_repo( strict_text=NOTE, exempt_text=NOTE ):
    """A temp repo with gated lib/strict (clean or noted) and lib/exempt, exempt listed in strict_exempt.txt."""
    return make_repo( {
        "tool/data/gated_dirs.txt"   : "lib/strict\nlib/exempt\n",
        "tool/data/strict_exempt.txt": "lib/exempt  # test fixture (row 0123abcd)\n",
        "pubspec.yaml"               : "name: fixture\nenvironment:\n  sdk: ^3.0.0\n",
        "lib/strict/analysis_options.yaml": OPTIONS_PRINT, "lib/strict/s.dart": strict_text,
        "lib/exempt/analysis_options.yaml": OPTIONS_PRINT, "lib/exempt/e.dart": exempt_text } )


class StrictGateTest( unittest.TestCase ):

    def setUp( self ):
        self._dart = os.environ.get( "DART" )
        os.environ["DART"] = REAL_DART

    def tearDown( self ):
        if self._dart is None: os.environ.pop( "DART", None )
        else: os.environ["DART"] = self._dart

    def run_strict( self, dirs, root ):
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout( buf ), contextlib.redirect_stderr( io.StringIO() ):
            ok = gate.check_strict( dirs, root )
        return ok, buf.getvalue()

    def test_strict_dir_with_one_style_note_fails_and_names_dir_rule_and_file( self ):
        root = make_strict_repo()
        ok, out = self.run_strict( [ "lib/strict" ], root )
        self.assertFalse( ok )
        self.assertIn( "STRICT lib/strict: avoid_print lib/strict/s.dart:2", out )

    def test_exempt_dir_with_the_same_note_passes_the_docs_check_but_would_fail_strict( self ):
        root = make_strict_repo()
        self.assertEqual( gate.partition_touched( [ "lib/exempt/e.dart" ], root ), ( [ "lib/exempt" ], [] ) )
        self.assertTrue( gate.check_docs( [ "lib/exempt" ], root ) )
        self.assertFalse( self.run_strict( [ "lib/exempt" ], root )[0] )

    def test_clean_strict_dir_passes( self ):
        root = make_strict_repo( strict_text=CLEAN )
        ok, out = self.run_strict( [ "lib/strict" ], root )
        self.assertTrue( ok, out )
        self.assertNotIn( "STRICT lib/strict", out )

    def test_a_new_gated_dir_is_strict_by_default( self ):
        root = make_strict_repo()
        with open( os.path.join( root, "tool/data/gated_dirs.txt" ), "a" ) as f: f.write( "lib/brand_new\n" )
        self.assertEqual( gate.strict_dirs( root ), [ "lib/strict", "lib/brand_new" ] )
        self.assertEqual( gate.partition_touched( [ "lib/brand_new/x.dart" ], root ), ( [], [ "lib/brand_new" ] ) )

    def test_exempt_line_without_reason_or_row_is_refused_with_its_line( self ):
        for bad in ( "lib/exempt\n", "lib/exempt  # no row here\n", "lib/exempt  # (row 0123abcd)\n" ):
            root = make_strict_repo()
            with open( os.path.join( root, "tool/data/strict_exempt.txt" ), "w" ) as f: f.write( "# c\n" + bad )
            with self.assertRaises( ValueError ) as cm: gate.exempt_dirs( root )
            self.assertIn( "strict_exempt.txt:2: need `<dir>  # <reason> (row <8 hex>)`", str( cm.exception ), bad )

    def test_exempt_dir_that_is_not_gated_is_refused_by_name( self ):
        root = make_strict_repo()
        with open( os.path.join( root, "tool/data/strict_exempt.txt" ), "w" ) as f: f.write( "lib/typo  # x (row 0123abcd)\n" )
        with self.assertRaises( ValueError ) as cm: gate.exempt_dirs( root )
        self.assertIn( "lib/typo is not in tool/data/gated_dirs.txt", str( cm.exception ) )

    def test_exempt_list_in_this_repo_only_shrinks( self ):
        self.assertLessEqual( set( gate.exempt_dirs() ),
                              { "lib/services", "lib/features/notifications", "lib/features/queue" } )

    def test_options_exclude_in_a_strict_dir_is_flagged( self ):
        root = make_strict_repo( strict_text=CLEAN )
        with open( os.path.join( root, "lib/strict/analysis_options.yaml" ), "a" ) as f:
            f.write( "analyzer:\n  exclude:\n    - s.dart\n" )
        probs = gate.strict_config_problems( [ "lib/strict" ], root )
        self.assertEqual( len( probs ), 1 )
        self.assertIn( "lib/strict/analysis_options.yaml:", probs[0] )
        self.assertIn( "exclude:", probs[0] )

    def test_unexplained_ignore_in_a_strict_dir_is_flagged_and_a_reasoned_one_is_not( self ):
        root = make_strict_repo( strict_text="void a() {\n  // ignore: avoid_print\n  print( 'x' );\n}\n" )
        probs = gate.strict_config_problems( [ "lib/strict" ], root )
        self.assertEqual( len( probs ), 1 )
        self.assertIn( "lib/strict/s.dart:2: ignore comment in a strict directory needs a reason", probs[0] )
        with open( os.path.join( root, "lib/strict/s.dart" ), "w" ) as f:
            f.write( "void a() {\n  // ignore: avoid_print - captured by the log test\n  print( 'x' );\n}\n" )
        self.assertEqual( gate.strict_config_problems( [ "lib/strict" ], root ), [] )
        with open( os.path.join( root, "lib/strict/s.dart" ), "w" ) as f:
            f.write( "// ignore_for_file: avoid_print - whole file\nvoid a() { print( 'x' ); }\n" )
        self.assertEqual( len( gate.strict_config_problems( [ "lib/strict" ], root ) ), 1 )

    def test_unreadable_analyzer_failure_is_not_read_as_clean( self ):
        orig = subprocess.run
        subprocess.run = lambda *a, **k: subprocess.CompletedProcess( a, 1, stdout="garbled\n", stderr="" )
        try:
            import io, contextlib
            with contextlib.redirect_stdout( io.StringIO() ), contextlib.redirect_stderr( io.StringIO() ):
                self.assertFalse( gate.check_strict( [ "lib/core" ] ) )
        finally:
            subprocess.run = orig


if __name__ == "__main__":
    unittest.main()
