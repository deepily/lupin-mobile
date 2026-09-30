/// AC-S1.11 — the four proven-dead `eventQueue*Update` constants carry a
/// DISPOSITION. The clause permits either action and forbids only silence:
/// delete them, or keep them with the reason stated. This file asserts
/// whichever action the tree actually took, so the disposition cannot quietly
/// revert to silence when someone adds a sixth event name.
///
/// ⚠️ Presence is measured on COMMENT-STRIPPED source. The disposition block in
/// `app_constants.dart` names `eventJobStateTransition` in prose, so an
/// un-stripped scan would find a "declaration" that is only an explanation.
///
/// ⚠️ The classifier is a pure function over source text, and BOTH of its other
/// arms are exercised against synthetic sources below. A delete-disposition
/// would be a ~40-site edit across three WebSocket services, so the deleted
/// arm can never be reached by mutating this tree — an unexercised branch here
/// would be a branch nobody had ever seen run.
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

      // KEPT — every one of the four states WHY, on its own declaration line.
      for ( final name in _deadNames ) {
        final line = _declLine( raw, name );
        expect( line, isNotNull, reason: '$name must be declared' );
        expect( line, contains( 'DEAD' ),
            reason: 'FALSIFIER: strip the reason comment from $name and this goes red — '
                    'the app still builds and runs, which is why nothing else catches it' );
        expect( line, contains( 'never emitted' ),
            reason: '$name must say WHY it is dead, not merely that it is' );
      }

      expect( raw, contains( 'AC-S1.11' ),
          reason: 'the disposition must cite the clause it discharges' );
      expect( RegExp( r'\bKEPT\b|\bkept\b' ).hasMatch( raw ), isTrue,
          reason: 'the chosen action must be named in words, not inferred from the code' );
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
