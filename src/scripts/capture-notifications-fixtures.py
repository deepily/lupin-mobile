#!/usr/bin/env python3
"""
Capture real Lupin backend notification responses, redact sensitive values,
and write stable JSON fixtures for repository-layer unit tests.

Usage:
    export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL="..."
    export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD="..."
    # Optional, defaults to http://localhost:7999
    # export LUPIN_API_BASE_URL="http://10.0.2.2:7999"
    python src/scripts/capture-notifications-fixtures.py

See test/fixtures/README.md for the pattern and redaction contract.
"""

from __future__ import annotations

import os
import sys
import urllib.parse
from typing import Any

import _fixture_lib as lib

# Keep fixtures compact and readable — real backend may have dozens of senders
# and hundreds of messages per date; we only need enough to verify shape.
MAX_SENDERS             = 3
MAX_CONVERSATION_MSGS   = 5
MAX_DATES_IN_BY_DATE    = 3
MAX_MSGS_PER_DATE       = 2


DOMAIN = "notifications"
DEFAULT_BASE_URL = "http://localhost:7999"


def _redact_message( msg: dict[str, Any], sender_alias: str, msg_index: int ) -> dict[str, Any]:
    """Redact a single notification / conversation message. Keeps the text
    content and flags; scrubs IDs and timestamps to stable placeholders."""
    out = { **msg }
    if "id" in out and out[ "id" ] is not None:
        out[ "id" ] = f"msg-fixture-{msg_index}"
    if "sender_id" in out and out[ "sender_id" ] is not None:
        out[ "sender_id" ] = sender_alias
    if "job_id" in out and out[ "job_id" ] is not None:
        out[ "job_id" ] = "job-fixture"
    if "progress_group_id" in out and out[ "progress_group_id" ] is not None:
        out[ "progress_group_id" ] = "pg-fixture"
    lib.redact_timestamp_fields(
        out,
        ( "created_at", "delivered_at", "responded_at", "timestamp" ),
    )
    return out


def _redact_sender( sender: dict[str, Any], idx: int ) -> dict[str, Any]:
    out = { **sender }
    if "sender_id" in out:
        out[ "sender_id" ] = f"sender-fixture-{idx}"
    lib.redact_timestamp_fields( out, ( "last_activity", ) )
    return out


def _redact_notifications_list_envelope( body: dict[str, Any] ) -> dict[str, Any]:
    """`/api/notifications/{user_id}` returns an envelope
    {status, user_id, notification_count, include_played, limit, timestamp, notifications[]}."""
    out = { **body }
    if "user_id" in out:
        out[ "user_id" ] = lib.REDACT_USER_ID
    lib.redact_timestamp_fields( out, ( "timestamp", ) )
    if isinstance( out.get( "notifications" ), list ):
        out[ "notifications" ] = [
            _redact_message( n, "sender-fixture", i )
            for i, n in enumerate( out[ "notifications" ] )
        ]
    return out


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

    print( f"Capturing notifications fixtures against {base_url}..." )

    # Need access token + user_id for the subsequent calls.
    login_body, access_token, _ = lib.login_for_capture( base_url, email, password )
    user_id = login_body[ "user" ][ "id" ]
    auth_hdr = { "Authorization": f"Bearer {access_token}" }

    # 1. senders-visible — real backend may have many; keep first MAX_SENDERS.
    # Filter out sender IDs containing '/' (FastAPI path-param routing can't
    # match them; separate mobile-app bug tracked elsewhere).
    enc_email = urllib.parse.quote( email, safe="" )
    status, senders_body = lib.get_json(
        base_url, f"/api/notifications/senders-visible/{enc_email}", headers=auth_hdr,
    )
    if status != 200:
        print( f"ERROR: senders-visible returned {status}: {senders_body}", file=sys.stderr )
        return 2
    # Returns a List[SenderSummary].
    if isinstance( senders_body, list ):
        routable = [ s for s in senders_body if "/" not in s.get( "sender_id", "" ) ]
        trimmed = routable[ :MAX_SENDERS ]
        real_sender_ids = [ s.get( "sender_id" ) for s in trimmed ]
        redacted_senders = [ _redact_sender( s, i ) for i, s in enumerate( trimmed ) ]
    else:
        real_sender_ids = []
        redacted_senders = senders_body
    lib.write_fixture( DOMAIN, "senders_visible.json", redacted_senders )

    # 2. notifications list (flat, keyed by user id)
    status, list_body = lib.get_json(
        base_url, f"/api/notifications/{user_id}",
        headers=auth_hdr,
    )
    if status != 200:
        print( f"WARN: /api/notifications/{user_id} returned {status}: {list_body}", file=sys.stderr )
    else:
        lib.write_fixture( DOMAIN, "list_response.json", _redact_notifications_list_envelope( list_body ) )

    # 3. conversation for first sender, if any — returns List[ConversationMessage].
    # Sender IDs contain `@` and `#` which urllib will mangle without encoding.
    if real_sender_ids:
        first_sender     = real_sender_ids[ 0 ]
        enc_first_sender = urllib.parse.quote( first_sender, safe="" )
        status, conv_body = lib.get_json(
            base_url,
            f"/api/notifications/conversation/{enc_first_sender}/{enc_email}?hours=24",
            headers=auth_hdr,
        )
        if status == 200 and isinstance( conv_body, list ):
            trimmed_conv = conv_body[ :MAX_CONVERSATION_MSGS ]
            redacted_conv = [
                _redact_message( m, "sender-fixture-0", i )
                for i, m in enumerate( trimmed_conv )
            ]
            lib.write_fixture( DOMAIN, "conversation.json", redacted_conv )
        else:
            print( f"WARN: conversation returned {status}: {conv_body}", file=sys.stderr )

        # 4. conversation-by-date — date-keyed map
        status, by_date_body = lib.get_json(
            base_url,
            f"/api/notifications/conversation-by-date/{enc_first_sender}/{enc_email}",
            headers=auth_hdr,
        )
        if status == 200 and isinstance( by_date_body, dict ):
            # Trim to recent dates + small message cap per date — fixture
            # stays readable even if the real backend has thousands of msgs.
            sorted_dates = sorted( by_date_body.keys(), reverse=True )[ :MAX_DATES_IN_BY_DATE ]
            redacted_by_date = {
                date: [
                    _redact_message( m, "sender-fixture-0", i )
                    for i, m in enumerate( by_date_body[ date ][ :MAX_MSGS_PER_DATE ] )
                ]
                for date in sorted_dates
            }
            lib.write_fixture( DOMAIN, "conversation_by_date.json", redacted_by_date )
        else:
            print( f"WARN: conversation-by-date returned {status}: {by_date_body}", file=sys.stderr )
    else:
        print( "  (no senders visible — skipping conversation fixtures)" )

    # Final safety net across everything.
    for path in ( "senders_visible.json", "list_response.json", "conversation.json", "conversation_by_date.json" ):
        full = lib.fixtures_dir( DOMAIN ) / path
        if full.exists():
            import json
            lib.assert_no_jwt_residue( json.loads( full.read_text() ), path )

    print( "Done." )
    return 0


if __name__ == "__main__":
    sys.exit( main() )
