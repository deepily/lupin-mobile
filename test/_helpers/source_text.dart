/// Source-text helper for tests that read `lib/` as text.
///
/// A scan that reads prose as code fails on documentation (a doc comment naming
/// the retired endpoint it replaced) — which is exactly what a doc rewrite adds.
/// Strip comments first so such a test measures CODE only.
library;

/// [source] with every comment removed. Strips `//` to end of line and
/// `/* ... */` blocks, and tracks quotes so a `//` inside a string literal
/// (a URL, say) survives.
String stripComments( String source ) {
  final code   = StringBuffer();
  String? quote;
  var inBlock = false;

  for ( var i = 0; i < source.length; i++ ) {
    final char = source[ i ];
    final next = i + 1 < source.length ? source[ i + 1 ] : "";

    if ( inBlock ) {
      if ( char == "*" && next == "/" ) {
        inBlock = false;
        i      += 1;
      }
      continue;
    }
    if ( quote == null && char == "/" && next == "/" ) {
      while ( i < source.length && source[ i ] != "\n" ) {
        i += 1;
      }
      code.write( "\n" );
      continue;
    }
    if ( quote == null && char == "/" && next == "*" ) {
      inBlock = true;
      i      += 1;
      continue;
    }
    if ( quote != null && char == r"\" ) {
      code.write( char );
      i += 1;
      if ( i < source.length ) code.write( source[ i ] );
      continue;
    }
    if ( char == quote ) {
      quote = null;
    } else if ( quote == null && ( char == "'" || char == '"' ) ) {
      quote = char;
    }
    code.write( char );
  }
  return code.toString();
}
