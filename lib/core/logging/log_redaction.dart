/// Credential scrubbing for anything that reaches a log sink.
///
/// Row `a7de7d69`: Dio's `LogInterceptor` printed `Authorization: Bearer <jwt>`
/// on every request and both tokens in the sign-in response body, to stdout,
/// which on Android is logcat. Rick's own pasted logcat tail on 2026-09-19
/// carried his live JWT twice, with his user id and email inside it.
///
/// This is the LAST line of defence, not the only one: the caller also declines
/// to log request headers at all, and registers the logger only in debug builds.
/// A leak therefore needs two independent failures.
library;

/// A JWT: three base64url segments, the first of which starts with the `{"` that
/// every JSON header encodes to. Deliberately anchored on `eyJ` rather than
/// matching any dotted triple, so ordinary dotted text is left alone.
final RegExp _jwt = RegExp( r"eyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}" );

/// An `Authorization` header value, however the sink spells the separator.
/// Stops at a newline, a comma, or a closing brace so only the value is eaten.
final RegExp _authHeader = RegExp(
  r"(authorization\s*[:=]\s*)([^\n,}]+)",
  caseSensitive: false,
);

/// A token field in a JSON body: `"access_token":"…"`.
final RegExp _jsonTokenField = RegExp(
  "\"((?:access|refresh|id)_token)\"\\s*:\\s*\"[^\"]*\"",
  caseSensitive: false,
);

/// A token field in a Dart map's `toString()`: `{refresh_token: …}`. Dio prints
/// request bodies this way, so the JSON form alone would miss them.
final RegExp _mapTokenField = RegExp(
  r"((?:access|refresh|id)_token)\s*:\s*([^\n,}]+)",
  caseSensitive: false,
);

const String _mask = "<redacted>";

/// Returns [line] with every credential we know how to recognise masked.
///
/// Requires:
///   - line is non-null
///
/// Ensures:
///   - no JWT-shaped substring survives in the result
///   - an `Authorization` header keeps its name and loses its value
///   - `access_token`, `refresh_token` and `id_token` keep their names and lose
///     their values, in both JSON and Dart-map spellings
///   - text containing no credential is returned unchanged, character for
///     character — this runs on every logged line, so it must not reformat
///   - the mask itself is never re-masked, so repeated application is stable
String redactSecrets( String line ) {
  var out = line;

  // Field names first: they bound the value precisely, so a non-JWT or opaque
  // token is caught even when the JWT pattern cannot see it.
  out = out.replaceAllMapped( _jsonTokenField, ( m ) => "\"${m[ 1 ]}\":\"$_mask\"" );
  out = out.replaceAllMapped( _mapTokenField,  ( m ) => "${m[ 1 ]}: $_mask" );
  out = out.replaceAllMapped( _authHeader,     ( m ) => "${m[ 1 ]}$_mask" );

  // Then the shape, wherever it appears — a token logged under a name we did
  // not anticipate still does not reach the sink.
  out = out.replaceAll( _jwt, _mask );

  return out;
}
