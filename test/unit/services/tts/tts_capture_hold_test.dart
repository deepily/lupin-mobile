/// Row a1c12c6e (Rick 2026-09-26): "when I'm in the Lupin Focus mode and I am
/// using the mic ... it does not block playback or TTS of incoming
/// notifications and that is a gigantic PITA."
///
/// While the microphone records, spoken notifications are HELD — queued, not
/// dropped — and play once the recording ends. The hold is separate from the
/// user's own pause toggle, so the mic releasing never un-pauses him.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';
import 'package:lupin_mobile/services/tts/streaming_tts_player.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';

class _MockPlayer   extends Mock implements StreamingTtsPlayer {}
class _MockFallback extends Mock implements NotificationAudioService {}
class _MockWs       extends Mock implements WebSocketService {}
class _MockDio      extends Mock implements Dio {}
class _MockRecorder extends Mock implements AudioRecorder {}

void main() {
  late _MockPlayer   player;
  late _MockFallback fallback;
  late _MockWs       ws;
  late StreamController<TtsCompleteEvent> completeCtrl;
  late StreamController<TtsErrorEvent>    errorCtrl;
  late List<String> spoken;
  TtsOrchestrator? orch;

  setUpAll( () {
    registerFallbackValue( const RecordConfig() );
    registerFallbackValue( AudioEncoder.wav );
  } );

  Future<TtsOrchestrator> newOrch() async {
    SharedPreferences.setMockInitialValues( {} );
    final prefs  = NotificationPreferences( await SharedPreferences.getInstance() );
    player       = _MockPlayer();
    fallback     = _MockFallback();
    ws           = _MockWs();
    completeCtrl = StreamController<TtsCompleteEvent>.broadcast();
    errorCtrl    = StreamController<TtsErrorEvent>   .broadcast();
    spoken       = [];

    when( () => player.completeStream ).thenAnswer( ( _ ) => completeCtrl.stream );
    when( () => player.errorStream    ).thenAnswer( ( _ ) => errorCtrl   .stream );
    when( () => player.isPlaying      ).thenReturn( false );
    when( () => player.speak(
      text      : any( named: "text"      ),
      sessionId : any( named: "sessionId" ),
      voiceId   : any( named: "voiceId"   ),
    ) ).thenAnswer( ( inv ) async { spoken.add( inv.namedArguments[ #text ] as String ); } );
    when( () => player.stop() ).thenAnswer( ( _ ) async {} );
    when( () => fallback.flutterTtsSpeak( any() ) ).thenAnswer( ( _ ) async {} );
    when( () => fallback.stopFallbackSpeech() ).thenAnswer( ( _ ) async {} );
    when( () => ws.sessionId ).thenReturn( "wise penguin" );

    orch = TtsOrchestrator( player: player, fallback: fallback, prefs: prefs, ws: ws );
    return orch!;
  }

  Future<void> pump() => Future<void>.delayed( Duration.zero );

  tearDown( () async {
    await orch?.dispose();
    await completeCtrl.close();
    await errorCtrl   .close();
  } );

  test( "a notification arriving mid-recording plays NOTHING until the recording ends, then plays", () async {
    final o = await newOrch();

    await o.setCaptureHold( true );
    o.enqueueAlways( priority: "high", message: "build finished" );
    await pump();
    expect( spoken, isEmpty, reason: "the mic is open; speaking now talks over Rick and into his recording" );
    expect( o.queueDepth, 1, reason: "held, not dropped" );

    await o.setCaptureHold( false );
    await pump();
    expect( spoken, [ "build finished" ] );
  } );

  test( "an URGENT arrival is held too, on the focus path and the legacy path", () async {
    final o = await newOrch();

    await o.setCaptureHold( true );
    o.enqueueAlways( priority: "urgent", message: "focus urgent" );
    o.enqueueIfSpeakable( priority: "urgent", message: "legacy urgent" );
    await pump();
    expect( spoken, isEmpty );

    await o.setCaptureHold( false );
    await pump();
    expect( spoken.single, "focus urgent" );
    completeCtrl.add( const TtsCompleteEvent() );
    await pump();
    expect( spoken, [ "focus urgent", "legacy urgent" ] );
  } );

  test( "starting to record STOPS an utterance in flight and replays it from the start afterwards", () async {
    final o = await newOrch();

    o.enqueueAlways( priority: "high", message: "long answer" );
    await pump();
    expect( spoken, [ "long answer" ] );

    await o.setCaptureHold( true );
    verify( () => player.stop() ).called( 1 );
    expect( o.queueDepth, 1, reason: "the interrupted utterance goes back to the head of the queue" );

    await o.setCaptureHold( false );
    await pump();
    expect( spoken, [ "long answer", "long answer" ] );
  } );

  test( "the mic releasing does NOT undo the user's own pause", () async {
    final o = await newOrch();

    o.pause();
    await o.setCaptureHold( true );
    o.enqueueAlways( priority: "high", message: "held twice" );
    await o.setCaptureHold( false );
    await pump();
    expect( spoken, isEmpty );
    expect( o.isPaused, isTrue );

    o.resume();
    await pump();
    expect( spoken, [ "held twice" ] );
  } );

  group( "AsrService reports each capture start and end", () {
    late _MockRecorder recorder;
    late List<bool>    events;
    late AsrService    asr;

    setUp( () async {
      recorder = _MockRecorder();
      events   = [];
      final tempDir = await Directory.systemTemp.createTemp( "asr-hold-" );
      addTearDown( () async { if ( tempDir.existsSync() ) await tempDir.delete( recursive: true ); } );
      asr = AsrService(
        dio                : _MockDio(),
        recorder           : recorder,
        tempDirProvider    : () async => tempDir,
        onCapturingChanged : events.add,
      );
      when( () => recorder.hasPermission() ).thenAnswer( ( _ ) async => true );
      when( () => recorder.isEncoderSupported( any() ) ).thenAnswer( ( _ ) async => true );
      when( () => recorder.start( any(), path: any( named: "path" ) ) ).thenAnswer( ( _ ) async {} );
      when( () => recorder.cancel() ).thenAnswer( ( _ ) async {} );
      when( () => recorder.stop() ).thenAnswer( ( _ ) async => throw Exception( "mic gone" ) );
    } );

    test( "start → true; cancel → false", () async {
      await asr.startRecording();
      await asr.cancelRecording();
      expect( events, [ true, false ] );
    } );

    test( "a stop that FAILS still releases the hold", () async {
      await asr.startRecording();
      await expectLater( asr.stopToFile(), throwsA( isA<AsrException>() ) );
      expect( events, [ true, false ],
          reason: "a hold left on after a failed stop would mute Rick until the app restarts" );
    } );

    test( "a cancel with nothing recording reports nothing", () async {
      await asr.cancelRecording();
      expect( events, isEmpty );
    } );
  } );
}
