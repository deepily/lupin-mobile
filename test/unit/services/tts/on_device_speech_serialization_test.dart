/// On-device speech is serialized, bounded and always reachable (TTS rounds 3 and 4, 2026-10-10).
///
/// Thirteen driven scenarios over the REAL `NotificationAudioService` (on a mocked `FlutterTts`) and a REAL
/// `TtsOrchestrator`, so the contract between the two is exercised, not each half against a mock of the other:
///   - B1-B5  a backlog of on-device messages stays outside the engine; Skip, Stop-all, the microphone hold,
///            an urgent arrival and pause all reach the speech
///   - C1, C2 the service's completion bound releases the queue, and the orchestrator's outer bound is strictly longer
///   - D1     pressing the mic again while a drained utterance speaks must not wait for that utterance
///   - R1     an engine's late cancel callback cannot release the utterance that is speaking now
///   - E1     the outer bound firing first does not let the abandoned call's late timeout cut the next one
///   - Q1     a quota error keeps the utterance in flight while it is re-spoken on-device, and says so on screen
///   - X1     nothing is dispatched after dispose
///   - N1     a stream that finished with no audio reads "failed", not "spoken"
///
/// Written by Chloe as review scenarios against 3e6bd33 and 4308765, adopted here as a regression suite.
library;

import 'dart:async';
import 'dart:ui' show VoidCallback;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';
import 'package:lupin_mobile/services/tts/streaming_tts_player.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';

class _MockPlayer extends Mock implements StreamingTtsPlayer {}
class _MockWs     extends Mock implements WebSocketService {}
class _MockTts    extends Mock implements FlutterTts {}
class _MockFln    extends Mock implements FlutterLocalNotificationsPlugin {}

int stopDelayMs  = 2;
int speakDelayMs = 0;

void main() {
  late _MockPlayer player;
  late _MockWs     ws;
  late _MockTts    tts;
  late StreamController<TtsCompleteEvent> completeCtrl;
  late StreamController<TtsErrorEvent>    errorCtrl;
  late List<String> spoken;     // every text handed to the engine, in order
  late int          stops;      // engine stop() calls
  VoidCallback?     onComplete;
  VoidCallback?     onCancel;
  late NotificationAudioService service;
  late TtsOrchestrator          orch;

  Future<void> build( {
    Duration accept      = const Duration( milliseconds: 100 ),
    Duration completion  = const Duration( milliseconds: 200 ),
    Duration outerAccept = const Duration( milliseconds: 100 ),
    Duration outerPlay   = const Duration( milliseconds: 200 ),
  } ) async {
    SharedPreferences.setMockInitialValues( {} );
    final prefs = NotificationPreferences( await SharedPreferences.getInstance() );
    player = _MockPlayer();
    ws     = _MockWs();
    tts    = _MockTts();
    completeCtrl = StreamController<TtsCompleteEvent>.broadcast();
    errorCtrl    = StreamController<TtsErrorEvent>.broadcast();
    final mySpoken = <String>[];
    spoken     = mySpoken;
    stops      = 0;
    onComplete = null;
    onCancel   = null;

    when( () => player.completeStream ).thenAnswer( ( _ ) => completeCtrl.stream );
    when( () => player.errorStream    ).thenAnswer( ( _ ) => errorCtrl.stream );
    when( () => player.isPlaying      ).thenReturn( false );
    when( () => player.isAudioPlaying ).thenReturn( false );
    when( () => player.lastActivityAt ).thenReturn( null );
    when( () => player.stop()         ).thenAnswer( ( _ ) async {} );
    when( () => ws.sessionId          ).thenReturn( null );   // every utterance takes the on-device path

    when( () => tts.setCompletionHandler( any() ) ).thenAnswer( ( inv ) { onComplete = inv.positionalArguments.first as VoidCallback; } );
    when( () => tts.setCancelHandler( any() )     ).thenAnswer( ( inv ) { onCancel   = inv.positionalArguments.first as VoidCallback; } );
    when( () => tts.setErrorHandler( any() )      ).thenAnswer( ( _ ) {} );
    when( () => tts.stop() ).thenAnswer( ( _ ) async {
      await Future<void>.delayed( Duration( milliseconds: stopDelayMs ) );
      stops++;
      return 1;
    } );
    when( () => tts.speak( any() ) ).thenAnswer( ( inv ) async {
      if ( speakDelayMs > 0 ) await Future<void>.delayed( Duration( milliseconds: speakDelayMs ) );
      mySpoken.add( inv.positionalArguments.first as String );
      return 1;
    } );

    service = NotificationAudioService(
      prefs: prefs, plugin: _MockFln(), tts: tts,
      speakAcceptBudget: accept, completionBound: completion,
    );
    orch = TtsOrchestrator(
      player: player, fallback: service, prefs: prefs, ws: ws,
      fallbackSpeakBudget: outerAccept, maxPlayback: outerPlay,
    );
  }

  Future<void> pump() => Future<void>.delayed( const Duration( milliseconds: 30 ) );

  tearDown( () async {
    await orch.dispose();
    await completeCtrl.close();
    await errorCtrl.close();
  } );

  test( "B1 burst of three: only the first is in the engine until it finishes; Skip reaches it", () async {
    await build();
    orch.enqueueAlways( priority: "high", message: "one" );
    orch.enqueueAlways( priority: "high", message: "two" );
    orch.enqueueAlways( priority: "high", message: "three" );
    await pump();
    expect( spoken, [ "one" ], reason: "serialized: later ones wait outside the engine" );
    expect( orch.isPlaying, isTrue );
    expect( orch.queueSnapshot.first.isCurrent, isTrue, reason: "Skip button is shown for it" );

    unawaited( orch.skipCurrent() );
    await pump();
    expect( spoken, [ "one", "two" ] );
    expect( stops, greaterThanOrEqualTo( 1 ) );
  } );

  test( "B2 Stop-all reaches an on-device utterance and clears the rest", () async {
    await build();
    orch.enqueueAlways( priority: "high", message: "one" );
    orch.enqueueAlways( priority: "high", message: "two" );
    await pump();
    final before = stops;
    await orch.stopAll();
    await pump();
    expect( stops, greaterThan( before ) );
    expect( spoken, [ "one" ] );
    expect( orch.isPlaying, isFalse );
    expect( orch.queueDepth, 0 );
  } );

  test( "B3 mic hold silences the engine whether or not something is in flight; nothing speaks while held", () async {
    await build();
    orch.enqueueAlways( priority: "high", message: "one" );
    await pump();
    final before = stops;
    await orch.setCaptureHold( true );
    expect( stops, greaterThan( before ), reason: "in flight: stopped and requeued" );
    orch.enqueueAlways( priority: "high", message: "two" );
    await pump();
    expect( spoken, [ "one" ], reason: "held: nothing new speaks" );
    final mid = stops;
    unawaited( orch.setCaptureHold( false ) );
    await pump();
    expect( spoken, [ "one", "one" ], reason: "released: the interrupted one replays from the start, the second waits behind it" );
    expect( stops, greaterThanOrEqualTo( mid ) );
  } );

  test( "B4 urgent arriving while an on-device utterance is in flight preempts it, and the interrupted one comes back", () async {
    await build();
    orch.enqueueAlways( priority: "high", message: "normal" );
    await pump();
    orch.enqueueAlways( priority: "urgent", message: "URGENT" );
    await pump();
    expect( spoken.take( 2 ).toList(), [ "normal", "URGENT" ] );
  } );

  test( "B5 pause: an in-flight on-device utterance finishes, then the queue parks", () async {
    await build();
    orch.enqueueAlways( priority: "high", message: "one" );
    await pump();
    orch.pause();
    orch.enqueueAlways( priority: "high", message: "two" );
    onComplete?.call();
    await pump();
    expect( spoken, [ "one" ], reason: "paused: the second must not start" );
    orch.resume();
    await pump();
    expect( spoken, [ "one", "two" ] );
  } );

  test( "C1 a completion callback that never fires still releases the queue at the service bound", () async {
    await build();
    orch.enqueueAlways( priority: "high", message: "one" );
    orch.enqueueAlways( priority: "high", message: "two" );
    await pump();
    expect( spoken, [ "one" ] );
    await Future<void>.delayed( const Duration( milliseconds: 260 ) );   // inner 200 ms + slack, outer is 300 ms
    expect( spoken, [ "one", "two" ], reason: "released without any callback" );
  } );

  test( "C2 the orchestrator's outer bound is strictly longer than the service's inner bounds, at production defaults", () async {
    SharedPreferences.setMockInitialValues( {} );
    final prefs = NotificationPreferences( await SharedPreferences.getInstance() );
    final svc   = NotificationAudioService( prefs: prefs, plugin: _MockFln(), tts: _MockTts() );
    final pl    = _MockPlayer();
    when( () => pl.completeStream ).thenAnswer( ( _ ) => const Stream<TtsCompleteEvent>.empty() );
    when( () => pl.errorStream    ).thenAnswer( ( _ ) => const Stream<TtsErrorEvent>.empty() );
    final o     = TtsOrchestrator( player: pl, fallback: svc, prefs: prefs, ws: _MockWs() );
    addTearDown( () => o.dispose() );
    for ( final n in [ 0, 8, 80, 800 ] ) {
      final text  = "x" * n;
      final inner = svc.speakAcceptBudget + svc.completionBoundFor( text );
      final outer = o.fallbackOuterBound( text );
      expect( outer, greaterThan( inner ), reason: "outer must exceed the inner sum for $n chars" );
    }
  } );

  test( "R1 stale cancel callback from the stopped utterance arrives after the next speak was accepted", () async {
    await build( completion: const Duration( seconds: 5 ), outerPlay: const Duration( seconds: 5 ) );
    orch.enqueueAlways( priority: "high", message: "A" );
    orch.enqueueAlways( priority: "high", message: "B" );
    orch.enqueueAlways( priority: "high", message: "C" );
    await pump();
    expect( spoken, [ "A" ] );

    unawaited( orch.skipCurrent() );   // engine.stop(); B is dispatched and accepted
    await pump();
    expect( spoken, [ "A", "B" ] );

    verifyNever( () => tts.setCancelHandler( any() ) );   // no cancel handler is registered at all
    onCancel?.call();           // the engine's late "cancelled" callback for A arrives now (a no-op once dropped)
    await pump();
    expect( spoken, [ "A", "B" ], reason: "B is still speaking; C must not start on A's stale callback" );
  } );

  test( "D1 mic pressed again while a drained on-device utterance speaks: the second hold's stop must not wait for that utterance", () async {
    await build( completion: const Duration( seconds: 3 ), outerPlay: const Duration( seconds: 3 ) );
    orch.enqueueAlways( priority: "high", message: "X" );
    await pump();
    expect( spoken, [ "X" ] );

    unawaited( orch.setCaptureHold( true ) );    // mic on: stop and requeue X
    await pump();
    unawaited( orch.setCaptureHold( false ) );   // mic off: drain, X speaks again on-device
    await pump();
    expect( spoken, [ "X", "X" ] );
    final before = stops;

    unawaited( orch.setCaptureHold( true ) );    // mic on again, while X is speaking
    await pump();
    expect( stops, greaterThan( before ), reason: "the engine must be stopped now, not when X finishes" );
  } );

  test( "E1 outer bound fires first (slow stop plus slow accept): the abandoned call's late timeout must not cut the next utterance", () async {
    stopDelayMs  = 20;
    speakDelayMs = 90;
    addTearDown( () { stopDelayMs = 2; speakDelayMs = 0; } );
    await build( accept: const Duration( milliseconds: 100 ), completion: const Duration( milliseconds: 200 ),
                 outerAccept: const Duration( milliseconds: 100 ), outerPlay: const Duration( milliseconds: 200 ) );
    orch.enqueueAlways( priority: "high", message: "one" );
    orch.enqueueAlways( priority: "high", message: "two" );
    orch.enqueueAlways( priority: "high", message: "three" );
    await Future<void>.delayed( const Duration( milliseconds: 700 ) );
    // 'one' is abandoned by the outer bound; 'two' then starts. Nothing finished 'two' yet, so 'three' must wait.
    expect( spoken, [ "one", "two" ], reason: "'two' is still speaking (its own bound runs from when it started)" );
  } );

  test( "Q1 quota error: the utterance keeps _current while it speaks on-device, and the line says it was re-spoken", () async {
    await build();
    when( () => ws.sessionId ).thenReturn( "s" );
    when( () => player.speak(
      text: any( named: "text" ), sessionId: any( named: "sessionId" ), voiceId: any( named: "voiceId" ),
    ) ).thenAnswer( ( _ ) async {} );
    orch.enqueueAlways( priority: "high", message: "first" );
    orch.enqueueAlways( priority: "high", message: "second" );
    await pump();
    errorCtrl.add( const TtsErrorEvent( errorCode: "quota_exceeded" ) );
    await pump();
    expect( spoken, [ "first" ], reason: "first re-spoken on-device; second waits" );
    expect( orch.isPlaying, isTrue );
    expect( orch.queueSnapshot.first.isCurrent, isTrue );
    expect( orch.lastOutcome!.line, "Spoken on this phone's own voice: the voice service is over quota",
        reason: "a quota error is a re-speak, not a failure the user has to act on" );
    expect( orch.lastOutcome!.line, isNot( contains( "quota_exceeded" ) ) );
    onComplete?.call();
    await pump();
    expect( spoken, [ "first", "second" ], reason: "second goes on-device through the quota window" );
  } );

  test( "Q2 any other server error still reads as a failure with its code", () async {
    await build();
    when( () => ws.sessionId ).thenReturn( "s" );
    when( () => player.speak(
      text: any( named: "text" ), sessionId: any( named: "sessionId" ), voiceId: any( named: "voiceId" ),
    ) ).thenAnswer( ( _ ) async {} );
    orch.enqueueAlways( priority: "high", message: "first" );
    await pump();
    errorCtrl.add( const TtsErrorEvent( errorCode: "auth_error" ) );
    await pump();
    expect( orch.lastOutcome!.line, "Last message failed: auth_error" );
    expect( orch.lastOutcome!.problem, isTrue );
  } );

  test( "X1 dispose with an on-device utterance in flight: nothing is dispatched afterwards", () async {
    await build();
    orch.enqueueAlways( priority: "high", message: "one" );
    orch.enqueueAlways( priority: "high", message: "two" );
    await pump();
    expect( spoken, [ "one" ] );
    await orch.dispose();
    onComplete?.call();
    await pump();
    expect( spoken, [ "one" ], reason: "disposed: 'two' must not reach the engine" );
  } );

  test( "N1 empty-audio completion reads failed, not spoken", () async {
    await build();
    when( () => ws.sessionId ).thenReturn( "s" );
    when( () => player.speak(
      text: any( named: "text" ), sessionId: any( named: "sessionId" ), voiceId: any( named: "voiceId" ),
    ) ).thenAnswer( ( _ ) async {} );
    orch.enqueueAlways( priority: "high", message: "silent stream" );
    await pump();
    completeCtrl.add( const TtsCompleteEvent( played: false ) );
    await pump();
    expect( orch.lastOutcome!.line, "Last message failed: the server sent no audio" );
  } );
}
