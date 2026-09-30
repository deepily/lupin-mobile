#!/usr/bin/env python3
"""
Capture real `/api/tasks` responses for the fleet-pane row tests.

Usage:
    export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL="..."
    export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD="..."
    # Optional, defaults to http://localhost:7999
    # export LUPIN_API_BASE_URL="http://10.0.2.2:7999"
    python src/scripts/capture-tasks-fixtures.py

See test/fixtures/README.md for the pattern and the redaction contract.

WHY THIS EXISTS RATHER THAN A HAND-WRITTEN MAP. A stub encodes the author's beliefs
about the shape, so it can only ever confirm them. `TaskRowModel` maps twelve cells and
most of them are independently nullable — a terse pull carries no `body` and no
`item_class`, `next_chase_ts` is null on most rows, `blocked_by` is usually an empty
list but is sometimes populated, and `priority` and `project` are null on rows nobody
has triaged. A fixture I typed myself would have every field populated, the mapper would
pass, and the first real row with an unexpected null would be the thing that found the
bug. test/fixtures/README.md records the motivating incident for exactly this
(`LoginResponse` envelope parse).

🔴 REDACTION MUST NOT CHANGE NULL-NESS. That is the one rule with teeth here. Replacing a
null with a placeholder, or filling an absent key, would hand the tests back the very
blind spot this capture exists to remove — a redactor that "tidies" the data is writing a
stub with extra steps. Every redaction below is value-for-value on a key that is already
present and non-null.
"""

from __future__ import annotations

import json
import os
import sys
from typing import Any

import _fixture_lib as lib


DOMAIN           = "tasks"
DEFAULT_BASE_URL = "http://localhost:7999"

# Keep fixtures small enough to read in a diff. The SHAPE is what matters, not the volume.
MAX_ROWS = 8

# The one capture that needs more rows than SHAPE requires, because the thing it has to
# contain is a REPETITION rather than a field: one persona filing from two sessions. Eight
# rows off the top of the board is not reliably wide enough to hold a second session of
# anybody, and a fixture that only sometimes contains the case is a test that only
# sometimes tests it.
MAX_WIDE_ROWS = 14


def _redact_row( row: dict[str, Any], idx: int ) -> dict[str, Any]:
    """Stabilise the identifying values of one row, preserving every null exactly."""
    out = { **row }

    # Ids and free text become stable placeholders — but ONLY where they are already
    # present and non-null. `if out.get(k) is not None` is doing real work on every line
    # below: an absent or null key must survive as absent or null.
    if out.get( "id" ) is not None:
        out[ "id" ] = f"task-fixture-{idx}"
    if out.get( "title" ) is not None:
        # Keep the length class — the 360 dp finding is about long titles sharing a
        # prefix, so a fixture of short titles would hide it.
        out[ "title" ] = f"[LUPIN-MOBILE] Phase {idx}: fixture row {idx} with a title long enough to truncate"
    if out.get( "body" ) is not None:
        out[ "body" ] = f"fixture body for row {idx}"

    for key in ( "created_ts", "updated_ts", "request_ts", "park_reason_captured_at" ):
        if out.get( key ) is not None:
            out[ key ] = lib.REDACT_TIMESTAMP

    return out


def main() -> int:
    base_url = os.environ.get( "LUPIN_API_BASE_URL", DEFAULT_BASE_URL )
    email    = os.environ.get( "LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL" )
    password = os.environ.get( "LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD" )

    if not email or not password:
        print(
            "ERROR: set LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL and "
            "LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD",
            file=sys.stderr,
        )
        return 2

    print( f"Capturing {DOMAIN} fixtures from {base_url}" )
    _, access, _ = lib.login_for_capture( base_url, email, password )
    auth = { "Authorization": f"Bearer {access}" }

    # The four shapes the panes actually request. Each is captured as the WHOLE envelope,
    # because `truncated` / `total` / `has_more` are part of what the repository must read
    # and a fixture of just the rows would quietly drop them.
    captures = [
        # The Task List's real query: terse, unscoped, parked rows visible.
        ( "task_list_terse.json",
          f"/api/tasks?limit={MAX_ROWS}&unscoped_audit=true&hide_parked=false&terse=true" ),
        # The same page NON-terse, so the fixtures carry `body` and `item_class` and the
        # mapper is exercised on both projections.
        ( "task_list_full.json",
          f"/api/tasks?limit={MAX_ROWS}&unscoped_audit=true&hide_parked=false" ),
        # The Holding Area. `status=not_approved` is the whole pane — those rows are
        # excluded from an ordinary query by default.
        ( "holding_area.json",
          f"/api/tasks?limit={MAX_ROWS}&unscoped_audit=true&status=not_approved" ),
        # 🔴 THE SAME PANE, WIDE ENOUGH TO CONTAIN ONE PERSONA'S SECOND SESSION.
        # Rick's R1=B ruling (09-22) merges a persona's sessions into ONE group, and the
        # eight-row page above cannot show that: it happens to hold one session each of
        # "mr radio" and "maya", so a grouper that merged sessions and one that did not
        # would produce IDENTICAL output against it. The wider page carries "maria" and
        # "mr radio" across two sessions apiece, a TWO-WORD persona, and the store's own
        # mixed casing ("Krishna" beside "maria") — the three things the persona key has
        # to survive. Censused live 2026-09-23: 41 held rows, six personas, two of them
        # multi-session.
        #
        # ⚠️ THE ROW CAP IS THE SERVER'S, NOT THIS NUMBER. `limit=200` comes back with 14
        # rows and `has_more: true`; asking for the cap is what makes the page WIDE rather
        # than what makes it 14 long.
        ( "holding_area_multi_session.json",
          "/api/tasks?limit=200&unscoped_audit=true&status=not_approved",
          MAX_WIDE_ROWS ),
        # An empty result that is NOT an error — the case §10 names explicitly.
        ( "holding_area_empty.json",
          "/api/tasks?limit=8&unscoped_audit=true&status=not_approved"
          "&project=a-project-that-does-not-exist" ),
    ]

    for capture in captures:
        filename, path = capture[ 0 ], capture[ 1 ]
        max_rows       = capture[ 2 ] if len( capture ) > 2 else MAX_ROWS

        status, body = lib.get_json( base_url, path, headers=auth )
        if status != 200:
            print( f"ERROR: GET {path} returned {status}: {body}", file=sys.stderr )
            return 4
        if not isinstance( body, dict ):
            print( f"ERROR: GET {path} returned {type( body ).__name__}, expected an envelope",
                   file=sys.stderr )
            return 5

        rows = body.get( "tasks" ) or []
        body = {
            **body,
            "tasks": [ _redact_row( r, i ) for i, r in enumerate( rows[ :max_rows ] ) ],
        }
        _stabilise_warnings( body )

        lib.assert_no_jwt_residue( body, filename )
        lib.write_fixture( DOMAIN, filename, body )

        nulls = _null_census( body.get( "tasks" ) or [] )
        print( f"    {len( body['tasks'] )} rows; keys null in at least one row: "
               f"{', '.join( sorted( nulls ) ) or '(none)'}" )

    print( "Done." )
    return 0


def _stabilise_warnings( body: dict[str, Any] ) -> None:
    """Replace the server's warning PROSE with a placeholder, keeping the key and the
    count.

    ⚠️ THIS IS NOT COSMETIC, AND IT IS NOT A REDACTION EITHER — it works around a false
    positive in the shared safety net. `assert_no_jwt_residue` is a naive three-dot check:
    any string of exactly three dot-separated segments, each 20+ characters, is treated as
    an unredacted JWT. The server's own row-cap warning is ordinary English prose that
    happens to contain two periods with long runs between them, so it trips the net:

        "row-cap truncation - 8 of 16 matching rows returned (li..."

    ⇒ The net is doing its job badly here, not doing the wrong job, so this script works
    around it rather than loosening it. Weakening a check that exists to stop a credential
    reaching a fixture file, in order to make a capture run, is the wrong trade in every
    case. The false-positive class is reported separately — any captured domain with a
    long prose field is exposed to it.

    What the tests need from `warnings` is that the key exists and carries a list of
    strings, which survives this intact.
    """
    warnings = body.get( "warnings" )
    if isinstance( warnings, list ):
        body[ "warnings" ] = [ f"fixture warning {i}" for i in range( len( warnings ) ) ]


def _null_census( rows: list[dict[str, Any]] ) -> set[str]:
    """Which keys are null or absent somewhere in this page.

    Printed at capture time because it is the evidence that the capture was worth
    making: a page where nothing is ever null tells the tests nothing a stub could not,
    and is a signal to widen the query rather than to accept the fixture.
    """
    keys = { k for r in rows for k in r }
    return { k for k in keys if any( r.get( k ) is None for r in rows ) }


if __name__ == "__main__":
    sys.exit( main() )
