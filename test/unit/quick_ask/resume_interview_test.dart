/// AC-S4.12 (UI/bloc half) and AC-S4.2 — the re-entrant Door-A interview, and
/// the terminal `needs_input` card that must offer nothing to answer.
///
/// This IS Rick's ruling 5: "which city?" answered in place is a second parked
/// turn on the SAME `pending_id`. `flow.py` comments the loop verbatim —
/// *"Interview continues — re-ask the next arg on the SAME pending_id"*.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/domain/job_lifecycle.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';

import '_quick_ask_harness.dart';

AskResponse parked( {
  required String pendingId,
  required String question,
  List<String>    missing = const [],
} ) => AskResponse(
  path        : 'needs_input',
  status      : 'parked',
  routeReason : 'args_missing',
  traceId     : 'tr-p',
  answer      : question,
  pendingId   : pendingId,
  argsMissing : missing,
);

AskResponse doneWith( String answer ) => AskResponse(
  path        : 'agent',
  status      : 'done',
  routeReason : 'router:weather',
  traceId     : 'tr-d',
  answer      : answer,
  jobId       : 'j-final',
);

const needsInput = AskResponse(
  path        : 'needs_input',
  status      : 'needs_input',
  routeReason : 'args_missing',
  traceId     : 'tr-n',
  argsMissing : [ 'city' ],
);

void main() {
  setUpAll( () {
    registerFallbackValue( const AskRequest( question: 'x' ) );
    registerFallbackValue( const ResumeRequest( pendingId: 'p', answer: 'a' ) );
  } );

  Future<Harness> askReturns( AskResponse first ) async {
    final h = Harness();
    h.stubEmptyQueues();
    when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'what is the weather' );
    when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) async => first );
    await settle();
    h.bloc.add( const QuickAskRecordPressed() );
    await settle();
    h.bloc.add( const QuickAskRecordReleased() );
    await settle();
    return h;
  }

  group( 'AC-S4.12 — N arguments, N round trips, ONE pending_id', () {

    test( 'a parked ask opens an interview rather than an answer card', () async {
      final h = await askReturns( parked(
        pendingId: 'pend-1', question: 'Which city?', missing: [ 'city', 'when' ] ) );

      expect( h.bloc.state.interview,            isNotNull );
      expect( h.bloc.state.interview!.pendingId, 'pend-1' );
      expect( h.bloc.state.interview!.question,  'Which city?' );
      expect( h.bloc.state.interview!.turn,      1 );
      expect( h.bloc.state.entries,              isEmpty, reason: 'nothing is answered yet' );
      await h.dispose();
    } );

    test( 'a SECOND parked loops BACK to the prompt on the SAME id, and args_missing shrinks', () async {
      // The falsifier: a client that treats the first `resume` as terminal
      // renders the answer card after turn one and never asks the second
      // question — ruling 5 silently half-implemented.
      final h = await askReturns( parked(
        pendingId: 'pend-1', question: 'Which city?', missing: [ 'city', 'when' ] ) );

      when( () => h.repo.resume( any() ) ).thenAnswer( ( _ ) async => parked(
        pendingId: 'pend-1', question: 'For when?', missing: [ 'when' ] ) );

      h.bloc.add( const QuickAskInterviewAnswered( 'Paris' ) );
      await settle();

      final iv = h.bloc.state.interview;
      expect( iv,             isNotNull, reason: 'the interview must NOT have terminated' );
      expect( iv!.question,   'For when?' );
      expect( iv.turn,        2 );
      expect( iv.pendingId,   'pend-1', reason: 'the SAME id across the whole interview' );
      expect( iv.argsMissing, [ 'when' ], reason: 'shrinks by one each turn' );
      expect( h.bloc.state.entries, isEmpty, reason: 'still nothing to show as an answer' );
      await h.dispose();
    } );

    test( 'every turn re-posts the SAME pending_id, and carries websocket_id', () async {
      final h = await askReturns( parked(
        pendingId: 'pend-1', question: 'Which city?', missing: [ 'city', 'when' ] ) );
      when( () => h.repo.resume( any() ) ).thenAnswer( ( _ ) async => parked(
        pendingId: 'pend-1', question: 'For when?', missing: [ 'when' ] ) );

      h.bloc.add( const QuickAskInterviewAnswered( 'Paris' ) );
      await settle();
      when( () => h.repo.resume( any() ) ).thenAnswer( ( _ ) async => doneWith( 'Rain on Tuesday.' ) );
      h.bloc.add( const QuickAskInterviewAnswered( 'Tuesday' ) );
      await settle();

      final sent = verify( () => h.repo.resume( captureAny() ) ).captured.cast<ResumeRequest>();
      expect( sent.length, 2 );
      expect( sent.map( ( r ) => r.pendingId ).toSet(), { 'pend-1' } );
      expect( sent.map( ( r ) => r.answer ).toList(), [ 'Paris', 'Tuesday' ] );
      // websocket_id rides EVERY turn — it is how the answer's TTS is routed,
      // and dropping it on turn two makes that turn speak nowhere.
      expect( sent.every( ( r ) => r.websocketId == ourSession ), isTrue );
      await h.dispose();
    } );

    test( 'the interview ENDS when the server stops parking, and the answer renders', () async {
      final h = await askReturns( parked( pendingId: 'pend-1', question: 'Which city?', missing: [ 'city' ] ) );
      when( () => h.repo.resume( any() ) ).thenAnswer( ( _ ) async => doneWith( 'Rain on Tuesday.' ) );

      h.bloc.add( const QuickAskInterviewAnswered( 'Paris' ) );
      await settle();

      expect( h.bloc.state.interview, isNull );
      expect( h.bloc.state.entries.single.state,  JobLifecycleState.completed );
      expect( h.bloc.state.entries.single.answer, 'Rain on Tuesday.' );
      await h.dispose();
    } );

    test( 'a live interview BLOCKS recording, with the prompt named as the reason', () async {
      final h = await askReturns( parked( pendingId: 'pend-1', question: 'Which city?' ) );
      expect( h.bloc.state.canRecord,   isFalse );
      expect( h.bloc.state.blockReason, QuickAskBlockReason.unansweredPrompt );
      await h.dispose();
    } );

    test( 'cancelling the interview clears it and unblocks recording', () async {
      final h = await askReturns( parked( pendingId: 'pend-1', question: 'Which city?' ) );
      h.bloc.add( const QuickAskInterviewCancelled() );
      await settle();
      expect( h.bloc.state.interview, isNull );
      expect( h.bloc.state.canRecord, isTrue );
      await h.dispose();
    } );

    test( 'a resume that ERRORS surfaces inline rather than dropping the turn silently', () async {
      final h = await askReturns( parked( pendingId: 'pend-1', question: 'Which city?' ) );
      when( () => h.repo.resume( any() ) )
          .thenThrow( const QueueApiException( 'grace period exceeded', statusCode: 400 ) );

      h.bloc.add( const QuickAskInterviewAnswered( 'Paris' ) );
      await settle();

      expect( h.bloc.state.errorMessage, 'grace period exceeded' );
      expect( h.bloc.state.phase,        QuickAskPhase.idle );
      await h.dispose();
    } );

    test( 'answering when no interview is live is a no-op, not a stray resume', () async {
      final h = await askReturns( doneWith( 'Sunny.' ) );
      h.bloc.add( const QuickAskInterviewAnswered( 'nobody asked' ) );
      await settle();
      verifyNever( () => h.repo.resume( any() ) );
      await h.dispose();
    } );
  } );

  group( 'AC-S4.2 — needs_input is the server TELLING, not asking', () {

    test( 'needs_input with NO id renders a terminal card and opens NO interview', () async {
      // The falsifier: the original id-sniffing router offers an answer box
      // for `needs_input` — a box with nowhere to send its value.
      final h = await askReturns( needsInput );

      expect( h.bloc.state.interview, isNull, reason: 'there is nothing to answer to' );
      final e = h.bloc.state.entries.single;
      expect( e.state, JobLifecycleState.failed );
      expect( e.lane,  JobLane.dead, reason: 'terminal — the lane with no reply controls' );
      expect( e.error, contains( 'city' ), reason: 'the card must NAME what was missing' );
      await h.dispose();
    } );

    test( 'needs_input does NOT block recording — it is finished, not pending', () async {
      final h = await askReturns( needsInput );
      expect( h.bloc.state.canRecord, isTrue );
      await h.dispose();
    } );

    test( 'parked and needs_input are branched on STATUS, not on which id is present', () async {
      // Both carry `path: needs_input`. Only `status` separates them, and a
      // router that sniffed for an id would conflate the two.
      final h1 = await askReturns( parked( pendingId: 'pend-1', question: 'Which city?' ) );
      expect( h1.bloc.state.interview, isNotNull );
      await h1.dispose();

      final h2 = await askReturns( needsInput );
      expect( h2.bloc.state.interview, isNull );
      await h2.dispose();
    } );
  } );
}
