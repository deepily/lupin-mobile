/// Row 51-hour finding (2026-10-10): a posted utterance whose audio events never arrive left
/// `_current` set for good, so every later notification queued behind it in silence.
///
/// The watchdog gives up on such an utterance after a silence window, speaks it on-device once, and
/// carries on with the queue. It must not fire while audio is playing or events are still arriving.
library;

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
  const window = Duration( milliseconds: 60 );

  late _MockPlayer   player;
  late _MockFallback fallback;
  late _MockWs       ws;
  late StreamController<TtsCompleteEvent> completeCtrl;
  late StreamController<TtsErrorEvent>    errorCtrl;
  late List<String> posted;
  late List<String> onDevice;
  late bool         audioPlaying;
  late DateTime?    lastActivity;
  TtsOrchestrator? orch;

  Future<TtsOrchestrator> newOrch( { Duration? fallbackBudget, Duration? maxPlayback } ) async {
    SharedPreferences.setMockInitialValues( {} );
    final prefs  = NotificationPreferences( await SharedPreferences.getInstance() );
    player       = _MockPlayer();
    fallback     = _MockFallback();
    ws           = _MockWs();
    completeCtrl = StreamController<TtsCompleteEvent>.broadcast();
    errorCtrl    = StreamController<TtsErrorEvent>   .broadcast();
    posted       = [];
    onDevice     = [];
    audioPlaying = false;
    lastActivity = null;

    when( () => player.completeStream   ).thenAnswer( ( _ ) => completeCtrl.stream );
    when( () => player.errorStream      ).thenAnswer( ( _ ) => errorCtrl   .stream );
    when( () => player.isPlaying        ).thenAnswer( ( _ ) => audioPlaying );
    when( () => player.isAudioPlaying   ).thenAnswer( ( _ ) => audioPlaying );
    when( () => player.lastActivityAt   ).thenAnswer( ( _ ) => lastActivity );
    when( () => player.speak(
      text      : any( named: "text"      ),
      sessionId : any( named: "sessionId" ),
      voiceId   : any( named: "voiceId"   ),
    ) ).thenAnswer( ( inv ) async { posted.add( inv.namedArguments[ #text ] as String ); } );
    when( () => player.stop() ).thenAnswer( ( _ ) async {} );
    when( () => fallback.flutterTtsSpeak( any() ) ).thenAnswer( ( inv ) async {
      onDevice.add( inv.positionalArguments.first as String );
    } );
    when( () => fallback.stopFallbackSpeech() ).thenAnswer( ( _ ) async {} );
    when( () => ws.sessionId ).thenReturn( "wise penguin" );

    orch = TtsOrchestrator(
      player: player, fallback: fallback, prefs: prefs, ws: ws, speakWatchdog: window,
      fallbackSpeakBudget: fallbackBudget ?? TtsOrchestrator.defaultFallbackSpeakBudget,
      maxPlayback: maxPlayback,
    );
    return orch!;
  }

  Future<void> pump() => Future<void>.delayed( Duration.zero );
  /// Long enough for one watchdog to fire, short enough that the next utterance's has not.
  Future<void> afterFirst() => Future<void>.delayed( window + const Duration( milliseconds: 30 ) );
  /// Long enough for every armed watchdog to have had its chance.
  Future<void> past() => Future<void>.delayed( window * 3 );

  tearDown( () async {
    await orch?.dispose();
    await completeCtrl.close();
    await errorCtrl   .close();
  } );

  test( "a posted utterance that never completes is spoken on-device once, and the queue moves on", () async {
    final o = await newOrch();

    o.enqueueAlways( priority: "high", message: "first, whose audio is lost" );
    o.enqueueAlways( priority: "high", message: "second" );
    await pump();
    expect( posted, [ "first, whose audio is lost" ], reason: "the second waits behind the first" );

    await afterFirst();
    expect( onDevice, [ "first, whose audio is lost" ], reason: "silence past the window: speak it on-device" );
    expect( posted, [ "first, whose audio is lost", "second" ], reason: "THE BUG: the queue stayed wedged" );
    verify( () => player.stop() ).called( greaterThanOrEqualTo( 1 ) );
  } );

  test( "it does not fire while audio is playing or while events are still arriving", () async {
    final o = await newOrch();

    o.enqueueAlways( priority: "high", message: "long answer" );
    await pump();

    audioPlaying = true;
    await past();
    expect( onDevice, isEmpty, reason: "audio is playing; completion is coming" );

    audioPlaying = false;
    lastActivity = DateTime.now();   // a chunk just arrived
    await Future<void>.delayed( window ~/ 2 );
    expect( onDevice, isEmpty, reason: "an event inside the window restarts the silence" );

    completeCtrl.add( const TtsCompleteEvent() );
    await past();
    expect( onDevice, isEmpty, reason: "a finished utterance is never re-spoken" );
    expect( o.isPlaying, isFalse );
  } );

  test( "a user skip before the window ends cancels the watchdog, so nothing is spoken on-device", () async {
    final o = await newOrch();

    o.enqueueAlways( priority: "high", message: "skipped by the user" );
    await pump();
    expect( posted, [ "skipped by the user" ] );

    await o.skipCurrent();
    await past();
    expect( onDevice, isEmpty, reason: "the utterance was abandoned on purpose; the watchdog must not resurrect it" );
    expect( o.isPlaying, isFalse );
  } );

  group( "the plain outcome line for the speech-queue viewer", () {
    late NotificationPreferences prefs;

    Future<TtsOrchestrator> withPrefs() async {
      final o = await newOrch();   // builds its own prefs; rebuild on shared ones to flip switches
      await o.dispose();
      SharedPreferences.setMockInitialValues( {} );
      prefs = NotificationPreferences( await SharedPreferences.getInstance() );
      orch = TtsOrchestrator( player: player, fallback: fallback, prefs: prefs, ws: ws, speakWatchdog: window );
      return orch!;
    }

    test( "master mute, notifications off and a zero slider each name themselves", () async {
      final o = await withPrefs();

      await prefs.setMasterMute( true );
      o.enqueueAlways( priority: "high", message: "hello there" );
      expect( o.lastOutcome!.line, "Last message not spoken: Master mute is on" );
      expect( o.lastOutcome!.problem, isTrue );

      await prefs.setMasterMute( false );
      await prefs.setEnabled( false );
      o.enqueueAlways( priority: "high", message: "hello there" );
      expect( o.lastOutcome!.line, "Last message not spoken: Notifications are switched off" );

      await prefs.setEnabled( true );
      await prefs.setTtsFraction( 0 );
      o.enqueueAlways( priority: "high", message: "hello there" );
      expect( o.lastOutcome!.line, "Last message not spoken: the TTS slider is at 0%" );
      expect( posted, isEmpty );
    } );

    test( "a paused queue reports held with the count, and a normal send reports ok", () async {
      final o = await withPrefs();

      o.pause();
      o.enqueueAlways( priority: "high", message: "waits" );
      expect( o.lastOutcome!.line, "Held, not spoken yet: speech is paused (1 waiting)" );

      o.resume();
      await pump();
      expect( o.lastOutcome!.line, "Last message sent to the speaker" );
      expect( o.lastOutcome!.problem, isFalse );
    } );
  } );

  group( "review findings on edf2704 (Chloe)", () {
    test( "finding 2: an on-device speak that never returns is abandoned and the queue moves on", () async {
      final o = await newOrch( fallbackBudget: const Duration( milliseconds: 50 ) );
      when( () => ws.sessionId ).thenReturn( null );   // every utterance takes the on-device path, no POST
      final hung = Completer<void>();
      var   calls = 0;
      when( () => fallback.flutterTtsSpeak( any() ) ).thenAnswer( ( inv ) async {
        onDevice.add( inv.positionalArguments.first as String );
        if ( ++calls == 1 ) await hung.future;   // the engine accepts the text and never answers
      } );

      o.enqueueAlways( priority: "high", message: "first, engine hangs" );
      o.enqueueAlways( priority: "high", message: "second" );
      await Future<void>.delayed( const Duration( milliseconds: 200 ) );

      expect( onDevice, [ "first, engine hangs", "second" ], reason: "THE BUG: _current stayed set, zero POSTs, silence" );
      expect( o.lastOutcome!.line, isNot( contains( "did not respond" ) ), reason: "the second spoke fine afterwards" );
      hung.complete();
    } );

    test( "finding 1: a POST that returns after an urgent preempt does not strip the preemptor's watchdog", () async {
      final o = await newOrch();
      final slowPost = Completer<void>();
      var   n = 0;
      when( () => player.speak(
        text      : any( named: "text"      ),
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId"   ),
      ) ).thenAnswer( ( inv ) async {
        posted.add( inv.namedArguments[ #text ] as String );
        if ( ++n == 1 ) await slowPost.future;   // A's acknowledgement is slow
      } );

      o.enqueueAlways( priority: "high", message: "A, slow to be acknowledged" );
      await pump();
      o.enqueueAlways( priority: "urgent", message: "U, urgent" );   // preempts A while its POST is in flight
      await pump();
      expect( posted, [ "A, slow to be acknowledged", "U, urgent" ] );

      slowPost.complete();   // A's POST finally returns, after U was dispatched
      await pump();
      await afterFirst();    // U's audio never arrives

      expect( onDevice, contains( "U, urgent" ), reason: "THE BUG: A's late arm cancelled U's timer and U had none" );
    } );

    test( "finding 3: audio that reports playing forever is stopped at the ceiling and the queue advances", () async {
      final o = await newOrch( maxPlayback: const Duration( milliseconds: 120 ) );
      audioPlaying = true;   // onComplete never fires

      o.enqueueAlways( priority: "high", message: "plays forever" );
      o.enqueueAlways( priority: "high", message: "next" );
      await pump();
      expect( posted, [ "plays forever" ] );

      await Future<void>.delayed( const Duration( milliseconds: 260 ) );
      expect( posted, [ "plays forever", "next" ], reason: "THE BUG: the watchdog re-armed forever" );
      expect( onDevice, isEmpty, reason: "it was heard already; it is not spoken a second time" );
      expect( o.lastOutcome!.line, contains( "never reported finishing" ) );
    } );

    test( "finding 4: a throw inside the watchdog releases the queue instead of leaving it held", () async {
      final o = await newOrch();
      when( () => player.stop() ).thenAnswer( ( _ ) async => throw StateError( "player gone" ) );

      o.enqueueAlways( priority: "high", message: "first" );
      o.enqueueAlways( priority: "high", message: "second" );
      await pump();
      await afterFirst();

      expect( posted, [ "first", "second" ], reason: "THE BUG: an unhandled throw left _current set" );
      expect( o.lastOutcome!.line, anyOf( contains( "watchdog hit an error" ), contains( "sent to the speaker" ) ) );
    } );
  } );
}
