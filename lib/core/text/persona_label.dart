/// ONE rule for turning a stored actor/filer string into the name a reader sees.
///
/// 🔴 WHY THIS IS A SHARED FUNCTION AND NOT A THIRD COPY OF THE REGEX.
/// The store holds `<persona> <8-hex session>`, and a persona CAN BE TWO WORDS. The
/// obvious implementation — `value.split( " " ).first` — renders "mr radio 8353ea70" as
/// "mr". Measured by María 2026-09-02 on the web side: WRONG ON 6 OF 13 LIVE ROWS, and
/// those six are exactly the ones Rick asked about, so the naive form fails hardest
/// precisely where the feature is for.
///
/// ⚠️ AND IT HAS ALREADY BEEN RE-DERIVED ONCE, IN THE OTHER CLIENT, IN A NEIGHBOURING
/// FILE. The web's `holdingAreaModel.taskFilerLabel` got it right and carried a docstring
/// saying so; `finishedTasksModel.actorPersona`, written months later a directory away,
/// used the naive split and shipped it to the WHO column (row 4a06ded1). A warning in a
/// docstring is not a control — the next author has no reason to read a file they are not
/// editing. The web's answer was `shared/personaLabel.ts`; this is that answer here.
///
/// 🔨 MARÍA'S RULING (2026-09-07): *"Export taskFilerLabel's regex helper or extract a
/// shared one to avoid three implementations of the same rule."* Once a rule has been
/// written twice and got it wrong once, the SHAPE is the defect and the SITE is not.
///
/// ⚠️ SCOPE — THIS CLIENT ONLY. Rick's no-shared-code ruling (`87812328`) means the
/// mobile and web clients reproduce behaviour independently. This is one rule for the
/// Flutter client, not a module either of them imports from the other.
library;

/// The stored suffix: whitespace then exactly 8 hex characters, at the very end.
///
/// 🔴 THE `\s+` IS LOAD-BEARING AND A BARE ID IS DELIBERATELY NOT A MATCH. `"0e61abe3"`
/// with no name in front of it renders WHOLE, not as the fallback — visibly odd, by
/// design, and pinned by the web client's JS-parity corpus, entry
/// `[ "0e61abe3", "0e61abe3" ]`.
///
/// ⚠️ DO NOT "FIX" THIS TO `\s*` OR `(?:^|\s+)`. It looks like the obvious repair; it was
/// tried on the web side on 2026-09-08 and REVERTED, because it diverges the two clients
/// and that divergence is the one thing the parity corpus exists to prevent.
final RegExp _trailingSessionId = RegExp( r"\s+[0-9a-f]{8}$", caseSensitive: false );

/// The display name inside a stored `<persona> <8-hex session>` value.
///
/// Requires:
///     - value is the raw stored string, or null
///     - fallback is what an absent or blank value renders as
///
/// Ensures:
///     - "mr radio 8353ea70" → "mr radio"   (a TWO-WORD persona survives)
///     - "krishna 420f5ec9"  → "krishna"
///     - no trailing session id → the WHOLE string, untouched. A truncated name is a
///       WRONG name wearing a right one's clothes; an unexpected format shown in full is
///       visibly odd and sends the reader to the row. A BARE session id is this case,
///       not an exception to it
///     - null or blank → fallback
///     - CASE IS UNTOUCHED. The store holds "Krishna" and "mr radio" both, and a caller
///       that wants display casing asks for it — see [personaDisplayLabel]
///     - pure: never throws
String personaLabel( String? value, String fallback ) {
  if ( value == null ) return fallback;
  final raw = value.trim();
  if ( raw.isEmpty ) return fallback;

  final stripped = raw.replaceFirst( _trailingSessionId, "" ).trim();

  // 🔴 THIS ARM IS UNREACHABLE BY CONSTRUCTION AND IT IS KEPT ON PURPOSE. `raw` is
  // trimmed, so it never starts with whitespace; `_trailingSessionId` requires whitespace
  // before the id, so a match can never start at index 0; so the unmatched prefix always
  // survives and `stripped` is never empty. It guards the REGEX, not the input — widen
  // the pattern to match at index 0 and this becomes reachable the same day, and without
  // this arm that renders an EMPTY name instead of the fallback.
  return stripped.isEmpty ? fallback : stripped;
}

/// The persona, display-cased — the spelling the multiplexer's holding-area card shows.
///
/// 🔴 THE CASING IS A SEPARATE FUNCTION BECAUSE ONLY SOME SURFACES WANT IT, AND FOLDING
/// IT INTO [personaLabel] WOULD SILENTLY RE-CASE THE ONES THAT DO NOT. The web keeps the
/// same split for the same reason: its holding-area card title-cases its filer labels
/// (`holdingAreaModel.taskFilerLabel`), while the Finished-Tasks WHO column reads the
/// store's own spelling.
///
/// ⚠️ THE CASING IS ALSO WHY THIS IS SAFE AS A GROUPING KEY. The store holds one persona
/// under more than one spelling — "Krishna" and "maria" sit side by side on the live
/// board — so grouping on the raw persona would split one person in two. Title-casing
/// first folds those spellings together, which is what Rick asked for: one group per
/// persona.
///
/// Requires:
///     - value is the raw stored string, or null
///
/// Ensures:
///     - "mr radio 0e61abe3" → "Mr Radio"   (EVERY word, not just the first)
///     - "Krishna 420f5ec9"  → "Krishna"
///     - "maria be26cc2d"    → "Maria"
///     - null or blank → fallback, UNCASED — the caller's own word for "nobody", which
///       is not a name and must not be mangled into one
///     - pure: never throws
String personaDisplayLabel( String? value, String fallback ) {
  final stripped = personaLabel( value, fallback );
  if ( stripped == fallback ) return fallback;
  return _displayCase( stripped );
}

/// The web's casing rule, character for character: upper-case every lower-case letter
/// that sits at a word boundary.
///
/// 🔴 A WORD BOUNDARY IS NOT A SPACE, AND THE FIRST VERSION OF THIS FUNCTION GOT THAT
/// WRONG. It split on whitespace and cased each piece, which agrees with the web on
/// "mr radio" and diverges the moment a name carries punctuation: `\b` also fires after
/// a hyphen and an apostrophe, so the web renders "mary-jane" as "Mary-Jane" and
/// "o'brien" as "O'Brien" where the whitespace split gives "Mary-jane" and "O'brien".
/// Caught by Tiffany in review, 2026-09-23, before it shipped.
///
/// ⚠️ THAT DIVERGENCE WOULD HAVE BEEN INVISIBLE ON TODAY'S BOARD. Every one of the six
/// live personas is plain letters and at most one space, so no fixture and no live
/// screen could show it — the first hyphenated persona anyone registers is what would
/// have surfaced it, in a pane whose grouping key this is. A parity rule is worth
/// reproducing exactly or not claiming.
///
/// ⚠️ `toUpperCase()` ON THE WHOLE STRING IS ALSO NOT THIS. Only lower-case letters AT a
/// boundary are touched, so "McCoy" survives as "McCoy" rather than becoming "MCCOY".
///
/// Ensures:
///     - "mr radio" → "Mr Radio"   ·   "mary-jane" → "Mary-Jane"
///     - "o'brien"  → "O'Brien"    ·   "McCoy"     → "McCoy"
///     - internal whitespace runs collapse to one space, so a stored value carrying a
///       tab or a double space cannot become a second spelling of one persona
String _displayCase( String value ) {
  // Collapse whitespace runs FIRST — that part is ours, not the web's, and it exists so
  // "mr  radio" and "mr radio" cannot become two groups.
  final collapsed = value.split( RegExp( r"\s+" ) ).where( ( w ) => w.isNotEmpty ).join( " " );

  // Then the web's rule verbatim: `/\b[a-z]/g`. Dart's RegExp supports `\b`, so this is
  // the same pattern rather than a reimplementation of it.
  return collapsed.replaceAllMapped(
    RegExp( r"\b[a-z]" ),
    ( m ) => m[ 0 ]!.toUpperCase(),
  );
}
