#!/usr/bin/env python3
"""Smoke/unit test for tool/doc_coverage.py — run: python3 tool/test_doc_coverage.py"""
import os, sys, tempfile, unittest
sys.path.insert( 0, os.path.dirname( os.path.abspath( __file__ ) ) )
import doc_coverage as dc

MACH = "\n".join( [
    "INFO|LINT|PUBLIC_MEMBER_API_DOCS|lib/core/a.dart|1|1|1|Missing a doc",
    "INFO|LINT|PUBLIC_MEMBER_API_DOCS|lib/features/queue/b.dart|1|1|1|Missing a \\| doc",
    "INFO|LINT|PUBLIC_MEMBER_API_DOCS|/tmp/x/lib/features/queue/c.dart|1|1|1|m",
    "INFO|LINT|PUBLIC_MEMBER_API_DOCS|lib/app.dart|1|1|1|m",
    "WARNING|HINT|UNUSED_IMPORT|lib/core/a.dart|1|1|1|m",
] )


class DocCoverageTest( unittest.TestCase ):

    def test_parse_keeps_only_rule_hits( self ):
        self.assertEqual( len( dc.parse_machine( MACH ) ), 4 )

    def test_buckets( self ):
        t = dc.tally( dc.parse_machine( MACH ) )
        self.assertEqual( t[ "by_top" ], { "(lib root)": 1, "core": 1, "features": 2 } )
        self.assertEqual( t[ "by_feature" ], { "features/queue": 2 } )

    def test_compare_flags_growth_only( self ):
        base = dc.tally( dc.parse_machine( MACH ) )
        self.assertEqual( dc.compare( base, base ), [] )
        more = dc.tally( dc.parse_machine( MACH + "\nINFO|LINT|PUBLIC_MEMBER_API_DOCS|lib/core/z.dart|1|1|1|m" ) )
        self.assertEqual( len( dc.compare( more, base ) ), 2 )   # total + core
        less = dc.tally( dc.parse_machine( MACH.splitlines()[ 0 ] ) )
        self.assertEqual( dc.compare( less, base ), [] )

    def test_exit_codes( self ):
        with tempfile.NamedTemporaryFile( "w", suffix=".txt", delete=False ) as f: f.write( MACH )
        orig = dc.BASELINE
        try:
            dc.BASELINE = "/nonexistent/base.json"
            self.assertEqual( dc.main( [ "--machine", f.name ] ), 2 )
            dc.BASELINE = os.path.join( tempfile.mkdtemp(), "b.json" )
            self.assertEqual( dc.main( [ "--machine", f.name, "--write" ] ), 0 )
            self.assertEqual( dc.main( [ "--machine", f.name ] ), 0 )
            with open( f.name, "a" ) as g: g.write( "\nINFO|LINT|PUBLIC_MEMBER_API_DOCS|lib/ui/n.dart|1|1|1|m\n" )
            self.assertEqual( dc.main( [ "--machine", f.name ] ), 1 )
        finally:
            dc.BASELINE = orig; os.unlink( f.name )


if __name__ == "__main__": unittest.main()
