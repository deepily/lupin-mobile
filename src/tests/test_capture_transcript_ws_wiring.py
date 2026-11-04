"""
The capture script's WS half, wired but unrunnable (row 768e852f slice 4).

`capture_ws_frames` is where the client meets the script, and the thing most
worth pinning is what it does when it CANNOT run: it must block each fixture with
a reason a reader can act on and write NOTHING, because the consuming test's red
on a missing file was María's condition for the `pending-capture` tag (retired
2026-10-10, once every fixture existed). A placeholder file would turn three red tests green while proving nothing.

Run: python -m pytest src/tests/test_capture_transcript_ws_wiring.py -v
"""

from __future__ import annotations

import importlib.util
import os
import sys
from typing import Any

import pytest

SCRIPTS = os.path.join( os.path.dirname( __file__ ), "..", "scripts" )
sys.path.insert( 0, SCRIPTS )


def _load_script() -> Any:
    """Import the capture script by path — its filename has dashes in it."""
    path = os.path.join( SCRIPTS, "capture-transcript-fixtures.py" )
    spec = importlib.util.spec_from_file_location( "capture_transcript_fixtures", path )
    module = importlib.util.module_from_spec( spec )
    spec.loader.exec_module( module )
    return module


@pytest.fixture
def script( monkeypatch ):
    module = _load_script()
    module.captured.clear()
    module.blocked.clear()
    # A write here would be the defect under test, so make it impossible rather
    # than merely unexpected.
    monkeypatch.setattr( module.lib, "write_fixture",
                         lambda *a, **k: pytest.fail( "wrote a fixture it had no business writing" ) )
    return module


WS_FIXTURES = ( "append_mixed_kinds.json", "append_thinking.json", "state_refused.json" )


def test_no_admin_credential_blocks_all_three_and_names_the_RIGHT_gate( script ):
    script.capture_ws_frames( "http://localhost:7999", None, "seat-1" )

    assert sorted( script.blocked ) == sorted( WS_FIXTURES )
    assert script.captured == []
    for why in script.blocked.values():
        assert "session_is_admin" in why, "the WS gate, not the REST require_admin"
        assert "700a48f9" in why, "cites the row the credential decision lives on"


def test_no_seat_blocks_all_three_rather_than_watching_something_arbitrary( script ):
    script.capture_ws_frames( "http://localhost:7999", "admin-jwt", None )

    assert sorted( script.blocked ) == sorted( WS_FIXTURES )
    assert all( "no seat to watch" in why for why in script.blocked.values() )


def test_a_ws_failure_is_reported_verbatim_per_fixture_and_writes_nothing( script, monkeypatch ):
    import _ws_capture as wsc

    def explode( *args: Any, **kwargs: Any ):
        raise wsc.AdminRefused( "the server refused `cc_transcript_watch`: 'admin required'" )

    monkeypatch.setattr( wsc, "capture_frames", explode )
    script.capture_ws_frames( "http://localhost:7999", "admin-jwt", "seat-1" )

    assert sorted( script.blocked ) == sorted( WS_FIXTURES )
    assert all( "admin required" in why for why in script.blocked.values() ), \
        "the server's own words reach the report, not a paraphrase"


def test_a_window_with_no_qualifying_frame_blocks_only_the_fixtures_that_wanted_one(
    script, monkeypatch
):
    """The three fixtures are selected independently out of ONE window, so a
    window that carries a usable `thinking` frame but no mixed-kinds frame must
    block exactly one of them — not all three, and not none."""
    import _ws_capture as wsc

    written: list[ str ] = []
    monkeypatch.setattr( script.lib, "write_fixture",
                         lambda domain, name, body: written.append( name ) )

    frame = {
        "type"          : wsc.APPEND_EVENT,
        "cc_session_id" : "00000000-0000-4000-8000-000000000001",
        "offset"        : 4,
        "blocks"        : [ { "kind": "thinking", "text": "the offsets must stay continuous" } ],
    }
    collector = wsc.TranscriptFrameCollector()
    collector.offer( frame )
    monkeypatch.setattr( wsc, "capture_frames", lambda *a, **k: _ready( collector ) )

    script.capture_ws_frames( "http://localhost:7999", "admin-jwt", "seat-1" )

    assert written == [ "append_thinking.json" ]
    assert script.captured == [ "append_thinking.json" ]
    assert sorted( script.blocked ) == [ "append_mixed_kinds.json", "state_refused.json" ]
    assert "no `tool_call` block" in script.blocked[ "append_mixed_kinds.json" ]
    assert "never sent" in script.blocked[ "append_mixed_kinds.json" ], \
        "and it says stitching frames together is not the fix"


async def _ready( value: Any ) -> Any:
    """An already-decided awaitable, so `asyncio.run` has something to run."""
    return value


def test_the_session_id_in_the_path_is_the_CLIENTS_not_the_watched_seats( script, monkeypatch ):
    """`/ws/queue/{session_id}` is the CALLER's queue; the seat being tailed
    travels in the `cc_transcript_watch` payload. Confusing the two subscribes to
    the wrong queue and waits forever."""
    import _ws_capture as wsc

    seen: dict[ str, Any ] = {}

    def record( url, token, cc_session_id, **kwargs ):
        if not seen: seen.update( url=url, token=token, cc_session_id=cc_session_id )   # the seat watch is the FIRST call
        return _ready( wsc.TranscriptFrameCollector() )

    monkeypatch.setattr( wsc, "capture_frames", record )
    monkeypatch.setenv( "LUPIN_CAPTURE_SESSION_ID", "my-own-session" )
    script.capture_ws_frames( "http://localhost:7999", "admin-jwt", "the-watched-seat" )

    assert seen[ "url" ] == "ws://localhost:7999/ws/queue/my-own-session"
    assert seen[ "cc_session_id" ] == "the-watched-seat"
    assert seen[ "token" ] == "admin-jwt"


def test_an_https_base_becomes_wss_not_ws( script, monkeypatch ):
    import _ws_capture as wsc

    seen: dict[ str, Any ] = {}
    monkeypatch.setattr( wsc, "capture_frames",
                         lambda url, *a, **k: ( seen.update( url=url ),
                                                _ready( wsc.TranscriptFrameCollector() ) )[ 1 ] )
    monkeypatch.setenv( "LUPIN_CAPTURE_SESSION_ID", "s" )
    script.capture_ws_frames( "https://lupin.example", "admin-jwt", "seat-1" )

    assert seen[ "url" ].startswith( "wss://" )


def _thinking_frame( text: str, offset: int ) -> dict:
    return {
        "type"          : "cc_transcript_append",
        "cc_session_id" : "00000000-0000-4000-8000-000000000001",
        "offset"        : offset,
        "blocks"        : [ { "kind": "thinking", "text": text } ],
    }


def test_a_frame_that_LOOKS_like_a_jwt_is_skipped_for_the_next_qualifying_frame( script, monkeypatch ):
    """A live seat's frames carry whatever it printed — source code with three
    long dotted segments trips the naive JWT guard, which exits the whole run.
    That frame is unsuitable, not the run: take the next whole frame instead."""
    import _ws_capture as wsc

    written: dict[ str, Any ] = {}
    monkeypatch.setattr( script.lib, "write_fixture",
                         lambda domain, name, body: written.update( { name: body } ) )

    dotted    = "eyJ" + "a" * 25 + "." + "b" * 25 + "." + "c" * 25
    collector = wsc.TranscriptFrameCollector()
    collector.offer( _thinking_frame( dotted, 4 ) )
    collector.offer( _thinking_frame( "the offsets must stay continuous", 5 ) )
    monkeypatch.setattr( wsc, "capture_frames", lambda *a, **k: _ready( collector ) )

    script.capture_ws_frames( "http://localhost:7999", "admin-jwt", "seat-1" )

    assert written[ "append_thinking.json" ][ "offset" ] == 5, "the clean frame, whole"


def test_when_every_qualifying_frame_looks_like_a_jwt_the_fixture_is_blocked_not_written( script, monkeypatch ):
    import _ws_capture as wsc

    dotted    = "eyJ" + "a" * 25 + "." + "b" * 25 + "." + "c" * 25
    collector = wsc.TranscriptFrameCollector()
    collector.offer( _thinking_frame( dotted, 4 ) )
    monkeypatch.setattr( wsc, "capture_frames", lambda *a, **k: _ready( collector ) )

    script.capture_ws_frames( "http://localhost:7999", "admin-jwt", "seat-1" )

    assert "append_thinking.json" in script.blocked
    assert "JWT" in script.blocked[ "append_thinking.json" ]
    assert "append_thinking.json" not in script.captured


def test_from_offset_reaches_the_watch( script, monkeypatch ):
    import _ws_capture as wsc

    seen: dict[ str, Any ] = {}

    def record( url, token, cc_session_id, **kwargs ):
        seen.update( kwargs )
        return _ready( wsc.TranscriptFrameCollector() )

    monkeypatch.setattr( wsc, "capture_frames", record )
    script.capture_ws_frames( "http://localhost:7999", "admin-jwt", "seat-1", 5.0, 1234 )

    assert seen[ "from_offset" ] == 1234
    assert seen[ "append_wait_s" ] == 5.0


def test_prose_with_two_dots_is_not_mistaken_for_a_jwt( script ):
    """Measured on a live seat: a `<local-command-caveat>` line with two dots and
    three long parts tripped the shared guard and blocked a whole capture."""
    caveat = ( "Caveat: The messages below were generated by the user while running local "
               "commands. DO NOT respond to these unless asked. Ignore this. Thanks for reading now." )
    assert not script._looks_like_jwt( { "text": caveat } )
    assert script._looks_like_jwt( { "text": "eyJ" + "a" * 25 + "." + "b" * 25 + "." + "c" * 25 } )


# A realistic token shape: header (36 chars), payload, signature (43 chars).
_HEADER  = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
_PAYLOAD = "eyJzdWIiOiI1MGM3M2JhNy0zNmRkLTRlYWYtYTdlMi02MzI1NjI1MmM4NGYiLCJleHAiOjE3OTE2MDExODZ9"
_SIG     = "dt7AKddyXdpWGYgKU91XiKsAbCdEfGhIjKlMnOpQrSt"
_TOKEN   = f"{_HEADER}.{_PAYLOAD}.{_SIG}"


def test_an_access_token_EMBEDDED_in_a_longer_string_is_caught( script ):
    """Measured 2026-10-09: a Bash tool_result carried `{'tokens': {'access_token':
    'eyJ...'}}` inside prose, and the whole-string test let it through."""
    frame = { "blocks": [ { "kind": "tool_result",
                            "text": f"{{'tokens': {{'access_token': '{_TOKEN}', 'token_type': 'bearer'}}}}" } ] }
    assert script._looks_like_jwt( frame )


def test_a_refresh_token_EMBEDDED_in_a_tool_call_is_caught( script ):
    frame = { "blocks": [ { "kind": "tool_call", "name": "Bash",
                            "text": f"Bash( command=python3 -c 'import x; r = \"{_TOKEN}\"; print( r )' )" } ] }
    assert script._looks_like_jwt( frame )


def test_a_token_in_a_nested_dict_value_is_caught( script ):
    assert script._looks_like_jwt( { "a": [ { "b": { "c": f"Authorization: Bearer {_TOKEN}\nnext line" } } ] } )


def test_a_three_dot_non_token_inside_a_longer_string_does_not_fire( script ):
    """Dotted identifiers and file names are long and three-part but are not tokens."""
    prose = ( "see src/cosa/rest/routers/cc_transcript.py and cosa.rest.routers.websocket.session_is_admin "
              "then lupin.mobile.fleet_status.fleet_status_bloc_test.dart at v0.2.1.2026.08.29 done." )
    assert not script._looks_like_jwt( { "text": prose } )


def test_state_refused_comes_from_a_watch_on_an_UNKNOWN_id_not_the_live_seat( script, monkeypatch ):
    """The server answers an unknown id with `state: refused`; the live seat's
    watch answers `live`, which can never qualify. So the refused fixture needs
    its own watch, on an id that is not the seat."""
    import _ws_capture as wsc

    watched: list[ str ] = []
    written: dict[ str, Any ] = {}
    monkeypatch.setattr( script.lib, "write_fixture",
                         lambda domain, name, body: written.update( { name: body } ) )

    refused = wsc.TranscriptFrameCollector()
    refused.offer( { "type": wsc.STATE_EVENT, "state": "refused", "reason": "not_found",
                     "cc_session_id": "11111111-1111-4111-8111-111111111111" } )

    def fake( url, token, cc_session_id, **kwargs ):
        watched.append( cc_session_id )
        return _ready( refused if cc_session_id != "the-seat" else wsc.TranscriptFrameCollector() )

    monkeypatch.setattr( wsc, "capture_frames", fake )
    script.capture_ws_frames( "http://localhost:7999", "admin-jwt", "the-seat" )

    assert watched[ 0 ] == "the-seat" and watched[ 1 ] != "the-seat"
    assert written[ "state_refused.json" ][ "reason" ] == "not_found"


# ── the admin login's env var names ─────────────────────────────────────────
_ADMIN_VARS = ( "LUPIN_TEST_ADMIN_EMAIL", "LUPIN_TEST_ADMIN_PASSWORD",
                "LUPIN_ADMIN_EMAIL", "LUPIN_ADMIN_PASSWORD" )


@pytest.fixture
def clean_admin_env( monkeypatch ):
    for var in _ADMIN_VARS: monkeypatch.delenv( var, raising=False )
    return monkeypatch


def test_the_TEST_admin_names_are_read( script, clean_admin_env ):
    clean_admin_env.setenv( "LUPIN_TEST_ADMIN_EMAIL", "e-new" )
    clean_admin_env.setenv( "LUPIN_TEST_ADMIN_PASSWORD", "p-new" )
    assert script.read_admin_login() == ( "e-new", "p-new" )


def test_the_TEST_admin_names_win_over_the_old_ones( script, clean_admin_env ):
    for var, val in zip( _ADMIN_VARS, ( "e-new", "p-new", "e-old", "p-old" ) ):
        clean_admin_env.setenv( var, val )
    assert script.read_admin_login() == ( "e-new", "p-new" )


def test_the_old_admin_names_still_work_as_a_fallback( script, clean_admin_env ):
    clean_admin_env.setenv( "LUPIN_ADMIN_EMAIL", "e-old" )
    clean_admin_env.setenv( "LUPIN_ADMIN_PASSWORD", "p-old" )
    assert script.read_admin_login() == ( "e-old", "p-old" )


def test_a_half_set_new_pair_falls_back_whole_not_mixed( script, clean_admin_env ):
    clean_admin_env.setenv( "LUPIN_TEST_ADMIN_EMAIL", "e-new" )
    clean_admin_env.setenv( "LUPIN_ADMIN_EMAIL", "e-old" )
    clean_admin_env.setenv( "LUPIN_ADMIN_PASSWORD", "p-old" )
    assert script.read_admin_login() == ( "e-old", "p-old" )


def test_no_admin_login_is_none_none( script, clean_admin_env ):
    assert script.read_admin_login() == ( None, None )


def test_the_not_set_messages_name_both_pairs( script ):
    src = open( os.path.join( SCRIPTS, "capture-transcript-fixtures.py" ) ).read()
    for var in _ADMIN_VARS:
        assert src.count( var ) >= 3, f"{var} should appear in usage and both not-set messages"
