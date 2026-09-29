"""
The WebSocket half of the transcript capture (row 768e852f slice 4).

Its own module ON PURPOSE. `_fixture_lib.py` is deliberately urllib-only, and
the six REST capture scripts import it; putting a `websockets` import in there
would break every one of them on a machine that lacks the package. Nothing here
is imported unless a WS fixture is actually being captured.

Two halves, split so the thinking part needs no server:

    TranscriptFrameCollector   PURE. Fed already-decoded frames and an injected
                               clock, no I/O at all. Every rule about which
                               frame qualifies lives here, and is unit-tested
                               against hand-written frames.

    capture_frames()           A thin async wrapper: connect, authenticate,
                               watch, feed the collector until the window
                               closes, unwatch. It contains no selection logic.

🔴 IT NEVER MERGES FRAMES. The consuming test needs ONE frame that genuinely
carries prose + a tool_call + a NOT-truncated tool_result together. If the
server split those across several frames, the honest outcome is
[NoQualifyingFrame] — a loud failure naming what it saw. Merging two frames
would fabricate a frame the server never sent, turn a red test green, and prove
nothing (fixtures README §5, "real frames, not invented ones").

The protocol, read off lupin `src/cosa/rest/routers/websocket.py`:

    1. connect  ws://host/ws/queue/{session_id}
    2. send     {"type": "auth_request", "token": "<jwt>"}    ← MUST be first,
                or the server closes with 4001
    3. expect   {"type": "auth_success", ...}
    4. send     {"type": "cc_transcript_watch", "cc_session_id": "<seat>",
                 "from_offset": 0}
    5. receive  cc_transcript_append / cc_transcript_state
    6. send     {"type": "cc_transcript_unwatch", "cc_session_id": "<seat>"}

A non-admin gets `{"type": "error", "event": "<verb>", "message": ...}` from
`handle_cc_transcript_verb` — the `websocket_manager.session_is_admin` gate,
which is a DIFFERENT mechanism from the REST `require_admin`. That arrives as
[AdminRefused], carrying the server's own words.
"""

from __future__ import annotations

import asyncio
import json
import time
from typing import Any, Callable, Iterable, Optional

# `cosa/rest/cc_transcript_tailer.py` owns these names; they are repeated rather
# than imported because this repo cannot import the server's package.
APPEND_EVENT = "cc_transcript_append"
STATE_EVENT  = "cc_transcript_state"

# `cc transcript coalesce window ms` in lupin's `src/conf/lupin-app.ini` (Rick's
# Q7 ruling). The server coalesces appends inside this window, so a capture that
# reads one frame and stops can read a FRAGMENT of what the seat printed.
COALESCE_WINDOW_MS = 300


class WsCaptureError( RuntimeError ):
    """Any WS capture failure. Carries a sentence a reader can act on."""


class AdminRefused( WsCaptureError ):
    """The `session_is_admin` gate refused a transcript verb, in its own words."""


class NoQualifyingFrame( WsCaptureError ):
    """No single collected frame satisfies the fixture's requirement.

    Raised INSTEAD of assembling one out of parts. The message names how many
    frames were seen and what each was missing, because that is the finding.
    """


# ── what each fixture needs, as predicates over ONE frame ────────────────────
#
# Each returns the list of reasons the frame does NOT qualify. Empty list means
# it does. Reasons rather than a bool so a failed capture can say WHY the eight
# frames it saw were all unsuitable.

def _blocks( frame: dict ) -> list[ dict ]:
    blocks = frame.get( "blocks" )
    return [ b for b in blocks if isinstance( b, dict ) ] if isinstance( blocks, list ) else []


def _text_of( block: dict ) -> str:
    text = block.get( "text" )
    return text if isinstance( text, str ) else ""


def envelope_reasons( frame: dict ) -> list[ str ]:
    """Row §3: every frame must carry its OWN `cc_session_id` and `offset`.

    The consuming test uses the frame's values rather than substituting its own,
    and seeds the backlog read so the append's offset is continuous. An append
    with no offset is a phase-1 finding, not a test bug — so it disqualifies the
    frame here rather than being filled in.
    """
    reasons = []
    if not isinstance( frame.get( "cc_session_id" ), str ) or not frame[ "cc_session_id" ]:
        reasons.append( "no `cc_session_id` on the frame" )
    if not isinstance( frame.get( "offset" ), int ):
        reasons.append( "no integer `offset` on the frame" )
    return reasons


def mixed_kinds_reasons( frame: dict ) -> list[ str ]:
    """`append_mixed_kinds.json` — ONE append frame carrying prose, a
    `tool_call`, and a `tool_result` that is NOT truncated.

    The truncated case answers over REST and belongs to C5.19; a truncated
    tool_result here would make C5.18 pass for the wrong reason.
    """
    if frame.get( "type" ) != APPEND_EVENT:
        return [ f"type is {frame.get( 'type' )!r}, not {APPEND_EVENT!r}" ]

    reasons = envelope_reasons( frame )
    blocks  = _blocks( frame )
    kinds   = [ b.get( "kind" ) for b in blocks ]

    if not any( k not in ( "tool_call", "tool_result", "thinking" ) and _text_of( b )
                for k, b in zip( kinds, blocks ) ):
        reasons.append( "no prose block with text" )
    if "tool_call" not in kinds:
        reasons.append( "no `tool_call` block" )

    results = [ b for b in blocks if b.get( "kind" ) == "tool_result" ]
    if not results:
        reasons.append( "no `tool_result` block" )
    elif not any( b.get( "truncated" ) is not True for b in results ):
        reasons.append( "every `tool_result` is truncated (that is C5.19's case, not C5.18's)" )

    return reasons


def thinking_reasons( frame: dict ) -> list[ str ]:
    """`append_thinking.json` — ONE append frame with a `thinking` block whose
    text is substantial enough to assert "hidden" or "shown" about.

    One line of 8+ characters is the floor: a two-character scratch block is
    indistinguishable from empty once it is folded.
    """
    if frame.get( "type" ) != APPEND_EVENT:
        return [ f"type is {frame.get( 'type' )!r}, not {APPEND_EVENT!r}" ]

    reasons  = envelope_reasons( frame )
    thinking = [ b for b in _blocks( frame ) if b.get( "kind" ) == "thinking" ]

    if not thinking:
        reasons.append( "no `thinking` block" )
    elif not any( any( len( line.strip() ) >= 8 for line in _text_of( b ).splitlines() )
                  for b in thinking ):
        reasons.append( "no `thinking` block carries a line of 8+ characters" )

    return reasons


def state_refused_reasons( frame: dict ) -> list[ str ]:
    """`state_refused.json` — ONE `cc_transcript_state` frame, `state: refused`,
    carrying the server's own `reason`."""
    if frame.get( "type" ) != STATE_EVENT:
        return [ f"type is {frame.get( 'type' )!r}, not {STATE_EVENT!r}" ]

    reasons = []
    if frame.get( "state" ) != "refused":
        reasons.append( f"state is {frame.get( 'state' )!r}, not 'refused'" )
    if not isinstance( frame.get( "reason" ), str ) or not frame[ "reason" ].strip():
        reasons.append( "no non-empty `reason` — the test puts the server's string on screen" )
    return reasons


class TranscriptFrameCollector:
    """Collect frames for the coalesce window, then pick ones that qualify.

    Pure: no sockets, no sleeping, and the clock is injected, so every rule here
    is unit-testable against hand-written frames.

    Requires:
        - [clock] returns monotonically non-decreasing seconds
        - [settle_ms] is the quiet period AFTER the first frame, so a coalesced
          batch finishes arriving before selection runs

    Ensures:
        - [open] is False once the window has closed, and the wrapper stops there
        - [select] returns a frame the server actually sent, or raises
          [NoQualifyingFrame] — it never combines two frames
    """

    def __init__(
        self,
        *,
        settle_ms: int = COALESCE_WINDOW_MS,
        clock: Callable[ [], float ] = time.monotonic,
    ) -> None:
        self._settle  = settle_ms / 1000.0
        self._clock   = clock
        self._frames: list[ dict ] = []
        self._first_at: Optional[ float ] = None

    @property
    def frames( self ) -> list[ dict ]:
        """Every frame offered, in arrival order. Never mutated by selection."""
        return list( self._frames )

    def offer( self, frame: dict ) -> None:
        """Take one decoded frame. The first one starts the settle clock."""
        if self._first_at is None:
            self._first_at = self._clock()
        self._frames.append( frame )

    @property
    def open( self ) -> bool:
        """True while more of a coalesced batch may still arrive."""
        if self._first_at is None:
            return True                         # nothing yet; the caller's own timeout governs
        return ( self._clock() - self._first_at ) < self._settle

    def remaining_s( self ) -> Optional[ float ]:
        """Seconds left in the settle period, or None before the first frame."""
        if self._first_at is None:
            return None
        return max( 0.0, self._settle - ( self._clock() - self._first_at ) )

    def select( self, name: str, reasons_for: Callable[ [ dict ], list[ str ] ] ) -> dict:
        """The first collected frame that satisfies [reasons_for], or raise.

        🔴 One frame, whole, as the server sent it. When several qualify the
        FIRST is taken — not the richest, and never a union of them.
        """
        rejected: list[ str ] = []
        for index, frame in enumerate( self._frames ):
            reasons = reasons_for( frame )
            if not reasons:
                return frame
            rejected.append( f"    frame {index} ({frame.get( 'type' )}): " + "; ".join( reasons ) )

        seen = len( self._frames )
        raise NoQualifyingFrame(
            f"{name}: none of the {seen} frame(s) collected in the coalesce window qualifies.\n"
            + ( "\n".join( rejected ) if rejected else "    (no frames arrived at all)" )
            + "\n  NOT FIXABLE HERE: the frames are the server's. Capture while the seat is "
              "printing the shape this fixture needs, or report it as a phase-1 finding. "
              "Do NOT stitch two frames together — that invents a frame the server never sent."
        )


# ── the I/O wrapper ──────────────────────────────────────────────────────────

def _decode( message: Any ) -> Optional[ dict ]:
    """One received message as a dict, or None if it is not JSON object text.

    Protocol-level fragmentation is the library's problem, not ours: a server
    that sends an iterable sends ONE fragmented message, and `websockets`
    reassembles it before it reaches us. Verified with a live probe, and pinned
    by a fake-server test.
    """
    if isinstance( message, ( bytes, bytearray ) ):
        message = message.decode( "utf-8", errors="replace" )
    if not isinstance( message, str ):
        return None
    try:
        decoded = json.loads( message )
    except json.JSONDecodeError:
        return None
    return decoded if isinstance( decoded, dict ) else None


async def capture_frames(
    url: str,
    token: str,
    cc_session_id: str,
    *,
    from_offset: int = 0,
    file_epoch: Optional[ str ] = None,
    settle_ms: int = COALESCE_WINDOW_MS,
    first_frame_timeout_s: float = 30.0,
    connect: Optional[ Callable[ ..., Any ] ] = None,
    clock: Callable[ [], float ] = time.monotonic,
) -> TranscriptFrameCollector:
    """Watch one seat's transcript and return the collector holding what arrived.

    Requires:
        - [token] is a JWT for an ADMIN session; the transcript verbs are gated
          by `websocket_manager.session_is_admin`
        - [url] is the full `ws://host/ws/queue/{session_id}` endpoint

    Ensures:
        - the FIRST message sent is `auth_request`, or the server closes 4001
        - `cc_transcript_unwatch` is sent on the way out, including after a
          failure, so the server is not left tailing a file for a dead client
        - returns as soon as the settle period after the first frame elapses
        - raises [AdminRefused] carrying the server's own message when the gate
          refuses, and [WsCaptureError] for a failed handshake or a silent watch
    """
    if connect is None:                                     # pragma: no cover - real I/O
        from websockets.asyncio.client import connect as connect  # noqa: PLC0415

    collector = TranscriptFrameCollector( settle_ms=settle_ms, clock=clock )

    async with connect( url ) as ws:
        await ws.send( json.dumps( { "type": "auth_request", "token": token } ) )

        auth = _decode( await asyncio.wait_for( ws.recv(), timeout=first_frame_timeout_s ) )
        if auth is None or auth.get( "type" ) != "auth_success":
            raise WsCaptureError(
                f"authentication did not succeed; the server answered {auth!r}. The FIRST "
                f"message on this socket must be `auth_request` (the server closes 4001 "
                f"otherwise), and the token must be live."
            )

        watch: dict[ str, Any ] = {
            "type"          : "cc_transcript_watch",
            "cc_session_id" : cc_session_id,
            "from_offset"   : from_offset,
        }
        # A stale non-null epoch is refused with `state: epoch_mismatch` and NO
        # blocks — the server never rebases, so it is sent only when given.
        if file_epoch is not None:
            watch[ "file_epoch" ] = file_epoch

        try:
            await ws.send( json.dumps( watch ) )
            await _pump( ws, collector, cc_session_id, first_frame_timeout_s )
        finally:
            # Best effort: the socket may already be closing, and an unwatch that
            # cannot be sent must not mask the error that closed it.
            try:
                await ws.send( json.dumps( {
                    "type": "cc_transcript_unwatch", "cc_session_id": cc_session_id,
                } ) )
            except Exception:
                pass

    return collector


async def _pump(
    ws: Any,
    collector: TranscriptFrameCollector,
    cc_session_id: str,
    first_frame_timeout_s: float,
) -> None:
    """Feed [collector] until the settle period closes, or the socket does."""
    while True:
        timeout = collector.remaining_s()
        if timeout is not None and timeout <= 0:
            return
        try:
            message = await asyncio.wait_for(
                ws.recv(), timeout=first_frame_timeout_s if timeout is None else timeout )
        except asyncio.TimeoutError:
            if collector.frames:
                return                                  # the batch simply ended
            raise WsCaptureError(
                f"no transcript frame arrived within {first_frame_timeout_s:.0f}s of watching "
                f"{cc_session_id}. The watch was accepted but the seat printed nothing — "
                f"capture while it is actually working."
            ) from None
        except Exception as closed:                     # the server hung up on us
            if collector.frames:
                return
            raise WsCaptureError(
                f"the socket closed while watching {cc_session_id} before any frame arrived: "
                f"{closed!r}"
            ) from closed

        frame = _decode( message )
        if frame is None:
            continue

        if frame.get( "type" ) == "error":
            raise AdminRefused(
                f"the server refused `{frame.get( 'event' )}`: {frame.get( 'message' )!r}. "
                f"This is the `websocket_manager.session_is_admin` gate, which is a DIFFERENT "
                f"mechanism from the REST `require_admin` — being let through one proves "
                f"nothing about the other."
            )

        if frame.get( "type" ) in ( APPEND_EVENT, STATE_EVENT ):
            collector.offer( frame )


def frames_of( collector: TranscriptFrameCollector, kinds: Iterable[ str ] ) -> list[ dict ]:
    """Collected frames whose `type` is one of [kinds] — for reporting."""
    wanted = set( kinds )
    return [ f for f in collector.frames if f.get( "type" ) in wanted ]
