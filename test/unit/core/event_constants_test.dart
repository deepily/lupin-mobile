/// AC-S1.11: the four proven-dead `eventQueue*Update` constants carry a
/// disposition. The clause permits either action and forbids only silence:
/// delete them, or keep them with the reason stated. This file asserts
/// whichever action the tree actually took.
///
/// When they are kept, the reason lives in a decision record
/// (`R-CORE-dead-queue-events` in `src/docs/decisions/README.md`), and that
/// record is what is asserted. The wording of source comments is not asserted
/// (Rick's ruling, row a1bbc3ef, same as R5b-AC-S1.10).
///
/// Presence is measured on comment-stripped source, so a name that appears
/// only in an explanation is not counted as a declaration.
///
/// The classifier is a pure function over source text, and both of its other
/// arms are exercised against synthetic sources below, because the deleted arm
/// cannot be reached by mutating this tree.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/constants/app_constants.dart';

const _deadNames = [
  'eventQueueTodoUpdate',
  'eventQueueRunningUpdate',
  'eventQueueDoneUpdate',
  'eventQueueDeadUpdate',
];

const _deadValues = {
  'eventQueueTodoUpdate'    : 'queue_todo_update',
  'eventQueueRunningUpdate' : 'queue_running_update',
  'eventQueueDoneUpdate'    : 'queue_done_update',
  'eventQueueDeadUpdate'    : 'queue_dead_update',
};

/// Strip `///`, `//` and `/* */` so a scan measures CODE, never its own explanation.
String codeOnly( String source ) {
  final noBlocks = source.replaceAll( RegExp( r'/\*.*?\*/', dotAll: true ), '' );
  return noBlocks
      .split( '\n' )
      .map( ( line ) {
        final idx = line.indexOf( '//' );
        return idx == -1 ? line : line.substring( 0, idx );
      } )
      .join( '\n' );
}

/// Which of AC-S1.11's two permitted dispositions this source took.
/// `partial` is neither — it is a half-finished edit.
String dispositionOf( String source ) {
  final code = codeOnly( source );
  final declared =
      _deadNames.where( ( n ) => code.contains( RegExp( '\\b$n\\s*=' ) ) ).length;
  if ( declared == 0 ) return 'deleted';
  if ( declared == _deadNames.length ) return 'kept';
  return 'partial';
}

String? _declLine( String source, String name ) {
  final hits = source
      .split( '\n' )
      .where( ( l ) => RegExp( '\\b$name\\s*=' ).hasMatch( l ) && !l.trimLeft().startsWith( '//' ) );
  return hits.isEmpty ? null : hits.first;
}

const _decisions = 'src/docs/decisions/README.md';
const _recordId  = 'R-CORE-dead-queue-events';

void main() {
  const path = 'lib/core/constants/app_constants.dart';

  group( 'AC-S1.11 — dead event-constant disposition', () {

    test( 'the LIVE event this plan added is declared (the trigger for the clause)', () {
      final code = codeOnly( File( path ).readAsStringSync() );
      expect( code, contains( 'eventJobStateTransition =' ),
          reason: 'the fifth name is what makes four unexplained dead ones ambiguous' );
      expect( AppConstants.eventJobStateTransition, 'job_state_transition' );
    } );

    test( 'the tree took one of the two permitted dispositions — never a partial edit', () {
      expect( dispositionOf( File( path ).readAsStringSync() ), isIn( [ 'kept', 'deleted' ] ),
          reason: 'a partial delete is neither disposition — it is a half-finished edit' );
    } );

    test( 'whichever disposition was taken, it is ASSERTED and not merely implied', () {
      final raw = File( path ).readAsStringSync();

      if ( dispositionOf( raw ) == 'deleted' ) {
        final strays = Directory( 'lib' )
            .listSync( recursive: true )
            .whereType<File>()
            .where( ( f ) => f.path.endsWith( '.dart' ) )
            .where( ( f ) => _deadNames.any( f.readAsStringSync().contains ) )
            .map( ( f ) => f.path )
            .toList();
        expect( strays, isEmpty,
            reason: 'deleted is valid only if nothing in lib/ still names them' );
        return;
      }

      // Kept: every one of the four is declared, and the decisions file carries
      // the record that says they are dead and why they stay. The record, not the
      // wording of a source comment, is what this asserts (ruling a1bbc3ef).
      for ( final name in _deadNames ) {
        expect( _declLine( raw, name ), isNotNull, reason: '$name must be declared' );
      }

      final record = File( _decisions )
          .readAsLinesSync()
          .where( ( l ) => l.contains( '· $_recordId ·' ) )
          .toList();
      expect( record, hasLength( 1 ),
          reason: 'exactly one decision record must carry the disposition' );
      for ( final value in _deadValues.values ) {
        expect( record.single, contains( value ),
            reason: 'the record must name $value, or a reader cannot tell which events are dead' );
      }
      expect( record.single, contains( 'never emitted' ),
          reason: 'the record must say why they are dead, not merely that they are' );
      expect( record.single, contains( 'kept' ),
          reason: 'the chosen action must be named in words' );
    } );

    test( 'the kept names still carry their original wire values (kept, not repurposed)', () {
      final raw = File( path ).readAsStringSync();
      _deadValues.forEach( ( name, value ) {
        final line = _declLine( raw, name );
        if ( line == null ) return; // deleted — covered above
        expect( line, contains( "'$value'" ),
            reason: '$name must keep its original wire value; KEPT-but-repurposed is a '
                    'third disposition the clause does not permit' );
      } );
    } );

    group( 'the classifier itself — both other arms exercised, not merely written', () {
      const kept = '''
class C {
  static const String eventQueueTodoUpdate = 'queue_todo_update';       // DEAD — never emitted
  static const String eventQueueRunningUpdate = 'queue_running_update'; // DEAD — never emitted
  static const String eventQueueDoneUpdate = 'queue_done_update';       // DEAD — never emitted
  static const String eventQueueDeadUpdate = 'queue_dead_update';       // DEAD — never emitted
}''';

      test( 'a source with none of the four classifies as DELETED', () {
        expect( dispositionOf( 'class C { static const String x = 1; }' ), 'deleted' );
      } );

      test( 'a source with all four classifies as KEPT', () {
        expect( dispositionOf( kept ), 'kept' );
      } );

      test( 'a source with three of four classifies as PARTIAL', () {
        final three = kept
            .split( '\n' )
            .where( ( l ) => !l.contains( 'eventQueueDeadUpdate' ) )
            .join( '\n' );
        expect( dispositionOf( three ), 'partial' );
      } );

      test( 'names appearing ONLY in prose do not count as declarations', () {
        const prose = '''
class C {
  // These were named eventQueueTodoUpdate = 'queue_todo_update' before deletion,
  // along with eventQueueRunningUpdate, eventQueueDoneUpdate, eventQueueDeadUpdate.
}''';
        expect( dispositionOf( prose ), 'deleted',
            reason: 'the comment stripper is what makes a prose mention not a declaration' );
      } );
    } );
  } );
}
