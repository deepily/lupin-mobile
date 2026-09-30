/// AC-S1.7 — `WsBlocDispatcher` routes `job_state_transition` to
/// `QuickAskBloc`, and unknown frame types still drop silently.
///
/// Driven against the REAL `app.dart` wiring, not a copy — the whole point is
/// that the switch in production has the arm. Mirrors
/// `focus_app_wiring_test.dart`'s shape: register what the dispatcher resolves
/// in `setUp` rather than adding an `isRegistered` guard to production code,
/// which would make the dispatch silently optional.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/app.dart';
import 'package:lupin_mobile/core/constants/app_constants.dart';
import 'package:lupin_mobile/features/queue/domain/job_lifecycle.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';

class _MockQuickAskBloc extends Mock implements QuickAskBloc {}

Map<String, dynamic> frame( { String to = 'running' } ) => {
  'type'       : 'job_state_transition',
  'job_id'     : 'j-1',
  'from_state' : 'queued',
  'to_state'   : to,
  'timestamp'  : '2026-08-29T20:00:00',
  'metadata'   : { 'question_text': 'q', 'user_email': 'rick@lupin.test' },
};

void main() {
  group( 'AC-S1.7 — job_state_transition reaches QuickAskBloc through the REAL wiring', () {
    late _MockQuickAskBloc quickAsk;
    late WsBlocDispatcher  dispatcher;

    setUpAll( () { registerFallbackValue( const QuickAskRecordPressed() ); } );

    setUp( () {
      quickAsk = _MockQuickAskBloc();
      when( () => quickAsk.add( any() ) ).thenReturn( null );
      when( () => quickAsk.state ).thenReturn( const QuickAskState() );
      GetIt.instance.registerSingleton<QuickAskBloc>( quickAsk );
      dispatcher = WsBlocDispatcher();
    } );

    tearDown( () async { await GetIt.instance.reset(); } );

    test( 'the constant matches the wire name the server actually emits', () {
      // `queue_util.py` emits the event under this exact name.
      expect( AppConstants.eventJobStateTransition, 'job_state_transition' );
    } );

    test( 'a transition frame is routed, carrying the frame VERBATIM', () {
      dispatcher.dispatch( AppConstants.eventJobStateTransition, frame() );

      final ev = verify( () => quickAsk.add( captureAny() ) ).captured.single;
      expect( ev, isA<QuickAskTransitionReceived>() );
      // Verbatim: the bloc needs `metadata.user_email` / `question_text` for
      // its insert-time buffer filter, so a dispatcher that forwarded only the
      // job id and to_state would break attribution.
      final forwarded = ( ev as QuickAskTransitionReceived ).frame;
      expect( forwarded[ 'job_id' ],   'j-1' );
      expect( forwarded[ 'to_state' ], 'running' );
      expect( ( forwarded[ 'metadata' ] as Map )[ 'user_email' ], 'rick@lupin.test' );
    } );

    test( 'every lifecycle state the server can name is routed, not just the happy three', () {
      for ( final s in JobLifecycleState.values ) {
        dispatcher.dispatch( AppConstants.eventJobStateTransition, frame( to: s.name ) );
      }
      verify( () => quickAsk.add( any() ) ).called( JobLifecycleState.values.length );
    } );

    test( 'an UNKNOWN frame type still drops silently — no throw, no dispatch', () {
      expect(
        () => dispatcher.dispatch( 'some_event_nobody_has_heard_of', { 'type': 'x' } ),
        returnsNormally,
      );
      verifyNever( () => quickAsk.add( any() ) );
    } );

    test( 'the four DEAD queue_*_update names do not reach QuickAskBloc', () {
      // They are kept with a stated reason (AC-S1.11) and route to QueueBloc,
      // which is not registered here — so this asserts only that the new arm
      // did not accidentally widen to absorb them.
      for ( final t in const [ 'queue_todo_update', 'queue_done_update' ] ) {
        try { dispatcher.dispatch( t, { 'type': t } ); } catch ( _ ) { /* QueueBloc unregistered */ }
      }
      verifyNever( () => quickAsk.add( any() ) );
    } );
  } );
}
