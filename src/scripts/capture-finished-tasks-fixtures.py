#!/usr/bin/env python3
"""
Capture REAL `/api/tasks/events` responses for the Finished Tasks pane.

WHY THIS EXISTS RATHER THAN HAND-WRITTEN JSON (Tiffany, 2026-09-19). A fixture
written by the same hand that wrote the parser encodes that hand's ASSUMPTIONS, so
the test passes against a shape the server may never produce. Chloé's pass found
exactly that failure in a neighbouring feature: hand-written fixtures disagreed with
live data on NULLABILITY, and the tests were green about it.

The columns this pane is most exposed on:

  · `reason`  → the WHY column. Nullable on the wire, and in practice very often
                null or blank — a transition can be recorded without one. The pane
                renders an em dash for both, and only live data says how common
                that is and whether blank-vs-null both occur.
  · `actor`   → the WHO column. Nullable, and when present it is shaped
                `<persona> <8-hex session>` — except when it is not. A TWO-WORD
                persona ("mr radio 8353ea70") is the case the naive leading-word
                split gets wrong, and a bare session id with no name is a real
                stored value that must render WHOLE.
  · `transition` → the status glyph. Nullable, and a torn value must render
                untinted rather than take the pane down.

Usage:
    export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL=...
    export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD=...
    export LUPIN_API_BASE_URL=http://localhost:7999        # optional
    python3 src/scripts/capture-finished-tasks-fixtures.py

Writes to test/fixtures/finished_tasks/:
    events_<status>.json   one capture per terminal status
    nullability.json       the measured shape report — what was null, how often

⚠️ REDACTION. Event rows carry `actor` (persona + session id) and `reason` (free
text a human wrote). Session ids are pseudonymous rather than secret and the persona
is the point of the WHO column, so both are KEPT — the fixture is worthless without
them. `receipt_refs` can carry commit shas and file paths and is kept too. Anything
resembling a JWT is asserted absent by the shared helper before the file is written.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert( 0, str( Path( __file__ ).resolve().parent ) )

import _fixture_lib as lib  # noqa: E402

DOMAIN           = "finished_tasks"
DEFAULT_BASE_URL = "http://localhost:7999"
ENDPOINT         = "/api/tasks/events"

# The three terminal statuses the pane can light. Kept in step with
# `kFinishedStatuses` in finished_tasks_models.dart.
STATUSES = ( "done", "dropped", "wont_fix" )

# 14 days — the pane's widest window, so one capture serves every slider position.
WINDOW_DAYS = 14
PAGE_LIMIT  = 500


def _since_iso( days: int ) -> str:
    from datetime import datetime, timedelta, timezone
    return ( datetime.now( timezone.utc ) - timedelta( days=days ) ).isoformat()


def _measure_nullability( rows: list[dict] ) -> dict:
    """
    Report what the live data actually contains, field by field.

    Ensures:
        - counts null and blank SEPARATELY, because the pane treats them the same
          and that equivalence is a decision rather than an accident
        - reports the actor shapes seen, so the two-word-persona and bare-session-id
          cases are visible rather than assumed
    """
    def blanks( field: str ) -> dict:
        nulls  = sum( 1 for r in rows if r.get( field ) is None )
        blank  = sum( 1 for r in rows if isinstance( r.get( field ), str ) and not r[ field ].strip() )
        return { "null": nulls, "blank": blank, "present": len( rows ) - nulls - blank }

    import re
    trailing_id = re.compile( r"\s+[0-9a-f]{8}$", re.IGNORECASE )
    bare_id     = re.compile( r"^[0-9a-f]{8}$", re.IGNORECASE )

    actor_shapes = { "two_word_persona": 0, "one_word_persona": 0, "bare_session_id": 0, "no_session_id": 0 }
    for r in rows:
        a = r.get( "actor" )
        if not isinstance( a, str ) or not a.strip():
            continue
        a = a.strip()
        if bare_id.match( a ):
            actor_shapes[ "bare_session_id" ] += 1
        elif trailing_id.search( a ):
            name = trailing_id.sub( "", a )
            key  = "two_word_persona" if " " in name.strip() else "one_word_persona"
            actor_shapes[ key ] += 1
        else:
            actor_shapes[ "no_session_id" ] += 1

    return {
        "rows"        : len( rows ),
        "reason"      : blanks( "reason" ),
        "actor"       : blanks( "actor" ),
        "transition"  : blanks( "transition" ),
        "title"       : blanks( "title" ),
        "actor_shapes": actor_shapes,
    }


def main() -> int:
    email    = os.environ.get( "LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL"    )
    password = os.environ.get( "LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD" )
    base_url = os.environ.get( "LUPIN_API_BASE_URL", DEFAULT_BASE_URL ).rstrip( "/" )

    if not email or not password:
        print(
            "ERROR: set LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL and "
            "LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD",
            file=sys.stderr,
        )
        return 1

    print( f"Capturing finished-tasks fixtures against {base_url}..." )
    _, access_token, _ = lib.login_for_capture( base_url, email, password )
    auth_hdr = { "Authorization": f"Bearer {access_token}" }

    since    = _since_iso( WINDOW_DAYS )
    all_rows : list[dict] = []

    for status in STATUSES:
        # The encoding lives in the shared lib, not here — Tiffany's ruling after the
        # "+00:00 decodes to a space" 422 this script found on its first run. One
        # encoder means fixing it here fixed it for capture-tasks-fixtures.py too,
        # which this script never touches.
        path = lib.build_query( ENDPOINT, {
            "to_status" : status,
            "since"     : since,
            "limit"     : PAGE_LIMIT,
        } )
        code, body = lib.get_json( base_url, path, headers=auth_hdr )
        if code != 200:
            print( f"  {status}: HTTP {code} — skipped", file=sys.stderr )
            continue
        rows = body.get( "events", [] )
        all_rows.extend( rows )
        # The `since` instant is a wall-clock value and would churn the fixture on
        # every capture; the rows' own ts values are the data and are kept.
        lib.write_fixture( DOMAIN, f"events_{status}.json", body )
        print( f"  {status}: {len( rows )} events" )

    report = _measure_nullability( all_rows )
    lib.write_fixture( DOMAIN, "nullability.json", report )

    print( "\nMeasured shape:" )
    print( f"  rows           : {report[ 'rows' ]}" )
    for field in ( "reason", "actor", "transition", "title" ):
        f = report[ field ]
        print( f"  {field:<15}: null={f[ 'null' ]} blank={f[ 'blank' ]} present={f[ 'present' ]}" )
    print( f"  actor shapes   : {report[ 'actor_shapes' ]}" )

    if report[ "rows" ] == 0:
        print(
            "\n⚠️ ZERO ROWS CAPTURED. A fixture of nothing proves nothing — widen the "
            "window or capture against an environment with finished work.",
            file=sys.stderr,
        )
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit( main() )
