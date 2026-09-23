import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/text/persona_label.dart';
import 'package:lupin_mobile/features/finished_tasks/data/finished_tasks_models.dart';

/// The ONE rule for turning a stored `<persona> <8-hex session>` value into a name.
///
/// 🔴 THIS FILE EXISTS BECAUSE THE RULE HAS BEEN RE-DERIVED WRONGLY BEFORE. The web
/// client wrote it correctly in `holdingAreaModel.taskFilerLabel`, then wrote it again
/// months later in a neighbouring file with `split(" ")[0]` and shipped "mr" to the WHO
/// column (row 4a06ded1). The mobile client was one caller away from the same story:
/// `actorPersona` had it, and the Holding Area's persona grouping needed it a third
/// time. María's 2026-09-07 ruling — extract, do not re-derive — is what this pins.
///
/// ⚠️ THE JS-PARITY CORPUS IS CARRIED, NOT PARAPHRASED. Rick's no-shared-code ruling
/// (`87812328`) means the two clients reproduce behaviour independently, so the only
/// thing keeping them from drifting is that both are pinned to the same table of
/// input → output pairs.

/// The web client's corpus, verbatim: `[ input, expected ]` with the case untouched.
const _jsParity = <List<String>>[
  [ 'mr radio 0e61abe3', 'mr radio' ],
  [ 'Krishna 420f5ec9',  'Krishna'  ],
  [ 'maria be26cc2d',    'maria'    ],
  // 🔴 A BARE SESSION ID IS SHOWN WHOLE, NOT REPLACED BY THE FALLBACK. The `\s+` in the
  // pattern is load-bearing: widening it to `\s*` makes this row read "—" and diverges
  // the two clients. Tried on the web side 2026-09-08 and reverted.
  [ '0e61abe3',          '0e61abe3' ],
  // No trailing session id at all → the whole string, untouched.
  [ 'mr radio',          'mr radio' ],
  // Nine hex characters is not a session id; eight is. An over-long suffix stays.
  [ 'sam 418857fbc',     'sam 418857fbc' ],
  // Seven is not one either.
  [ 'sam 418857f',       'sam 418857f' ],
  // Non-hex in the suffix: not a session id.
  [ 'sam 418857fg',      'sam 418857fg' ],
];

void main() {
  group( "personaLabel — the strip", () {
    for ( final pair in _jsParity ) {
      test( "JS PARITY: '${pair[ 0 ]}' → '${pair[ 1 ]}'", () {
        expect( personaLabel( pair[ 0 ], '—' ), pair[ 1 ] );
      } );
    }

    test( "🔴 a TWO-WORD persona survives — the naive split is what this forbids", () {
      // Measured by María 2026-09-02: `split(" ").first` was wrong on 6 of 13 live rows,
      // and those six are exactly the ones the feature is for.
      expect( personaLabel( 'mr radio 8353ea70', '—' ), 'mr radio' );
      expect( personaLabel( 'mr radio 8353ea70', '—' ), isNot( 'mr' ) );
    } );

    test( "the id match is END-anchored — a hex run mid-string is left alone", () {
      expect( personaLabel( 'deadbeef the second', '—' ), 'deadbeef the second' );
    } );

    test( "case does not matter to the MATCH, only to the value", () {
      expect( personaLabel( 'sam 418857FB', '—' ), 'sam' );
    } );

    test( "null, empty and whitespace take the caller's fallback", () {
      expect( personaLabel( null, '—' ), '—' );
      expect( personaLabel( '', '—' ), '—' );
      expect( personaLabel( '    ', '—' ), '—' );
    } );

    test( "⚠️ the FALLBACK is the caller's word, not this file's", () {
      // The Finished-Tasks WHO column says "—"; the Holding Area says "Unattributed".
      // Baking either one in would have made the other caller wrong.
      expect( personaLabel( null, 'Unattributed' ), 'Unattributed' );
      expect( personaLabel( null, '—' ), '—' );
    } );

    test( "surrounding whitespace is trimmed off the value", () {
      expect( personaLabel( '  sam 418857fb  ', '—' ), 'sam' );
    } );

    test( "🔴 the CASE is untouched — display casing is the other function's job", () {
      expect( personaLabel( 'maria be26cc2d', '—' ), 'maria' );
      expect( personaLabel( 'Krishna 420f5ec9', '—' ), 'Krishna' );
    } );
  } );

  group( "personaDisplayLabel — the casing", () {
    test( "EVERY word is cased, not just the first", () {
      // `split(" ").first` + capitalise would give "Mr radio"; the web uppercases the
      // leading letter of each word (`/\b[a-z]/g`).
      expect( personaDisplayLabel( 'mr radio 8fa24215', 'Unattributed' ), 'Mr Radio' );
    } );

    test( "an already-cased name is left as it is", () {
      expect( personaDisplayLabel( 'Krishna 12c43f44', 'Unattributed' ), 'Krishna' );
      expect( personaDisplayLabel( 'Rachel 5c88e8d6', 'Unattributed' ), 'Rachel' );
    } );

    test( "🔴 a WORD BOUNDARY is not a space — hyphens and apostrophes case too", () {
      // 🔴 THE DIVERGENCE THIS PINS, AND IT NEARLY SHIPPED. The web's rule is
      // `/\b[a-z]/g`; the first version here split on whitespace and cased each piece.
      // The two agree on every persona on today's board — all six are plain letters —
      // and disagree the moment a name carries punctuation. Caught by Tiffany in review
      // 2026-09-23; no fixture could have caught it.
      expect( personaDisplayLabel( 'mary-jane 5c88e8d6', 'Unattributed' ), 'Mary-Jane' );
      expect( personaDisplayLabel( "o'brien 5c88e8d6", 'Unattributed' ), "O'Brien" );
      expect( personaDisplayLabel( 'jean-luc picard', 'Unattributed' ), 'Jean-Luc Picard' );
    } );

    test( "⚠️ a DIGIT is a word character, so it is NOT a boundary", () {
      // 🔴 THIS TEST WAS WRITTEN ASSERTING THE OPPOSITE AND THE CODE WAS RIGHT. `\b`
      // sits between a word character and a non-word one, and a digit is a WORD
      // character in both Dart and JavaScript — so there is no boundary inside
      // "agent7smith" and the "s" stays lower-case. Kept, with the expectation
      // corrected, because "surely a digit breaks a word" is the intuition that wrote it
      // the first time and the next reader will have it too.
      //
      // ⚠️ IT ALSO PINS THE PARITY IN THE DIRECTION THAT MATTERS: Dart's `\b` and
      // JavaScript's agree here, which is what lets this file claim to reproduce
      // `/\b[a-z]/g` rather than approximate it.
      expect( personaDisplayLabel( 'agent7smith', 'Unattributed' ), 'Agent7smith' );
    } );

    test( "🔴 inner capitals SURVIVE — this is not toUpperCase()", () {
      expect( personaDisplayLabel( 'mcCoy 5c88e8d6', 'Unattributed' ), 'McCoy' );
      expect( personaDisplayLabel( 'McCoy 5c88e8d6', 'Unattributed' ), 'McCoy' );
    } );

    test( "two casings of one persona collapse to ONE spelling", () {
      // This is what makes the display label safe as a grouping key: the live board
      // holds "Krishna" and "maria" side by side, one store, two conventions.
      expect(
        personaDisplayLabel( 'krishna 12c43f44', 'Unattributed' ),
        personaDisplayLabel( 'Krishna 99999999', 'Unattributed' ),
      );
    } );

    test( "⚠️ the fallback is NOT cased — it is not a name", () {
      // Casing "Unattributed" would be harmless; casing an em dash or a lower-case
      // fallback would turn the pane's word for "nobody" into something that reads like
      // a persona.
      expect( personaDisplayLabel( null, 'unattributed' ), 'unattributed' );
      expect( personaDisplayLabel( '   ', '—' ), '—' );
    } );

    test( "a doubled space does not produce two spellings of one persona", () {
      expect( personaDisplayLabel( 'mr  radio 8fa24215', 'Unattributed' ), 'Mr Radio' );
      expect(
        personaDisplayLabel( 'mr  radio 8fa24215', 'Unattributed' ),
        personaDisplayLabel( 'mr radio 8fa24215', 'Unattributed' ),
      );
    } );

    test( "a bare session id is shown whole here too, display-cased", () {
      expect( personaDisplayLabel( '0e61abe3', 'Unattributed' ), '0e61abe3' );
    } );
  } );

  group( "🔴 the Finished-Tasks WHO column still behaves exactly as it did", () {
    // The extraction moved the rule out of `finished_tasks_models.dart`. These are the
    // contract lines from that file's own docstring, re-asserted from outside it, so the
    // delegation cannot quietly change the column that was already shipping.
    test( "'mr radio 8353ea70' → 'mr radio'", () {
      expect( actorPersona( 'mr radio 8353ea70' ), 'mr radio' );
    } );

    test( "'krishna 420f5ec9' → 'krishna' — the store's casing, NOT display casing", () {
      expect( actorPersona( 'krishna 420f5ec9' ), 'krishna' );
    } );

    test( "no trailing session id → the whole string, untouched", () {
      expect( actorPersona( 'a plain string' ), 'a plain string' );
    } );

    test( "null or empty → the em dash", () {
      expect( actorPersona( null ), kFinishedUnmeasured );
      expect( actorPersona( '' ), kFinishedUnmeasured );
      expect( actorPersona( '   ' ), kFinishedUnmeasured );
    } );
  } );
}
