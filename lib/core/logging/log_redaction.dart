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

/// A credential field name, such as `access_token`, `client_secret` or `x-api-key`.
///
/// It is an identifier ending in `token`, `password`, `passwd`, `secret`, `api_key`, `secret_key`, `private_key`
/// or `access_key` (dash, underscore or camelCase), singular or plural.
/// Only token-count names (`max_tokens`, `total_tokens`, ...) may hold a bare number; see [_countNames].
/// It must start a word, so `tokenizer`, `passwordless`, `secretary` and `monkey` are left alone.
/// The lookahead exempts the OAuth error code `invalid_token`, so its reason survives.
const String _credentialName =
    r"(?<![A-Za-z0-9_-])(?!invalid[_-]token\b)([A-Za-z0-9_-]*(?:token|password|passwd|secret|api[_-]?key|(?:secret|private|access)[_-]?key)s?)";

/// A credential field name and separator, such as `"access_token":` or `password=`.
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

/// A bare number (`123`, `-4`, `7.5`) ending at whitespace, `&`, `,`, a bracket or the text end.
///
/// Letters after the digits (`512abc`, `1e5`) mean it could be a credential, so it does not count.
final RegExp _bareNumber = RegExp( r"-?\d+(\.\d+)?(?=[\s&,\]})]|$)" );

/// Underscores and dashes in a field name, dropped before it is looked up in [_countNames].
final RegExp _nameSeparators = RegExp( r"[_-]" );

/// The names whose bare-number values are counts and stay readable, lowercase and without `_` or `-`.
const Set<String> _countNames = {
  "tokens", "maxtokens", "prompttokens", "completiontokens", "totaltokens", "inputtokens", "outputtokens",
};

const String _mask = "<redacted>";

/// Returns the index past the value starting at [start] in [text].
///
/// A string ends at its closing quote, an array or object at its matching bracket (across lines).
/// An unclosed string is masked to its line end, an unclosed array or object to the text end.
/// A bare scalar ends at a newline, comma, brace or ampersand (after a quoted name, also whitespace or `]`).
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

  if ( first == "\"" || first == "'" ) {
    return _stringEnd( text, start, stopAtNewline: true ) ?? _lineEnd( text, start );
  }

  if ( first == "[" || first == "{" ) {
    var depth = 0;
    var i     = start;
    while ( i < n ) {
      final c = text[ i ];
      if ( c == "\"" || c == "'" ) {
        final close = _stringEnd( text, i, stopAtNewline: false );
        if ( close == null ) return n;
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
    return n;
  }

  var i = start;
  while ( i < n ) {
    final c = text[ i ];
    if ( c == "\n" || c == "," || c == "}" || c == "&" ) break;
    if ( nameQuoted && ( c == " " || c == "\t" || c == "\r" || c == "]" ) ) break;
    i++;
  }
  return i;
}

/// Returns the index of the first newline at or after [from], or the text length.
int _lineEnd( String text, int from ) {
  final at = text.indexOf( "\n", from );
  return at < 0 ? text.length : at;
}

/// Returns the index past the string opened at [open], or null if never closed.
///
/// With [stopAtNewline], a newline before the closing quote means it never closes.
int? _stringEnd( String text, int open, { required bool stopAtNewline } ) {
  final quote = text[ open ];
  var i       = open + 1;
  while ( i < text.length ) {
    final c = text[ i ];
    if ( c == "\\" ) { i += 2; continue; }
    if ( c == quote ) return i + 1;
    if ( stopAtNewline && c == "\n" ) return null;
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
    // A token-count name holding a bare number (`max_tokens=512`) is a usage count, not a credential.
    if ( _countNames.contains( m[ 2 ]!.toLowerCase().replaceAll( _nameSeparators, "" ) ) && _bareNumber.matchAsPrefix( out, m.end ) != null ) continue;
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
