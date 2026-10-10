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
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';
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
      final o = await newOrch( fallbackBudget: const Duration( milliseconds: 50 ), maxPlayback: const Duration( milliseconds: 50 ) );
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

  group( "round 2 (Chloe, 291777b): stale lines, completion, wordings", () {
    late NotificationPreferences prefs;

    Future<TtsOrchestrator> fresh( { bool withStopList = false } ) async {
      final o = await newOrch();   // sets up the mocks; its own prefs are replaced below
      await o.dispose();
      SharedPreferences.setMockInitialValues( {} );
      final sp = await SharedPreferences.getInstance();
      prefs = NotificationPreferences( sp );
      orch = TtsOrchestrator(
        player: player, fallback: fallback, prefs: prefs, ws: ws, speakWatchdog: window,
        stopList: withStopList ? NotificationStopList( sp ) : null,
      );
      return orch!;
    }

    const emptied = "Speech queue emptied: nothing is waiting";

    test( "the held line retires when the queue is emptied: clearQueued, removeQueued and stopAll", () async {
      final o = await fresh();
      o.pause();

      o.enqueueAlways( priority: "high", message: "one" );
      o.enqueueAlways( priority: "high", message: "two" );
      expect( o.lastOutcome!.line, "Held, not spoken yet: speech is paused (2 waiting)" );
      o.clearQueued();
      expect( o.lastOutcome!.line, emptied, reason: "THE BUG: it kept saying 2 waiting" );
      expect( o.lastOutcome!.problem, isFalse );

      o.enqueueAlways( priority: "high", message: "three" );
      expect( o.lastOutcome!.line, "Held, not spoken yet: speech is paused (1 waiting)" );
      final id = o.queueSnapshot.single.id;
      expect( o.removeQueued( id ), isTrue );
      expect( o.lastOutcome!.line, emptied );

      o.enqueueAlways( priority: "high", message: "four" );
      await o.stopAll();
      expect( o.lastOutcome!.line, emptied );
    } );

    test( "a held line is kept while something is still waiting", () async {
      final o = await fresh();
      o.pause();
      o.enqueueAlways( priority: "high", message: "one" );
      o.enqueueAlways( priority: "high", message: "two" );
      o.removeQueued( o.queueSnapshot.first.id );
      expect( o.lastOutcome!.line, startsWith( "Held, not spoken yet" ) );
    } );

    test( "a finished utterance reads 'Last message spoken', quietly; a stale completion says nothing", () async {
      final o = await fresh();

      o.enqueueAlways( priority: "high", message: "say this" );
      await pump();
      expect( o.lastOutcome!.line, "Last message sent to the speaker" );

      completeCtrl.add( const TtsCompleteEvent() );
      await pump();
      expect( o.lastOutcome!.line, "Last message spoken" );
      expect( o.lastOutcome!.problem, isFalse );

      // No utterance in flight, so a stray completion must not rewrite the line.
      final before = o.lastOutcome;
      await o.stopAll();
      completeCtrl.add( const TtsCompleteEvent() );
      await pump();
      expect( o.lastOutcome!.line, before!.line );
    } );

    test( "each remaining wording is exactly what Rick reads", () async {
      final o = await fresh( withStopList: true );

      await prefs.muteSender( "key-1", "Some Worker" );
      o.enqueueAlways( priority: "high", message: "hi", senderKey: "key-1" );
      expect( o.lastOutcome!.line, "Last message not spoken: that sender is muted" );
      await prefs.unmuteSender( "key-1" );

      await prefs.setQuietEnabled( true );
      final now = DateTime.now();
      final m   = now.hour * 60 + now.minute;
      await prefs.setQuietStartMinutes( m - 30 );
      await prefs.setQuietEndMinutes( m + 30 );
      await prefs.setQuietUrgentBypass( false );
      o.enqueueAlways( priority: "high", message: "hi" );
      expect( o.lastOutcome!.line, "Last message not spoken: quiet hours are on" );
      await prefs.setQuietEnabled( false );

      o.enqueueAlways( priority: "high", message: "Done: Bash ls -la" );
      expect( o.lastOutcome!.line, "Last message not spoken: it matches the stop-list" );

      await prefs.setSpeakSystemSenders( false );
      o.enqueueAlways( priority: "high", message: "from a script" );
      expect( o.lastOutcome!.line, "Last message not spoken: Speak system senders is off" );
      await prefs.setSpeakSystemSenders( true );

      o.setCaptureHold( true );
      o.enqueueAlways( priority: "high", message: "mic is open" );
      expect( o.lastOutcome!.line, "Held, not spoken yet: the microphone is recording (1 waiting)" );
    } );

    test( "the fallback and failure wordings", () async {
      final o = await fresh();

      when( () => ws.sessionId ).thenReturn( null );
      o.enqueueAlways( priority: "high", message: "no connection" );
      await pump();
      expect( o.lastOutcome!.line, "Spoken on this phone's own voice: no server audio connection" );

      when( () => ws.sessionId ).thenReturn( "wise penguin" );
      when( () => player.speak(
        text      : any( named: "text"      ),
        sessionId : any( named: "sessionId" ),
        voiceId   : any( named: "voiceId"   ),
      ) ).thenThrow( Exception( "network down" ) );
      o.enqueueAlways( priority: "high", message: "post refused" );
      await pump();
      expect( o.lastOutcome!.line, "Spoken on this phone's own voice: the server did not take the request" );
    } );
  } );

  group( "round 3 (Chloe, 7b4e48d): on-device speech stays reachable", () {
    late Completer<void> engineDone;
    late List<String>    engineGot;
    late int             stopCalls;

    /// Every utterance takes the on-device path, and the engine "plays" until [engineDone] completes.
    Future<TtsOrchestrator> onDeviceOnly() async {
      final o = await newOrch();
      when( () => ws.sessionId ).thenReturn( null );
      engineDone = Completer<void>();
      engineGot  = [];
      stopCalls  = 0;
      when( () => fallback.flutterTtsSpeak( any() ) ).thenAnswer( ( inv ) async {
        engineGot.add( inv.positionalArguments.first as String );
        await engineDone.future;
      } );
      when( () => fallback.stopFallbackSpeech() ).thenAnswer( ( _ ) async {
        stopCalls++;
        if ( !engineDone.isCompleted ) engineDone.complete();   // what the real service does on stop
      } );
      return o;
    }

    test( "an on-device utterance stays in flight until the engine finishes, so Skip can reach it", () async {
      final o = await onDeviceOnly();

      o.enqueueAlways( priority: "high", message: "first" );
      o.enqueueAlways( priority: "high", message: "second" );
      await pump();
      expect( engineGot, [ "first" ], reason: "THE BUG: the second was accepted at once and piled up in the engine" );
      expect( o.queueSnapshot.where( ( i ) => i.isCurrent ).length, 1, reason: "Skip is available" );
      expect( o.queueDepth, 1 );

      await o.skipCurrent();
      expect( stopCalls, greaterThanOrEqualTo( 1 ), reason: "skip reached the engine" );
      await pump();
      expect( engineGot, [ "first", "second" ] );
    } );

    test( "the microphone hold stops the engine even when nothing is in flight", () async {
      final o = await onDeviceOnly();

      await o.setCaptureHold( true );
      expect( stopCalls, 1, reason: "THE BUG: with _current == null the hold returned before stopping the engine" );
    } );

    test( "an urgent arrival with nothing in flight stops the engine first; one in flight preempts it", () async {
      final o = await onDeviceOnly();

      o.enqueueAlways( priority: "urgent", message: "urgent while idle" );
      await pump();
      expect( stopCalls, greaterThanOrEqualTo( 1 ), reason: "an urgent never waits behind engine speech" );
      expect( engineGot, [ "urgent while idle" ] );
    } );

    test( "only audio that really played reads 'Last message spoken'", () async {
      final o = await newOrch();

      o.enqueueAlways( priority: "high", message: "no audio came" );
      await pump();
      completeCtrl.add( const TtsCompleteEvent( played: false ) );
      await pump();
      expect( o.lastOutcome!.line, "Last message failed: the server sent no audio" );
      expect( o.lastOutcome!.problem, isTrue );

      o.enqueueAlways( priority: "high", message: "audio came" );
      await pump();
      completeCtrl.add( const TtsCompleteEvent() );
      await pump();
      expect( o.lastOutcome!.line, "Last message spoken" );
    } );

    test( "removing one of three held items re-states the count", () async {
      final o = await newOrch();
      o.pause();
      o.enqueueAlways( priority: "high", message: "a" );
      o.enqueueAlways( priority: "high", message: "b" );
      o.enqueueAlways( priority: "high", message: "c" );
      expect( o.lastOutcome!.line, "Held, not spoken yet: speech is paused (3 waiting)" );

      o.removeQueued( o.queueSnapshot.first.id );
      expect( o.lastOutcome!.line, "Held, not spoken yet: speech is paused (2 waiting)", reason: "THE BUG: it said 3" );
    } );
  } );
}
