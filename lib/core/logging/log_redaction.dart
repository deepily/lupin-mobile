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

/// A credential field name, such as `access_token`, `db_password`, `client_secret` or `x-api-key`.
///
/// It is any identifier ending in `token`, `password`, `passwd`, `secret` or `api_key` (also `api-key`, `apikey`).
/// It must start a word, so `tokenizer`, `passwordless`, `secretary` and `monkey` are left alone.
/// The lookahead exempts the OAuth error code `invalid_token`, so its reason survives.
const String _credentialName =
    r"(?<![A-Za-z0-9_-])(?!invalid[_-]token\b)([A-Za-z0-9_-]*(?:token|password|passwd|secret|api[_-]?key))";

/// A credential field name and separator, such as `"access_token":`, `'api_token': ` or `password=`.
///
/// Group 1 is the name's opening quote (empty if unquoted), group 2 the name, group 4 the separator.
/// The closing quote (group 3) must repeat the opening one.
/// The value is found by [_valueEnd], because a regular expression cannot find where a nested one ends.
final RegExp _credentialField = RegExp(
  "([\"']?)$_credentialName(\\1)\\s*([:=])\\s*",
  caseSensitive: false,
);

/// An `Authorization` header value, with any separator and a quoted or bare name.
///
/// It stops at a newline, a comma or a closing brace, so only the value is eaten.
final RegExp _authHeader = RegExp(
  r"""(authorization["']?\s*[:=]\s*)([^\n,}]+)""",
  caseSensitive: false,
);

const String _mask = "<redacted>";

/// Returns the index past the value starting at [start] in [text].
///
/// A string ends at its closing quote; an array or object ends at its matching bracket, skipping strings.
/// A value never closed (a truncated line) runs to the end of the line, so it is over-masked, not leaked.
/// A bare scalar ends at a newline, comma, closing brace or ampersand, and, after a quoted name, at whitespace or `]`.
///
/// Requires:
///   - 0 <= start <= text.length
///
/// Ensures:
///   - returns an index in [start, text.length]
int _valueEnd( String text, int start, { required bool nameQuoted } ) {
  final n = text.length;
  if ( start >= n ) return n;
  final first = text[ start ];

  var lineEnd = text.indexOf( "\n", start );
  if ( lineEnd < 0 ) lineEnd = n;

  if ( first == "\"" || first == "'" ) {
    final close = _stringEnd( text, start, lineEnd );
    return close ?? lineEnd;
  }

  if ( first == "[" || first == "{" ) {
    var depth = 0;
    var i     = start;
    while ( i < lineEnd ) {
      final c = text[ i ];
      if ( c == "\"" || c == "'" ) {
        final close = _stringEnd( text, i, lineEnd );
        if ( close == null ) return lineEnd;
        i = close;
        continue;
      }
      if ( c == "[" || c == "{" ) depth++;
      if ( c == "]" || c == "}" ) {
        depth--;
        if ( depth == 0 ) return i + 1;
      }
      i++;
    }
    return lineEnd;
  }

  final stop = nameQuoted ? RegExp( r"[\s,}\]&]" ) : RegExp( r"[\n,}&]" );
  final hit  = stop.firstMatch( text.substring( start ) );
  return hit == null ? n : start + hit.start;
}

/// Returns the index past the string opened at [open], or null if unclosed before [limit].
int? _stringEnd( String text, int open, int limit ) {
  final quote = text[ open ];
  var i       = open + 1;
  while ( i < limit ) {
    final c = text[ i ];
    if ( c == "\\" ) { i += 2; continue; }
    if ( c == quote ) return i + 1;
    i++;
  }
  return null;
}

/// Returns [line] with every credential it recognizes masked.
///
/// Requires:
///   - line is non-null
///
/// Ensures:
///   - no JWT-shaped substring survives in the result
///   - an `Authorization` header keeps its name and loses its value
///   - any name ending in `token`, `password`, `passwd`, `secret` or `api_key` (`access_token`, `db_password`, `accessToken`, `client_secret`, `x-api-key`, bare `token`) keeps its name and loses its value, whether the name is bare, double-quoted or single-quoted, and whether the value is a string, a scalar, an array or a nested object, in JSON, Python-repr, Dart-map and form spellings
///   - an error code that merely ends in `id_token`, such as `invalid_token`, is left alone
///   - text containing no credential is returned unchanged, character for character, because this runs on every logged line
///   - the mask itself is never re-masked, so repeated application is stable
String redactSecrets( String line ) {
  var out = line;

  // Field names first: they bound the value precisely, so a non-JWT or opaque
  // token is caught even when the JWT pattern cannot see it.
  final buffer      = StringBuffer();
  var   copiedUpTo  = 0;
  for ( final m in _credentialField.allMatches( out ) ) {
    // A credential name inside a value already masked (a nested object) is gone with it.
    if ( m.start < copiedUpTo ) continue;
    final quote      = m[ 1 ]!;
    final end        = _valueEnd( out, m.end, nameQuoted: quote.isNotEmpty );
    buffer.write( out.substring( copiedUpTo, m.start ) );
    if ( quote == "\"" && m[ 4 ] == ":" ) {
      buffer.write( "\"${m[ 2 ]}\":\"$_mask\"" );
    } else {
      buffer.write( "$quote${m[ 2 ]}$quote${m[ 4 ] == "=" ? "=" : ": "}$_mask" );
    }
    copiedUpTo = end;
  }
  buffer.write( out.substring( copiedUpTo ) );
  out = buffer.toString();
  out = out.replaceAllMapped( _authHeader, ( m ) => "${m[ 1 ]}$_mask" );

  // Then the shape, wherever it appears — a token logged under a name we did
  // not anticipate still does not reach the sink.
  out = out.replaceAll( _jwt, _mask );

  return out;
}
