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

    def test_every_swept_dir_in_this_repo_is_gated_or_named_left_out( self ):
        listed = set( gate.swept_dirs() ) | set( gate.left_out_dirs() )
        self.assertEqual( set( gate.all_swept_dirs() ) - listed, set() )
        self.assertEqual( set( gate.swept_dirs() ) & set( gate.left_out_dirs() ), set() )

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
        gate.run_check    = lambda name, cmd, root=None: calls.append( name ) or name.startswith( "ignore" )
        gate.staged_paths = lambda root=None: [ "lib/core/a.dart" ]
        gate.swept_dirs   = lambda root=None: [ "lib/core" ]
        try:
            code = gate.main( [] )
        finally:
            gate.run_check, gate.staged_paths, gate.swept_dirs = orig
        self.assertEqual( code, 1 )
        self.assertEqual( len( calls ), 3 )

    def test_main_passes_when_all_checks_pass_and_skips_untouched_dirs( self ):
        calls = []
        orig  = ( gate.run_check, gate.staged_paths, gate.swept_dirs )
        gate.run_check    = lambda name, cmd, root=None: calls.append( name ) or True
        gate.staged_paths = lambda root=None: [ "README.md" ]
        gate.swept_dirs   = lambda root=None: [ "lib/core" ]
        try:
            code = gate.main( [] )
        finally:
            gate.run_check, gate.staged_paths, gate.swept_dirs = orig
        self.assertEqual( code, 0 )
        self.assertEqual( len( calls ), 2 )


if __name__ == "__main__":
    unittest.main()
