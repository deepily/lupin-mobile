#!/usr/bin/env python3
"""
Capture real Lupin backend auth responses, redact sensitive values, and write
stable JSON fixtures for repository-layer unit tests.

Usage:
    export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL="ricardo.felipe.ruiz@gmail.com"
    export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD="..."
    # Optional, defaults to http://localhost:7999
    # export LUPIN_API_BASE_URL="http://10.0.2.2:7999"
    python src/scripts/capture-auth-fixtures.py

Exit codes:
    0 — all fixtures captured and written
    1 — config / env error
    2 — HTTP error from backend
    3 — unexpected response shape (redaction or required-field check failed)

See test/fixtures/README.md for the broader pattern and redaction contract.
"""

from __future__ import annotations

import os
import sys
from typing import Any

import _fixture_lib as lib


DOMAIN = "auth"
DEFAULT_BASE_URL = "http://localhost:7999"


def _redact_user( user: dict[str, Any] ) -> dict[str, Any]:
    redacted = { **user }
    if "id" in redacted:
        redacted[ "id" ] = lib.REDACT_USER_ID
    if "email" in redacted:
        redacted[ "email" ] = lib.REDACT_EMAIL
    lib.redact_timestamp_fields( redacted, ( "created_at", "last_login_at" ) )
    return redacted


def _redact_envelope( body: dict[str, Any] ) -> dict[str, Any]:
    out = { **body }
    if "tokens" in out and isinstance( out[ "tokens" ], dict ):
        out[ "tokens" ] = lib.redact_tokens( out[ "tokens" ] )
    if "user" in out and isinstance( out[ "user" ], dict ):
        out[ "user" ] = _redact_user( out[ "user" ] )
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

    print( f"Capturing auth fixtures against {base_url}..." )

    # 1. Successful login
    login_body, access_token, refresh_token = lib.login_for_capture( base_url, email, password )
    redacted_login = _redact_envelope( login_body )
    lib.assert_no_jwt_residue( redacted_login, "login_response.json" )
    lib.write_fixture( DOMAIN, "login_response.json", redacted_login )

    # 2. Failed login (capture 401 shape)
    status, login_err_body = lib.post_json(
        base_url, "/auth/login",
        { "email": email, "password": f"{password}_WRONG" },
    )
    if status != 401:
        print( f"WARN: bad-password login returned {status}, expected 401: {login_err_body}", file=sys.stderr )
    # Error bodies typically have no secrets beyond {"detail": "..."}.
    lib.write_fixture( DOMAIN, "login_error_401.json", login_err_body )

    # 3. /auth/me with the fresh access token
    status, me_body = lib.get_json(
        base_url, "/auth/me",
        headers={ "Authorization": f"Bearer {access_token}" },
    )
    if status != 200:
        print( f"ERROR: /auth/me returned {status}: {me_body}", file=sys.stderr )
        return 2
    redacted_me = _redact_user( me_body )
    lib.assert_no_jwt_residue( redacted_me, "me_response.json" )
    lib.write_fixture( DOMAIN, "me_response.json", redacted_me )

    # 4. /auth/refresh with the fresh refresh token
    status, refresh_body = lib.post_json(
        base_url, "/auth/refresh",
        { "refresh_token": refresh_token },
    )
    if status != 200:
        print( f"ERROR: /auth/refresh returned {status}: {refresh_body}", file=sys.stderr )
        return 2
    redacted_refresh = _redact_envelope( refresh_body )
    lib.assert_no_jwt_residue( redacted_refresh, "refresh_response.json" )
    lib.write_fixture( DOMAIN, "refresh_response.json", redacted_refresh )

    print( "All fixtures captured and redacted." )
    return 0


if __name__ == "__main__":
    sys.exit( main() )
