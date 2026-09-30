import 'package:flutter/services.dart';

/// Where one dictated chunk lands in an editor box — the one rule, shared.
///
/// Row 570c2fce (Rick, P0): a microphone on an editor box must record a NEW
/// chunk and APPEND it to what the box already holds. Replacing the text is
/// the defect, because the operator may have typed — or dictated — half the
/// message before reaching for the microphone again.
///
/// This was `new_ticket_sheet.dart`'s private `_splice`, lifted out verbatim in
/// behaviour so a second box cannot drift from the first. It is pure: no
/// controller, no widget, no recorder — the whole of the append rule in one
/// testable function.
///
/// Requires:
///   - [caret] is the offset the box held when recording began, or null when
///     the box was never focused
///
/// Ensures:
///   - a blank [heard] returns [value] UNCHANGED, text and selection alike
///   - the existing text is never replaced, only grown
///   - the returned selection is collapsed immediately after the inserted
///     words, so the next chunk continues where this one stopped
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
  // The right-hand pad is the one thing NOT carried over from `_splice`, which
  // padded only the left: dictating with the caret mid-sentence spliced
  // 'middle' into 'head |tail' as 'head middletail', welding two words
  // together. Appending at the end — the row's case — is unaffected either way.
  final tail  = right.isEmpty || right.startsWith( ' ' ) || right.startsWith( '\n' ) ? '' : ' ';

  return TextEditingValue(
    text      : '$left$pad$words$tail$right',
    selection : TextSelection.collapsed( offset: ( left + pad + words ).length ),
  );
}
