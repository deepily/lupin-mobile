/// AC-S4.1 — branching is on `status` FIRST, and all seven outcomes route to
/// something the user can act on.
///
/// 🔴 Seven, not six. `v2_ask.py:91` documents six — `done | waiting | parked |
/// needs_input | expired | failed` — and `flow.py:178` emits a seventh,
/// `rejected`, from the fitness gate that runs before the cache, the router or
/// the expeditor sees the question. The wire is the authority; the field's own
/// docstring is one line behind it.
///
/// 🔴 Two of them were falling through to the no-job-id case and vanishing in
/// silence: `expired` and `rejected`. "Routes correctly" is undefined unless
/// each outcome NAMES itself, which is what AC-S4.13 established for the pair
/// of endings the resume door has.
///
/// 🔴 Verification-map deviation, reported rather than quietly absorbed: the
/// map names `quick_ask_bloc_test.dart` for AC-S4.1, alongside eleven other
/// ids. That file does not exist and never has — those eleven live across
/// `quick_ask_predicate_test.dart`, `quick_ask_watchdog_test.dart` and
/// `quick_ask_correlation_test.dart`. Creating it here for AC-S4.1 alone would
/// leave the map wrong about the other eleven and look right. Same call, same
/// reason as the AC-S3.6 split at `9dc7306`.
///
/// ⚠️ `AC-S4.n` ids COLLIDE ACROSS PLANS — 30 of this plan's 55 present ids
/// appear in more than one file, and an older ASR plan has its own S4.1. A
/// grep audit reports this covered either way. Read the body.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/domain/job_lifecycle.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';

import '_quick_ask_harness.dart';

/// The resume door's two endings. BOTH carry `status: expired` — verified in
/// the server source, where `flow.py:698` and `:727` call `_emit` with
/// `status="expired"` either way. Only `route_reason` separates them, which is
/// exactly why routing on `status` alone collapses them into one card.
AskResponse expiredWith( String routeReason ) => AskResponse(
  path        : 'needs_input',
  status      : 'expired',
  routeReason : routeReason,
  traceId     : 'tr-x',
  pendingId   : 'p-1',
);

const rejected = AskResponse(
  path        : 'rejected',
  status      : 'rejected',
  routeReason : 'question_too_short',
  traceId     : 'tr-r',
  // The fitness gate puts its refusal SENTENCE in `answer` — the same words
  // the server speaks aloud (`flow.py:178`).
  answer      : 'I need a bit more than that to work with.',
);

const failed = AskResponse(
  path        : 'agent',
  status      : 'failed',
  routeReason : 'router:weather',
  traceId     : 'tr-f',
  error       : 'the agent blew up',
);

AskResponse doneWith( String answer ) => AskResponse(
  path        : 'agent',
  status      : 'done',
  routeReason : 'router:weather',
  traceId     : 'tr-d',
  answer      : answer,
  jobId       : 'j-done',
);

void main() {
  setUpAll( () {
    registerFallbackValue( const AskRequest( question: 'x' ) );
    registerFallbackValue( const ResumeRequest( pendingId: 'p', answer: 'a' ) );
  } );

  Future<Harness> askReturns( AskResponse res ) async {
    final h = Harness();
    h.stubEmptyQueues();
    when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'what is the weather' );
    when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) async => res );
    await settle();
    h.bloc.add( const QuickAskRecordPressed() );
    await settle();
    h.bloc.add( const QuickAskRecordReleased() );
    await settle();
    h.bloc.add( const QuickAskDraftSent() );
    await settle();
    return h;
  }

  /// The last card's error text — where a terminal outcome has to name itself.
  String? lastError( Harness h ) => h.bloc.state.entries.last.details?.error;

  group( 'AC-S4.1 — every outcome lands SOMEWHERE, and none lands in silence', () {

    test( 'done renders the answer and arms no watchdog', () async {
      final h = await askReturns( doneWith( 'seventy two and sunny' ) );
      expect( h.bloc.state.entries.single.state, JobLifecycleState.completed );
      expect( h.bloc.state.entries.single.details?.responseText, 'seventy two and sunny' );
      expect( h.bloc.state.phase,     QuickAskPhase.idle );
      expect( h.bloc.state.liveJobId, isNull );
      await h.dispose();
    } );

    test( 'waiting keeps the job live for correlation', () async {
      final h = await askReturns( waitingAsk() );
      expect( h.bloc.state.phase,     QuickAskPhase.waiting );
      expect( h.bloc.state.liveJobId, ourJob );
      await h.dispose();
    } );

    test( 'failed surfaces the error and opens no card lane of its own', () async {
      final h = await askReturns( failed );
      expect( h.bloc.state.errorMessage, 'the agent blew up' );
      expect( h.bloc.state.phase,        QuickAskPhase.idle );
      await h.dispose();
    } );

    test( 'parked opens the interview; needs_input does not — branched on STATUS', () async {
      final h = await askReturns( const AskResponse(
        path: 'needs_input', status: 'parked', routeReason: 'args_missing',
        traceId: 'tr-p', answer: 'which city?', pendingId: 'p-1' ) );
      expect( h.bloc.state.interview?.pendingId, 'p-1' );
      await h.dispose();

      final g = await askReturns( const AskResponse(
        path: 'needs_input', status: 'needs_input', routeReason: 'args_missing',
        traceId: 'tr-n', argsMissing: [ 'city' ] ) );
      expect( g.bloc.state.interview, isNull );
      expect( g.bloc.state.entries.last.state, JobLifecycleState.failed );
      await g.dispose();
    } );

    test( 'NO outcome leaves the phase hung — every one of the seven settles', () async {
      // The falsifier for the whole group: an unrouted status used to fall
      // through to the no-job-id case, clear the question and emit NOTHING —
      // the turn simply disappeared. Asserting `idle` alone would pass on that
      // silence, so each case below also asserts what it SAID.
      for ( final res in [
        doneWith( 'x' ), failed, rejected,
        expiredWith( 'pending_expired' ), expiredWith( 'already_resumed' ),
        const AskResponse( path: 'needs_input', status: 'needs_input',
            routeReason: 'args_missing', traceId: 't', argsMissing: [ 'city' ] ),
      ] ) {
        final h = await askReturns( res );
        expect( h.bloc.state.phase, QuickAskPhase.idle,
            reason: 'status "${res.status}"/"${res.routeReason}" left the UI hung' );
        final spoke = h.bloc.state.errorMessage != null || h.bloc.state.entries.isNotEmpty;
        expect( spoke, isTrue,
            reason: 'status "${res.status}"/"${res.routeReason}" resolved in SILENCE' );
        await h.dispose();
      }
    } );
  } );

  group( 'AC-S4.13 — the resume door\'s two endings are OWNED BY NAME', () {

    test( 'pending_expired says the question TIMED OUT and to ask again', () async {
      final h = await askReturns( expiredWith( 'pending_expired' ) );
      expect( lastError( h ), 'Expired — the question timed out. Ask again.' );
      expect( h.bloc.state.entries.last.state, JobLifecycleState.failed );
      expect( h.bloc.state.interview, isNull );
      await h.dispose();
    } );

    test( 'already_resumed says it was ALREADY ANSWERED, here or elsewhere', () async {
      final h = await askReturns( expiredWith( 'already_resumed' ) );
      expect( lastError( h ), 'Already answered — here or on another device.' );
      await h.dispose();
    } );

    test( 'the two endings do NOT share a card — that is the whole point', () async {
      final a = await askReturns( expiredWith( 'pending_expired' ) );
      final b = await askReturns( expiredWith( 'already_resumed' ) );
      // One shared "something went wrong" card passes AC-S4.1's "routes
      // correctly" and is exactly what AC-S4.13 exists to refuse.
      expect( lastError( a ), isNot( lastError( b ) ) );
      await a.dispose();
      await b.dispose();
    } );

    test( 'an expired arriving on the RESUME turn takes the same table', () async {
      // One implementation for the ask turn and the resume turn, so the second
      // turn of an interview cannot drift from the first.
      final h = await askReturns( const AskResponse(
        path: 'needs_input', status: 'parked', routeReason: 'args_missing',
        traceId: 'tr-p', answer: 'which city?', pendingId: 'p-1' ) );
      when( () => h.repo.resume( any() ) )
          .thenAnswer( ( _ ) async => expiredWith( 'already_resumed' ) );

      h.bloc.add( const QuickAskInterviewAnswered( 'Boston' ) );
      await settle();

      expect( h.bloc.state.interview, isNull );
      expect( lastError( h ), 'Already answered — here or on another device.' );
      await h.dispose();
    } );
  } );

  group( 'AC-S4.1 — rejected is a REFUSAL, not a crash', () {

    test( 'the fitness gate\'s own sentence is what the card shows', () async {
      final h = await askReturns( rejected );
      // `answer` carries the words the server also spoke. Replacing them with
      // "Request failed" throws away the only thing that says WHY, and makes a
      // refusal look identical to a blown-up agent.
      expect( lastError( h ), 'I need a bit more than that to work with.' );
      expect( h.bloc.state.entries.last.state, JobLifecycleState.failed );
      await h.dispose();
    } );

    test( 'rejected is distinguishable from failed', () async {
      final r = await askReturns( rejected );
      final f = await askReturns( failed );
      expect( lastError( r ), isNotNull );
      expect( f.bloc.state.errorMessage, 'the agent blew up' );
      expect( lastError( r ), isNot( f.bloc.state.errorMessage ) );
      await r.dispose();
      await f.dispose();
    } );

    test( 'a rejected with no sentence still says something', () async {
      final h = await askReturns( const AskResponse(
        path: 'rejected', status: 'rejected', routeReason: 'empty', traceId: 't' ) );
      expect( lastError( h ), 'That question was refused.' );
      await h.dispose();
    } );
  } );
}
