"""
Tests for the transcript WS capture (`src/scripts/_ws_capture.py`), row 768e852f
slice 4.

Tiffany's instruction, 2026-09-28: write the client, but not blind — prove the
collect-one-whole-frame logic against an in-process fake server that emits split
frames inside the ~300 ms coalesce window, BEFORE anyone has an admin credential
to run the real capture with (row 700a48f9).

Two layers, matching the module:
  - the pure rules, against hand-written frames and an injected clock. No socket.
  - the wrapper, against a real `websockets` server on an ephemeral port: the
    handshake order, a deliberately FRAGMENTED frame, the coalesce window, the
    non-admin refusal, and the unwatch on the way out.

🔴 The load-bearing negative: two frames that TOGETHER satisfy a fixture, and
neither alone, must fail loudly. Anything that returns a merged frame has
fabricated server output.

Run: python -m pytest src/tests/test_ws_capture.py -v
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
from typing import Any

import pytest

sys.path.insert( 0, os.path.join( os.path.dirname( __file__ ), "..", "scripts" ) )

import _ws_capture as wsc   # noqa: E402


# ── frame builders ───────────────────────────────────────────────────────────

def append_frame( blocks: list[ dict ], *, seat: str = "seat-1", offset: int = 7 ) -> dict:
    return {
        "type"          : wsc.APPEND_EVENT,
        "cc_session_id" : seat,
        "offset"        : offset,
        "blocks"        : blocks,
    }


PROSE       = { "kind": "text",        "text": "Reading the config now." }
TOOL_CALL   = { "kind": "tool_call",   "text": "Read(lupin-app.ini)" }
TOOL_RESULT = { "kind": "tool_result", "text": "coalesce window ms = 300", "truncated": False }
THINKING    = { "kind": "thinking",    "text": "The offsets have to stay continuous." }


class FakeClock:
    """A clock that only moves when the test says so."""

    def __init__( self ) -> None:
        self.now = 1000.0

    def __call__( self ) -> float:
        return self.now

    def advance_ms( self, ms: float ) -> None:
        self.now += ms / 1000.0


# ── the pure rules ───────────────────────────────────────────────────────────

class TestMixedKinds:
    def test_one_frame_carrying_all_three_kinds_qualifies( self ):
        frame = append_frame( [ PROSE, TOOL_CALL, TOOL_RESULT ] )
        assert wsc.mixed_kinds_reasons( frame ) == []

    def test_a_truncated_tool_result_is_refused_it_is_c5_19s_case( self ):
        frame   = append_frame( [ PROSE, TOOL_CALL, { **TOOL_RESULT, "truncated": True } ] )
        reasons = wsc.mixed_kinds_reasons( frame )
        assert any( "truncated" in r for r in reasons )

    def test_a_frame_missing_the_tool_call_says_which_piece_is_missing( self ):
        reasons = wsc.mixed_kinds_reasons( append_frame( [ PROSE, TOOL_RESULT ] ) )
        assert reasons == [ "no `tool_call` block" ]

    def test_prose_must_carry_TEXT_an_empty_block_is_not_prose( self ):
        frame   = append_frame( [ { "kind": "text", "text": "" }, TOOL_CALL, TOOL_RESULT ] )
        reasons = wsc.mixed_kinds_reasons( frame )
        assert reasons == [ "no prose block with text" ]

    def test_a_state_frame_is_not_an_append_frame( self ):
        reasons = wsc.mixed_kinds_reasons( { "type": wsc.STATE_EVENT, "state": "refused" } )
        assert reasons and "not" in reasons[ 0 ]


class TestEnvelope:
    """Row §3: the test reads the frame's own ids rather than substituting its own,
    so a frame without them is a phase-1 finding and cannot be patched up."""

    def test_a_frame_with_no_offset_is_disqualified_not_filled_in( self ):
        frame = append_frame( [ PROSE, TOOL_CALL, TOOL_RESULT ] )
        del frame[ "offset" ]
        assert "no integer `offset` on the frame" in wsc.mixed_kinds_reasons( frame )

    def test_a_frame_with_no_cc_session_id_is_disqualified( self ):
        frame = append_frame( [ PROSE, TOOL_CALL, TOOL_RESULT ] )
        frame[ "cc_session_id" ] = ""
        assert "no `cc_session_id` on the frame" in wsc.mixed_kinds_reasons( frame )

    def test_offset_zero_is_a_VALID_offset_not_a_missing_one( self ):
        frame = append_frame( [ PROSE, TOOL_CALL, TOOL_RESULT ], offset=0 )
        assert wsc.mixed_kinds_reasons( frame ) == []


class TestThinking:
    def test_a_substantial_thinking_block_qualifies( self ):
        assert wsc.thinking_reasons( append_frame( [ THINKING ] ) ) == []

    def test_a_two_character_scratch_block_is_not_enough_to_assert_hidden_or_shown( self ):
        frame   = append_frame( [ { "kind": "thinking", "text": "ok" } ] )
        reasons = wsc.thinking_reasons( frame )
        assert any( "8+ characters" in r for r in reasons )

    def test_a_frame_with_no_thinking_block_says_so( self ):
        assert wsc.thinking_reasons( append_frame( [ PROSE ] ) ) == [ "no `thinking` block" ]


class TestStateRefused:
    def test_a_refused_state_with_the_servers_reason_qualifies( self ):
        frame = { "type": wsc.STATE_EVENT, "state": "refused", "reason": "not an admin session" }
        assert wsc.state_refused_reasons( frame ) == []

    def test_a_refusal_with_no_reason_is_refused_the_test_puts_that_string_on_screen( self ):
        frame   = { "type": wsc.STATE_EVENT, "state": "refused", "reason": "  " }
        reasons = wsc.state_refused_reasons( frame )
        assert any( "reason" in r for r in reasons )

    def test_epoch_mismatch_is_not_refused( self ):
        frame   = { "type": wsc.STATE_EVENT, "state": "epoch_mismatch", "reason": "stale epoch" }
        reasons = wsc.state_refused_reasons( frame )
        assert any( "epoch_mismatch" in r for r in reasons )


class TestSelection:
    def test_the_first_qualifying_frame_is_returned_whole( self ):
        clock     = FakeClock()
        collector = wsc.TranscriptFrameCollector( clock=clock )
        collector.offer( append_frame( [ PROSE ] ) )
        wanted = append_frame( [ PROSE, TOOL_CALL, TOOL_RESULT ], offset=9 )
        collector.offer( wanted )
        collector.offer( append_frame( [ PROSE, TOOL_CALL, TOOL_RESULT ], offset=11 ) )

        picked = collector.select( "append_mixed_kinds", wsc.mixed_kinds_reasons )
        assert picked is wanted, "the FIRST qualifying frame, not the richest"

    def test_CRITICAL_TWO_frames_that_only_JOINTLY_qualify_FAIL_LOUD_and_are_never_merged( self ):
        clock     = FakeClock()
        collector = wsc.TranscriptFrameCollector( clock=clock )
        collector.offer( append_frame( [ PROSE, TOOL_CALL ] ) )          # half of it
        collector.offer( append_frame( [ TOOL_RESULT ], offset=8 ) )     # the other half

        with pytest.raises( wsc.NoQualifyingFrame ) as raised:
            collector.select( "append_mixed_kinds", wsc.mixed_kinds_reasons )

        message = str( raised.value )
        assert "2 frame(s)" in message
        assert "no `tool_result` block" in message, "says what frame 0 was missing"
        assert "no prose block with text" in message, "and what frame 1 was missing"
        assert "never sent" in message, "and that stitching them is not the fix"

    def test_an_empty_window_fails_with_no_frames_arrived( self ):
        collector = wsc.TranscriptFrameCollector( clock=FakeClock() )
        with pytest.raises( wsc.NoQualifyingFrame, match="no frames arrived" ):
            collector.select( "append_thinking", wsc.thinking_reasons )

    def test_selection_does_not_consume_the_frames_two_fixtures_read_one_window( self ):
        clock     = FakeClock()
        collector = wsc.TranscriptFrameCollector( clock=clock )
        collector.offer( append_frame( [ PROSE, TOOL_CALL, TOOL_RESULT ] ) )
        collector.offer( append_frame( [ THINKING ], offset=8 ) )

        assert collector.select( "mixed", wsc.mixed_kinds_reasons )[ "offset" ] == 7
        assert collector.select( "thinking", wsc.thinking_reasons )[ "offset" ] == 8
        assert len( collector.frames ) == 2


class TestCoalesceWindow:
    """The window is why the capture does not read one frame and stop."""

    def test_the_window_stays_open_until_the_settle_period_after_the_FIRST_frame( self ):
        clock     = FakeClock()
        collector = wsc.TranscriptFrameCollector( settle_ms=300, clock=clock )

        assert collector.open, "nothing has arrived; the caller's own timeout governs"
        assert collector.remaining_s() is None

        collector.offer( append_frame( [ PROSE ] ) )
        clock.advance_ms( 299 )
        assert collector.open, "still inside the 300 ms coalesce window"

        clock.advance_ms( 2 )
        assert not collector.open
        assert collector.remaining_s() == 0.0

    def test_a_later_frame_does_not_extend_the_window( self ):
        clock     = FakeClock()
        collector = wsc.TranscriptFrameCollector( settle_ms=300, clock=clock )
        collector.offer( append_frame( [ PROSE ] ) )
        clock.advance_ms( 250 )
        collector.offer( append_frame( [ TOOL_CALL ], offset=8 ) )
        clock.advance_ms( 60 )
        assert not collector.open, "the window is measured from the first frame, not the last"

    def test_the_default_settle_period_is_the_servers_own_coalesce_window( self ):
        assert wsc.COALESCE_WINDOW_MS == 300


# ── the wrapper, against a real in-process server ────────────────────────────

class FakeTranscriptServer:
    """A `websockets` server speaking just enough of lupin's queue protocol.

    Real sockets on an ephemeral port, so the client's handshake order, framing
    and window behaviour are exercised against the library rather than a stub of
    it — the only way the fragmentation claim means anything.
    """

    def __init__( self, *, script: list[ Any ], admit: bool = True ) -> None:
        self.script   = script          # what to send after the watch is accepted
        self.admit    = admit           # False ⇒ answer the watch with an `error` frame
        self.received: list[ dict ] = []
        self._server: Any = None

    async def __aenter__( self ) -> "FakeTranscriptServer":
        from websockets.asyncio.server import serve
        self._server = await serve( self._handle, "127.0.0.1", 0 )
        return self

    async def __aexit__( self, *exc: Any ) -> None:
        self._server.close()
        await self._server.wait_closed()

    @property
    def url( self ) -> str:
        port = self._server.sockets[ 0 ].getsockname()[ 1 ]
        return f"ws://127.0.0.1:{port}/ws/queue/session-under-test"

    async def _handle( self, ws: Any ) -> None:
        try:
            async for raw in ws:
                message = json.loads( raw )
                self.received.append( message )

                if message.get( "type" ) == "auth_request":
                    await ws.send( json.dumps( { "type": "auth_success", "user": "tester" } ) )
                    continue

                if message.get( "type" ) == "cc_transcript_watch":
                    if not self.admit:
                        await ws.send( json.dumps( {
                            "type"    : "error",
                            "event"   : "cc_transcript_watch",
                            "message" : "admin session required",
                        } ) )
                        continue
                    for item in self.script:
                        # A LIST payload is one FRAGMENTED message: `websockets`
                        # sends it as several frames and the peer reassembles it.
                        await ws.send( item if isinstance( item, list ) else json.dumps( item ) )
                    continue

                if message.get( "type" ) == "cc_transcript_unwatch":
                    await ws.close()
                    return
        except Exception:
            return


async def _connect_to( url: str ):
    from websockets.asyncio.client import connect
    return connect( url )


@pytest.mark.asyncio
class TestAgainstFakeServer:
    async def test_the_handshake_order_is_auth_then_watch_then_unwatch( self ):
        frame = append_frame( [ PROSE, TOOL_CALL, TOOL_RESULT ] )
        async with FakeTranscriptServer( script=[ frame ] ) as server:
            from websockets.asyncio.client import connect
            collector = await wsc.capture_frames(
                server.url, "jwt-token", "seat-1", settle_ms=60, connect=connect )

        kinds = [ m[ "type" ] for m in server.received ]
        assert kinds == [ "auth_request", "cc_transcript_watch", "cc_transcript_unwatch" ], \
            "auth_request MUST be first or the server closes 4001"
        assert server.received[ 0 ][ "token" ] == "jwt-token"
        assert server.received[ 1 ][ "cc_session_id" ] == "seat-1"
        assert server.received[ 1 ][ "from_offset" ] == 0
        assert "file_epoch" not in server.received[ 1 ], \
            "a null epoch is not sent at all; a stale one is refused with no blocks"
        assert collector.select( "mixed", wsc.mixed_kinds_reasons ) == frame

    async def test_CRITICAL_a_FRAGMENTED_frame_arrives_as_ONE_whole_frame( self ):
        """The claim Tiffany asked to see proven: a frame split at the protocol
        level inside the window is reassembled, and the collector sees one frame
        carrying all three block kinds — not two halves."""
        whole = json.dumps( append_frame( [ PROSE, TOOL_CALL, TOOL_RESULT ] ) )
        half  = len( whole ) // 2
        async with FakeTranscriptServer( script=[ [ whole[ :half ], whole[ half: ] ] ] ) as server:
            from websockets.asyncio.client import connect
            collector = await wsc.capture_frames(
                server.url, "jwt", "seat-1", settle_ms=60, connect=connect )

        assert len( collector.frames ) == 1, "reassembled by the library, not stitched by us"
        assert wsc.mixed_kinds_reasons( collector.frames[ 0 ] ) == []

    async def test_several_frames_inside_the_window_are_ALL_collected( self ):
        script = [
            append_frame( [ PROSE ] ),
            append_frame( [ THINKING ], offset=8 ),
            append_frame( [ PROSE, TOOL_CALL, TOOL_RESULT ], offset=9 ),
        ]
        async with FakeTranscriptServer( script=script ) as server:
            from websockets.asyncio.client import connect
            collector = await wsc.capture_frames(
                server.url, "jwt", "seat-1", settle_ms=200, connect=connect )

        assert len( collector.frames ) == 3, "the window is why we do not read one and stop"
        assert collector.select( "thinking", wsc.thinking_reasons )[ "offset" ] == 8
        assert collector.select( "mixed", wsc.mixed_kinds_reasons )[ "offset" ] == 9

    async def test_CRITICAL_halves_that_only_jointly_qualify_still_fail_over_a_real_socket( self ):
        """The same negative as the pure test, end to end: two SEPARATE frames
        (not one fragmented message) inside the window stay two frames."""
        script = [ append_frame( [ PROSE, TOOL_CALL ] ), append_frame( [ TOOL_RESULT ], offset=8 ) ]
        async with FakeTranscriptServer( script=script ) as server:
            from websockets.asyncio.client import connect
            collector = await wsc.capture_frames(
                server.url, "jwt", "seat-1", settle_ms=150, connect=connect )

        assert len( collector.frames ) == 2
        with pytest.raises( wsc.NoQualifyingFrame ):
            collector.select( "append_mixed_kinds", wsc.mixed_kinds_reasons )

    async def test_the_non_admin_refusal_surfaces_the_servers_own_words( self ):
        async with FakeTranscriptServer( script=[], admit=False ) as server:
            from websockets.asyncio.client import connect
            with pytest.raises( wsc.AdminRefused ) as raised:
                await wsc.capture_frames(
                    server.url, "jwt", "seat-1", settle_ms=60, connect=connect )

        message = str( raised.value )
        assert "admin session required" in message
        assert "session_is_admin" in message, "names the gate that refused, not the REST one"

    async def test_a_state_frame_is_collected_alongside_appends( self ):
        script = [ { "type": wsc.STATE_EVENT, "state": "refused", "reason": "console is admin-only" } ]
        async with FakeTranscriptServer( script=script ) as server:
            from websockets.asyncio.client import connect
            collector = await wsc.capture_frames(
                server.url, "jwt", "seat-1", settle_ms=60, connect=connect )

        assert collector.select( "state_refused", wsc.state_refused_reasons )[ "reason" ] \
            == "console is admin-only"

    async def test_unrelated_traffic_on_the_socket_is_ignored_not_collected( self ):
        """NEGATIVE CONTROL. The queue socket carries other events; only transcript
        frames may reach a transcript fixture."""
        script = [
            { "type": "notification", "message": "something else entirely" },
            "not json at all",
            append_frame( [ THINKING ] ),
        ]
        async with FakeTranscriptServer( script=script ) as server:
            from websockets.asyncio.client import connect
            collector = await wsc.capture_frames(
                server.url, "jwt", "seat-1", settle_ms=150, connect=connect )

        assert [ f[ "type" ] for f in collector.frames ] == [ wsc.APPEND_EVENT ]

    async def test_a_failed_handshake_says_what_the_server_answered( self ):
        class Rude( FakeTranscriptServer ):
            async def _handle( self, ws: Any ) -> None:
                async for _ in ws:
                    await ws.send( json.dumps( { "type": "auth_failed", "reason": "bad token" } ) )
                    return

        async with Rude( script=[] ) as server:
            from websockets.asyncio.client import connect
            with pytest.raises( wsc.WsCaptureError, match="auth_failed" ):
                await wsc.capture_frames(
                    server.url, "expired", "seat-1", settle_ms=60, connect=connect )

    async def test_a_watch_that_prints_nothing_fails_loudly_rather_than_returning_empty( self ):
        async with FakeTranscriptServer( script=[] ) as server:
            from websockets.asyncio.client import connect
            with pytest.raises( wsc.WsCaptureError, match="printed nothing" ):
                await wsc.capture_frames(
                    server.url, "jwt", "seat-1", settle_ms=60,
                    first_frame_timeout_s=0.3, connect=connect )

    async def test_a_file_epoch_is_sent_only_when_given( self ):
        async with FakeTranscriptServer( script=[ append_frame( [ THINKING ] ) ] ) as server:
            from websockets.asyncio.client import connect
            await wsc.capture_frames(
                server.url, "jwt", "seat-1", file_epoch="epoch-42",
                settle_ms=60, connect=connect )

        watch = server.received[ 1 ]
        assert watch[ "file_epoch" ] == "epoch-42"


def test_the_module_imports_without_websockets_installed_being_required_at_import_time():
    """`_fixture_lib` is urllib-only on purpose and the six REST capture scripts
    import it. This module is separate, and its `websockets` import is deferred
    into the one function that needs it, so nothing REST breaks on a machine
    without the package."""
    source = open( os.path.join( os.path.dirname( wsc.__file__ ), "_ws_capture.py" ) ).read()
    header = source.split( "async def capture_frames" )[ 0 ]
    assert "import websockets" not in header
    assert "from websockets" not in header
