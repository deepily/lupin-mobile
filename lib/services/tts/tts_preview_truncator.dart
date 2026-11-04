/// Port of the web client's TTS preview limiter (`notifications.js::_truncateAtBoundary`).
///
/// Truncates text to roughly a fraction of its length, extending forward from the fraction mark to the next boundary:
///   1. targetPos = ceil( length x fraction ).
///   2. Scan forward for the first boundary: a newline, an em or en dash (never a hyphen-minus),
///      or one of `. ! ? ;` followed by whitespace or the end. So "3.14", "v0.1.7" and "file.py" are not boundaries.
///   3. Cut inclusive of the marker.
///   4. With no boundary, cut at the next word boundary after targetPos; it never expands back to 100%.
/// Common abbreviations (Mr., e.g., a.m. and so on) are masked, preserving length, so their periods are not boundaries.
class TtsPreviewTruncator {
  /// Abbreviations whose periods are masked so they are not read as sentence ends.
  static const List<String> abbreviations = [
    'Mr.', 'Mrs.', 'Ms.', 'Mx.', 'Dr.', 'Prof.', 'Sr.', 'Jr.', 'Rev.',
    'St.', 'Mt.', 'Ft.', 'Ave.', 'Blvd.', 'Rd.',
    'vs.', 'e.g.', 'i.e.', 'etc.', 'viz.', 'cf.', 'No.',
    'a.m.', 'p.m.', 'A.M.', 'P.M.',
  ];
  static const String _mask     = '\u0001';   // SOH -- never appears in real TTS text
  static const String _terminal = '.!?;';
  static const String _dashes   = '—–';   // em-dash, en-dash (NOT hyphen-minus)

  /// Messages shorter than this are always spoken in full, in characters.
  ///
  /// It matches the web client's `ttsPreviewMinChars`.
  static const int minChars = 80;

  /// Returns the preview slice for [fraction] in [0,1].
  ///
  /// A fraction of 1 or more returns the whole trimmed text, and empty input returns an empty string.
  static String truncateAtBoundary( String text, double fraction ) {
    if ( text.isEmpty ) return '';
    if ( fraction >= 1 ) return text.trim();

    var masked = text;
    for ( final abbr in abbreviations ) {
      masked = masked.split( abbr ).join( abbr.replaceAll( '.', _mask ) );
    }

    final targetPos = ( masked.length * fraction ).ceil();
    var cut = -1;
    for ( var i = targetPos; i < masked.length; i++ ) {
      final ch   = masked[ i ];
      final next = i + 1 < masked.length ? masked[ i + 1 ] : null;
      if ( ch == '\n' || _dashes.contains( ch ) ) { cut = i; break; }
      if ( _terminal.contains( ch ) && ( next == null || next.trim().isEmpty ) ) { cut = i; break; }
    }

    String slice;
    if ( cut != -1 ) {
      slice = masked.substring( 0, cut + 1 );
    } else {
      final ws = masked.indexOf( ' ', targetPos );
      slice = ws == -1 ? masked : masked.substring( 0, ws );
    }
    return slice.replaceAll( _mask, '.' ).trim();
  }

  /// True when [fraction] is zero or less: the slider at 0% means silence.
  ///
  /// It is not the first sentence, a short message spoken whole, a title or an answer the user asked for.
  /// Every speech path checks this before it enqueues, the background FCM path included.
  /// Design: src/docs/decisions/README.md (R-TTS-zero-silence)
  static bool silences( double fraction ) => fraction <= 0;

  /// The speech the orchestrator should send for [message] at [fraction].
  ///
  /// It is the full text when the slider is at 100%, the message is under [minChars], or the scan reaches the
  /// end anyway. Those are the web-parity opt-outs.
  static String previewFor( String message, double fraction ) {
    final full = message.trim();
    if ( fraction >= 1 || full.length < minChars ) return full;
    final preview = truncateAtBoundary( message, fraction );
    return preview.length >= full.length ? full : preview;
  }
}
