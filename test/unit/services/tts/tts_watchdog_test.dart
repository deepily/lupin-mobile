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

  Future<TtsOrchestrator> newOrch() async {
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
}
