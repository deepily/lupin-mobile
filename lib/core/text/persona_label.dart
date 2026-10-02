/// One rule for turning a stored actor or filer string into the name a reader sees.
///
/// The store holds `<persona> <8-hex session>`, and a persona can be two words.
/// The obvious `value.split( " " ).first` renders "mr radio" plus a session id as "mr".
/// On the web side that was wrong on 6 of 13 live rows, which are the rows the feature is for.
/// The web client got the rule right in one file and re-derived it wrongly in a neighboring one.
/// A docstring warning was not a control, so the web answer was a shared `shared/personaLabel.ts`, and this file is that answer here.
/// Design: src/docs/decisions/README.md (R-TEXT-shared-label-rule)
///
/// Scope is this client only. The mobile and web clients reproduce behavior independently and import nothing from each other.
/// Design: src/docs/decisions/README.md (R-CORE-no-shared-code)
library;

/// The stored session suffix: whitespace, then exactly 8 hex characters, at the very end.
///
/// The `\s+` matters. A bare 8-hex id with no name before it is not a match, so it renders whole and not as the fallback.
/// That looks odd, and the web client's JS-parity corpus pins it.
/// Do not change the pattern to `\s*` or `(?:^|\s+)`: it looks like the obvious repair, but the two clients then diverge.
/// The parity corpus exists to prevent exactly that divergence.
final RegExp _trailingSessionId = RegExp( r"\s+[0-9a-f]{8}$", caseSensitive: false );

/// The display name inside a stored `<persona> <8-hex session>` value.
///
/// Requires:
///   - value is the raw stored string, or null
///   - fallback is what an absent or blank value renders as
///
/// Ensures:
///   - "mr radio" followed by a session id gives "mr radio", so a two-word persona survives
///   - with no trailing session id, the whole string is returned untouched; a truncated name would be a wrong name
///     that looks right, and an unexpected format shown in full sends the reader to the row; a bare session id is this case
///   - null or blank gives fallback
///   - case is untouched, because the store holds both "Krishna" and "mr radio"; [personaDisplayLabel] cases for display
///   - pure; never throws
String personaLabel( String? value, String fallback ) {
  if ( value == null ) return fallback;
  final raw = value.trim();
  if ( raw.isEmpty ) return fallback;

  final stripped = raw.replaceFirst( _trailingSessionId, "" ).trim();

  // This arm is unreachable today, and it stays. `raw` is trimmed, so it never starts with whitespace, and
  // `_trailingSessionId` needs whitespace before the id, so a match never starts at index 0 and `stripped` is never empty.
  // The arm guards the regex, not the input: if the pattern is ever widened to match at index 0, this arm is what keeps
  // an empty name from rendering instead of the fallback.
  return stripped.isEmpty ? fallback : stripped;
}

/// The persona, display-cased: the spelling the multiplexer's holding-area card shows.
///
/// Casing is a separate function, because folding it into [personaLabel] would re-case the surfaces that do not want it.
/// It also makes this safe as a grouping key. The store holds one persona under more than one spelling,
/// "Krishna" and "maria" side by side. Title-casing folds them into one group per persona.
///
/// Requires:
///   - value is the raw stored string, or null
///
/// Ensures:
///   - "mr radio" plus a session id gives "Mr Radio" (every word, not just the first)
///   - "krishna" plus a session id gives "Krishna" and "maria" plus a session id gives "Maria"
///   - null or blank gives fallback, uncased: it is the caller's own word for nobody and must not be turned into a name
///   - pure; never throws
String personaDisplayLabel( String? value, String fallback ) {
  final stripped = personaLabel( value, fallback );
  if ( stripped == fallback ) return fallback;
  return _displayCase( stripped );
}

/// The web's casing rule: upper-case every lower-case letter that sits at a word boundary.
///
/// Only lower-case letters at a boundary change, so "McCoy" stays "McCoy" and does not become "MCCOY".
///
/// Ensures:
///   - "mr radio" gives "Mr Radio" and "mary-jane" gives "Mary-Jane"
///   - "o'brien" gives "O'Brien" and "McCoy" gives "McCoy"
///   - internal whitespace runs collapse to one space, so a tab or double space cannot become a second spelling of one persona
String _displayCase( String value ) {
  // A word boundary is not a space. `\b` also fires after a hyphen and an apostrophe, so the web renders "mary-jane" as "Mary-Jane"
  // and "o'brien" as "O'Brien", where a whitespace split gives "Mary-jane" and "O'brien".
  // Today's board has only plain-letter personas, so no fixture would show that divergence, and the first hyphenated persona would.
  // A parity rule is worth reproducing exactly or not claiming.
  //
  // Collapse whitespace runs first. That part is ours, not the web's, and it keeps "mr  radio" and "mr radio" from becoming two groups.
  final collapsed = value.split( RegExp( r"\s+" ) ).where( ( w ) => w.isNotEmpty ).join( " " );

  // Then the web's rule verbatim: `/\b[a-z]/g`. Dart's RegExp supports `\b`, so this is the same pattern, not a reimplementation.
  return collapsed.replaceAllMapped(
    RegExp( r"\b[a-z]" ),
    ( m ) => m[ 0 ]!.toUpperCase(),
  );
}
