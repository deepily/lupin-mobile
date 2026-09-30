# Test fixtures — captured real backend responses

These JSON files are captured from a running Lupin backend, redacted to stable
placeholder values, and loaded by repository-layer unit tests. The pattern
exists to prevent stub drift: when the backend response shape changes, a
re-capture regenerates these fixtures and any test still assuming the old shape
fails immediately.

## Why

Before fixtures, tests hand-crafted stub Maps in Dart. If the real backend
response and the stub diverged, the tests stayed green while the app broke on
real hardware. See `src/rnd/v0.1.7/2026.04.17-auth-login-envelope-parse-fix.md`
for the motivating bug (`LoginResponse` envelope parse).

## Layout

```
test/fixtures/
├── README.md            (this file)
└── auth/
    ├── login_response.json        — /auth/login 200 success
    ├── refresh_response.json      — /auth/refresh 200 success
    ├── me_response.json           — /auth/me 200 success
    └── login_error_401.json       — /auth/login 401 bad-creds
```

Expand as additional endpoints need fixture coverage.

## Capture workflow

```bash
# From the lupin-mobile package root:
export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL="ricardo.felipe.ruiz@gmail.com"
export LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD="..."
# Optional, defaults to http://localhost:7999
# export LUPIN_API_BASE_URL="http://10.0.2.2:7999"

python src/scripts/capture-auth-fixtures.py
```

The script:
1. POSTs to `/auth/login` twice — once with good creds (captures 200), once
   with deliberately-wrong password (captures 401 shape).
2. Uses the captured access token to GET `/auth/me`.
3. Uses the captured refresh token to POST `/auth/refresh`.
4. Redacts the captured JSON (see below) and writes the four fixtures.

## Redaction rules

The capture script MUST replace real sensitive values with stable placeholders
before writing. This lets fixtures be committed to git safely and makes test
assertions stable across captures.

| Field | Real value | Fixture value |
|---|---|---|
| `tokens.access_token` | actual JWT | `"fixture_access_token"` |
| `tokens.refresh_token` | actual JWT | `"fixture_refresh_token"` |
| `user.id` | real UUID | `"uid-fixture"` |
| `user.email` | real address | `"fixture@example.com"` |
| `user.created_at` | real timestamp | `"2025-01-01T00:00:00+00:00"` |
| `user.last_login_at` | real timestamp | `"2025-01-01T00:00:00+00:00"` |

Anything not in this table is preserved as-is. If a real JWT ever lands in
this directory, it's a bug in the capture script — treat it as a security
incident.

## Loading a fixture from a test

```dart
import '../../_helpers/fixture_loader.dart';

adapter.handlers["POST /auth/login"] =
  ( _ ) => jsonBodyFromFixture( "auth/login_response.json" );
```

For the raw decoded Map (no Dio wrapping):

```dart
final Map<String, dynamic> body = loadFixture( "auth/login_response.json" );
```

## When to re-capture

- After any change to backend Pydantic response models under
  `src/cosa/rest/auth_models.py` (or any endpoint touched by the change).
- When a test failure mentions a missing key or wrong type — run the capture
  once and compare the diff against the old fixture to confirm the backend
  shape changed.
- Never re-capture to "fix" a failing test without checking the diff first.

## Negative test (drift detection demo)

To verify this pattern works:

1. Manually edit `auth/login_response.json` and delete the `tokens` key.
2. Run `./flutter.sh test test/unit/auth/auth_repository_test.dart`.
3. Tests should fail on "login parses access + refresh tokens from the
   LoginResponse envelope" with a clear AuthException message about the
   missing tokens envelope.
4. Restore the fixture.
