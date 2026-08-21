/// Port of the web client's TTS preview limiter
/// (`notifications.js::_truncateAtBoundary`, 2026-05-22 boundary-scan
/// rewrite; design `lupin/src/rnd/v0.1.7/2026.05.22-tts-limiter-boundary-scan.md`).
///
/// Truncate [text] to roughly [fraction] of its length, extending FORWARD
/// from the fraction mark to the next natural boundary:
///   1. targetPos = ceil( length x fraction )
///   2. scan forward for the first boundary -- '\n', em/en-dash (never
///      hyphen-minus), or `. ! ? ;` followed by whitespace/end (so "3.14",
///      "v0.1.7", "file.py" are not boundaries)
///   3. cut inclusive of the marker
///   4. no boundary => next word boundary after targetPos (never silently
///      expands back to 100%)
/// Common abbreviations (Mr., e.g., a.m., ...) are masked length-preservingly
/// so their periods are not false boundaries.
class TtsPreviewTruncator {
  static const List<String> abbreviations = [
    'Mr.', 'Mrs.', 'Ms.', 'Mx.', 'Dr.', 'Prof.', 'Sr.', 'Jr.', 'Rev.',
    'St.', 'Mt.', 'Ft.', 'Ave.', 'Blvd.', 'Rd.',
    'vs.', 'e.g.', 'i.e.', 'etc.', 'viz.', 'cf.', 'No.',
    'a.m.', 'p.m.', 'A.M.', 'P.M.',
  ];
  static const String _mask     = '\u0001';   // SOH -- never appears in real TTS text
  static const String _terminal = '.!?;';
  static const String _dashes   = '—–';   // em-dash, en-dash (NOT hyphen-minus)

  /// Messages shorter than this are always spoken in full (web parity:
  /// `ttsPreviewMinChars`).
  static const int minChars = 80;

  /// Returns the preview slice for [fraction] in [0,1]. `fraction >= 1` =>
  /// the whole (trimmed) text. Empty input => ''.
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

  /// The speech the orchestrator should send for [message] at [fraction]:
  /// full text when the slider is at 100%, the message is under [minChars],
  /// or the scan reaches the end anyway (web parity opt-outs).
  static String previewFor( String message, double fraction ) {
    final full = message.trim();
    if ( fraction >= 1 || full.length < minChars ) return full;
    final preview = truncateAtBoundary( message, fraction );
    return preview.length >= full.length ? full : preview;
  }
}
