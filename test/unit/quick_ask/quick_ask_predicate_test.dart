/// AC-S2.2a — `canRecord` is correct as a PREDICATE, and AC-S2.5a — a real
/// `AsrException` dispatches no submit.
///
/// 🔴 Every test here drives a REAL `QuickAskBloc`. Under `MockBloc` these
/// could not discriminate BY CONSTRUCTION: mocking the bloc replaces the
/// computation, so the test would prove the button greys out when told to and
/// pass unchanged against an inverted, stale, or missing clause. Name the stub
/// that turns a MockBloc version red and there is none — which is the whole
/// reason AC-S2.2 was split.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';

import '_quick_ask_harness.dart';

void main() {
  setUpAll( () { registerFallbackValue( const AskRequest( question: 'x' ) ); } );

  group( 'AC-S2.2a — each clause is driven INDEPENDENTLY and names itself', () {

    test( 'all four clauses satisfied ⇒ canRecord is true and there is no reason', () async {
      final h = Harness();
      h.stubEmptyQueues();
      await settle();
      expect( h.bloc.state.canRecord,      isTrue );
      expect( h.bloc.state.blockReason,    isNull );
      expect( h.bloc.state.blockedMessage, isNull );
      await h.dispose();
    } );

    test( 'clause (c) SOCKET alone ⇒ false, and the reason names the socket', () async {
      final h = Harness( connected: false );
      h.stubEmptyQueues();
      await settle();
      expect( h.bloc.state.canRecord,   isFalse );
      expect( h.bloc.state.blockReason, QuickAskBlockReason.socketDisconnected );
      expect( h.bloc.state.blockedMessage, contains( 'connect' ) );
      await h.dispose();
    } );

    test( 'clause (c) recovers when the socket comes back — the predicate is not stale', () async {
      // The sharp one: a predicate over an UNOBSERVABLE bool goes stale
      // silently — the socket drops, the button stays enabled until something
      // unrelated repaints, and the screen never learns.
      final h = Harness( connected: false );
      h.stubEmptyQueues();
      await settle();
      expect( h.bloc.state.canRecord, isFalse );

      h.connCtrl.add( true );
      await settle();
      expect( h.bloc.state.canRecord, isTrue );

      h.connCtrl.add( false );
      await settle();
      expect( h.bloc.state.canRecord,   isFalse );
      expect( h.bloc.state.blockReason, QuickAskBlockReason.socketDisconnected );
      await h.dispose();
    } );

    test( 'clause (a) LIVE JOB alone ⇒ false, and the reason names the live job', () async {
      final h = Harness();
      h.stubEmptyQueues();
      when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) async => waitingAsk() );
      when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'q' );
      await settle();

      h.bloc.add( const QuickAskRecordPressed() );
      await settle();
      h.bloc.add( const QuickAskRecordReleased() );
      await settle();

      expect( h.bloc.state.liveJobId,   ourJob );
      expect( h.bloc.state.canRecord,   isFalse );
      expect( h.bloc.state.blockReason, QuickAskBlockReason.liveJobInFlight );
      await h.dispose();
    } );

    test( 'clause (b) UNANSWERED PROMPT alone ⇒ false, and the reason names the prompt', () async {
      final h = Harness();
      h.stubEmptyQueues();
      await settle();
      h.bloc.add( QuickAskNotificationReceived( notif( id: 'p-1', responseRequested: true ) ) );
      await settle();

      expect( h.bloc.state.pendingPromptId, 'p-1' );
      expect( h.bloc.state.canRecord,       isFalse );
      expect( h.bloc.state.blockReason,     QuickAskBlockReason.unansweredPrompt );
      await h.dispose();
    } );

    test( 'clause (d) SHARED RECORDER alone ⇒ false, and the reason names the capture', () async {
      // AC-S2.2c's other half seen from the predicate side: the recorder is a
      // SINGLETON, so a capture started by focus mode's VoiceReplyField makes
      // this true without Quick Ask having started anything.
      final h = Harness();
      h.stubEmptyQueues();
      when( () => h.asr.isCapturing ).thenReturn( true );
      when( () => h.asr.startRecording() )
          .thenThrow( const AsrException( 'A recording is already in progress' ) );
      await settle();

      h.bloc.add( const QuickAskRecordPressed() );
      await settle();

      expect( h.bloc.state.canRecord,   isFalse );
      expect( h.bloc.state.blockReason, QuickAskBlockReason.captureInFlight );
      await h.dispose();
    } );

    test( 'the exposed reason is DETERMINISTIC when more than one clause is false', () async {
      final h = Harness( connected: false );
      h.stubEmptyQueues();
      await settle();
      h.bloc.add( QuickAskNotificationReceived( notif( id: 'p-2', responseRequested: true ) ) );
      await settle();
      // Prompt outranks socket in the fixed evaluation order, so the message
      // never flickers between two true statements.
      expect( h.bloc.state.blockReason, QuickAskBlockReason.unansweredPrompt );
      await h.dispose();
    } );

    test( 'every reason carries a message a human can act on', () async {
      for ( final r in QuickAskBlockReason.values ) {
        expect( r.message.trim(), isNotEmpty );
        expect( r.message.length, lessThan( 60 ) );
      }
    } );
  } );

  group( 'AC-S2.5a — a REAL AsrException dispatches no submit', () {

    test( 'an EMPTY transcript throws, no submit reaches the repository, bloc returns to idle', () async {
      // Whisper hallucinates on silence and can return junk; an empty
      // transcript is the other outcome and must not become a question.
      final h = Harness();
      h.stubEmptyQueues();
      when( () => h.asr.stopAndTranscribe() )
          .thenThrow( const AsrException( 'Transcription came back empty' ) );
      await settle();

      h.bloc.add( const QuickAskRecordPressed() );
      await settle();
      h.bloc.add( const QuickAskRecordReleased() );
      await settle();

      verifyNever( () => h.repo.ask( any() ) );
      expect( h.bloc.state.phase,        QuickAskPhase.idle );
      expect( h.bloc.state.errorMessage, 'Transcription came back empty' );
      await h.dispose();
    } );

    test( 'PERMISSION DENIED throws at start, no submit, bloc returns to idle', () async {
      final h = Harness();
      h.stubEmptyQueues();
      when( () => h.asr.startRecording() )
          .thenThrow( const AsrException( 'Microphone permission denied' ) );
      await settle();

      h.bloc.add( const QuickAskRecordPressed() );
      await settle();

      verifyNever( () => h.repo.ask( any() ) );
      expect( h.bloc.state.phase,        QuickAskPhase.idle );
      expect( h.bloc.state.errorMessage, 'Microphone permission denied' );
      await h.dispose();
    } );

    test( 'the error clears on dismissal and recording is possible again', () async {
      final h = Harness();
      h.stubEmptyQueues();
      when( () => h.asr.startRecording() )
          .thenThrow( const AsrException( 'Microphone permission denied' ) );
      await settle();
      h.bloc.add( const QuickAskRecordPressed() );
      await settle();

      h.bloc.add( const QuickAskErrorDismissed() );
      await settle();
      expect( h.bloc.state.errorMessage, isNull );
      expect( h.bloc.state.canRecord,    isTrue );
      await h.dispose();
    } );
  } );

  group( 'AC-S2.1 — exactly ONE submit, including when cancelled mid-press', () {

    test( 'hold then release submits exactly once', () async {
      final h = Harness();
      h.stubEmptyQueues();
      when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) async => waitingAsk() );
      when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'q' );
      await settle();

      h.bloc.add( const QuickAskRecordPressed() );
      await settle();
      h.bloc.add( const QuickAskRecordReleased() );
      await settle();

      verify( () => h.repo.ask( any() ) ).called( 1 );
      await h.dispose();
    } );

    test( 'a release AFTER a cancel submits NOTHING', () async {
      final h = Harness();
      h.stubEmptyQueues();
      when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) async => waitingAsk() );
      when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'q' );
      await settle();

      h.bloc.add( const QuickAskRecordPressed() );
      await settle();
      h.bloc.add( const QuickAskRecordCancelled() );
      await settle();
      h.bloc.add( const QuickAskRecordReleased() );
      await settle();

      verifyNever( () => h.repo.ask( any() ) );
      verify( () => h.asr.cancelRecording() ).called( 1 );
      await h.dispose();
    } );

    test( 'a cancel landing WHILE the transcription is in flight drops the result', () async {
      // The epoch guard, mirroring `voice_reply_field.dart`'s `_opEpoch` rather
      // than re-inventing it: an in-flight `stopAndTranscribe()` whose epoch no
      // longer matches is discarded instead of submitted.
      final h = Harness();
      h.stubEmptyQueues();
      final slow = Completer<String>();
      when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) async => waitingAsk() );
      when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) => slow.future );
      await settle();

      h.bloc.add( const QuickAskRecordPressed() );
      await settle();
      h.bloc.add( const QuickAskRecordReleased() );
      await settle();

      // The user drags off mid-upload.
      h.bloc.add( const QuickAskRecordCancelled() );
      await settle();

      slow.complete( 'a transcript nobody wants any more' );
      await settle();

      verifyNever( () => h.repo.ask( any() ) );
      expect( h.bloc.state.phase, QuickAskPhase.idle );
      await h.dispose();
    } );

    test( 'a second press while already recording does not start a second capture', () async {
      final h = Harness();
      h.stubEmptyQueues();
      await settle();
      h.bloc.add( const QuickAskRecordPressed() );
      await settle();
      h.bloc.add( const QuickAskRecordPressed() );
      await settle();
      verify( () => h.asr.startRecording() ).called( 1 );
      await h.dispose();
    } );
  } );

  group( 'AC-S2.7 — a first-run user is PROMPTED for the microphone, not refused', () {

    test( 'holding the button ISSUES the permission request before capturing', () async {
      // 🔴 The falsifier: an implementation that calls only
      // `AsrService.startRecording()` and renders its `AsrException` passes
      // every existing test while the prompt NEVER APPEARS. So this asserts the
      // REQUEST was issued, not that an error rendered.
      final h = Harness();
      h.stubEmptyQueues();
      await settle();

      h.bloc.add( const QuickAskRecordPressed() );
      await settle();

      expect( h.micRequests, 1, reason: 'a fresh install must be ASKED, not refused' );
      verify( () => h.asr.startRecording() ).called( 1 );
      await h.dispose();
    } );

    test( 'the request comes BEFORE the recorder is touched', () async {
      final h = Harness();
      h.stubEmptyQueues();
      h.micGranted = false;
      await settle();

      h.bloc.add( const QuickAskRecordPressed() );
      await settle();

      expect( h.micRequests, 1 );
      verifyNever( () => h.asr.startRecording() );
      await h.dispose();
    } );

    test( 'a DENIED permission surfaces a message that names the fix', () async {
      final h = Harness();
      h.stubEmptyQueues();
      h.micGranted = false;
      await settle();

      h.bloc.add( const QuickAskRecordPressed() );
      await settle();

      expect( h.bloc.state.phase, QuickAskPhase.idle );
      expect( h.bloc.state.errorMessage, contains( 'system settings' ) );
      await h.dispose();
    } );

    test( 'a granted permission does not re-prompt on every subsequent hold', () async {
      // `request()` is a no-op returning the existing status once decided, so
      // calling it per capture is safe — but the bloc must not add its own
      // extra prompt on top.
      final h = Harness();
      h.stubEmptyQueues();
      when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'q' );
      when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) async => waitingAsk( jobId: null ) );
      await settle();

      h.bloc.add( const QuickAskRecordPressed() );
      await settle();
      h.bloc.add( const QuickAskRecordReleased() );
      await settle();
      expect( h.micRequests, 1 );
      await h.dispose();
    } );
  } );
}
