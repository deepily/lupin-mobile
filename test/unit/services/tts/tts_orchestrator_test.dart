import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';
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

    // ── Queue viewer + system-sender gate (Rick 2026-08-21) ──
    test( "queue viewer: queueSnapshot/queueStream = current (flagged) then pending in play order, with sender meta", () async {
      await setUpMocks();
      final o = newOrch();
      final emitted = <List<TtsQueueItem>>[];
      final sub = o.queueStream.listen( emitted.add );
      const tiff = TtsSender( senderId: "cc@lupin#e082", name: "Tiffany", icon: "💍" );
      const sys  = TtsSender( senderId: "pytest.runner@lupin#1" );

      o.enqueueAlways( priority: "high", message: "first",  sender: tiff );
      await Future<void>.delayed( Duration.zero );
      o.enqueueAlways( priority: "low",  message: "second", sender: sys );
      o.enqueueAlways( priority: "low",  message: "third" );
      await Future<void>.delayed( Duration.zero );

      final snap = o.queueSnapshot;
      expect( snap.map( ( i ) => i.text ).toList(), [ "first", "second", "third" ] );
      expect( snap[ 0 ].isCurrent, isTrue );
      expect( snap[ 1 ].isCurrent, isFalse );
      expect( snap[ 0 ].sender.label, "Tiffany" );
      expect( snap[ 0 ].sender.isPersona, isTrue );
      expect( snap[ 1 ].sender.label, "pytest.runner", reason: "no persona ⇒ sender-id local part" );
      expect( snap[ 1 ].sender.isPersona, isFalse );
      expect( snap[ 2 ].sender.label, "system", reason: "no sender at all" );
      expect( snap.map( ( i ) => i.id ).toSet().length, 3, reason: "ids unique" );
      expect( emitted.last.map( ( i ) => i.text ).toList(), [ "first", "second", "third" ] );

      // current completes ⇒ 'second' becomes current
      completeCtrl.add( const TtsCompleteEvent() );
      await Future<void>.delayed( Duration.zero );
      expect( o.queueSnapshot.first.text, "second" );
      expect( o.queueSnapshot.first.isCurrent, isTrue );
      await sub.cancel();
    } );

    test( "queue viewer: skipCurrent stops the player and advances; removeQueued drops ONE pending by id; clearQueued keeps the current one", () async {
      await setUpMocks();
      final o = newOrch();
      o.enqueueAlways( priority: "low", message: "a" );
      await Future<void>.delayed( Duration.zero );
      o.enqueueAlways( priority: "low", message: "b" );
      o.enqueueAlways( priority: "low", message: "c" );
      o.enqueueAlways( priority: "low", message: "d" );
      await Future<void>.delayed( Duration.zero );
      expect( o.queueSnapshot.map( ( i ) => i.text ).toList(), [ "a", "b", "c", "d" ] );

      final cId = o.queueSnapshot.firstWhere( ( i ) => i.text == "c" ).id;
      expect( o.removeQueued( cId ), isTrue );
      expect( o.removeQueued( cId ), isFalse, reason: "already gone" );
      expect( o.queueSnapshot.map( ( i ) => i.text ).toList(), [ "a", "b", "d" ] );
      expect( o.removeQueued( o.queueSnapshot.first.id ), isFalse, reason: "the in-flight one is not removable here" );

      await o.skipCurrent();
      await Future<void>.delayed( Duration.zero );
      verify( () => player.stop() ).called( 1 );
      expect( o.queueSnapshot.map( ( i ) => i.text ).toList(), [ "b", "d" ] );
      expect( o.queueSnapshot.first.isCurrent, isTrue, reason: "b dispatched after the skip" );
      verify( () => player.speak( text: "b", sessionId: any( named: "sessionId" ), voiceId: any( named: "voiceId" ) ) ).called( 1 );

      // a stale completion for the skipped utterance must NOT double-advance
      completeCtrl.add( const TtsCompleteEvent() );
      await Future<void>.delayed( Duration.zero );
      expect( o.queueSnapshot.map( ( i ) => i.text ).toList(), [ "d" ], reason: "completion belongs to b (current epoch) ⇒ advance once" );

      o.enqueueAlways( priority: "low", message: "e" );
      o.clearQueued();
      expect( o.queueSnapshot.map( ( i ) => i.text ).toList(), [ "d" ], reason: "clearQueued drops pending only" );
      expect( o.queueDepth, 0 );
      await o.skipCurrent();
      expect( o.queueSnapshot, isEmpty );
      await o.skipCurrent();   // idle: no-op, no throw
    } );

    test( "system-sender gate: speakSystemSenders=false mutes persona-less senders on BOTH entry points; personas still speak; default is ON", () async {
      await setUpMocks();
      expect( prefs.speakSystemSenders, isTrue );
      await prefs.setSpeakSystemSenders( false );
      final o = newOrch();
      const tiff = TtsSender( senderId: "cc#1", name: "Tiffany", icon: "💍" );
      const sys  = TtsSender( senderId: "hooks@lupin#9" );

      o.enqueueAlways( priority: "high", message: "sys-always",  sender: sys );
      o.enqueueAlways( priority: "high", message: "none-always" );              // unknown sender ⇒ system
      o.enqueueIfSpeakable( priority: "high", message: "sys-speakable", sender: sys );
      o.enqueueAlways( priority: "high", message: "tiff-always", sender: tiff );
      o.enqueueIfSpeakable( priority: "high", message: "tiff-speakable", sender: tiff );
      await Future<void>.delayed( Duration.zero );
      expect( o.queueSnapshot.map( ( i ) => i.text ).toList(), [ "tiff-always", "tiff-speakable" ] );

      await prefs.setSpeakSystemSenders( true );
      o.enqueueAlways( priority: "high", message: "sys-now-ok", sender: sys );
      expect( o.queueSnapshot.map( ( i ) => i.text ).toList(), [ "tiff-always", "tiff-speakable", "sys-now-ok" ] );
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

  // S1 — TTS pause/resume + enqueueAlways (focus-mode-voice-chat milestone,
  // 10-section-s1-tts-pause-resume.md §5, AC-S1.1–S1.11). The mock player
  // mirrors the wire-grounded semantics (testing-strategy rule 4 /
  // F-S1-S3-1): `stop()` emits NOTHING on `completeStream`
  // (streaming_tts_player.dart:162-176, :242-249).
  group( "TtsOrchestrator S1 — pause/resume + enqueueAlways", () {
    late _MockPlayer   player;
    late _MockFallback fallback;
    late _MockWs       ws;
    late NotificationPreferences prefs;
    late StreamController<TtsCompleteEvent> completeCtrl;
    late StreamController<TtsErrorEvent>    errorCtrl;
    late List<String> spoken;          // player.speak texts, in call order
    late List<String> fallbackSpoken;  // flutterTtsSpeak texts, in call order
    TtsOrchestrator? orch;

    Future<void> setUpMocks( {
      String? sessionId = "wise penguin",
    } ) async {
      SharedPreferences.setMockInitialValues( {} );
      final sp = await SharedPreferences.getInstance();
      prefs = NotificationPreferences( sp );

      player         = _MockPlayer();
      fallback       = _MockFallback();
      ws             = _MockWs();
      completeCtrl   = StreamController<TtsCompleteEvent>.broadcast();
      errorCtrl      = StreamController<TtsErrorEvent>   .broadcast();
      spoken         = [];
      fallbackSpoken = [];

      when( () => player.completeStream ).thenAnswer( ( _ ) => completeCtrl.stream );
      when( () => player.errorStream    ).thenAnswer( ( _ ) => errorCtrl   .stream );
      when( () => player.isPlaying      ).thenReturn( false );
      when( () => player.speak(
        text      : any( named: "text"      ),
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId"   ),
      ) ).thenAnswer( ( inv ) async {
        spoken.add( inv.namedArguments[ #text ] as String );
      } );
      when( () => player.stop() ).thenAnswer( ( _ ) async {} );

      when( () => fallback.flutterTtsSpeak( any() ) ).thenAnswer( ( inv ) async {
        fallbackSpoken.add( inv.positionalArguments.first as String );
      } );
      when( () => fallback.stopFallbackSpeech() ).thenAnswer( ( _ ) async {} );

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

    Future<void> pump() => Future<void>.delayed( Duration.zero );

    Future<void> completeUtterance() async {
      completeCtrl.add( const TtsCompleteEvent() );
      await pump();
    }

    tearDown( () async {
      await orch?.dispose();
      await completeCtrl.close();
      await errorCtrl   .close();
    } );

    test( "AC-S1.1 — pause() then 3 enqueueAlways (incl. low): nothing speaks, queue holds 3", () async {
      await setUpMocks();
      final o = newOrch();

      o.pause();
      o.enqueueAlways( priority: "low",    message: "one"   );
      o.enqueueAlways( priority: "medium", message: "two"   );
      o.enqueueAlways( priority: "high",   message: "three" );
      await pump();

      verifyNever( () => player.speak(
        text      : any( named: "text" ),
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId" ),
      ) );
      verifyNever( () => fallback.flutterTtsSpeak( any() ) );
      expect( o.queueDepth, 3 );
    } );

    test( "AC-S1.2 — resume() drains accumulated utterances in arrival order", () async {
      await setUpMocks();
      final o = newOrch();

      o.pause();
      o.enqueueAlways( priority: "low",    message: "one"   );
      o.enqueueAlways( priority: "medium", message: "two"   );
      o.enqueueAlways( priority: "high",   message: "three" );
      await pump();

      o.resume();
      await pump();
      await completeUtterance();
      await completeUtterance();
      await completeUtterance();

      expect( spoken, [ "one", "two", "three" ] );
      expect( o.queueDepth, 0 );
    } );

    test( "AC-S1.3 — pause during in-flight: current completes via the completion seam, next does NOT start", () async {
      await setUpMocks();
      final o = newOrch();

      o.enqueueAlways( priority: "high", message: "in-flight" );
      await pump();
      expect( spoken, [ "in-flight" ] );

      o.pause();
      o.enqueueAlways( priority: "high", message: "held" );
      await pump();

      await completeUtterance();   // _player.completeStream → _onUtteranceFinished honored

      expect( spoken, [ "in-flight" ], reason: "held utterance must not start under pause" );
      expect( o.queueDepth, 1 );
      expect( o.isPlaying, isFalse, reason: "completion cleared the current slot" );
    } );

    test( "AC-S1.4 — urgent while paused: no preempt; two urgents drain arrival-ordered ahead of non-urgents", () async {
      await setUpMocks();
      final o = newOrch();

      o.pause();
      o.enqueueAlways( priority: "medium", message: "N1" );
      o.enqueueAlways( priority: "urgent", message: "U1" );
      o.enqueueAlways( priority: "urgent", message: "U2" );
      await pump();

      verifyNever( () => player.stop() );
      expect( spoken, isEmpty );
      expect( o.queueDepth, 3 );

      o.resume();
      await pump();
      expect( spoken, [ "U1" ], reason: "urgent plays FIRST on resume" );
      await completeUtterance();
      expect( spoken, [ "U1", "U2" ], reason: "no LIFO inversion — urgent block arrival-ordered" );
      await completeUtterance();
      expect( spoken, [ "U1", "U2", "N1" ] );
      await completeUtterance();
      expect( o.queueDepth, 0 );
    } );

    test( "AC-S1.5 — quota window opened pre-pause: resumed utterances route via flutter_tts fallback", () async {
      await setUpMocks();
      final o = newOrch();

      o.enqueueAlways( priority: "high", message: "first" );
      await pump();
      errorCtrl.add( const TtsErrorEvent( errorCode: "quota_exceeded" ) );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );
      expect( fallbackSpoken, [ "first" ], reason: "quota error re-speaks current via fallback" );

      o.pause();
      o.enqueueAlways( priority: "medium", message: "held one" );
      o.enqueueAlways( priority: "low",    message: "held two" );
      await pump();
      expect( fallbackSpoken, [ "first" ] );

      o.resume();
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      expect( fallbackSpoken, [ "first", "held one", "held two" ] );
      expect( spoken, [ "first" ], reason: "ElevenLabs got only the pre-window dispatch" );
    } );

    test( "AC-S1.7 — urgent while UNPAUSED: non-destructive preempt, replay-from-start, nothing dropped, exactly one post-preempt dispatch", () async {
      await setUpMocks();
      final o = newOrch();

      o.enqueueAlways( priority: "medium", message: "current" );
      await pump();
      expect( spoken, [ "current" ] );

      o.enqueueAlways( priority: "low",    message: "q1" );
      o.enqueueAlways( priority: "medium", message: "q2" );
      o.enqueueAlways( priority: "high",   message: "q3" );
      await pump();
      expect( o.queueDepth, 3 );

      o.enqueueAlways( priority: "urgent", message: "URGENT" );
      await pump();

      verify( () => player.stop() ).called( 1 );
      // F-S1-S3-1: exactly ONE dispatch follows the preempt, asserted via
      // TOTAL speak-call count — the mock's stop() emitted nothing on
      // completeStream, so no completion-driven double-advance can hide here.
      expect( spoken, [ "current", "URGENT" ] );
      expect( o.queueDepth, 4, reason: "interrupted utterance re-queued at the front — nothing dropped" );

      await completeUtterance();   // URGENT finishes
      expect( spoken, [ "current", "URGENT", "current" ],
        reason: "interrupted utterance replays from the start" );
      await completeUtterance();
      await completeUtterance();
      await completeUtterance();
      await completeUtterance();
      expect( spoken, [ "current", "URGENT", "current", "q1", "q2", "q3" ] );
      expect( o.queueDepth, 0 );
    } );

    test( "AC-S1.7 ext (F-S1-S2-1b) — urgent does NOT preempt an in-flight urgent", () async {
      await setUpMocks();
      final o = newOrch();

      o.enqueueAlways( priority: "urgent", message: "U1" );
      await pump();
      expect( spoken, [ "U1" ] );

      o.enqueueAlways( priority: "urgent", message: "U2" );
      await pump();

      verifyNever( () => player.stop() );
      expect( spoken, [ "U1" ], reason: "U2 waits — replay churn avoided under urgent bursts" );

      await completeUtterance();
      expect( spoken, [ "U1", "U2" ] );
    } );

    test( "AC-S1.8 — enqueueAlways bypasses masterMute AND priority gates: low speaks while everything is muted", () async {
      await setUpMocks();
      await prefs.setMasterMute( true );
      await prefs.setSpeakOnHigh( false );
      await prefs.setSpeakOnUrgent( false );
      final o = newOrch();

      o.enqueueAlways( priority: "low", message: "ungated low" );
      await pump();

      expect( spoken, [ "ungated low" ] );
    } );

    test( "AC-S1.9 sub-case (F-S1-S2-2) — legacy urgent while paused PREEMPTS: pause-exempt by design", () async {
      await setUpMocks();
      final o = newOrch();

      o.pause();
      o.enqueueAlways( priority: "medium", message: "held focus item" );
      await pump();
      expect( o.queueDepth, 1 );

      o.enqueueIfSpeakable( priority: "urgent", message: "LEGACY URGENT" );
      await pump();

      verify( () => player.stop() ).called( 1 );
      expect( spoken, [ "LEGACY URGENT" ], reason: "legacy urgent dispatches directly despite pause" );
      expect( o.queueDepth, 0, reason: "legacy flush behavior verbatim — pending cleared" );
    } );

    test( "AC-S1.10 — ElevenLabs error while paused: queue does not advance; resume drains normally", () async {
      await setUpMocks();
      final o = newOrch();

      o.enqueueAlways( priority: "high", message: "erroring" );
      await pump();
      o.enqueueAlways( priority: "medium", message: "next up" );
      await pump();
      expect( spoken, [ "erroring" ] );

      o.pause();
      errorCtrl.add( const TtsErrorEvent( errorCode: "server_error" ) );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      expect( spoken, [ "erroring" ], reason: "error continuation parks at the _tryStartNext gate" );
      expect( o.queueDepth, 1 );

      o.resume();
      await pump();
      expect( spoken, [ "erroring", "next up" ] );
    } );

    test( "AC-S1.11 — queueDepthStream emits 1,2,3 under hold and decrements to 0 on resume drain", () async {
      await setUpMocks();
      final o = newOrch();
      final depths = <int>[];
      final sub    = o.queueDepthStream.listen( depths.add );

      o.pause();
      o.enqueueAlways( priority: "low",    message: "a" );
      o.enqueueAlways( priority: "medium", message: "b" );
      o.enqueueAlways( priority: "high",   message: "c" );
      await pump();
      expect( depths, [ 1, 2, 3 ] );

      o.resume();
      await pump();
      await completeUtterance();
      await completeUtterance();
      await completeUtterance();

      expect( depths, [ 1, 2, 3, 2, 1, 0 ] );
      await sub.cancel();
    } );

    test( "F-S1-IMPL-1 — arrival during the preempt-stop await window does NOT double-dispatch", () async {
      await setUpMocks();
      // Hold the preempt open: stop() parks on a test-controlled Completer
      // (the real stop() awaits network/audio teardown — the mock's default
      // microtask completion never exposes the window).
      final stopGate = Completer<void>();
      when( () => player.stop() ).thenAnswer( ( _ ) => stopGate.future );
      final o = newOrch();

      o.enqueueAlways( priority: "medium", message: "current" );
      await pump();
      expect( spoken, [ "current" ] );

      o.enqueueAlways( priority: "urgent", message: "URGENT" );   // enters preempt, parks on stop()
      await pump();
      o.enqueueAlways( priority: "low", message: "arrival" );     // arrives INSIDE the window
      await pump();

      expect( spoken, [ "current" ],
        reason: "preempt owns the slot — the arrival must not idle-dispatch" );

      stopGate.complete();
      await pump();

      expect( spoken, [ "current", "URGENT" ],
        reason: "exactly ONE dispatch follows the preempt (total speak-call count)" );

      await completeUtterance();   // URGENT finishes → interrupted replays
      expect( spoken, [ "current", "URGENT", "current" ] );
      await completeUtterance();   // replay finishes → the window arrival drains
      expect( spoken, [ "current", "URGENT", "current", "arrival" ] );
      expect( o.queueDepth, 0, reason: "nothing dropped" );
    } );

    test( "pausedStream — emits transitions only; idempotent pause()/resume() do not re-emit", () async {
      await setUpMocks();
      final o      = newOrch();
      final states = <bool>[];
      final sub    = o.pausedStream.listen( states.add );

      o.pause();
      o.pause();    // idempotent — no second emission
      o.resume();
      o.resume();   // idempotent — no second emission
      await pump();

      expect( states, [ true, false ] );
      expect( o.isPaused, isFalse );
      await sub.cancel();
    } );
  
    // ── stop-list gate (plan 2026.08.21 §3: checked = hide + MUTE) ──────
    test( "stop-list: a matched message is muted on enqueueIfSpeakable even at high priority", () async {
      await setUpMocks();
      final sp = await SharedPreferences.getInstance();
      final sl = NotificationStopList( sp );
      orch = TtsOrchestrator( player: player, fallback: fallback, prefs: prefs, ws: ws, stopList: sl );
      orch!.enqueueIfSpeakable( priority: "high", message: "Done: Bash ls", title: "Tiffany" );
      await Future<void>.delayed( Duration.zero );
      verifyNever( () => player.speak( text: any( named: "text" ), sessionId: any( named: "sessionId" ), voiceId: any( named: "voiceId" ) ) );
      expect( orch!.queueDepth, 0 );

      orch!.enqueueIfSpeakable( priority: "high", message: "Build finished", title: "Tiffany" );
      await Future<void>.delayed( Duration.zero );
      verify( () => player.speak( text: "Tiffany. Build finished", sessionId: any( named: "sessionId" ), voiceId: any( named: "voiceId" ) ) ).called( 1 );
    } );

    test( "stop-list: the UNGATED focus path (enqueueAlways) is still muted by a checked pattern — and unmuted when unchecked", () async {
      await setUpMocks();
      final sp = await SharedPreferences.getInstance();
      final sl = NotificationStopList( sp );
      orch = TtsOrchestrator( player: player, fallback: fallback, prefs: prefs, ws: ws, stopList: sl );
      orch!.enqueueAlways( priority: "low", message: "Done: mcp__cosa-voice__notify", title: null );
      await Future<void>.delayed( Duration.zero );
      verifyNever( () => player.speak( text: any( named: "text" ), sessionId: any( named: "sessionId" ), voiceId: any( named: "voiceId" ) ) );

      await sl.setEnabled( 0, false );   // Done: mcp off
      orch!.enqueueAlways( priority: "low", message: "Done: mcp__cosa-voice__notify", title: null );
      await Future<void>.delayed( Duration.zero );
      verify( () => player.speak( text: "Done: mcp__cosa-voice__notify", sessionId: any( named: "sessionId" ), voiceId: any( named: "voiceId" ) ) ).called( 1 );
    } );

    // TTS preview fraction (Rick 2026-08-21, web #cc-tts-fraction-slider parity)
    test( "fraction: a long message is cut to the first sentence(s) at 30%; title spoken whole", () async {
      await setUpMocks();
      await prefs.setTtsFraction( 0.3 );
      final o = newOrch();
      final long = List.generate( 6, ( i ) => "Sentence number ${i + 1} is here and long enough." ).join( " " );
      o.enqueueAlways( priority: "low", message: long, title: "Tiffany" );
      await Future<void>.delayed( Duration.zero );
      final captured = verify( () => player.speak( text: captureAny( named: "text" ), sessionId: any( named: "sessionId" ), voiceId: any( named: "voiceId" ) ) ).captured;
      final spoken = captured.single as String;
      expect( spoken, startsWith( "Tiffany. Sentence number 1" ) );
      expect( spoken.length, lessThan( long.length ) );
      expect( spoken, endsWith( "." ) );
    } );

    test( "fraction: 100% speaks the whole message; short messages are never cut", () async {
      await setUpMocks();
      await prefs.setTtsFraction( 1.0 );
      final o = newOrch();
      final long = List.generate( 6, ( i ) => "Sentence number ${i + 1} is here and long enough." ).join( " " );
      o.enqueueAlways( priority: "low", message: long, title: null );
      await Future<void>.delayed( Duration.zero );
      verify( () => player.speak( text: long, sessionId: any( named: "sessionId" ), voiceId: any( named: "voiceId" ) ) ).called( 1 );

      // Fresh orchestrator: the first utterance is still "current" (one at a
      // time), so a second enqueue on `o` would queue, not speak.
      await o.dispose();
      await setUpMocks();
      await prefs.setTtsFraction( 0.0 );
      final o2 = newOrch();
      o2.enqueueAlways( priority: "low", message: "Build finished", title: null );
      await Future<void>.delayed( Duration.zero );
      verify( () => player.speak( text: "Build finished", sessionId: any( named: "sessionId" ), voiceId: any( named: "voiceId" ) ) ).called( 1 );
    } );
  } );
}
