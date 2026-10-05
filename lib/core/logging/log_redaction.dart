/// Credential scrubbing for anything that reaches a log sink.
///
/// Dio's `LogInterceptor` prints `Authorization: Bearer <jwt>` on every request and both tokens in the sign-in response body.
/// It prints to stdout, which on Android is logcat. A pasted logcat tail then carries a live JWT, with the user id and email inside it.
/// This is the last line of defense, not the only one. The caller also declines to log request headers
/// and registers the logger only in debug builds, so a leak needs two independent failures.
library;

/// A JWT: three base64url segments, the first starting with `{"`, as every JSON header does.
///
/// It is anchored on `eyJ` rather than matching any dotted triple, so ordinary dotted text is left alone.
final RegExp _jwt = RegExp( r"eyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}" );

/// An `Authorization` header value, however the sink spells the separator.
///
/// It stops at a newline, a comma or a closing brace, so only the value is eaten.
final RegExp _authHeader = RegExp(
  r"(authorization\s*[:=]\s*)([^\n,}]+)",
  caseSensitive: false,
);

/// A token or password field in a JSON body: `"access_token":"…"`, `"password":"…"`.
final RegExp _jsonTokenField = RegExp(
  "\"((?:(?:access|refresh|id)_)?token|password)\"\\s*:\\s*\"[^\"]*\"",
  caseSensitive: false,
);

/// A token field written `name: value` (a Dart map's `toString()`) or `name=value` (a form body or query string).
///
/// Dio prints request bodies as maps, and a parse error can quote a form-encoded frame, so the JSON form alone
/// would miss both. The value stops at a newline, comma, closing brace or ampersand.
///
/// The name must start a word: the lookbehind refuses a letter, digit or underscore before it, so an error code
/// such as `invalid_token: the token expired` keeps its reason. Bare `token` and `password` fields are masked too.
final RegExp _mapTokenField = RegExp(
  r"(?<![A-Za-z0-9_])((?:(?:access|refresh|id)_)?token|password)\s*([:=])\s*([^\n,}&]+)",
  caseSensitive: false,
);

const String _mask = "<redacted>";

/// Returns [line] with every credential it recognizes masked.
///
/// Requires:
///   - line is non-null
///
/// Ensures:
///   - no JWT-shaped substring survives in the result
///   - an `Authorization` header keeps its name and loses its value
///   - `access_token`, `refresh_token`, `id_token`, bare `token` and `password` keep their names and lose their values, in both JSON and Dart-map spellings
///   - an error code that merely ends in `id_token`, such as `invalid_token`, is left alone
///   - text containing no credential is returned unchanged, character for character, because this runs on every logged line
///   - the mask itself is never re-masked, so repeated application is stable
String redactSecrets( String line ) {
  var out = line;

  // Field names first: they bound the value precisely, so a non-JWT or opaque
  // token is caught even when the JWT pattern cannot see it.
  out = out.replaceAllMapped( _jsonTokenField, ( m ) => "\"${m[ 1 ]}\":\"$_mask\"" );
  out = out.replaceAllMapped( _mapTokenField,  ( m ) => "${m[ 1 ]}${m[ 2 ] == "=" ? "=" : ": "}$_mask" );
  out = out.replaceAllMapped( _authHeader,     ( m ) => "${m[ 1 ]}$_mask" );

  // Then the shape, wherever it appears — a token logged under a name we did
  // not anticipate still does not reach the sink.
  out = out.replaceAll( _jwt, _mask );

  return out;
}
