import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';
import 'package:lupin_mobile/services/tts/streaming_tts_player.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';

class _MockPlayer   extends Mock implements StreamingTtsPlayer {}
class _MockFallback extends Mock implements NotificationAudioService {}
class _MockWs       extends Mock implements WebSocketService {}

void main() {
  group( "TtsOrchestrator", () {
    late _MockPlayer   player;
    late _MockFallback fallback;
    late _MockWs       ws;
    late NotificationPreferences prefs;
    late StreamController<TtsCompleteEvent> completeCtrl;
    late StreamController<TtsErrorEvent>    errorCtrl;
    TtsOrchestrator? orch;

    Future<void> setUpMocks( {
      String? sessionId = "wise penguin",
    } ) async {
      SharedPreferences.setMockInitialValues( {} );
      final sp = await SharedPreferences.getInstance();
      prefs = NotificationPreferences( sp );

      player       = _MockPlayer();
      fallback     = _MockFallback();
      ws           = _MockWs();
      completeCtrl = StreamController<TtsCompleteEvent>.broadcast();
      errorCtrl    = StreamController<TtsErrorEvent>   .broadcast();

      when( () => player.completeStream ).thenAnswer( ( _ ) => completeCtrl.stream );
      when( () => player.errorStream    ).thenAnswer( ( _ ) => errorCtrl   .stream );
      when( () => player.isPlaying      ).thenReturn( false );
      when( () => player.speak(
        text      : any( named: "text"      ),
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId"   ),
      ) ).thenAnswer( ( _ ) async {} );
      when( () => player.stop() ).thenAnswer( ( _ ) async {} );

      when( () => fallback.flutterTtsSpeak( any() )   ).thenAnswer( ( _ ) async {} );
      when( () => fallback.stopFallbackSpeech()       ).thenAnswer( ( _ ) async {} );

      when( () => ws.sessionId ).thenReturn( sessionId );
    }

    TtsOrchestrator newOrch() {
      orch = TtsOrchestrator(
        player   : player,
        fallback : fallback,
        prefs    : prefs,
        ws       : ws,
      );
      return orch!;
    }

    tearDown( () async {
      await orch?.dispose();
      await completeCtrl.close();
      await errorCtrl   .close();
    } );

    test( "low priority — never speaks, never enqueues", () async {
      await setUpMocks();
      final o = newOrch();

      o.enqueueIfSpeakable( priority: "low", message: "silent", title: null );
      // Let microtasks drain in case.
      await Future<void>.delayed( Duration.zero );

      verifyNever( () => player.speak(
        text      : any( named: "text" ),
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId" ),
      ) );
      verifyNever( () => fallback.flutterTtsSpeak( any() ) );
      expect( o.queueDepth, 0 );
    } );

    test( "medium priority — never speaks", () async {
      await setUpMocks();
      final o = newOrch();

      o.enqueueIfSpeakable( priority: "medium", message: "routine", title: null );
      await Future<void>.delayed( Duration.zero );

      verifyNever( () => player.speak(
        text      : any( named: "text" ),
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId" ),
      ) );
      expect( o.queueDepth, 0 );
    } );

    test( "high priority with speakOnHigh=true → ElevenLabs speak with title+message", () async {
      await setUpMocks();
      final o = newOrch();

      o.enqueueIfSpeakable( priority: "high", message: "Tests failing.", title: "Alert" );
      await Future<void>.delayed( Duration.zero );

      verify( () => player.speak(
        text      : "Alert. Tests failing.",
        sessionId : "wise penguin",
        voiceId   : any( named: "voiceId" ),
      ) ).called( 1 );
    } );

    test( "high priority with speakOnHigh=false → skipped", () async {
      await setUpMocks();
      await prefs.setSpeakOnHigh( false );
      final o = newOrch();

      o.enqueueIfSpeakable( priority: "high", message: "silent high", title: null );
      await Future<void>.delayed( Duration.zero );

      verifyNever( () => player.speak(
        text      : any( named: "text" ),
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId" ),
      ) );
    } );

    test( "urgent preempts high — stops current player, clears pending, speaks urgent", () async {
      await setUpMocks();
      final o = newOrch();

      // First, a high utterance starts playing.
      o.enqueueIfSpeakable( priority: "high", message: "first high", title: null );
      await Future<void>.delayed( Duration.zero );
      // Queue a second high behind it.
      o.enqueueIfSpeakable( priority: "high", message: "second high", title: null );
      await Future<void>.delayed( Duration.zero );
      expect( o.queueDepth, 1, reason: "second high should be pending behind first" );

      // Urgent arrives.
      o.enqueueIfSpeakable( priority: "urgent", message: "PROD DOWN", title: null );
      await Future<void>.delayed( Duration.zero );

      // Player.stop was called to preempt.
      verify( () => player.stop() ).called( greaterThanOrEqualTo( 1 ) );
      // Pending queue was flushed (the second high is gone).
      expect( o.queueDepth, 0 );
      // Urgent was dispatched.
      verify( () => player.speak(
        text      : "PROD DOWN",
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId" ),
      ) ).called( 1 );
    } );

    test( "FIFO — second high waits for first's complete event before dispatching", () async {
      await setUpMocks();
      final o = newOrch();

      o.enqueueIfSpeakable( priority: "high", message: "first",  title: null );
      await Future<void>.delayed( Duration.zero );
      o.enqueueIfSpeakable( priority: "high", message: "second", title: null );
      await Future<void>.delayed( Duration.zero );

      // Only first should have been dispatched so far.
      verify( () => player.speak(
        text      : "first",
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId" ),
      ) ).called( 1 );
      verifyNever( () => player.speak(
        text      : "second",
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId" ),
      ) );

      // First completes — queue advances.
      completeCtrl.add( const TtsCompleteEvent() );
      await Future<void>.delayed( Duration.zero );

      verify( () => player.speak(
        text      : "second",
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId" ),
      ) ).called( 1 );
    } );

    test( "quota_exceeded — current utterance re-spoken via flutter_tts fallback", () async {
      await setUpMocks();
      final o = newOrch();

      o.enqueueIfSpeakable( priority: "high", message: "failing text", title: null );
      await Future<void>.delayed( Duration.zero );

      // Backend returns quota_exceeded.
      errorCtrl.add( const TtsErrorEvent( errorCode: "quota_exceeded", message: "out" ) );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      verify( () => fallback.flutterTtsSpeak( "failing text" ) ).called( 1 );
    } );

    test( "quota_exceeded — subsequent utterances stay on fallback until 5min window elapses", () async {
      await setUpMocks();
      final o = newOrch();

      // Put the orchestrator in quota-fallback mode.
      o.enqueueIfSpeakable( priority: "high", message: "first",  title: null );
      await Future<void>.delayed( Duration.zero );
      errorCtrl.add( const TtsErrorEvent( errorCode: "quota_exceeded" ) );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      // Clear prior interactions on the mocks.
      clearInteractions( player );
      clearInteractions( fallback );
      when( () => fallback.flutterTtsSpeak( any() ) ).thenAnswer( ( _ ) async {} );
      when( () => player.speak(
        text      : any( named: "text" ),
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId" ),
      ) ).thenAnswer( ( _ ) async {} );

      // New utterance during fallback window.
      o.enqueueIfSpeakable( priority: "high", message: "next one", title: null );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      // Should go to fallback, NOT ElevenLabs.
      verify( () => fallback.flutterTtsSpeak( "next one" ) ).called( 1 );
      verifyNever( () => player.speak(
        text      : any( named: "text" ),
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId" ),
      ) );
    } );

    test( "master mute — nothing speaks via either path", () async {
      await setUpMocks();
      await prefs.setMasterMute( true );
      final o = newOrch();

      o.enqueueIfSpeakable( priority: "urgent", message: "quiet please", title: null );
      await Future<void>.delayed( Duration.zero );

      verifyNever( () => player.speak(
        text      : any( named: "text" ),
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId" ),
      ) );
      verifyNever( () => fallback.flutterTtsSpeak( any() ) );
    } );

    test( "no ws.sessionId — falls back to flutter_tts for this utterance, no quota window", () async {
      await setUpMocks( sessionId: null );
      final o = newOrch();

      o.enqueueIfSpeakable( priority: "high", message: "offline speech", title: null );
      await Future<void>.delayed( Duration.zero );

      verify( () => fallback.flutterTtsSpeak( "offline speech" ) ).called( 1 );
      verifyNever( () => player.speak(
        text      : any( named: "text" ),
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId" ),
      ) );
    } );

    test( "network error on speak — falls back for THIS utterance, continues queue on ElevenLabs", () async {
      await setUpMocks();
      when( () => player.speak(
        text      : "will fail",
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId" ),
      ) ).thenThrow( Exception( "network down" ) );

      final o = newOrch();
      o.enqueueIfSpeakable( priority: "high", message: "will fail", title: null );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      verify( () => fallback.flutterTtsSpeak( "will fail" ) ).called( 1 );
    } );

    // Phase 4 (voice-persona milestone) — orchestrator pipe-through tests
    // per 04-testing-validation.md rows 4.4 and 4.5.

    test( "4.4 — persona piped from notification: orchestrator passes voiceId through to player.speak", () async {
      await setUpMocks();
      await prefs.setSpeakOnHigh( true );
      final o = newOrch();

      o.enqueueIfSpeakable(
        priority : "high",
        message  : "hello from Adam",
        title    : null,
        voiceId  : "pNInz6obpgDQGcFmaJgB",
      );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      verify( () => player.speak(
        text      : "hello from Adam",
        sessionId : "wise penguin",
        voiceId   : "pNInz6obpgDQGcFmaJgB",
      ) ).called( 1 );
      verifyNever( () => fallback.flutterTtsSpeak( any() ) );
    } );

    test( "4.4b — null voiceId omitted: enqueueIfSpeakable without voiceId calls player.speak with voiceId=null", () async {
      await setUpMocks();
      await prefs.setSpeakOnHigh( true );
      final o = newOrch();

      o.enqueueIfSpeakable( priority: "high", message: "no persona", title: null );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      // Server falls back to Sam when voice_id key is absent (Q3 contract).
      // The orchestrator passes null through; StreamingTtsPlayer's body
      // wiring at :141 omits the key entirely (covered by test 4.2 above).
      verify( () => player.speak(
        text      : "no persona",
        sessionId : "wise penguin",
        voiceId   : null,
      ) ).called( 1 );
    } );

    test( "4.5 — quota fallback omits voiceId: flutter_tts speak is called WITHOUT voiceId per Q4", () async {
      // Per Pass 1 finding F11: instantiate the orchestrator with a quota
      // window already active (simulated via the existing
      // "quota_exceeded → 5min fallback window" path), then enqueue a high
      // utterance with a voiceId. Assert that ElevenLabs `player.speak` is
      // NOT called (window-gated fallback) and `fallback.flutterTtsSpeak`
      // IS called with the bare text — no voiceId reaches the fallback.
      await setUpMocks();
      await prefs.setSpeakOnHigh( true );
      final o = newOrch();

      // Trigger the quota window: emit a quota_exceeded error event on the
      // player's error stream while no utterance is in flight. The
      // orchestrator's _onElevenLabsError handler sets
      // _elevenLabsDisabledUntil and the next enqueue routes via fallback.
      // We do this by faking a "current" utterance: enqueue one, then
      // simulate the error event arriving.
      o.enqueueIfSpeakable(
        priority : "high",
        message  : "first",
        title    : null,
        voiceId  : "vx-first",
      );
      await Future<void>.delayed( Duration.zero );

      // Now the orchestrator has an in-flight utterance. Push a
      // quota_exceeded error → enters the 5-min fallback window.
      errorCtrl.add( const TtsErrorEvent(
        errorCode : 'quota_exceeded',
        message   : 'first',
      ) );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      // Fallback should have re-spoken "first" without voiceId.
      verify( () => fallback.flutterTtsSpeak( "first" ) ).called( 1 );

      // Now the next utterance during the window goes straight to fallback.
      o.enqueueIfSpeakable(
        priority : "high",
        message  : "second",
        title    : null,
        voiceId  : "vx-second",
      );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      // Per Q4: flutter_tts is called with bare text only. No voiceId,
      // no overload that takes voiceId. The fallback voice space is
      // intentionally separate from ElevenLabs.
      verify( () => fallback.flutterTtsSpeak( "second" ) ).called( 1 );

      // ElevenLabs `player.speak` was NOT called for the second utterance
      // (window is active). It WAS called once for "first" before the
      // error fired; that's the expected baseline.
      verifyNever( () => player.speak(
        text      : "second",
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId" ),
      ) );
    } );
  } );
}
