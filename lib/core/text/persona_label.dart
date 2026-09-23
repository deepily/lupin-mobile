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

/// Upper-case the first letter of every word, leaving the rest alone.
///
/// ⚠️ `toUpperCase()` ON THE WHOLE STRING IS NOT THIS. The web uppercases the first
/// LOWERCASE letter of each word (`/\b[a-z]/g`), so "McCoy" survives as "McCoy" rather
/// than becoming "MCCOY". Only the leading character of each word is touched.
///
/// ⚠️ SPLIT ON WHITESPACE RUNS AND REJOIN WITH ONE SPACE. A stored value carrying a tab
/// or a double space would otherwise yield an empty "word" and, worse, two spellings of
/// one persona that this function is supposed to fold together.
String _displayCase( String value ) {
  return value
      .split( RegExp( r"\s+" ) )
      .where( ( word ) => word.isNotEmpty )
      .map( ( word ) => word[ 0 ].toUpperCase() + word.substring( 1 ) )
      .join( " " );
}
