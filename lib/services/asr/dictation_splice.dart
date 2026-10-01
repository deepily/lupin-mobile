import 'package:flutter/services.dart';

/// Where one dictated chunk lands in an editor box; the one rule, shared.
///
/// A microphone on an editor box appends a new chunk. Replacing the text is the defect, because the
/// operator may have typed or dictated half the message already. The function is pure, so boxes cannot drift.
/// Design: src/docs/decisions/README.md (R-ASR-dictation-append)
///
/// Requires:
///   - [caret] is the offset the box held when recording began, or null when the box was never focused
///
/// Ensures:
///   - a blank [heard] returns [value] unchanged, text and selection alike
///   - the existing text is never replaced, only grown
///   - the returned selection is collapsed immediately after the inserted words, so the next chunk
///     continues where this one stopped
///   - a [caret] outside the text is clamped to the end rather than throwing
TextEditingValue spliceDictation( {
  required TextEditingValue value,
  required String heard,
  int? caret,
} ) {
  final words = heard.trim();
  if ( words.isEmpty ) return value;

  final text  = value.text;
  final at    = ( caret == null || caret < 0 || caret > text.length ) ? text.length : caret;
  final left  = text.substring( 0, at );
  final right = text.substring( at );
  final pad   = left.isEmpty || left.endsWith( ' ' ) || left.endsWith( '\n' ) ? '' : ' ';
  // The right-hand pad is new. The earlier splice padded only the left, so dictating with the caret
  // mid-sentence turned 'head |tail' into 'head middletail', welding two words together.
  // Appending at the end is unaffected either way.
  final tail  = right.isEmpty || right.startsWith( ' ' ) || right.startsWith( '\n' ) ? '' : ' ';

  return TextEditingValue(
    text      : '$left$pad$words$tail$right',
    selection : TextSelection.collapsed( offset: ( left + pad + words ).length ),
  );
}
