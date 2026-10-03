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
        orig  = ( gate.run_check, gate.staged_paths, gate.swept_dirs )
        orig_docs = gate.check_docs
        gate.run_check    = lambda name, cmd, root=None: calls.append( name ) or name.startswith( "ignore" )
        gate.check_docs   = lambda dirs, root=None: calls.append( "docs" ) or True
        gate.staged_paths = lambda root=None: [ "lib/core/a.dart" ]
        gate.swept_dirs   = lambda root=None: [ "lib/core" ]
        try:
            code = gate.main( [] )
        finally:
            gate.run_check, gate.staged_paths, gate.swept_dirs = orig
            gate.check_docs = orig_docs
        self.assertEqual( code, 1 )
        self.assertEqual( calls, [ "doc linter (staged lines)", "ignore checker", "docs" ] )

    def test_main_passes_when_all_checks_pass_and_skips_untouched_dirs( self ):
        calls = []
        orig  = ( gate.run_check, gate.staged_paths, gate.swept_dirs )
        orig_docs = gate.check_docs
        gate.run_check    = lambda name, cmd, root=None: calls.append( name ) or True
        gate.check_docs   = lambda dirs, root=None: calls.append( f"docs {dirs}" ) or True
        gate.staged_paths = lambda root=None: [ "README.md" ]
        gate.swept_dirs   = lambda root=None: [ "lib/core" ]
        try:
            code = gate.main( [] )
        finally:
            gate.run_check, gate.staged_paths, gate.swept_dirs = orig
            gate.check_docs = orig_docs
        self.assertEqual( code, 0 )
        self.assertEqual( calls[2:], [ "docs []" ] )

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


if __name__ == "__main__":
    unittest.main()
