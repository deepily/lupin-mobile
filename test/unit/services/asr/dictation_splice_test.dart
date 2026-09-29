import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/services/asr/dictation_splice.dart';

/// Row 570c2fce (Rick, P0): a second recording must APPEND to what the editor
/// box already holds, never replace it.
///
/// The rules asserted here are the ones `new_ticket_sheet.dart` already shipped
/// as its private `_splice` — this is that logic extracted so a second box
/// cannot drift from it, so the New Ticket behaviour is pinned here too.
void main() {
  group( 'spliceDictation', () {
    test( 'appends to existing text at the end, with one space between', () {
      final next = spliceDictation(
        value : const TextEditingValue( text: 'first chunk' ),
        heard : 'second chunk',
        caret : 11,
      );
      expect( next.text, 'first chunk second chunk' );
    } );

    test( 'into an EMPTY box the transcript stands alone — no leading space', () {
      final next = spliceDictation(
        value : const TextEditingValue( text: '' ),
        heard : 'the only words',
        caret : 0,
      );
      expect( next.text, 'the only words' );
      expect( next.selection, const TextSelection.collapsed( offset: 14 ) );
    } );

    test( 'the caret lands after the words just spliced in, not at the end of the box', () {
      final next = spliceDictation(
        value : const TextEditingValue( text: 'head tail' ),
        heard : 'middle',
        caret : 5,                                   // between 'head ' and 'tail'
      );
      expect( next.text, 'head middle tail' );
      expect( next.selection, const TextSelection.collapsed( offset: 11 ),
          reason: 'after "head middle", ready to keep dictating where the operator was' );
      expect( next.selection.isCollapsed, isTrue );
    } );

    test( 'a null caret (never focused) appends at the very end', () {
      final next = spliceDictation(
        value : const TextEditingValue( text: 'typed by hand' ),
        heard : 'and dictated',
        caret : null,
      );
      expect( next.text, 'typed by hand and dictated' );
      expect( next.selection, const TextSelection.collapsed( offset: 26 ) );
    } );

    test( 'a caret past the end of the text is clamped to the end rather than throwing', () {
      final next = spliceDictation(
        value : const TextEditingValue( text: 'short' ),
        heard : 'added',
        caret : 999,                                 // box was edited since recording began
      );
      expect( next.text, 'short added' );
      expect( next.selection, const TextSelection.collapsed( offset: 11 ) );
    } );

    test( 'no double space: a box already ending in a space or newline gets no pad', () {
      expect(
        spliceDictation( value: const TextEditingValue( text: 'trailing ' ), heard: 'words', caret: 9 ).text,
        'trailing words',
      );
      expect(
        spliceDictation( value: const TextEditingValue( text: 'line\n' ), heard: 'words', caret: 5 ).text,
        'line\nwords',
      );
    } );

    test( 'NEGATIVE CONTROL — nothing heard changes nothing at all, text and selection alike', () {
      const before = TextEditingValue(
        text      : 'what was already there',
        selection : TextSelection.collapsed( offset: 4 ),
      );
      expect( spliceDictation( value: before, heard: '',    caret: 4 ), before );
      expect( spliceDictation( value: before, heard: '   ', caret: 4 ), before,
          reason: 'a blank transcript is not speech; the box must be left untouched' );
    } );

    test( 'the transcript is trimmed of its own surrounding whitespace before splicing', () {
      final next = spliceDictation(
        value : const TextEditingValue( text: 'a' ),
        heard : '  b  ',
        caret : 1,
      );
      expect( next.text, 'a b' );
    } );
  } );
}
