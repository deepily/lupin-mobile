#!/usr/bin/env python3
"""Unit tests for tool/merge_gate.py — run: python3 -m pytest tool/test_merge_gate.py -q

Covers the parts that decide the verdict, without running Flutter: the new-error comparison, the
comments-only comparison, the verdict word and exit code, and a throwaway git repo for the range code.
"""
import contextlib, io, os, subprocess, sys, tempfile, unittest
sys.path.insert( 0, os.path.dirname( os.path.abspath( __file__ ) ) )
import merge_gate as mg


def err( path, code, msg, line=1, col=1, sev="ERROR" ):
    """
    Build one machine-format finding.

    Requires:
        - path, code and msg are strings; line and col are integers
    Ensures:
        - returns SEVERITY|COMPILE_TIME_ERROR|code|path|line|col|3|msg
    """
    return f"{sev}|COMPILE_TIME_ERROR|{code}|{path}|{line}|{col}|3|{msg}"


class NewErrorTest( unittest.TestCase ):

    def counts( self, *lines ):
        """
        Parse finding lines as the head of a checkout rooted at /r.

        Requires:
            - each line is a machine-format finding
        Ensures:
            - returns the Counter parse_errors gives, with the /r/ prefix stripped
        """
        return mg.parse_errors( "\n".join( lines ), ( "/r/", ) )

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

    def test_raw_string_ending_in_a_backslash_closes_there( self ):             # L8: raw strings have no escapes
        old = "var a = r'\\'; int b = 1; // c\n"
        self.assertFalse( mg.comments_differ( old, "var a = r'\\'; int b = 1; // d\n" ) )   # comment after it is a comment
        self.assertTrue(  mg.comments_differ( old, "var a = r'\\'; int b = 2; // c\n" ) )   # code after it is code
        self.assertFalse( mg.comments_differ( 'var a = r"\\"; int b = 1; // c\n', 'var a = r"\\"; int b = 1;\n' ) )

    def test_a_file_added_or_deleted_is_a_change( self ):
        self.assertTrue( mg.comments_differ( "", "int a = 1;" ) )
        self.assertTrue( mg.comments_differ( "int a = 1;", "" ) )
        self.assertFalse( mg.comments_differ( "", "// only a comment\n" ) )


class ToolPresenceTest( unittest.TestCase ):

    NEEDED = [ "flutter.sh", "flutter/bin/flutter", "tool/pre_commit_gate.py", "tool/check_doc_ignores.py", "tool/doc_coverage.py",
               "tool/check_test_failures.py", "tool/check_ac_g2.py" ]

    def test_a_missing_binary_and_scripts_are_named_not_raised( self ):             # L3
        saved = os.environ.get( "DART" )
        os.environ[ "DART" ] = "/nonexistent/dart"
        try:
            with tempfile.TemporaryDirectory() as d:
                missing = mg.missing_tools( d, skip_suite=False )
        finally:
            if saved is None: del os.environ[ "DART" ]
            else: os.environ[ "DART" ] = saved
        for name in self.NEEDED + [ "/nonexistent/dart" ]: self.assertTrue( any( name in m for m in missing ), name )

    def test_nothing_is_missing_when_everything_is_there( self ):                    # negative control
        saved = os.environ.get( "DART" )
        os.environ[ "DART" ] = sys.executable
        try:
            with tempfile.TemporaryDirectory() as d:
                for rel in self.NEEDED:
                    os.makedirs( os.path.dirname( os.path.join( d, rel ) ), exist_ok=True )
                    open( os.path.join( d, rel ), "w" ).close()
                self.assertEqual( mg.missing_tools( d, skip_suite=False ), [] )
        finally:
            if saved is None: del os.environ[ "DART" ]
            else: os.environ[ "DART" ] = saved

    def test_skip_suite_does_not_need_flutter_sh( self ):
        with tempfile.TemporaryDirectory() as d:
            self.assertFalse( any( "flutter.sh" in m for m in mg.missing_tools( d, skip_suite=True ) ) )


class AnalyzerExitTest( unittest.TestCase ):

    KEY = ( "lib/a.dart", "X", "m" )

    def test_exit_3_with_no_parsed_errors_is_a_failure( self ):                      # L2
        self.assertIn( "no ERROR", mg.analyzer_failure( 3, mg.collections.Counter(), "head" ) )

    def test_exit_3_with_errors_is_a_finished_run( self ):                           # negative control
        self.assertIsNone( mg.analyzer_failure( 3, mg.collections.Counter( { self.KEY: 1 } ), "head" ) )

    def test_clean_and_info_exits_are_finished_runs( self ):
        for code in ( 0, 1, 2 ): self.assertIsNone( mg.analyzer_failure( code, mg.collections.Counter(), "head" ) )

    def test_exit_outside_0_to_3_did_not_finish( self ):
        self.assertIn( "did not finish", mg.analyzer_failure( 64, mg.collections.Counter(), "start" ) )


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

    def test_changed_gate_inputs_make_pass_with_warning_and_stay_zero( self ):      # L5
        self.assertEqual( mg.verdict( self.OK, [ "tool/check_ac_g2.py" ] ), ( "PASS-WITH-WARNING", 0 ) )

    def test_a_warning_never_softens_a_fail_or_a_quick( self ):
        self.assertEqual( mg.verdict( [ ( "a", 1, "" ) ], [ "tool/data/x.json" ] ), ( "FAIL", 1 ) )
        self.assertEqual( mg.verdict( [ ( "a", 0, "" ), ( "suite", None, "" ) ], [ "tool/data/x.json" ] ), ( "QUICK", 3 ) )

    def test_gate_inputs_are_recognised( self ):
        names = [ "tool/merge_gate.py", "tool/check_ac_g2.py", "tool/check_test_failures.py", "tool/pre_commit_gate.py",
                  "tool/doc_coverage.py", "tool/data/test_failures_baseline.json", "test/fixtures/ac_g2_passing_baseline.json" ]
        self.assertEqual( mg.gate_input_files( names + [ "lib/a.dart", "tool/notes.md", "README.md" ] ), sorted( names ) )
        self.assertEqual( mg.gate_input_files( [ "lib/a.dart", "tool/notes.md", "tool/helper.py" ] ), [] )          # negative control

    def test_every_tool_test_file_is_a_gate_input( self ):                           # G2
        names = [ "tool/test_check_doc_ignores.py", "tool/test_pre_commit_gate.py", "tool/test_merge_gate.py" ]
        self.assertEqual( mg.gate_input_files( names ), sorted( names ) )
        self.assertEqual( mg.gate_input_files( [ "test/unit/test_x.dart", "tool/doc_lint/test_y.py", "tool/test_x.md" ] ), [] )   # controls

    def test_files_that_decide_what_the_suite_and_tests_do_are_gate_inputs( self ):    # N4
        names = [ "flutter.sh", "dart_test.yaml", "pytest.ini", "tool/conftest.py", "pubspec.yaml", "pubspec.lock",
                  "tool/lint_dart_docs.py", "tool/test_merge_gate.py", ".github/workflows/flutter-ci.yml" ]
        self.assertEqual( mg.gate_input_files( names ), sorted( names ) )
        self.assertEqual( mg.gate_input_files( [ "docs/flutter.sh.md", "lib/pubspec.yaml.dart", "tool/conftest.py.txt" ] ), [] )   # control

    def test_usage_text_says_a_warning_pass_still_exits_zero( self ):
        self.assertIn( "PASS-WITH-WARNING exits 0", mg.__doc__ )
        self.assertIn( "not only the exit code", mg.__doc__ )

    def test_count_ignore_lines( self ):                                             # N1
        text = "// ignore_for_file: a, b\nint x = 1; // ignore: c\n// we do not ignore this\nint y = 2;\n"
        self.assertEqual( mg.count_ignore_lines( text ), 2 )
        self.assertEqual( mg.count_ignore_lines( "int y = 2;\n" ), 0 )

    def test_range_label_says_when_ignores_were_allowed( self ):
        self.assertIn( "ignores-allowed", mg.range_label( "a" * 40, "b" * 40, 1, False, False, True ) )
        self.assertNotIn( "ignores-allowed", mg.range_label( "a" * 40, "b" * 40, 1, False, False ) )

    def test_dart_roots_are_top_level_dirs_and_root_files( self ):                    # N2
        paths = [ "lib/a.dart", "lib/x/b.dart", "test/t.dart", "integration_test/s.dart", "main.dart", "tool/hello.dart" ]
        self.assertEqual( mg.dart_roots( paths ), [ "integration_test", "lib", "main.dart", "test", "tool" ] )
        self.assertEqual( mg.dart_roots( [] ), [] )

    def test_limited_listing_shows_ten_and_counts_the_rest( self ):                   # N3
        text = mg.limited( [ f"f{i}" for i in range( 13 ) ] )
        self.assertEqual( len( text.splitlines() ), 11 )
        self.assertIn( "and 3 more", text )
        self.assertNotIn( "more", mg.limited( [ "a", "b" ] ) )

    def test_warning_line_sits_under_the_verdict_and_names_the_files( self ):
        text = mg.report( "PASS-WITH-WARNING", [ ( "analyzer", 0, "ok" ) ], "a..b", "/tmp/x", [ "tool/check_ac_g2.py" ] ).splitlines()
        self.assertEqual( text[ 1 ], "WARNING: this range changes the gate's own inputs: tool/check_ac_g2.py. A human must read that diff." )

    def test_range_label_says_when_analyzer_config_changes_were_allowed( self ):   # F1
        self.assertIn( "analyzer-config-allowed", mg.range_label( "a" * 40, "b" * 40, 2, False, True ) )
        self.assertNotIn( "analyzer-config-allowed", mg.range_label( "a" * 40, "b" * 40, 2, False, False ) )

    def test_report_leads_with_the_verdict_and_lists_each_exit_code( self ):
        text = mg.report( "FAIL", [ ( "analyzer", 0, "ok" ), ( "ignores", 1, "bad" ), ( "suite", None, "skipped" ) ], "abc..def", "/tmp/x" ).splitlines()
        self.assertTrue( text[ 0 ].startswith( "FAIL" ) )
        self.assertIn( "exit 1", text[ 2 ] )
        self.assertIn( "SKIPPED", text[ 3 ] )
        self.assertEqual( text[ -1 ], "logs: /tmp/x" )


class ToolTestsCommandTest( unittest.TestCase ):

    def test_a_failing_unittest_style_tool_test_reports_as_an_ordinary_failure( self ):    # round 2, item 2
        """The row's own command, pointed at a folder holding one failing unittest.TestCase."""
        with tempfile.TemporaryDirectory() as d:
            with open( os.path.join( d, "test_boom.py" ), "w" ) as f:
                f.write( "import unittest\nclass T( unittest.TestCase ):\n    def test_boom( self ): self.assertEqual( 1, 2 )\n" )
            cmd = [ d if a == "tool/" else a for a in mg.TOOL_TESTS_CMD ]
            p   = subprocess.run( cmd, cwd=d, capture_output=True, text=True )
        self.assertEqual( p.returncode, 1, p.stdout[ -400: ] )          # 3 is pytest's INTERNALERROR
        self.assertIn( "1 failed", p.stdout )
        self.assertNotIn( "INTERNALERROR", p.stdout )


class GitRangeTest( unittest.TestCase ):
    """A throwaway repo: one base commit, one comment-only commit, one token-changing commit."""

    def sh( self, *a ):
        """
        Run git in the throwaway repo.

        Requires:
            - a is a list of git arguments; self.d is the repo
        Ensures:
            - returns stdout, stripped; raises CalledProcessError on failure
        """
        return subprocess.run( [ "git", "-c", "user.name=t", "-c", "user.email=t@t", *a ], cwd=self.d, capture_output=True, text=True, check=True ).stdout.strip()

    def commit( self, text, msg, extra=None ):
        """
        Write a.dart (and optionally one more file), commit, and return the new sha.

        Requires:
            - text is the new contents of a.dart; extra is None or a ( path, contents ) pair
        Ensures:
            - returns the full sha of the new commit
        """
        with open( os.path.join( self.d, "a.dart" ), "w" ) as f: f.write( text )
        if extra:
            os.makedirs( os.path.dirname( os.path.join( self.d, extra[ 0 ] ) ), exist_ok=True )
            with open( os.path.join( self.d, extra[ 0 ] ), "w" ) as f: f.write( extra[ 1 ] )
        self.sh( "add", "-A" ); self.sh( "commit", "-q", "-m", msg )
        return self.sh( "rev-parse", "HEAD" )

    def setUp( self ):
        self.tmp = tempfile.TemporaryDirectory(); self.d = self.tmp.name
        self.sh( "init", "-q", "-b", "main" )
        self.c0 = self.commit( "int f() => 1;\n", "base" )
        self.c1 = self.commit( "/// Docs.\nint f() => 1; // why\n", "comments" )
        self.c2 = self.commit( "/// Docs.\nint f() => 2; // why\n", "token" )
        self.c3 = self.commit( "/// Docs.\nint f() => 2; // why, said better\n", "comment plus a pubspec change", ( "pubspec.yaml", "name: x\n" ) )

    def tearDown( self ): self.tmp.cleanup()

    def test_comment_only_commit_passes( self ):
        self.assertEqual( mg.check_comments_only( self.c0, self.c1, self.d )[ 0 ], 0 )

    def test_token_changing_commit_fails( self ):                            # negative control
        self.assertEqual( mg.check_comments_only( self.c1, self.c2, self.d )[ 0 ], 1 )

    def test_a_range_with_one_bad_commit_fails( self ):
        self.assertEqual( mg.check_comments_only( self.c0, self.c2, self.d )[ 0 ], 1 )

    def test_a_range_with_no_dart_change_fails_rather_than_passes_vacuously( self ):
        self.assertEqual( mg.check_comments_only( self.c1, self.c1, self.d )[ 0 ], 1 )

    def test_a_non_dart_change_fails_comments_only_and_names_the_file( self ):      # F3
        code, detail = mg.check_comments_only( self.c2, self.c3, self.d )
        self.assertEqual( code, 1 )
        self.assertIn( "pubspec.yaml", detail )

    def test_non_dart_files_are_listed_apart_from_dart_files( self ):
        self.assertEqual( mg.changed_dart_files( self.c2, self.c3, self.d ), ( [ "a.dart" ], [ "pubspec.yaml" ] ) )

    def test_range_commits_counts_and_an_empty_range_is_zero( self ):             # L1
        self.assertEqual( mg.range_commits( self.c1, self.c1, self.d ), 0 )
        self.assertEqual( mg.range_commits( self.c0, self.c2, self.d ), 2 )

    def test_main_refuses_an_empty_range_with_exit_2( self ):
        self.assertEqual( mg.main( [ "--base", "HEAD", "--skip-suite" ], root=self.d ), 2 )

    def test_analyzer_config_files_are_picked_out( self ):                        # F1
        names = [ "lib/a.dart", "analysis_options.yaml", "lib/features/x/analysis_options.yaml", "docs/analysis_options.yaml.md" ]
        self.assertEqual( mg.analyzer_config_files( names ), [ "analysis_options.yaml", "lib/features/x/analysis_options.yaml" ] )
        self.assertEqual( mg.analyzer_config_files( [ "lib/a.dart" ] ), [] )

    def test_a_range_that_edits_analyzer_options_fails_the_analyzer_row( self ):
        c4 = self.commit( "int f() => 2;\n", "options", ( "analysis_options.yaml", "analyzer:\n  exclude:\n    - lib/zz.dart\n" ) )
        with tempfile.TemporaryDirectory() as logs:
            code, detail = mg.check_analyzer( self.c3, logs, root=self.d, allow_config=False )
        self.assertEqual( code, 1 )
        self.assertIn( "analysis_options.yaml", detail )
        self.assertIn( "--allow-analyzer-config", detail )
        self.assertEqual( mg.analyzer_config_files( mg.changed_dart_files( self.c3, c4, self.d )[ 1 ] ), [ "analysis_options.yaml" ] )

    def touch( self, *rels ):
        """
        Create small untracked files in the throwaway repo.

        Requires:
            - each rel is a repo-relative path
        Ensures:
            - each file exists with the text "x"
        """
        for rel in rels:
            os.makedirs( os.path.dirname( os.path.join( self.d, rel ) ) or self.d, exist_ok=True )
            with open( os.path.join( self.d, rel ), "w" ) as f: f.write( "x" )

    def test_untracked_files_anywhere_are_listed( self ):                          # F2, widened by N3
        self.touch( "lib/zz_missing.dart", "test/t_test.dart", "tool/x.py", "pubspec.lock", "lib/features/q/analysis_options.yaml",
                    "assets/config/zz.json", "README.md", "integration_test/s.dart" )
        self.assertEqual( mg.untracked_inputs( self.d ),
                          [ "README.md", "assets/config/zz.json", "integration_test/s.dart", "lib/features/q/analysis_options.yaml",
                            "lib/zz_missing.dart", "pubspec.lock", "test/t_test.dart", "tool/x.py" ] )

    def test_the_allow_list_is_not_refused( self ):                                # N3 negative control
        self.touch( "src/rnd/x.md", "history/x.md", "todo-archive/x.md", "io/m.md", ".claude/x.json" )
        self.assertEqual( mg.untracked_inputs( self.d ), [] )

    def test_every_allow_list_entry_carries_a_reason( self ):                      # G3 class
        self.assertEqual( set( mg.ALLOWED_UNTRACKED ), set( mg.ALLOWED_UNTRACKED_WHY ) )
        for prefix, why in mg.ALLOWED_UNTRACKED_WHY.items():
            self.assertTrue( prefix.endswith( "/" ), prefix )
            self.assertGreater( len( why.split() ), 3, f"{prefix} needs a written reason" )

    def test_src_docs_is_refused_because_a_test_reads_it( self ):                    # G3
        self.touch( "src/docs/decisions/new.md" )
        self.assertEqual( mg.untracked_inputs( self.d ), [ "src/docs/decisions/new.md" ] )

    def test_an_ignored_file_is_not_an_untracked_input( self ):                   # negative control
        with open( os.path.join( self.d, ".gitignore" ), "w" ) as f: f.write( "lib/gen.dart\n" )
        self.sh( "add", ".gitignore" ); self.sh( "commit", "-q", "-m", "ignore" )
        self.touch( "lib/gen.dart" )
        self.assertEqual( mg.untracked_inputs( self.d ), [] )

    def test_main_refuses_an_untracked_asset( self ):                              # N3
        self.touch( "assets/config/zz.json" )
        err = io.StringIO()
        with contextlib.redirect_stderr( err ): code = mg.main( [ "--skip-suite", self.c3 ], root=self.d )
        self.assertEqual( code, 2 )
        self.assertIn( "assets/config/zz.json", err.getvalue() )     # refused for THIS reason, not for a missing tool

    def test_ignore_additions_name_file_and_code( self ):                          # N1
        c4 = self.commit( "// ignore_for_file: invalid_assignment\nint f() => 2;\n", "adds an ignore" )
        self.assertEqual( mg.ignore_additions( self.c3, c4, self.d ), [ ( "a.dart", "invalid_assignment" ) ] )

    def test_a_moved_or_removed_ignore_is_not_an_addition( self ):                 # N1 negative controls
        c4 = self.commit( "int f() => 2; // ignore: invalid_assignment\n", "adds" )
        c5 = self.commit( "// ignore: invalid_assignment\nint f() => 2;\n", "moves it" )
        self.assertEqual( mg.ignore_additions( c4, c5, self.d ), [] )
        self.assertEqual( mg.ignore_additions( c4, self.c3, self.d ), [] )

    def test_an_edited_ignore_line_is_an_addition( self ):                           # G1
        c4 = self.commit( "int f() => 2; // ignore: avoid_print\n", "has one ignore" )
        c5 = self.commit( "// ignore_for_file: avoid_print, invalid_assignment\nint f() => 2;\n", "edits it to cover more" )
        self.assertEqual( mg.ignore_additions( c4, c5, self.d ), [ ( "a.dart", "avoid_print, invalid_assignment" ) ] )

    def test_an_ignore_that_moves_onto_new_code_is_an_addition( self ):             # M1: the recycled ignore
        c4 = self.commit( "int g() => 1; // ignore: avoid_print\n", "ignore sits on g" )
        c5 = self.commit( "int g() => 1;\nString f() => 1; // ignore: avoid_print\n", "same ignore text, now on new code" )
        self.assertEqual( mg.ignore_additions( c4, c5, self.d ), [ ( "a.dart", "avoid_print" ) ] )

    def test_an_ignore_line_that_moves_above_other_code_is_an_addition( self ):    # M1: comment-only form
        c4 = self.commit( "// ignore: avoid_print\nint g() => 1;\nint h() => 2;\n", "ignore covers g" )
        c5 = self.commit( "int g() => 1;\n// ignore: avoid_print\nint h() => 2;\n", "now covers h" )
        self.assertEqual( mg.ignore_additions( c4, c5, self.d ), [ ( "a.dart", "avoid_print" ) ] )

    def test_editing_code_beside_an_ignore_is_an_addition( self ):                  # M1: the edit can add the error it hides
        c4 = self.commit( "int f() => 2; // ignore: avoid_print\n", "has one ignore" )
        c5 = self.commit( "int f() => 3; // ignore: avoid_print\n", "edits the code on that line" )
        self.assertEqual( mg.ignore_additions( c4, c5, self.d ), [ ( "a.dart", "avoid_print" ) ] )

    def test_an_ignore_whose_code_is_untouched_is_not_an_addition( self ):         # M1 negative control
        c4 = self.commit( "int f() => 2; // ignore: avoid_print\nint k() => 1;\n", "has one ignore" )
        c5 = self.commit( "int f() => 2; // ignore: avoid_print\nint k() => 9;\nint z() => 0;\n", "edits other lines" )
        self.assertEqual( mg.ignore_additions( c4, c5, self.d ), [] )

    def test_an_ignore_moved_onto_identical_code_is_caught_by_the_file_rule( self ):    # H1
        c4 = self.commit( "int a() {\n  return 1; // ignore: return_of_invalid_type\n}\nString b() {\n  return 1;\n}\n", "ignore on a" )
        c5 = self.commit( "int a() {\n  return 1;\n}\nString b() {\n  return 1; // ignore: return_of_invalid_type\n}\n", "ignore on b" )
        self.assertEqual( mg.ignore_additions( c4, c5, self.d ), [] )                  # the pair rule is blind to it
        self.assertEqual( mg.ignore_files_changed( c4, c5, self.d ), [ "a.dart" ] )

    def test_an_edit_away_from_the_ignore_line_is_caught_by_the_file_rule( self ):     # H2
        c4 = self.commit( "int b() {\n  return 1; // ignore: return_of_invalid_type\n}\n", "has an ignore" )
        c5 = self.commit( "String b() {\n  return 1; // ignore: return_of_invalid_type\n}\n", "signature edited" )
        self.assertEqual( mg.ignore_additions( c4, c5, self.d ), [] )
        self.assertEqual( mg.ignore_files_changed( c4, c5, self.d ), [ "a.dart" ] )

    def test_any_change_under_ignore_for_file_is_caught_by_the_file_rule( self ):      # H2, file-wide form
        c4 = self.commit( "// ignore_for_file: return_of_invalid_type\nint c() => 1;\n", "file-wide ignore" )
        c5 = self.commit( "// ignore_for_file: return_of_invalid_type\nString c() => 1;\n", "code edited" )
        self.assertEqual( mg.ignore_additions( c4, c5, self.d ), [] )
        self.assertEqual( mg.ignore_files_changed( c4, c5, self.d ), [ "a.dart" ] )

    def test_a_file_without_an_ignore_is_not_listed( self ):                           # negative control
        c4 = self.commit( "int c() => 1;\n", "no ignore" )
        c5 = self.commit( "int c() => 2;\n", "edited" )
        self.assertEqual( mg.ignore_files_changed( c4, c5, self.d ), [] )

    def test_an_unchanged_file_with_an_ignore_is_not_listed( self ):                   # negative control
        c4 = self.commit( "int c() => 1; // ignore: avoid_print\n", "has an ignore" )
        c5 = self.commit( "int c() => 1; // ignore: avoid_print\n", "touches another file", ( "notes.txt", "x\n" ) )
        self.assertEqual( mg.ignore_files_changed( c4, c5, self.d ), [] )

    def test_an_emptied_file_with_no_ignore_left_is_not_listed( self ):                      # negative control
        c4 = self.commit( "int c() => 1; // ignore: avoid_print\n", "has an ignore" )
        c5 = self.commit( "", "empties it" )
        self.assertEqual( mg.ignore_files_changed( c4, c5, self.d ), [] )

    def test_the_analyzer_row_refuses_a_changed_file_that_carries_an_ignore( self ):   # H1 and H2, refusal message
        self.commit( "int b() {\n  return 1; // ignore: return_of_invalid_type\n}\n", "has an ignore" )
        base = self.sh( "rev-parse", "HEAD" ).strip()
        self.commit( "String b() {\n  return 1; // ignore: return_of_invalid_type\n}\n", "signature edited" )
        with tempfile.TemporaryDirectory() as logs:
            code, detail = mg.check_analyzer( base, logs, root=self.d, allow_config=False, allow_ignores=False )
        self.assertEqual( code, 1 )
        self.assertIn( "carry an ignore", detail )
        self.assertIn( "a.dart", detail )
        self.assertIn( "--allow-ignores", detail )

    OPTIONS = "include: package:flutter_lints/flutter.yaml\n# note\nanalyzer:\n  exclude:\n    # the SDK\n    - flutter/**\n    - build/**   # output\n    - \"**/*.g.dart\"\n\nlinter:\n  rules:\n    - avoid_print\n"

    def test_analyzer_excludes_are_read_from_the_options_file( self ):               # N5
        self.assertEqual( mg.analyzer_excludes( self.OPTIONS ), [ "flutter/**", "build/**", "**/*.g.dart" ] )
        self.assertEqual( mg.analyzer_excludes( "linter:\n  rules:\n    - avoid_print\n" ), [] )
        self.assertEqual( mg.analyzer_excludes( "" ), [] )

    def test_an_exclude_list_in_flow_style_is_refused_not_read_as_empty( self ):     # N5, fails open otherwise
        for text in ( "analyzer:\n  exclude: [ flutter/**, build/** ]\n", "analyzer: { exclude: [ build/** ] }\n",
                      "analyzer:\n  exclude: build/**\n", "analyzer:\n  exclude:\n    - *skip\n", "analyzer:\n  exclude:\n    key: build/**\n",
                      "include: other_options.yaml\n" ):
            with self.assertRaises( ValueError, msg=text ): mg.analyzer_excludes( text )

    def test_the_analyzer_row_refuses_an_exclude_list_it_cannot_read( self ):           # N5, refusal message
        self.commit( "int f() => 1;\n", "options", ( "analysis_options.yaml", "analyzer:\n  exclude: [ build/** ]\n" ) )
        base = self.sh( "rev-parse", "HEAD" )
        self.commit( "int f() => 1;\n", "forced file", ( "build/zz_broken.dart", "int x = 'no';\n" ) )
        with tempfile.TemporaryDirectory() as logs:
            code, detail = mg.check_analyzer( base, logs, root=self.d, allow_config=True, allow_ignores=False )
        self.assertEqual( code, 1 )
        self.assertIn( "cannot tell which paths the analyzer skips", detail )
        self.assertIn( "exclude is not a block list", detail )

    def test_the_real_options_file_is_readable( self ):                                 # N5 negative control
        with open( os.path.join( mg.ROOT, "analysis_options.yaml" ) ) as f: self.assertEqual( mg.analyzer_excludes( f.read() ), [ "flutter/**", "build/**" ] )

    def test_exclude_globs_match_whole_paths( self ):                                # N5
        self.assertTrue( mg.glob_matches( "build/**", "build/zz.dart" ) )
        self.assertTrue( mg.glob_matches( "build/**", "build/a/b/zz.dart" ) )
        self.assertFalse( mg.glob_matches( "build/**", "lib/build/zz.dart" ) )
        self.assertTrue( mg.glob_matches( "**/*.g.dart", "lib/x/a.g.dart" ) )
        self.assertTrue( mg.glob_matches( "**/*.g.dart", "a.g.dart" ) )
        self.assertFalse( mg.glob_matches( "**/*.g.dart", "lib/a.dart" ) )

    def test_a_tracked_dart_file_under_an_excluded_path_is_listed( self ):           # N5
        self.commit( "int f() => 1;\n", "options", ( "analysis_options.yaml", self.OPTIONS ) )
        c5 = self.commit( "int f() => 1;\n", "forced file", ( "build/zz_broken.dart", "int x = 'no';\n" ) )
        self.assertEqual( mg.excluded_dart_files( c5, self.d ), [ "build/zz_broken.dart" ] )

    def test_files_the_analyzer_does_read_or_that_are_not_dart_are_not_listed( self ):   # N5 negative control
        self.commit( "int f() => 1;\n", "options", ( "analysis_options.yaml", self.OPTIONS ) )
        os.makedirs( os.path.join( self.d, "build" ) )
        with open( os.path.join( self.d, "build", "out.txt" ), "w" ) as f: f.write( "x" )
        c5 = self.commit( "int f() => 2;\n", "plain" )
        self.assertEqual( mg.excluded_dart_files( c5, self.d ), [] )

    def test_the_analyzer_row_refuses_a_tracked_file_the_analyzer_never_opens( self ):    # N5, refusal message
        self.commit( "int f() => 1;\n", "options", ( "analysis_options.yaml", self.OPTIONS ) )
        base = self.sh( "rev-parse", "HEAD" )
        self.commit( "int f() => 1;\n", "forced file", ( "build/zz_broken.dart", "int x = 'no';\n" ) )
        with tempfile.TemporaryDirectory() as logs:
            code, detail = mg.check_analyzer( base, logs, root=self.d, allow_config=False, allow_ignores=False )
        self.assertEqual( code, 1 )
        self.assertIn( "analyzer-excluded", detail )
        self.assertIn( "build/zz_broken.dart", detail )

    def test_the_docs_ignore_form_is_not_exempt( self ):                           # N1 ruling
        c4 = self.commit( "// ignore: public_member_api_docs - generated\nint f() => 2;\n", "docs ignore" )
        self.assertEqual( mg.ignore_additions( self.c3, c4, self.d ), [ ( "a.dart", "public_member_api_docs - generated" ) ] )

    def test_a_range_that_adds_an_ignore_fails_the_analyzer_row( self ):            # N1
        c4 = self.commit( "// ignore_for_file: invalid_assignment\nint f() => 2;\n", "adds an ignore" )
        with tempfile.TemporaryDirectory() as logs:
            code, detail = mg.check_analyzer( self.c3, logs, root=self.d, allow_config=False, allow_ignores=False )
        self.assertEqual( code, 1 )
        self.assertIn( "a.dart", detail )
        self.assertIn( "invalid_assignment", detail )
        self.assertIn( "--allow-ignores", detail )

    def test_dart_roots_at_a_commit( self ):                                       # N2
        self.assertEqual( mg.dart_roots_at( self.c3, self.d ), [ "a.dart" ] )
        c4 = self.commit( "int f() => 2;\n", "adds integration test", ( "integration_test/z.dart", "int z = 1;\n" ) )
        self.assertEqual( mg.dart_roots_at( c4, self.d ), [ "a.dart", "integration_test" ] )
        self.assertEqual( mg.dart_roots_at( self.c0, self.d ), [ "a.dart" ] )

    def test_main_refuses_to_run_with_an_untracked_lib_file( self ):
        os.makedirs( os.path.join( self.d, "lib" ), exist_ok=True )
        with open( os.path.join( self.d, "lib", "zz_missing.dart" ), "w" ) as f: f.write( "x" )
        err = io.StringIO()
        with contextlib.redirect_stderr( err ): code = mg.main( [ "--skip-suite", self.c3 ], root=self.d )
        self.assertEqual( code, 2 )
        self.assertIn( "lib/zz_missing.dart", err.getvalue() )

    def test_resolve_range_forms( self ):
        self.assertEqual( mg.resolve_range( None, "main", self.d ), ( self.c3, self.c3 ) )          # base is HEAD itself
        self.assertEqual( mg.resolve_range( f"{self.c0}..{self.c2}", "main", self.d ), ( self.c0, self.c2 ) )
        self.assertEqual( mg.resolve_range( self.c1, "main", self.d ), ( self.c0, self.c1 ) )

    def test_unknown_revision_raises( self ):
        with self.assertRaises( RuntimeError ): mg.resolve_range( "nope", "main", self.d )


if __name__ == "__main__":
    unittest.main()
