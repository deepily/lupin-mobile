#!/usr/bin/env python3
"""Unit tests for tool/merge_gate.py — run: python3 -m pytest tool/test_merge_gate.py -q

Covers the parts that decide the verdict, without running Flutter: the new-error comparison, the
comments-only comparison, the verdict word and exit code, and a throwaway git repo for the range code.
"""
import os, subprocess, sys, tempfile, unittest
sys.path.insert( 0, os.path.dirname( os.path.abspath( __file__ ) ) )
import merge_gate as mg


def err( path, code, msg, line=1, col=1, sev="ERROR" ):
    """One machine-format finding."""
    return f"{sev}|COMPILE_TIME_ERROR|{code}|{path}|{line}|{col}|3|{msg}"


class NewErrorTest( unittest.TestCase ):

    def counts( self, *lines ): return mg.parse_errors( "\n".join( lines ), ( "/r/", ) )

    def test_same_error_on_a_moved_line_is_not_new( self ):
        base = self.counts( err( "/r/lib/a.dart", "UNDEFINED_IDENTIFIER", "Undefined name 'x'.", line=10, col=5 ) )
        head = self.counts( err( "/r/lib/a.dart", "UNDEFINED_IDENTIFIER", "Undefined name 'x'.", line=42, col=9 ) )
        self.assertEqual( mg.new_errors( base, head ), [] )

    def test_new_code_in_the_same_file_is_new( self ):                       # negative control
        base = self.counts( err( "/r/lib/a.dart", "UNDEFINED_IDENTIFIER", "Undefined name 'x'." ) )
        head = self.counts( err( "/r/lib/a.dart", "UNDEFINED_IDENTIFIER", "Undefined name 'x'.", line=7 ),
                            err( "/r/lib/a.dart", "INVALID_ASSIGNMENT", "A value of type 'int' can't be assigned.", line=9 ) )
        self.assertEqual( mg.new_errors( base, head ), [ ( "lib/a.dart", "INVALID_ASSIGNMENT", "A value of type 'int' can't be assigned." ) ] )

    def test_a_second_copy_of_a_known_error_is_new( self ):
        e = err( "/r/lib/a.dart", "UNDEFINED_IDENTIFIER", "Undefined name 'x'." )
        self.assertEqual( len( mg.new_errors( self.counts( e ), self.counts( e, e ) ) ), 1 )

    def test_warnings_and_infos_are_not_errors( self ):
        head = self.counts( err( "/r/lib/a.dart", "UNUSED_IMPORT", "unused", sev="WARNING" ), err( "/r/lib/a.dart", "X", "m", sev="INFO" ) )
        self.assertEqual( mg.new_errors( self.counts(), head ), [] )

    def test_a_fixed_error_is_not_new( self ):
        e = err( "/r/lib/a.dart", "UNDEFINED_IDENTIFIER", "Undefined name 'x'." )
        self.assertEqual( mg.new_errors( self.counts( e ), self.counts() ), [] )

    def test_pipe_in_a_message_does_not_shift_columns( self ):
        c = self.counts( err( "/r/lib/a.dart", "X", "a \\| b" ) )
        self.assertEqual( list( c )[ 0 ][ 0 ], "lib/a.dart" )


class CommentsOnlyTest( unittest.TestCase ):

    def test_a_changed_comment_passes( self ):
        old = "/// Old words.\nint f() => 1; // trailing\n"
        new = "/// New words, longer.\n/// Second line.\nint f() => 1;\n"
        self.assertFalse( mg.comments_differ( old, new ) )

    def test_a_changed_token_fails( self ):                                  # negative control
        self.assertTrue( mg.comments_differ( "int f() => 1; // c\n", "int f() => 2; // c\n" ) )

    def test_a_trailing_comma_fails( self ):
        self.assertTrue( mg.comments_differ( "var a = [ 1, 2 ];\n", "var a = [ 1, 2, ];\n" ) )

    def test_a_block_comment_between_tokens_is_a_space( self ):
        self.assertFalse( mg.comments_differ( "int /* x */ a = 1;", "int a = 1;" ) )
        self.assertTrue(  mg.comments_differ( "int/**/a = 1;", "inta = 1;" ) )

    def test_nested_block_comment_is_one_comment( self ):
        self.assertFalse( mg.comments_differ( "a /* x /* y */ z */ b", "a b" ) )

    def test_slashes_inside_a_string_are_text( self ):
        self.assertTrue( mg.comments_differ( "var u = 'http://a.b';", "var u = 'http:';" ) )

    def test_whitespace_inside_a_string_is_a_change( self ):                  # negative control
        self.assertTrue( mg.comments_differ( "var s = 'a  b';", "var s = 'a b';" ) )

    def test_whitespace_runs_in_code_are_not_a_change( self ):
        self.assertFalse( mg.comments_differ( "int f( int a ) => a;", "int  f( int a )\n  =>   a;" ) )

    def test_adding_a_space_where_there_was_none_is_a_change( self ):         # conservative on purpose
        self.assertTrue( mg.comments_differ( "int f( int a ) => a;", "int f(int a) => a;" ) )

    def test_interpolation_with_a_quote_does_not_end_the_string( self ):
        src = "var s = 'x ${ m['k'] } // not a comment'; // real comment\n"
        self.assertEqual( mg.strip_dart( src ), "var s = 'x ${ m['k'] } // not a comment';" )

    def test_raw_string_and_triple_quotes_keep_their_text( self ):
        src = "var a = r'// \\n'; var b = '''\n// kept\n'''; // gone\n"
        self.assertIn( "// kept", mg.strip_dart( src ) )
        self.assertNotIn( "gone", mg.strip_dart( src ) )

    def test_a_file_added_or_deleted_is_a_change( self ):
        self.assertTrue( mg.comments_differ( "", "int a = 1;" ) )
        self.assertTrue( mg.comments_differ( "int a = 1;", "" ) )
        self.assertFalse( mg.comments_differ( "", "// only a comment\n" ) )


class VerdictTest( unittest.TestCase ):

    OK = [ ( "analyzer", 0, "" ), ( "docs-gate", 0, "" ), ( "suite", 0, "" ) ]

    def test_all_zero_is_pass( self ):
        self.assertEqual( mg.verdict( self.OK ), ( "PASS", 0 ) )

    def test_one_failing_check_is_fail_and_non_zero( self ):                 # negative control
        word, code = mg.verdict( self.OK[ :1 ] + [ ( "ignores", 1, "" ) ] + self.OK[ 1: ] )
        self.assertEqual( ( word, code ), ( "FAIL", 1 ) )

    def test_skip_suite_is_quick_never_pass( self ):
        word, code = mg.verdict( self.OK[ :2 ] + [ ( "suite", None, "" ), ( "ac-g2", None, "" ) ] )
        self.assertEqual( word, "QUICK" )
        self.assertNotEqual( code, 0 )

    def test_a_failure_beats_a_skip( self ):
        self.assertEqual( mg.verdict( [ ( "analyzer", 1, "" ), ( "suite", None, "" ) ] )[ 0 ], "FAIL" )

    def test_report_leads_with_the_verdict_and_lists_each_exit_code( self ):
        text = mg.report( "FAIL", [ ( "analyzer", 0, "ok" ), ( "ignores", 1, "bad" ), ( "suite", None, "skipped" ) ], "abc..def", "/tmp/x" ).splitlines()
        self.assertTrue( text[ 0 ].startswith( "FAIL" ) )
        self.assertIn( "exit 1", text[ 2 ] )
        self.assertIn( "SKIPPED", text[ 3 ] )
        self.assertEqual( text[ -1 ], "logs: /tmp/x" )


class GitRangeTest( unittest.TestCase ):
    """A throwaway repo: one base commit, one comment-only commit, one token-changing commit."""

    def sh( self, *a ): return subprocess.run( [ "git", "-c", "user.name=t", "-c", "user.email=t@t", *a ], cwd=self.d, capture_output=True, text=True, check=True ).stdout.strip()

    def commit( self, text, msg ):
        with open( os.path.join( self.d, "a.dart" ), "w" ) as f: f.write( text )
        with open( os.path.join( self.d, "notes.md" ), "a" ) as f: f.write( msg )
        self.sh( "add", "-A" ); self.sh( "commit", "-q", "-m", msg )
        return self.sh( "rev-parse", "HEAD" )

    def setUp( self ):
        self.tmp = tempfile.TemporaryDirectory(); self.d = self.tmp.name
        self.sh( "init", "-q", "-b", "main" )
        self.c0 = self.commit( "int f() => 1;\n", "base" )
        self.c1 = self.commit( "/// Docs.\nint f() => 1; // why\n", "comments" )
        self.c2 = self.commit( "/// Docs.\nint f() => 2; // why\n", "token" )

    def tearDown( self ): self.tmp.cleanup()

    def test_comment_only_commit_passes( self ):
        self.assertEqual( mg.check_comments_only( self.c0, self.c1, self.d )[ 0 ], 0 )

    def test_token_changing_commit_fails( self ):                            # negative control
        self.assertEqual( mg.check_comments_only( self.c1, self.c2, self.d )[ 0 ], 1 )

    def test_a_range_with_one_bad_commit_fails( self ):
        self.assertEqual( mg.check_comments_only( self.c0, self.c2, self.d )[ 0 ], 1 )

    def test_a_range_with_no_dart_change_fails_rather_than_passes_vacuously( self ):
        self.assertEqual( mg.check_comments_only( self.c1, self.c1, self.d )[ 0 ], 1 )

    def test_non_dart_files_are_listed_not_judged( self ):
        self.assertEqual( mg.changed_dart_files( self.c0, self.c1, self.d ), ( [ "a.dart" ], [ "notes.md" ] ) )

    def test_resolve_range_forms( self ):
        self.assertEqual( mg.resolve_range( None, "main", self.d ), ( self.c2, self.c2 ) )          # base is HEAD itself
        self.assertEqual( mg.resolve_range( f"{self.c0}..{self.c2}", "main", self.d ), ( self.c0, self.c2 ) )
        self.assertEqual( mg.resolve_range( self.c1, "main", self.d ), ( self.c0, self.c1 ) )

    def test_unknown_revision_raises( self ):
        with self.assertRaises( RuntimeError ): mg.resolve_range( "nope", "main", self.d )


if __name__ == "__main__":
    unittest.main()
