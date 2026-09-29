#!/usr/bin/env python3
"""
Capture the SIX real Claude-Code-transcript fixtures the `pending-capture` tests
need, redact them, and write them to `test/fixtures/transcript/`.

Row 768e852f slice 4. The consumers are the two tagged files, and their headers
are the authoritative spec for each fixture's content:
    test/widget/transcript/live_console_captured_test.dart
    test/widget/fleet_status/fleet_watch_button_captured_test.dart

    fixture                        source                                      gate
    ----------------------------   -----------------------------------------   -----------
    watchable_roster.json          GET /api/cc-transcript-roster               ADMIN
    fleet_state_recaptured.json    GET /api/arbiter/fleet-state                jwt
    backlog_403.json               GET /api/cc-transcript/{id}  (the refusal)  non-admin
    append_mixed_kinds.json        WS  cc_transcript_append                    ADMIN (ws)
    append_thinking.json           WS  cc_transcript_append                    ADMIN (ws)
    state_refused.json             WS  cc_transcript_state                     ADMIN (ws)

🔴 FOUR OF THE SIX NEED AN ADMIN ACCOUNT, AND THE SERVER TEAM HAS ALREADY WRITTEN
DOWN THAT THE FLEET DOES NOT HAVE ONE. From `cosa/rest/routers/cc_transcript.py`:
*"the only admin accounts are `admin@lupin.deepily.ai` and Rick's own, and the
fleet holds neither password … Rick ruled 2026-09-27 that v1 ships on the
`dependency_overrides[ require_admin ]` positive arm, with a dev-only test admin
account as a separate follow-up."* So this script CANNOT complete on the ordinary
capture credentials, and it says so loudly per fixture instead of writing
something plausible. A fabricated fixture is worse than a red test: the red test
is honest.

⚠️ AND THE TWO GATES ARE DIFFERENT MECHANISMS. The REST routes use
`require_admin`; the WebSocket verbs use
`websocket_manager.session_is_admin[ session_id ]`. Being let through one proves
nothing about the other, so this script probes and reports them separately.

Usage:
    export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL="..."
    export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD="..."
    # An ADMIN login, for the four admin-gated fixtures:
    export LUPIN_ADMIN_EMAIL="..."
    export LUPIN_ADMIN_PASSWORD="..."
    # Optional, defaults to http://localhost:7999
    # export LUPIN_API_BASE_URL="http://localhost:7999"
    python src/scripts/capture-transcript-fixtures.py [--seat <cc_session_id>]

Exit codes:
    0  every fixture this run was able to capture was captured, and the run is
       COMPLETE (all six on disk)
    4  partial: what could be captured was, and what could not is named. This is
       a deliberate non-zero — a partial capture must not read as success to any
       caller that only checks the status.
    2  the server or the login is unusable (nothing was captured)
    3  a captured body failed its own shape check — a phase-1 finding

See test/fixtures/README.md for the redaction contract.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any, Optional

import _fixture_lib as lib

DOMAIN           = "transcript"
DEFAULT_BASE_URL = "http://localhost:7999"

# Every fixture this script owns. Used for the final completeness report, so a
# fixture cannot be quietly forgotten by being left out of the summary.
ALL_FIXTURES = (
    "watchable_roster.json",
    "fleet_state_recaptured.json",
    "backlog_403.json",
    "append_mixed_kinds.json",
    "append_thinking.json",
    "state_refused.json",
)

# ── outcome bookkeeping ──────────────────────────────────────────────────────

captured: list[ str ] = []
blocked : dict[ str, str ] = {}


def _ok( name: str ) -> None:
    captured.append( name )


def _block( name: str, why: str ) -> None:
    """Record a fixture that could NOT be captured, with the reason a reader can
    act on. Never writes a placeholder file: the consuming test must keep failing
    on the missing file, which is María's condition for the `pending-capture`
    tag."""
    blocked[ name ] = why
    print( f"  BLOCKED {name}\n          {why}", file=sys.stderr )


# ── redaction ────────────────────────────────────────────────────────────────

def _redact_seat_id( seat: str, index: int ) -> str:
    """A stable alias for a real session id.

    ⚠️ THE WIDTH IS PRESERVED ON PURPOSE. A3.6 — the question the two-body join
    exists to answer — is whether the roster and fleet-state agree on the id at
    the SAME width, and three id widths circulate in this fleet. Redacting a
    36-character UUID to `seat-1` would make the join trivially succeed and the
    test vacuous, so the alias is a UUID of the same shape.
    """
    return f"00000000-0000-4000-8000-{index:012d}"


def _build_seat_alias_map( *bodies: Any ) -> dict[ str, str ]:
    """One alias per real session id, shared across every fixture in the run.

    🔴 ONE MAP FOR ALL BODIES, NOT ONE PER BODY. The roster and fleet-state
    fixtures are joined BY ID by the test that reads them. Redacting them
    independently would give the same seat two different aliases and break the
    join — which the test would report as an A3.6 id-width finding, i.e. a real
    bug in phase 1 that does not exist. Measured risk, not hypothetical: that
    test's own header says a red on the join "is the finding, not a test bug".
    """
    seen: dict[ str, str ] = {}

    def walk( node: Any ) -> None:
        if isinstance( node, dict ):
            for key, value in node.items():
                if key in ( "session_id", "cc_session_id" ) and isinstance( value, str ) and value:
                    if value not in seen:
                        seen[ value ] = _redact_seat_id( value, len( seen ) + 1 )
                else:
                    walk( value )
        elif isinstance( node, list ):
            for item in node:
                walk( item )

    for body in bodies:
        walk( body )
    return seen


def _apply_aliases( node: Any, aliases: dict[ str, str ] ) -> Any:
    """Rewrite every session id in place, recursively, using [aliases]."""
    if isinstance( node, dict ):
        return {
            key: ( aliases.get( value, value )
                   if key in ( "session_id", "cc_session_id" ) and isinstance( value, str )
                   else _apply_aliases( value, aliases ) )
            for key, value in node.items()
        }
    if isinstance( node, list ):
        return [ _apply_aliases( item, aliases ) for item in node ]
    return node


# ── the REST half ────────────────────────────────────────────────────────────

def capture_backlog_403( base: str, user_headers: dict[ str, str ], seat: str ) -> None:
    """`backlog_403.json` — the endpoint's REAL refusal body.

    🔴 A FINDING ABOUT THIS FIXTURE'S PREMISE, worth reading before trusting it.
    The consuming test describes this as "the REST endpoint's real 403 body for a
    seat the caller may not read". There is NO SUCH CASE. `get_cc_transcript`
    raises nothing at all: a seat with no readable transcript returns **200** with
    `blocks: []` and `watchable: false`, because "this seat is not printing" is an
    answer. The only 403 the route can produce comes from the `require_admin`
    dependency, i.e. the caller is not an admin — not the seat.

    So this captures the one refusal that exists. It is still the right fixture
    for the test's actual assertion (the refusal reason on screen is the SERVER's
    string, read through the repository's own 403 mapping), but the row's wording
    should be corrected rather than left to imply a per-seat gate that is not
    there.
    """
    status, body = lib.get_json( base, f"/api/cc-transcript/{seat}", headers=user_headers )

    if status != 403:
        _block( "backlog_403.json",
                f"GET /api/cc-transcript/{{seat}} answered {status}, not 403. The capture "
                f"account must be a NON-admin for this fixture (the 403 is the "
                f"require_admin gate). Body: {json.dumps( body )[:200]}" )
        return

    if not ( isinstance( body, dict ) and isinstance( body.get( "detail" ), str )
             and body[ "detail" ].strip() ):
        _block( "backlog_403.json",
                f"the 403 body carries no non-empty string `detail`, and the test puts that "
                f"string on screen. Got: {json.dumps( body )[:200]}" )
        return

    lib.write_fixture( DOMAIN, "backlog_403.json", body )
    _ok( "backlog_403.json" )


def capture_fleet_state( base: str, headers: dict[ str, str ] ) -> Optional[ dict ]:
    """`fleet_state_recaptured.json` — returns the RAW body so the roster capture
    can share one alias map with it."""
    status, body = lib.get_json( base, "/api/arbiter/fleet-state", headers=headers )

    if status != 200 or not isinstance( body, dict ):
        _block( "fleet_state_recaptured.json",
                f"GET /api/arbiter/fleet-state answered {status}: {json.dumps( body )[:200]}" )
        return None

    if body.get( "status" ) == "unreachable":
        # A3.7: this is NOT an empty fleet, and capturing it would bake a dead
        # arbiter into a fixture that is supposed to carry real seats.
        _block( "fleet_state_recaptured.json",
                "fleet-state reports status=unreachable — the :8001 arbiter is down. "
                "That is a real envelope but useless here: the test needs seats to join "
                "against. Bring the arbiter up and re-run." )
        return None

    sessions = ( body.get( "fleet_arbiter" ) or {} ).get( "sessions" ) or []
    if not sessions:
        _block( "fleet_state_recaptured.json",
                "fleet_arbiter.sessions is EMPTY. The consuming test iterates the sessions "
                "and would assert nothing at all — a vacuous pass. Capture while seats are "
                "live." )
        return None

    return body


def capture_roster( base: str, admin_headers: dict[ str, str ] ) -> Optional[ dict ]:
    """`watchable_roster.json` — returns the RAW body; shares the alias map with
    fleet-state.

    The test requires `transcript_watchable` BOTH true and false, because it
    proves an "iff" and needs both directions. That is a property of the LIVE
    FLEET at capture time, not something this script may manufacture — so it is
    verified and reported, never fixed up.
    """
    status, body = lib.get_json( base, "/api/cc-transcript-roster", headers=admin_headers )

    if status == 403:
        _block( "watchable_roster.json",
                "403 from /api/cc-transcript-roster — the login is not an admin. This route "
                "is require_admin (ruling Q5, console is admin-only)." )
        return None
    if status != 200 or not isinstance( body, dict ):
        _block( "watchable_roster.json",
                f"GET /api/cc-transcript-roster answered {status}: {json.dumps( body )[:200]}" )
        return None
    if body.get( "status" ) == "unreachable":
        _block( "watchable_roster.json",
                "the roster reports status=unreachable — :8001 is down (A3.7: that is not an "
                "empty fleet). Bring the arbiter up and re-run." )
        return None

    seats = body.get( "seats" ) or []
    yes   = [ s for s in seats if s.get( "transcript_watchable" ) is True ]
    no    = [ s for s in seats if s.get( "transcript_watchable" ) is False ]

    if not yes or not no:
        _block( "watchable_roster.json",
                f"the live roster does not carry BOTH directions "
                f"(watchable={len(yes)}, not-watchable={len(no)}), and the test proves an "
                f"'iff' that needs both. Capture when at least one seat is printing a "
                f"transcript and at least one is not — do NOT hand-edit the fixture." )
        return None

    return body


def write_joined_pair( roster: Optional[ dict ], fleet: Optional[ dict ] ) -> None:
    """Redact and write the roster + fleet-state pair under ONE alias map.

    Either may be None (blocked); whichever survived is still written, because a
    fixture that can be captured should be, and the other stays absent so its
    test stays honestly red.
    """
    aliases = _build_seat_alias_map( *[ b for b in ( roster, fleet ) if b is not None ] )

    if fleet is not None:
        redacted = _apply_aliases( fleet, aliases )
        lib.redact_timestamp_fields( redacted, ( "generated_at", ) )
        arb = redacted.get( "fleet_arbiter" )
        if isinstance( arb, dict ):
            lib.redact_timestamp_fields( arb, ( "generated_at", ) )
        lib.assert_no_jwt_residue( redacted, "fleet_state_recaptured.json" )
        lib.write_fixture( DOMAIN, "fleet_state_recaptured.json", redacted )
        _ok( "fleet_state_recaptured.json" )

    if roster is not None:
        redacted = _apply_aliases( roster, aliases )
        for seat in redacted.get( "seats" ) or []:
            lib.redact_timestamp_fields( seat, ( "last_ts", ) )
        lib.assert_no_jwt_residue( redacted, "watchable_roster.json" )
        lib.write_fixture( DOMAIN, "watchable_roster.json", redacted )
        _ok( "watchable_roster.json" )

        if fleet is not None:
            _verify_join( redacted, _apply_aliases( fleet, aliases ) )


def _verify_join( roster: dict, fleet: dict ) -> None:
    """A3.6 — do the two captured surfaces agree on the session id AT ONE WIDTH?

    This is the question §3 says phase 1 verifies rather than assumes, and the
    reason the test reads two captured bodies instead of one stubbed row. Checked
    HERE as well as in the test so the capture run itself reports a mismatch,
    rather than the finding surfacing later as a confusing widget-test failure.
    """
    roster_ids = { s.get( "session_id" ) for s in ( roster.get( "seats" ) or [] ) }
    fleet_ids  = { s.get( "session_id" )
                   for s in ( ( fleet.get( "fleet_arbiter" ) or {} ).get( "sessions" ) or [] ) }
    roster_ids.discard( None )
    fleet_ids.discard( None )

    overlap = roster_ids & fleet_ids
    if overlap:
        print( f"  A3.6 join OK — {len(overlap)} session id(s) shared at one width" )
        return

    print( "  🔴 A3.6 FINDING: the roster and fleet-state share NO session id.\n"
           f"     roster ids: {sorted( roster_ids )[:3]}\n"
           f"     fleet  ids: {sorted( fleet_ids )[:3]}\n"
           "     This is a PHASE-1 finding, not a capture bug — the two surfaces "
           "disagree on id width. Report it; do not reshape the fixtures to hide it.",
           file=sys.stderr )


# ── the WebSocket half ───────────────────────────────────────────────────────

def capture_ws_frames( base: str, admin_access: Optional[ str ], seat: Optional[ str ] ) -> None:
    """`append_mixed_kinds` · `append_thinking` · `state_refused`.

    🔴 NOT IMPLEMENTED YET, AND DELIBERATELY NOT FAKED. Two things are missing and
    the first blocks the second:

      1. AN ADMIN WS SESSION. The verbs are gated by
         `websocket_manager.session_is_admin[ session_id ]`, a DIFFERENT mechanism
         from the REST `require_admin`. Without an admin login there is nothing to
         capture, so writing the client first would be writing code nobody can run.

      2. A WEBSOCKET CLIENT IN THIS REPO'S CAPTURE TOOLING. `_fixture_lib` is
         urllib-only — every existing capture script is REST — so `cc_transcript_watch`
         needs a WS client added, plus the ~300 ms coalesce window honoured
         (`cc transcript coalesce window ms`, Rick's Q7 ruling) so one append frame
         is collected rather than a fragment.

    What the frames must carry, from the consuming test's header, so whoever
    finishes this does not have to re-derive it:
      - append_mixed_kinds: ONE frame whose `blocks` hold a prose block, a
        `tool_call`, and a `tool_result` that is NOT truncated (a truncated one
        answers over REST, which is C5.19's row, and conflating them would make
        C5.18 pass for the wrong reason)
      - append_thinking: ONE frame with a `kind: thinking` block carrying
        non-trivial text (at least one line of 8+ characters, or the test cannot
        assert either "hidden" or "shown" about it)
      - state_refused: ONE `cc_transcript_state` frame with `state: "refused"`
        carrying the server's own `reason`
      - 🔴 EVERY frame must carry its own `cc_session_id` AND `offset`. The test
        uses them rather than substituting its own, and seeds the backlog read so
        the append's offset is continuous. An append with no offset is a phase-1
        finding, not a test bug.
    """
    why = ( "not implemented: needs (a) an ADMIN WebSocket session — the verbs are gated by "
            "websocket_manager.session_is_admin, a different mechanism from the REST "
            "require_admin — and (b) a WS client in the capture tooling, which is urllib-only "
            "today. The required frame contents are documented in this function's docstring." )
    if admin_access is None:
        why = "no admin login available, and the WS verbs are admin-gated. " + why
    for name in ( "append_mixed_kinds.json", "append_thinking.json", "state_refused.json" ):
        _block( name, why )


# ── main ─────────────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser( description="Capture transcript fixtures from a live server." )
    parser.add_argument( "--seat", default=None,
                         help="cc_session_id to read a backlog for. Defaults to a live seat "
                              "from fleet-state, else this process's own session." )
    args = parser.parse_args()

    base = os.environ.get( "LUPIN_API_BASE_URL", DEFAULT_BASE_URL )
    print( f"Capturing transcript fixtures from {base}\n" )

    # ── the ordinary (non-admin) login: fleet-state, and the 403 body ────────
    email = os.environ.get( "LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL" )
    pw    = os.environ.get( "LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD" )
    if not email or not pw:
        print( "ERROR: LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL / _PASSWORD must be set.",
               file=sys.stderr )
        return 2

    _, access, _ = lib.login_for_capture( base, email, pw )
    user_headers = { "Authorization": f"Bearer {access}" }
    print( f"non-admin login ok ({email})" )

    # ── the admin login, if the fleet has one ───────────────────────────────
    admin_email = os.environ.get( "LUPIN_ADMIN_EMAIL" )
    admin_pw    = os.environ.get( "LUPIN_ADMIN_PASSWORD" )
    admin_access: Optional[ str ] = None
    admin_headers: Optional[ dict[ str, str ] ] = None
    if admin_email and admin_pw:
        _, admin_access, _ = lib.login_for_capture( base, admin_email, admin_pw )
        admin_headers = { "Authorization": f"Bearer {admin_access}" }
        print( f"admin login ok ({admin_email})" )
    else:
        print( "no LUPIN_ADMIN_EMAIL / LUPIN_ADMIN_PASSWORD — the four admin-gated "
               "fixtures will be reported as blocked" )

    print()

    # ── REST ────────────────────────────────────────────────────────────────
    fleet  = capture_fleet_state( base, user_headers )
    roster = ( capture_roster( base, admin_headers ) if admin_headers is not None
               else _blocked_roster_no_admin() )
    write_joined_pair( roster, fleet )

    seat = args.seat or _pick_seat( fleet )
    if seat is None:
        _block( "backlog_403.json",
                "no seat to read: fleet-state gave none and --seat was not passed." )
    else:
        capture_backlog_403( base, user_headers, seat )

    # ── WebSocket ───────────────────────────────────────────────────────────
    capture_ws_frames( base, admin_access, seat )

    # ── the report ──────────────────────────────────────────────────────────
    print( "\n" + "=" * 72 )
    print( f"CAPTURED {len(captured)}/{len(ALL_FIXTURES)}" )
    for name in ALL_FIXTURES:
        mark = "ok     " if name in captured else "BLOCKED"
        print( f"  {mark}  {name}" )
    if blocked:
        print( "\nWHY, per blocked fixture:" )
        for name, why in blocked.items():
            print( f"  {name}\n      {why}" )
        print( "\nNothing was written for a blocked fixture ON PURPOSE: its test must keep "
               "failing on the missing file (María's condition for the `pending-capture` "
               "tag). A fabricated fixture would turn a red test green while proving "
               "nothing." )
        return 4
    print( "\nAll six captured. Run: ./flutter.sh test --tags pending-capture" )
    return 0


def _blocked_roster_no_admin() -> None:
    _block( "watchable_roster.json",
            "no admin login supplied (LUPIN_ADMIN_EMAIL / LUPIN_ADMIN_PASSWORD), and "
            "/api/cc-transcript-roster is require_admin." )
    return None


def _pick_seat( fleet: Optional[ dict ] ) -> Optional[ str ]:
    """A live seat's id, preferring fleet-state over this process's own session."""
    if fleet is not None:
        for session in ( fleet.get( "fleet_arbiter" ) or {} ).get( "sessions" ) or []:
            sid = session.get( "session_id" )
            if isinstance( sid, str ) and sid:
                return sid
    return None


if __name__ == "__main__":
    sys.exit( main() )
