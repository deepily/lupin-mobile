#!/usr/bin/env python3
"""
Capture real Lupin decision-proxy responses, redact sensitive values, and
write stable JSON fixtures for repository-layer unit tests.

Usage:
    export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL="..."
    export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD="..."
    # Optional, defaults to http://localhost:7999
    # export LUPIN_API_BASE_URL="http://10.0.2.2:7999"
    python src/scripts/capture-decision-proxy-fixtures.py

See test/fixtures/README.md for the pattern and redaction contract.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.parse
from typing import Any

import _fixture_lib as lib


DOMAIN = "decision_proxy"
DEFAULT_BASE_URL = "http://localhost:7999"

# Keep pending/trust-state fixtures compact.
MAX_DECISIONS    = 3
MAX_TRUST_STATES = 3


def _redact_decision( d: dict[str, Any], idx: int ) -> dict[str, Any]:
    out = { **d }
    if "id" in out:
        out[ "id" ] = f"decision-fixture-{idx}"
    if out.get( "notification_id" ) is not None:
        out[ "notification_id" ] = f"notif-fixture-{idx}"
    if out.get( "sender_id" ) is not None:
        out[ "sender_id" ] = f"sender-fixture-{idx}"
    lib.redact_timestamp_fields( out, ( "created_at", "updated_at" ) )
    return out


def _redact_pending_envelope( body: dict[str, Any] ) -> dict[str, Any]:
    out = { **body }
    if isinstance( out.get( "decisions" ), list ):
        out[ "decisions" ] = [
            _redact_decision( d, i )
            for i, d in enumerate( out[ "decisions" ][ :MAX_DECISIONS ] )
        ]
    if isinstance( out.get( "summary" ), dict ):
        summary = { **out[ "summary" ] }
        lib.redact_timestamp_fields( summary, ( "oldest_pending", ) )
        out[ "summary" ] = summary
    if isinstance( out.get( "batch" ), dict ):
        # Batch IDs are arbitrary strings that can include timestamps; leave as-is
        # unless a future capture reveals secrets.
        pass
    return out


def _redact_trust_state( ts: dict[str, Any], idx: int ) -> dict[str, Any]:
    out = { **ts }
    if "id" in out:
        out[ "id" ] = f"ts-fixture-{idx}"
    lib.redact_timestamp_fields( out, ( "created_at", "updated_at" ) )
    return out


def _redact_trust_envelope( body: dict[str, Any] ) -> dict[str, Any]:
    out = { **body }
    if "user_email" in out:
        out[ "user_email" ] = lib.REDACT_EMAIL
    if isinstance( out.get( "trust_states" ), list ):
        out[ "trust_states" ] = [
            _redact_trust_state( s, i )
            for i, s in enumerate( out[ "trust_states" ][ :MAX_TRUST_STATES ] )
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

    print( f"Capturing decision-proxy fixtures against {base_url}..." )

    _, access_token, _ = lib.login_for_capture( base_url, email, password )
    auth_hdr = { "Authorization": f"Bearer {access_token}" }
    enc_email = urllib.parse.quote( email, safe="" )

    # 1. GET /api/proxy/mode
    status, mode_body = lib.get_json( base_url, "/api/proxy/mode", headers=auth_hdr )
    if status != 200:
        print( f"ERROR: /api/proxy/mode returned {status}: {mode_body}", file=sys.stderr )
        return 2
    lib.write_fixture( DOMAIN, "mode.json", mode_body )

    # 2. GET /api/proxy/pending/{email}
    status, pending_body = lib.get_json(
        base_url, f"/api/proxy/pending/{enc_email}", headers=auth_hdr,
    )
    if status != 200:
        print( f"WARN: /api/proxy/pending returned {status}: {pending_body}", file=sys.stderr )
    else:
        lib.write_fixture( DOMAIN, "pending.json", _redact_pending_envelope( pending_body ) )

    # 3. POST /api/proxy/acknowledge
    status, ack_body = lib.post_json(
        base_url, "/api/proxy/acknowledge", {}, headers=auth_hdr,
    )
    if status != 200:
        print( f"WARN: /api/proxy/acknowledge returned {status}: {ack_body}", file=sys.stderr )
    else:
        lib.write_fixture( DOMAIN, "acknowledge.json", ack_body )

    # 4. GET /api/proxy/trust/{email}
    status, trust_body = lib.get_json(
        base_url, f"/api/proxy/trust/{enc_email}", headers=auth_hdr,
    )
    if status != 200:
        print( f"WARN: /api/proxy/trust returned {status}: {trust_body}", file=sys.stderr )
    else:
        lib.write_fixture( DOMAIN, "trust_state.json", _redact_trust_envelope( trust_body ) )

    # Final safety net
    for path in ( "mode.json", "pending.json", "acknowledge.json", "trust_state.json" ):
        full = lib.fixtures_dir( DOMAIN ) / path
        if full.exists():
            lib.assert_no_jwt_residue( json.loads( full.read_text() ), path )

    print( "Done." )
    return 0


if __name__ == "__main__":
    sys.exit( main() )
