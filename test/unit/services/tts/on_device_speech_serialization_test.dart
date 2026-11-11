/// On-device speech is serialized, bounded and always reachable (TTS rounds 3 and 4, 2026-10-10).
///
/// Fifteen driven scenarios on the real `NotificationAudioService`, with a mocked `FlutterTts`, and a real
/// `TtsOrchestrator`. The contract between the two is exercised, not each half against a mock of the other:
///   - B1-B5  a backlog of on-device messages stays outside the engine; Skip, Stop-all, the microphone hold,
///            an urgent arrival and pause all reach the speech
///   - C1, C2 the service's completion bound releases the queue, and the orchestrator's outer bound is strictly longer
///   - D1     pressing the mic again while a drained utterance speaks must not wait for that utterance
///   - R1     an engine's late cancel callback cannot release the utterance that is speaking now
///   - G1: an engine that never accepts the text is released by the service's accept budget
///   - G2: a service that never returns is released by the orchestrator's outer bound
///   - E1     the outer bound firing first does not let the abandoned call's late timeout cut the next one
///   - Q1     a quota error keeps the utterance in flight while it is re-spoken on-device, and says so on screen
///   - X1     nothing is dispatched after dispose
///   - N1     a stream that finished with no audio reads "failed", not "spoken"
///
/// Written by Chloe as review scenarios against 3e6bd33 and 4308765, adopted here as a regression suite.
library;

import 'dart:async';
import 'dart:ui' show VoidCallback;

import 'package:fake_async/fake_async.dart';
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
class _MockSvc    extends Mock implements NotificationAudioService {}
class _MockFln    extends Mock implements FlutterLocalNotificationsPlugin {}

int  stopDelayMs   = 2;
int  speakDelayMs  = 0;
bool hangFirstSpeak = false;   // G1: the engine never accepts the first text

void main() {
  late _MockPlayer player;
  late _MockWs     ws;
  late _MockTts    tts;
  late StreamController<TtsCompleteEvent> completeCtrl;
  late StreamController<TtsErrorEvent>    errorCtrl;
  late List<String> spoken;     // every text the engine accepted, in order
  late List<String> attempts;   // every text handed to the engine, accepted or not
  late int          stops;      // engine stop() calls
  VoidCallback?     onComplete;
  VoidCallback?     onCancel;
  late NotificationAudioService service;
  late TtsOrchestrator          orch;
  var built = false;            // build() ran; C2 builds its own orchestrator, so the shared tearDown skips it

  Future<void> build( {
    Duration accept      = const Duration( milliseconds: 100 ),
    Duration completion  = const Duration( milliseconds: 200 ),
    Duration outerAccept = const Duration( milliseconds: 100 ),
    Duration outerPlay   = const Duration( milliseconds: 200 ),
    Duration outerMargin = const Duration( milliseconds: 5 ),
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
    final myAttempts = <String>[];
    attempts   = myAttempts;
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
      myAttempts.add( inv.positionalArguments.first as String );
      if ( hangFirstSpeak && myAttempts.length == 1 ) await Completer<void>().future;
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
      fallbackSpeakBudget: outerAccept, maxPlayback: outerPlay, fallbackOuterMargin: outerMargin,
    );
    built = true;
  }

  /// Waits 30 ms on the fake clock; the stub delays are on the same clock.
  Future<void> pump() => Future<void>.delayed( const Duration( milliseconds: 30 ) );

  tearDown( () async {
    if ( !built ) return;
    built = false;
    await orch.dispose();
    await completeCtrl.close();
    await errorCtrl.close();
  } );

  /// Runs [body] on a fake clock, like `onFakeTime` in fcm_wake_chain_test.dart.
  ///
  /// Every timer and stub delay is a zone timer, so `FakeAsync` owns them all.
  /// Neither service reads `DateTime.now` on these paths, so no wall-clock time passes.
  /// A cancelled subscription needs the real microtask queue, so the driver yields one real turn per 1 ms step.
  ///
  /// Requires:
  ///   - [body] needs no real I/O
  ///
  /// Ensures:
  ///   - fails if [body] has not finished within one fake minute
  void fakeTest( String name, Future<void> Function() body ) {
    test( name, () async {
      final fa    = FakeAsync();
      Object?     error;
      StackTrace? trace;
      var         done = false;
      fa.run( ( _ ) {
        () async {
          try {
            await body();
          } catch ( e, st ) {
            error = e;
            trace = st;
          }
          done = true;
        }();
      } );
      for ( var i = 0; i < 60000 && !done; i++ ) {
        fa.elapse( const Duration( milliseconds: 1 ) );
        await Future<void>.delayed( Duration.zero );
      }
      if ( !done ) fail( "did not finish within one fake minute: it hung" );
      if ( error != null ) Error.throwWithStackTrace( error!, trace! );
    } );
  }

  fakeTest( "B1 burst of three: only the first is in the engine until it finishes; Skip reaches it", () async {
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

  fakeTest( "B2 Stop-all reaches an on-device utterance and clears the rest", () async {
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

  fakeTest( "B3 mic hold silences the engine whether or not something is in flight; nothing speaks while held", () async {
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

  fakeTest( "B4 urgent arriving while an on-device utterance is in flight preempts it, and the interrupted one comes back", () async {
    await build();
    orch.enqueueAlways( priority: "high", message: "normal" );
    await pump();
    orch.enqueueAlways( priority: "urgent", message: "URGENT" );
    await pump();
    expect( spoken.take( 2 ).toList(), [ "normal", "URGENT" ] );
  } );

  fakeTest( "B5 pause: an in-flight on-device utterance finishes, then the queue parks", () async {
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

  fakeTest( "C1 a completion callback that never fires still releases the queue at the service bound", () async {
    await build();
    orch.enqueueAlways( priority: "high", message: "one" );
    orch.enqueueAlways( priority: "high", message: "two" );
    await pump();
    expect( spoken, [ "one" ] );
    // The service's bound (200 ms) runs from when the engine accepted the text, about 2 ms in; the outer one is longer.
    await Future<void>.delayed( const Duration( milliseconds: 160 ) );   // t = 190 ms: not released early
    expect( spoken, [ "one" ], reason: "the bound has not run out yet, so nothing may release the queue" );
    await Future<void>.delayed( const Duration( milliseconds: 40 ) );    // t = 230 ms: past 200, short of the outer bound
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

  fakeTest( "R1 stale cancel callback from the stopped utterance arrives after the next speak was accepted", () async {
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

  fakeTest( "D1 mic pressed again while a drained on-device utterance speaks: the second hold's stop must not wait for that utterance", () async {
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

  fakeTest( "E1 outer bound fires first (slow stop plus slow accept): the abandoned call's late timeout must not cut the next utterance", () async {
    stopDelayMs  = 60;
    speakDelayMs = 90;
    addTearDown( () { stopDelayMs = 2; speakDelayMs = 0; } );
    // Outer bound = 100 + 200 + 5 = 305 ms. The service alone needs the 60 ms stop, 90 ms to accept
    // and its 200 ms completion bound: 350 ms. So the outer bound abandons 'one' 45 ms earlier.
    await build();
    orch.enqueueAlways( priority: "high", message: "one" );
    orch.enqueueAlways( priority: "high", message: "two" );
    orch.enqueueAlways( priority: "high", message: "three" );
    await Future<void>.delayed( const Duration( milliseconds: 300 ) );
    expect( attempts, [ "one" ], reason: "neither bound has run out at 300 ms" );
    await Future<void>.delayed( const Duration( milliseconds: 80 ) );   // t = 380 ms
    expect( attempts, [ "one", "two" ], reason: "the outer bound (305 ms) released 'one'; the service alone would not have until 350 + 60 ms" );
    await Future<void>.delayed( const Duration( milliseconds: 320 ) );   // t = 700 ms
    // 'one' is abandoned by the outer bound; 'two' then starts. Nothing finished 'two' yet, so 'three' must wait.
    expect( spoken, [ "one", "two" ], reason: "'two' is still speaking: the late 350 ms timeout of 'one' must not release it" );
  } );

  fakeTest( "G1 an engine that never accepts the text releases the queue at the service's accept budget", () async {
    hangFirstSpeak = true;
    addTearDown( () { hangFirstSpeak = false; } );
    await build();   // accept 100 ms, completion 200 ms, outer 5.3 s
    orch.enqueueAlways( priority: "high", message: "one" );
    orch.enqueueAlways( priority: "high", message: "two" );
    await Future<void>.delayed( const Duration( milliseconds: 90 ) );
    expect( attempts, [ "one" ], reason: "the accept budget (100 ms from the engine call, about 2 ms in) has not run out" );
    await Future<void>.delayed( const Duration( milliseconds: 40 ) );   // t = 130 ms: past 102, far short of every other bound
    expect( attempts, [ "one", "two" ], reason: "released by the accept budget, not by the completion or outer bound" );
  } );

  fakeTest( "G2 a service that never returns releases the queue at the orchestrator's outer bound", () async {
    SharedPreferences.setMockInitialValues( {} );
    final prefs = NotificationPreferences( await SharedPreferences.getInstance() );
    final svc   = _MockSvc();
    final calls = <String>[];
    when( () => svc.stopFallbackSpeech() ).thenAnswer( ( _ ) async {} );
    when( () => svc.flutterTtsSpeak( any() ) ).thenAnswer( ( inv ) {
      calls.add( inv.positionalArguments.first as String );
      return calls.length == 1 ? Completer<void>().future : Future<void>.value();
    } );
    final pl = _MockPlayer();
    when( () => pl.completeStream ).thenAnswer( ( _ ) => const Stream<TtsCompleteEvent>.empty() );
    when( () => pl.errorStream    ).thenAnswer( ( _ ) => const Stream<TtsErrorEvent>.empty() );
    final o = TtsOrchestrator(
      player: pl, fallback: svc, prefs: prefs, ws: _MockWs(),
      fallbackSpeakBudget: const Duration( milliseconds: 100 ), maxPlayback: const Duration( milliseconds: 200 ),
      fallbackOuterMargin: const Duration( milliseconds: 50 ),
    );   // outer bound = 100 + 200 + 50 = 350 ms
    o.enqueueAlways( priority: "high", message: "one" );
    o.enqueueAlways( priority: "high", message: "two" );
    await Future<void>.delayed( const Duration( milliseconds: 340 ) );
    expect( calls, [ "one" ], reason: "the outer bound has not run out yet" );
    await Future<void>.delayed( const Duration( milliseconds: 20 ) );   // t = 360 ms
    expect( calls, [ "one", "two" ], reason: "released by the outer bound" );
  } );

  fakeTest( "Q1 quota error: the utterance keeps _current while it speaks on-device, and the line says it was re-spoken", () async {
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

  fakeTest( "Q2 any other server error still reads as a failure with its code", () async {
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

  fakeTest( "X1 dispose with an on-device utterance in flight: nothing is dispatched afterwards", () async {
    await build();
    orch.enqueueAlways( priority: "high", message: "one" );
    orch.enqueueAlways( priority: "high", message: "two" );
    await pump();
    expect( spoken, [ "one" ] );
    unawaited( orch.dispose() );   // the flag flips synchronously; the stream closes finish on their own
    onComplete?.call();
    await pump();
    expect( spoken, [ "one" ], reason: "disposed: 'two' must not reach the engine" );
    built = false;   // the controllers closed on the fake clock; a second close from the shared tearDown would never finish
  } );

  fakeTest( "N1 empty-audio completion reads failed, not spoken", () async {
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
