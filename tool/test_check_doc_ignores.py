#!/usr/bin/env python3
"""Unit test for tool/check_doc_ignores.py — run: python3 -m pytest tool/test_check_doc_ignores.py"""
import contextlib, io, os, sys, tempfile, unittest
sys.path.insert( 0, os.path.dirname( os.path.abspath( __file__ ) ) )
import check_doc_ignores as cdi

GOOD  = "// ignore: public_member_api_docs - generated override, see x.dart\nclass A {}\n"
FILEW = "// ignore_for_file: public_member_api_docs\nclass A {}\n"
BARE  = "// ignore: public_member_api_docs\nclass A {}\n"
WEAK  = "// ignore: public_member_api_docs - TODO\nclass A {}\n"
OTHER = "// ignore: unused_element\n// ignore_for_file: avoid_print\nclass A {}\n"
DOC   = "/// Mentions // ignore: public_member_api_docs in prose.\nclass A {}\n"


def run( files ):
    """Write { relative path: text } under a temp repo, run the gate on lib/, return ( code, output )."""
    root = tempfile.mkdtemp()
    for rel, text in files.items():
        path = os.path.join( root, rel )
        os.makedirs( os.path.dirname( path ), exist_ok=True )
        with open( path, "w", encoding="utf-8" ) as f: f.write( text )
    out = io.StringIO()
    with contextlib.redirect_stdout( out ):
        code = cdi.main( [ "--root", root ] )
    return code, out.getvalue()


class CheckDocIgnoresTest( unittest.TestCase ):

    def test_positive_control_file_wide_ignore_fails( self ):
        code, out = run( { "lib/a/x.dart": FILEW } )
        self.assertEqual( code, 1 )
        self.assertIn( "lib/a/x.dart:1: ignore_for_file", out )

    def test_positive_control_bare_ignore_fails( self ):
        code, out = run( { "lib/a/x.dart": BARE } )
        self.assertEqual( code, 1 )
        self.assertIn( "no reason on the same line", out )

    def test_placeholder_reason_fails( self ):
        code, out = run( { "lib/a/x.dart": WEAK } )
        self.assertEqual( code, 1 )
        self.assertIn( "names no fact", out )

    def test_ignore_with_reason_passes_and_is_counted_per_directory( self ):
        code, out = run( { "lib/a/x.dart": GOOD, "lib/a/y.dart": GOOD, "lib/b/z.dart": GOOD } )
        self.assertEqual( code, 0 )
        self.assertIn( "   2  lib/a", out )
        self.assertIn( "   1  lib/b", out )

    def test_other_rules_and_doc_comments_are_not_touched( self ):
        code, out = run( { "lib/a/x.dart": OTHER, "lib/a/y.dart": DOC } )
        self.assertEqual( code, 0 )
        self.assertIn( "(none)", out )

    def test_one_violation_among_clean_files_still_fails( self ):
        code, _ = run( { "lib/a/x.dart": GOOD, "lib/b/y.dart": BARE } )
        self.assertEqual( code, 1 )

    def test_no_dart_files_is_bad_input( self ):
        code, out = run( { "lib/a/readme.txt": "x" } )
        self.assertEqual( code, 2 )
        self.assertIn( "INPUT BAD", out )

    def test_missing_path_is_bad_input( self ):
        out = io.StringIO()
        with contextlib.redirect_stdout( out ):
            code = cdi.main( [ "--root", tempfile.mkdtemp(), "nowhere" ] )
        self.assertEqual( code, 2 )

    def test_real_tree_has_no_violations( self ):
        out = io.StringIO()
        with contextlib.redirect_stdout( out ):
            code = cdi.main( [] )
        self.assertEqual( code, 0, out.getvalue() )


if __name__ == "__main__":
    unittest.main()
