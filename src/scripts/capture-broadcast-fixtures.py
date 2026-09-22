#!/usr/bin/env python3
"""
Capture real Commons/Broadcast responses for the Phase 5 Broadcast pane tests.

Usage:
    export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL="..."
    export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD="..."
    # Optional, defaults to http://localhost:7999
    # export LUPIN_API_BASE_URL="http://10.0.2.2:7999"
    python src/scripts/capture-broadcast-fixtures.py

See test/fixtures/README.md for the pattern and the redaction contract.

🔴 THIS SCRIPT IS READ-ONLY, AND THAT IS A DELIBERATE LIMIT RATHER THAN AN OVERSIGHT.

`POST /api/commons/broadcast-to-cc-sessions` is the one door this pane exists to press,
and it is NOT captured here. Firing it sends a real message to every live Claude Code
session in the fleet — it is the most outward-facing write in this repo, and a fixture is
not a reason to interrupt working seats. Capturing the send response therefore needs a
person's explicit go-ahead at the moment it runs, which a script cannot hold on file.

⇒ So the two endpoints below are captured live. The send response and the ack frame are
NOT, and `test/fixtures/commons/README-broadcast.md` records where their shapes came from
instead, which is the producer source rather than a run. That distinction is the point:
a fixture that says "captured" when it was transcribed is worse than one that says
"transcribed", because only the first will be trusted without re-checking.

WHY CAPTURE RATHER THAN HAND-WRITE THE TWO THAT CAN BE. Same reason as the tasks capture:
a stub encodes the author's beliefs about the shape and can only confirm them.
`/api/commons/active-sessions` drives a Send button that is disabled on the recipient
count, so the one field that matters is how an EMPTY fleet is expressed — `[]`, a missing
key, or a key whose value is null. Those are three different mapper behaviours and a
fixture I typed myself would pick whichever I already believed.

🔴 REDACTION MUST NOT CHANGE NULL-NESS, and it must not change COUNT. Replacing a null
with a placeholder hands the tests back the blind spot the capture exists to remove.
Dropping or padding a session would change the exact number the Send button reads.
Every redaction below is value-for-value on a key that is already present and non-null.
"""

from __future__ import annotations

import os
import sys
from typing import Any

import _fixture_lib as lib


def redact_sessions( body: Any ) -> Any:
    """
    Redact identity out of the active-session roster, value-for-value.

    Requires:
        - body is the decoded `/api/commons/active-sessions` response

    Ensures:
        - every session keeps exactly the keys it arrived with
        - the NUMBER of sessions is unchanged (the Send button reads this count)
        - no key that was null becomes non-null, and none that was present goes missing
    """
    sessions = body.get( "sessions" ) if isinstance( body, dict ) else body
    if not isinstance( sessions, list ):
        return body

    for i, s in enumerate( sessions ):
        if not isinstance( s, dict ): continue
        # Value-for-value only, and only on keys that are already present and non-null.
        if s.get( "session_id"   ): s[ "session_id"   ] = f"sess-fixture-{i}"
        if s.get( "user_id"      ): s[ "user_id"      ] = lib.REDACT_USER_ID
        if s.get( "email"        ): s[ "email"        ] = lib.REDACT_EMAIL
        if s.get( "sender_id"    ): s[ "sender_id"    ] = f"{lib.REDACT_SENDER_ID}-{i}"

    return body


def main() -> int:
    base_url = os.environ.get( "LUPIN_API_BASE_URL" ) or "http://localhost:7999"
    email    = os.environ.get( "LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL" )
    password = os.environ.get( "LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD" )

    if not email or not password:
        print(
            "ERROR: set LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL and "
            "LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD",
            file=sys.stderr,
        )
        return 2

    _, access, _ = lib.login_for_capture( base_url, email, password )
    auth = { "Authorization": f"Bearer {access}" }

    wrote: list[str] = []

    # ── 1. The recipient roster ──────────────────────────────────────────────
    #
    # Drives BOTH halves of the Send button's disabled condition, so the count is the
    # load-bearing value and redaction must not touch it.
    status, sessions = lib.get_json( base_url, "/api/commons/active-sessions", headers=auth )
    if status != 200:
        print( f"ERROR: active-sessions returned {status}: {sessions}", file=sys.stderr )
        return 4
    sessions = redact_sessions( sessions )
    lib.assert_no_jwt_residue( sessions, "active-sessions" )
    wrote.append( str( lib.write_fixture( "commons", "active_sessions.json", sessions ) ) )

    # ── 2. Broadcast history ─────────────────────────────────────────────────
    #
    # 🔴 AN EXPLICIT `limit`, AND IT IS THIS ROW'S OWN LESSON APPLIED TO THE CAPTURE.
    # The server's default is 200 (`commons.py` `get_broadcast_history`, `limit: int =
    # 200`). A capture taken at the default pulled 144 KB of real fleet traffic — two
    # hundred live commons posts — into a test fixture, which is both a data dump nobody
    # reads and a request shape the pane must never make. Passing the limit here is the
    # same discipline the pane owes the drain.
    #
    # ⚠️ AND IT DOES NOT EXERCISE `disabled`. The flag is emitted ONLY when the INI
    # kill-switch `commons traffic visibility enabled` is false, and flipping a shared
    # server's configuration to capture a fixture is not a trade worth making. The
    # disabled shape is fully determined by the producer and is written beside this one
    # as a TRANSCRIPTION, labelled as such — see README-broadcast.md.
    status, history = lib.get_json(
        base_url,
        lib.build_query( "/api/commons/broadcast-history", { "limit": 5 } ),
        headers=auth,
    )
    if status != 200:
        print( f"ERROR: broadcast-history returned {status}: {history}", file=sys.stderr )
        return 5
    lib.assert_no_jwt_residue( history, "broadcast-history" )
    wrote.append( str( lib.write_fixture( "commons", "broadcast_history.json", history ) ) )

    if "disabled" in history:
        print(
            "NOTE: this capture DID carry `disabled` — the kill-switch is off. "
            "broadcast_history_disabled.json is then redundant; check it still matches.",
            file=sys.stderr,
        )

    print( "Captured:" )
    for w in wrote: print( f"  {w}" )
    print()
    print( "NOT captured, and deliberately so — see the module docstring:" )
    print( "  POST /api/commons/broadcast-to-cc-sessions  (writes to every live seat)" )
    print( "  the commons_broadcast_ack socket frame      (only exists after a real send)" )
    return 0


if __name__ == "__main__":
    raise SystemExit( main() )
