/// AC-S1.9 — the transition frame is parsed by the EXISTING parser, against
/// frames CAPTURED VERBATIM from the live `:7999` server rather than
/// hand-written ones.
///
/// Why a live capture matters here: a hand-written fixture pins the parser to
/// the plan's *description* of the wire, and the description is exactly the
/// thing that can be wrong. These bytes are what the server actually sent on
/// 2026-08-29 (identity scrubbed, nothing else altered).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/features/queue/domain/job_lifecycle.dart';
import 'package:lupin_mobile/features/quick_ask/data/quick_ask_models.dart';

import '../../_helpers/fixture_loader.dart';

void main() {
  final capture = loadFixture( 'queue/job_state_transition_live_capture.json' );
  final frames  = ( capture[ 'frames' ] as List )
      .cast<Map<String, dynamic>>();

  group( 'AC-S1.9 — parsing the REAL wire', () {

    test( 'the live server sent exactly the three transitions the plan claims', () {
      expect( frames.map( ( f ) => f[ 'to_state' ] ).toList(),
          [ 'queued', 'running', 'completed' ] );
      expect( frames.first[ 'from_state' ], 'pending' );
    } );

    test( 'every frame parses, and its lane comes from to_state', () {
      for ( final f in frames ) {
        final e = QuickAskEntry.fromTransition( f );
        expect( e, isNotNull, reason: 'live frame ${f['to_state']} failed to parse' );
        expect( e!.state, JobLifecycleState.parse( f[ 'to_state' ] as String ) );
      }
    } );

    test( '🔴 the lane is NOT taken from metadata.status', () {
      // The completed frame carries BOTH `to_state: completed` and
      // `metadata.status: completed`, so it cannot discriminate on its own.
      // These two can: the queued and running frames carry NO metadata.status
      // at all, and `JobSummary.fromJson` silently defaults it to 'queued'.
      final running = frames.firstWhere( ( f ) => f[ 'to_state' ] == 'running' );
      expect( ( running[ 'metadata' ] as Map ).containsKey( 'status' ), isFalse,
          reason: 'the premise of this test — if the server starts sending it, revisit' );

      final e = QuickAskEntry.fromTransition( running )!;
      expect( e.state, JobLifecycleState.running,
          reason: 'reading metadata.status would silently yield `queued` here' );
      expect( e.lane, JobLane.run );
    } );

    test( 'the completed frame carries the ANSWER, and the parser finds it', () {
      final done = frames.firstWhere( ( f ) => f[ 'to_state' ] == 'completed' );
      final e    = QuickAskEntry.fromTransition( done )!;
      expect( e.isTerminal, isTrue );
      expect( e.lane,       JobLane.done );
      expect( e.hasAnswer,  isTrue );
      expect( e.answer,     isNotEmpty );
    } );

    test( 'the two insert-time buffer filter keys are on EVERY frame', () {
      // The whole pre-attribution filter rests on this. The plan measured it;
      // this is the live confirmation, so a server change breaks a test rather
      // than silently degrading correlation to a text-only match.
      for ( final f in frames ) {
        final md = f[ 'metadata' ] as Map;
        expect( md[ 'user_email' ],    isNotNull, reason: '${f['to_state']} lacks user_email' );
        expect( md[ 'question_text' ], isNotNull, reason: '${f['to_state']} lacks question_text' );
      }
    } );

    test( 'session_id is present on the FIRST frame only — the plan\'s measured table', () {
      // pending→queued carries it; queued→running and running→completed do
      // not. That asymmetry is why the filter needs `question_text` OR
      // `session_id`, not `session_id` alone.
      final md0 = frames[ 0 ][ 'metadata' ] as Map;
      expect( md0.containsKey( 'session_id' ), isTrue );
      for ( final f in frames.skip( 1 ) ) {
        expect( ( f[ 'metadata' ] as Map ).containsKey( 'session_id' ), isFalse,
            reason: '${f['to_state']} unexpectedly carries session_id — the filter can be simplified' );
      }
    } );

    test( 'the ask response that produced these frames was `waiting` + a job id', () {
      // AC-S1.5's branch, confirmed live: this is what the server really
      // returns for a conversational question, and it is the shape that used
      // to summarise as "Done".
      final ask = capture[ '_ask_response' ] as Map<String, dynamic>;
      expect( ask[ 'status' ], 'waiting' );
      expect( ask[ 'job_id' ], isNotNull );
    } );
  } );
}
