#!/usr/bin/env python3
"""Smoke test for tool/check_test_failures.py — run: python3 tool/test_check_test_failures.py"""
import json, os, sys, tempfile, unittest
sys.path.insert( 0, os.path.dirname( os.path.abspath( __file__ ) ) )
import check_test_failures as c


def run_file( d, name, results ):
    """Write a minimal JSON-lines run: results maps test name -> 'success'|'failure'."""
    p = os.path.join( d, name )
    root = c.ROOT
    lines = [ json.dumps( { "type": "suite", "suite": { "id": 0, "path": f"{root}/test/a_test.dart" } } ) ]
    for i, ( n, r ) in enumerate( results.items(), 1 ):
        lines.append( json.dumps( { "type": "testStart", "test": { "id": i, "name": n, "suiteID": 0 } } ) )
        lines.append( json.dumps( { "type": "testDone", "testID": i, "result": r, "hidden": False, "skipped": False } ) )
    open( p, "w" ).write( "\n".join( lines ) )
    return p


class GateTest( unittest.TestCase ):

    def test_exit_codes( self ):
        orig = c.BASELINE
        with tempfile.TemporaryDirectory() as d:
            try:
                c.BASELINE = os.path.join( d, "b.json" )
                self.assertEqual( c.check( run_file( d, "x.json", { "t": "success" } ) ), c.BASELINE_OR_INPUT_BAD )
                runs = [ run_file( d, f"r{i}.json", r ) for i, r in enumerate( [
                    { "always": "failure", "some": "failure", "ok": "success" },
                    { "always": "failure", "some": "success", "ok": "success" } ] ) ]
                c.build( runs )
                b = json.load( open( c.BASELINE ) )
                self.assertEqual( ( b[ "always_fail" ], b[ "sometimes_fail" ] ),
                                  ( [ "test/a_test.dart::always" ], [ "test/a_test.dart::some" ] ) )
                known = run_file( d, "k.json", { "always": "failure", "ok": "success" } )
                bad   = run_file( d, "n.json", { "always": "failure", "ok": "failure" } )
                self.assertEqual( c.check( known ), c.NO_NEW_FAILURE )
                self.assertEqual( c.check( bad ), c.RERUN_REQUIRED )
                self.assertEqual( c.check( bad, bad ), c.NEW_FAILURE )
                self.assertEqual( c.check( bad, known ), c.NO_NEW_FAILURE )   # did not repeat
                self.assertEqual( c.check( os.path.join( d, "missing.json" ) ), c.BASELINE_OR_INPUT_BAD )
            finally:
                c.BASELINE = orig


if __name__ == "__main__": unittest.main()
