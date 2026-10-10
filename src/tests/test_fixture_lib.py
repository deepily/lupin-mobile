"""
The shared capture library's token guard (row 768e852f, Chloé's review of 085bad5).

`write_fixture` is the one door every capture script writes through, so the
embedded-token check lives THERE: a call site that forgets `assert_no_jwt_residue`
still cannot put a token in a committed fixture.

Run: python -m pytest src/tests/test_fixture_lib.py -v
"""

from __future__ import annotations

import os
import sys

import pytest

SCRIPTS = os.path.join( os.path.dirname( __file__ ), "..", "scripts" )
sys.path.insert( 0, SCRIPTS )

import _fixture_lib as lib  # noqa: E402

_HEADER  = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
_PAYLOAD = "eyJzdWIiOiI1MGM3M2JhNy0zNmRkLTRlYWYtYTdlMi02MzI1NjI1MmM4NGYiLCJleHAiOjE3OTE2MDExODZ9"
_SIG     = "dt7AKddyXdpWGYgKU91XiKsAbCdEfGhIjKlMnOpQrSt"
TOKEN    = f"{_HEADER}.{_PAYLOAD}.{_SIG}"

PROSE = ( "see src/cosa/rest/routers/cc_transcript.py and cosa.rest.routers.websocket.session_is_admin "
          "then lupin.mobile.fleet_status.fleet_status_bloc_test.dart at v0.2.1.2026.08.29 done." )


@pytest.fixture
def out_dir( monkeypatch, tmp_path ):
    """Redirect fixture output into tmp_path; a real write here is observable."""
    monkeypatch.setattr( lib, "fixtures_dir", lambda domain: tmp_path )
    monkeypatch.setattr( lib, "project_root", lambda: tmp_path.parent )
    return tmp_path


def test_a_bare_token_is_found():
    assert lib.contains_jwt( { "t": TOKEN } )


def test_a_token_EMBEDDED_in_a_longer_string_is_found():
    assert lib.contains_jwt( { "text": f"{{'access_token': '{TOKEN}', 'token_type': 'bearer'}}" } )
    assert lib.contains_jwt( [ { "x": { "cmd": f"curl -H 'Authorization: Bearer {TOKEN}' x" } } ] )


def test_dotted_prose_is_not_a_token():
    assert not lib.contains_jwt( { "text": PROSE } )


def test_write_fixture_REFUSES_an_embedded_token_and_writes_nothing( out_dir ):
    with pytest.raises( ValueError, match="JWT" ):
        lib.write_fixture( "d", "f.json", { "blocks": [ { "text": f"result: {TOKEN} done" } ] } )
    assert list( out_dir.iterdir() ) == [], "a refused body must leave no file behind"


def test_write_fixture_REFUSES_a_bare_token_too( out_dir ):
    with pytest.raises( ValueError ):
        lib.write_fixture( "d", "f.json", { "access_token": TOKEN } )
    assert list( out_dir.iterdir() ) == []


def test_write_fixture_still_writes_an_ordinary_body( out_dir ):
    path = lib.write_fixture( "d", "ok.json", { "text": PROSE, "n": 1 } )
    assert path.exists()


def test_the_redaction_placeholders_are_not_mistaken_for_tokens( out_dir ):
    body = lib.redact_tokens( { "access_token": "x", "refresh_token": "y" } )
    assert not lib.contains_jwt( body )
    lib.write_fixture( "d", "red.json", body )


def test_assert_no_jwt_residue_exits_on_an_embedded_token_and_passes_prose():
    with pytest.raises( SystemExit ) as why:
        lib.assert_no_jwt_residue( { "text": f"printed {TOKEN} here" }, "x.json" )
    assert why.value.code == 3
    lib.assert_no_jwt_residue( { "text": PROSE }, "x.json" )
