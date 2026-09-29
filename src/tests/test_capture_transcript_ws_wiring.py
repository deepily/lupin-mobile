"""
The capture script's WS half, wired but unrunnable (row 768e852f slice 4).

`capture_ws_frames` is where the client meets the script, and the thing most
worth pinning is what it does when it CANNOT run: it must block each fixture with
a reason a reader can act on and write NOTHING, because the consuming test's red
on a missing file is María's condition for the `pending-capture` tag. A
placeholder file would turn three red tests green while proving nothing.

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
        seen.update( url=url, token=token, cc_session_id=cc_session_id )
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
