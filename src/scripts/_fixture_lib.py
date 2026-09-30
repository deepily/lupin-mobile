"""
Shared helpers for fixture-capture scripts.

Each domain (auth, notifications, decision_proxy, ...) has a small CLI script
that captures real backend responses, redacts sensitive values, and writes
stable-format JSON into test/fixtures/<domain>/. This module is their common
infrastructure.

See test/fixtures/README.md for the pattern overview and redaction contract.
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

def project_root() -> Path:
    """Repo root resolved from this file's location (src/scripts/_fixture_lib.py)."""
    return Path( __file__ ).resolve().parent.parent.parent


def fixtures_dir( domain: str ) -> Path:
    """`test/fixtures/<domain>/`, created on demand."""
    path = project_root() / "test" / "fixtures" / domain
    path.mkdir( parents=True, exist_ok=True )
    return path


# ---------------------------------------------------------------------------
# HTTP — urllib only (no requests dep required)
# ---------------------------------------------------------------------------

def post_json(
    base_url: str,
    path: str,
    body: dict[str, Any],
    *,
    headers: dict[str, str] | None = None,
) -> tuple[int, dict[str, Any]]:
    """POST application/json; return (status, decoded body). HTTP errors are
    caught and returned with their status so callers can assert error shapes."""
    data    = json.dumps( body ).encode( "utf-8" )
    req_hdr = { "Content-Type": "application/json" }
    if headers:
        req_hdr.update( headers )
    req = urllib.request.Request( base_url + path, data=data, headers=req_hdr, method="POST" )
    try:
        with urllib.request.urlopen( req ) as resp:
            return resp.status, json.loads( resp.read().decode( "utf-8" ) )
    except urllib.error.HTTPError as e:
        return e.code, json.loads( e.read().decode( "utf-8" ) )


def get_json(
    base_url: str,
    path: str,
    *,
    headers: dict[str, str] | None = None,
) -> tuple[int, dict[str, Any] | list[Any]]:
    """GET; return (status, decoded body — dict OR list). Error bodies come
    back with their status instead of raising."""
    req = urllib.request.Request( base_url + path, headers=headers or {}, method="GET" )
    try:
        with urllib.request.urlopen( req ) as resp:
            return resp.status, json.loads( resp.read().decode( "utf-8" ) )
    except urllib.error.HTTPError as e:
        return e.code, json.loads( e.read().decode( "utf-8" ) )


# ---------------------------------------------------------------------------
# Redaction primitives
# ---------------------------------------------------------------------------

REDACT_ACCESS_TOKEN  = "fixture_access_token"
REDACT_REFRESH_TOKEN = "fixture_refresh_token"
REDACT_USER_ID       = "uid-fixture"
REDACT_EMAIL         = "fixture@example.com"
REDACT_TIMESTAMP     = "2025-01-01T00:00:00+00:00"
REDACT_SENDER_ID     = "sender-fixture"
REDACT_DECISION_ID   = "decision-fixture"
REDACT_NOTIFICATION_ID = "notif-fixture"
REDACT_MESSAGE_ID      = "msg-fixture"


def redact_tokens( tokens: dict[str, Any] ) -> dict[str, Any]:
    """Replace JWTs with stable placeholders. Raises SystemExit(3) if the
    tokens dict is missing required fields — that's a real backend change we
    want to notice loudly, not silently paper over."""
    if "access_token" not in tokens or "refresh_token" not in tokens:
        print( f"ERROR: tokens object missing required fields: {list( tokens.keys() )}", file=sys.stderr )
        sys.exit( 3 )
    return {
        **tokens,
        "access_token"  : REDACT_ACCESS_TOKEN,
        "refresh_token" : REDACT_REFRESH_TOKEN,
    }


def redact_timestamp_fields( body: dict[str, Any], fields: tuple[str, ...] ) -> None:
    """In-place: normalize timestamps to REDACT_TIMESTAMP when non-null."""
    for f in fields:
        if body.get( f ) is not None:
            body[ f ] = REDACT_TIMESTAMP


def assert_no_jwt_residue( body: Any, label: str ) -> None:
    """Naive three-dot check. If any string in the serialized body looks like
    a JWT (three base64-ish segments separated by dots, each ≥20 chars), bail
    with a security-incident-style error. Called after redaction as a safety
    net — a positive here means the capture script's redaction has a gap."""
    text = json.dumps( body )
    for chunk in text.split( '"' ):
        parts = chunk.split( "." )
        if len( parts ) == 3 and all( len( p ) >= 20 for p in parts ):
            print( f"ERROR: possible unredacted JWT in {label}: {chunk[:60]}...", file=sys.stderr )
            sys.exit( 3 )


# ---------------------------------------------------------------------------
# Write
# ---------------------------------------------------------------------------

def write_fixture( domain: str, filename: str, body: Any ) -> Path:
    """Write `body` to test/fixtures/<domain>/<filename> with stable key order
    and two-space indent so diffs stay readable. Returns the path for
    logging."""
    path = fixtures_dir( domain ) / filename
    path.write_text(
        json.dumps( body, indent=2, sort_keys=True ) + "\n",
        encoding="utf-8",
    )
    rel = path.relative_to( project_root() )
    print( f"  wrote {rel}" )
    return path


# ---------------------------------------------------------------------------
# Auth login (shared by every domain — everyone needs a token)
# ---------------------------------------------------------------------------

def login_for_capture( base_url: str, email: str, password: str ) -> tuple[dict[str, Any], str, str]:
    """Log in for fixture capture. Returns (raw_body, access_token, refresh_token).
    Exits with a clear error on non-200."""
    status, body = post_json( base_url, "/auth/login", { "email": email, "password": password } )
    if status != 200:
        print( f"ERROR: login returned {status}: {body}", file=sys.stderr )
        sys.exit( 2 )
    tokens = body.get( "tokens" ) or {}
    access  = tokens.get( "access_token"  )
    refresh = tokens.get( "refresh_token" )
    if not access or not refresh:
        print( f"ERROR: login response missing tokens: {list( body.keys() )}", file=sys.stderr )
        sys.exit( 3 )
    return body, access, refresh


# ---------------------------------------------------------------------------
# Query building — ONE encoder, because the alternative diverged once already
# ---------------------------------------------------------------------------

def build_query( path: str, params: dict[str, Any] ) -> str:
    """
    Build `path?k=v&...` with every value percent-encoded.

    🔴 WHY THIS IS A SHARED FUNCTION RATHER THAN AN f-STRING AT EACH CALL SITE
    (Tiffany's ruling, 2026-09-19). An ISO-8601 offset ends `+00:00`, and a RAW `+`
    in a query string decodes to a SPACE — so `since=2026-09-06T00:00:00+00:00`
    reaches the server as a malformed datetime and earns a 422.

    ⚠️ AND THE SYMPTOM POINTS AT THE WRONG THING. Login has already SUCCEEDED by
    then, so three endpoints answering 422 in a row reads as "the endpoint is broken"
    or "my token is wrong". Measured in capture-finished-tasks-fixtures.py on its
    first run, 2026-09-19; it was nearly filed as a server defect.

    ⇒ The capture scripts stay separate because `/api/tasks` and `/api/tasks/events`
    return different shapes and want different windowing — but the ENCODING is the
    same problem for both, and fixing it in one place fixes it for a script this one
    never touches.

    Requires:
        - path starts with "/"
        - params values are str, int, bool or None

    Ensures:
        - a None value is OMITTED, not sent as the string "None"
        - a bool is sent lowercase, as the server's query parsers expect
        - every other value is percent-encoded, so "+", "/", "?" and "#" survive
        - a params dict that is empty returns the bare path, with no trailing "?"
    """
    from urllib.parse import quote

    pairs = []
    for key, value in params.items():
        if value is None:
            continue
        if isinstance( value, bool ):
            rendered = "true" if value else "false"
        else:
            rendered = str( value )
        pairs.append( f"{quote( str( key ) )}={quote( rendered )}" )

    return path if not pairs else f"{path}?{'&'.join( pairs )}"
