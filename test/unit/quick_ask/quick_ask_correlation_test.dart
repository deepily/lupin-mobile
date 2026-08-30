/// S1 correlation core — the pre-attribution buffer, the monotonic fold, and
/// the `waiting` branch.
///
/// Every test drives a REAL `QuickAskBloc`.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/domain/job_lifecycle.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';

import '_quick_ask_harness.dart';

void main() {
  setUpAll( () {
    registerFallbackValue( const AskRequest( question: 'x' ) );
  } );

  group( 'AC-S1.2 — frames arriving BEFORE the AskResponse resolves are buffered and folded', () {

    test( 'pending→queued and queued→running dispatched while ask() is still pending end in RUNNING', () async {
      final h = Harness();
      h.stubEmptyQueues();
      await settle();

      // Hold the ask open, exactly as the server does: `push()` emits
      // pending→queued SYNCHRONOUSLY inside itself, before FastAPI has
      // serialized the response body.
      final gate = Completer<AskResponse>();
      when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) => gate.future );
      when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'what is the weather' );

      h.bloc.add( const QuickAskRecordPressed() );
      await settle();
      h.bloc.add( const QuickAskRecordReleased() );
      await settle();

      // ── the pre-attribution window ──
      h.bloc.add( QuickAskTransitionReceived( transitionFrame( to: 'queued' ) ) );
      h.bloc.add( QuickAskTransitionReceived( transitionFrame( from: 'queued', to: 'running' ) ) );
      await settle();

      // Nothing has been attributed yet — there is no job id.
      expect( h.bloc.state.liveJobId, isNull );

      gate.complete( waitingAsk() );
      await settle();

      expect( h.bloc.state.liveJobId,        ourJob );
      expect( h.bloc.state.liveEntry?.state, JobLifecycleState.running,
          reason: 'both buffered frames must fold, in rank order, on attribution' );
      await h.dispose();
    } );
  } );

  group( 'AC-S1.3 — the fold is rank-monotonic', () {

    Future<Harness> live() async {
      final h = Harness();
      h.stubEmptyQueues();
      when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) async => waitingAsk() );
      when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'what is the weather' );
      await settle();
      h.bloc.add( const QuickAskRecordPressed() );
      await settle();
      h.bloc.add( const QuickAskRecordReleased() );
      await settle();
      return h;
    }

    test( 'completed then running STAYS completed', () async {
      final h = await live();
      h.bloc.add( QuickAskTransitionReceived(
        transitionFrame( from: 'running', to: 'completed', responseText: 'It is sunny.' ) ) );
      await settle();
      expect( h.bloc.state.entries.last.state,  JobLifecycleState.completed );
      expect( h.bloc.state.entries.last.answer, 'It is sunny.' );

      // A late, out-of-order `running` must be a no-op — not a walk-back.
      h.bloc.add( QuickAskTransitionReceived( transitionFrame( from: 'queued', to: 'running' ) ) );
      await settle();
      expect( h.bloc.state.entries.last.state,  JobLifecycleState.completed );
      expect( h.bloc.state.entries.last.answer, 'It is sunny.' );
      await h.dispose();
    } );

    test( 'a DUPLICATE completed emits one state, not two', () async {
      final h = await live();
      final seen = <QuickAskState>[];
      final sub  = h.bloc.stream.listen( seen.add );

      final frame = transitionFrame( from: 'running', to: 'completed', responseText: 'It is sunny.' );
      h.bloc.add( QuickAskTransitionReceived( frame ) );
      await settle();
      final afterFirst = seen.length;

      h.bloc.add( QuickAskTransitionReceived( frame ) );
      await settle();

      expect( seen.length, afterFirst, reason: 'the duplicate must be a no-op' );
      await sub.cancel();
      await h.dispose();
    } );

    test( 'a frame for ANOTHER job id changes nothing', () async {
      final h = await live();
      final before = h.bloc.state;
      h.bloc.add( QuickAskTransitionReceived(
        transitionFrame( jobId: 'someone-elses-job', from: 'running', to: 'completed',
                         responseText: 'not yours' ) ) );
      await settle();
      expect( h.bloc.state, before );
      await h.dispose();
    } );

    test( 'a frame with an UNKNOWN to_state is dropped, not guessed at', () async {
      final h = await live();
      final before = h.bloc.state;
      h.bloc.add( QuickAskTransitionReceived( transitionFrame( to: 'teleported' ) ) );
      await settle();
      expect( h.bloc.state, before );
      await h.dispose();
    } );

    test( 'AC-S1.9 — the lane comes from to_state, NEVER from metadata.status', () async {
      final h = await live();
      // `JobSummary.fromJson` reads `(j['status'] as String?) ?? 'queued'` — a
      // SILENT fallback. Here the metadata carries a status that disagrees with
      // `to_state`, and an implementation reading the metadata would land on
      // the wrong lane while looking perfectly healthy.
      h.bloc.add( QuickAskTransitionReceived( transitionFrame(
        from: 'queued', to: 'running', metaStatus: 'completed' ) ) );
      await settle();
      expect( h.bloc.state.liveEntry?.state, JobLifecycleState.running,
          reason: 'metadata.status said completed; the frame said running — to_state wins' );

      // And an ABSENT/unknown metadata status must not silently become queued.
      h.bloc.add( QuickAskTransitionReceived( transitionFrame(
        from: 'running', to: 'completed', metaStatus: 'nonsense', responseText: 'done' ) ) );
      await settle();
      expect( h.bloc.state.entries.last.state, JobLifecycleState.completed );
      await h.dispose();
    } );
  } );

  group( 'AC-S1.3b — foreign frames CANNOT evict ours from the pre-attribution buffer', () {

    test( 'a flood exceeding the cap, interleaved with ours, still folds ours', () async {
      final h = Harness();
      h.stubEmptyQueues();
      final gate = Completer<AskResponse>();
      when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) => gate.future );
      when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'what is the weather' );
      await settle();

      h.bloc.add( const QuickAskRecordPressed() );
      await settle();
      h.bloc.add( const QuickAskRecordReleased() );
      await settle();

      // OUR frame goes in first, then a flood of MORE THAN THE CAP of foreign
      // frames. On an admin account the transition fan-out is every other
      // user's jobs — unbounded, and not a number any cap can be sized
      // against. A drain-time-only filter evicts ours here and folds an
      // incomplete history without ever knowing it happened.
      h.bloc.add( QuickAskTransitionReceived( transitionFrame( to: 'queued' ) ) );
      for ( var i = 0; i < QuickAskBloc.bufferCap * 2; i++ ) {
        h.bloc.add( QuickAskTransitionReceived( transitionFrame(
          jobId     : 'foreign-$i',
          to        : 'queued',
          question  : 'a completely different question $i',
          email     : 'someone.else@lupin.test',
          sessionId : 'other session',
        ) ) );
      }
      h.bloc.add( QuickAskTransitionReceived( transitionFrame( from: 'queued', to: 'running' ) ) );
      await settle( 12 );

      gate.complete( waitingAsk() );
      await settle();

      expect( h.bloc.state.liveEntry?.state, JobLifecycleState.running,
          reason: 'insert-time filtering must keep our frames out of the flood\'s way' );
      await h.dispose();
    } );

    test( 'a foreign frame carrying OUR question text but ANOTHER user\'s email is refused at the door', () async {
      final h = Harness();
      h.stubEmptyQueues();
      final gate = Completer<AskResponse>();
      when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) => gate.future );
      when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'what is the weather' );
      await settle();
      h.bloc.add( const QuickAskRecordPressed() );
      await settle();
      h.bloc.add( const QuickAskRecordReleased() );
      await settle();

      // The residual a text-only filter leaves open: another user asking the
      // IDENTICAL question. The email key closes it.
      h.bloc.add( QuickAskTransitionReceived( transitionFrame(
        from: 'queued', to: 'completed',
        question: 'what is the weather',          // identical text
        email   : 'someone.else@lupin.test',      // different person
        responseText: 'THEIR answer' ) ) );
      await settle();

      gate.complete( waitingAsk() );
      await settle();

      expect( h.bloc.state.liveEntry?.state, JobLifecycleState.pending,
          reason: 'their completed frame must not have been buffered as ours' );
      expect( h.bloc.state.liveEntry?.answer, isNot( 'THEIR answer' ) );
      await h.dispose();
    } );
  } );

  group( 'AC-S1.6 — the ask carries the LIVE websocket session id', () {

    test( 'websocket_id is the live sessionId, never the literal "mobile"', () async {
      final h = Harness( sessionId: 'clever dolphin' );
      h.stubEmptyQueues();
      when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) async => waitingAsk() );
      when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'what is the weather' );
      await settle();
      h.bloc.add( const QuickAskRecordPressed() );
      await settle();
      h.bloc.add( const QuickAskRecordReleased() );
      await settle();

      final sent = verify( () => h.repo.ask( captureAny() ) ).captured.single as AskRequest;
      expect( sent.websocketId, 'clever dolphin' );
      expect( sent.websocketId, isNot( 'mobile' ) );
      expect( sent.question,    'what is the weather' );
      await h.dispose();
    } );
  } );
}
