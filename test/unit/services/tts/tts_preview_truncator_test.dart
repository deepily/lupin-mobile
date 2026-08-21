import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/tts/tts_preview_truncator.dart';

void main() {
  const t = TtsPreviewTruncator.truncateAtBoundary;

  group( 'TtsPreviewTruncator.truncateAtBoundary (port of notifications.js self-test cases)', () {
    test( 'newline boundary for a punctuation-free technical list (the twist)', () {
      const input = 'alpha_one\nbeta_two\ngamma_three\ndelta_four';
      expect( t( input, 0.25 ), 'alpha_one\nbeta_two' );
    } );
    test( 'sentence terminal in plain prose; cut is inclusive of the marker', () {
      // 38 chars × 0.25 ⇒ targetPos 10 = the first '.', followed by a space ⇒ cut there.
      expect( t( 'Alpha beta. Gamma delta. Epsilon zeta.', 0.25 ), 'Alpha beta.' );
      expect( t( 'Alpha beta. Gamma delta. Epsilon zeta.', 0.5 ),  'Alpha beta. Gamma delta.' );
    } );
    test( 'decimal / version internal periods are NOT boundaries', () {
      expect( t( 'Pi is 3.14159 and the build is v0.1.7 here. Next sentence follows.', 0.1 ),
              'Pi is 3.14159 and the build is v0.1.7 here.' );
    } );
    test( 'em-dash IS a boundary; hyphen-minus is NOT', () {
      expect( t( 'bug-fix-queue end-to-end run — then the rest of it', 0.1 ), 'bug-fix-queue end-to-end run —' );
    } );
    test( 'abbreviation periods (Mr., e.g.) are not false boundaries and are restored', () {
      expect( t( 'Mr. Smith met Dr. Jones, e.g. at noon. Then they left.', 0.05 ),
              'Mr. Smith met Dr. Jones, e.g. at noon.' );
    } );
    test( 'no boundary after the mark => next word boundary (never silently 100%)', () {
      const input = 'one two three four five six seven eight nine ten';
      final got = t( input, 0.5 );
      expect( got.length, lessThan( input.length ) );
      expect( input.startsWith( got ), isTrue );
      expect( got.endsWith( ' ' ), isFalse );
    } );
    test( 'fraction >= 1 returns the whole (trimmed) text; empty => empty', () {
      expect( t( '  Alpha. Beta. Gamma.  ', 1 ), 'Alpha. Beta. Gamma.' );
      expect( t( '', 0.5 ), '' );
    } );
    test( 'fraction 0 => first boundary only', () {
      expect( t( 'First sentence. Second sentence. Third.', 0 ), 'First sentence.' );
    } );
  } );

  group( 'TtsPreviewTruncator.previewFor (orchestrator entry)', () {
    test( 'short messages (< minChars) are spoken in full regardless of fraction', () {
      expect( TtsPreviewTruncator.previewFor( 'Done: Bash ls', 0.1 ), 'Done: Bash ls' );
    } );
    test( 'long message at 30% => first sentences only; at 100% => full', () {
      final long = List.generate( 6, ( i ) => 'Sentence number ${i + 1} is here and long enough.' ).join( ' ' );
      final p = TtsPreviewTruncator.previewFor( long, 0.3 );
      expect( p.length, lessThan( long.length ) );
      expect( p, endsWith( '.' ) );
      expect( TtsPreviewTruncator.previewFor( long, 1.0 ), long );
    } );
    test( 'scan that reaches the end => full text (web opt-out)', () {
      final s = '${'x' * 100} tail';
      expect( TtsPreviewTruncator.previewFor( s, 0.99 ), s );
    } );
  } );
}
