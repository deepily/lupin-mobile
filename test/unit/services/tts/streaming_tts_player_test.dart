import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/constants/app_constants.dart';
import 'package:lupin_mobile/services/tts/streaming_tts_player.dart';

class _MockDio         extends Mock implements Dio {}
class _MockAudioPlayer extends Mock implements StreamingTtsAudioPlayer {}

class _FakeRequestOptions extends Fake implements RequestOptions {}

void main() {
  setUpAll( () {
    registerFallbackValue( _FakeRequestOptions() );
    registerFallbackValue( Uint8List( 0 ) );
  } );

  group( "StreamingTtsPlayer — playback-gated complete contract", () {
    late _MockDio         dio;
    late _MockAudioPlayer audioPlayer;
    late StreamController<void> onCompleteCtrl;
    StreamingTtsPlayer?   player;

    setUp( () {
      dio             = _MockDio();
      audioPlayer     = _MockAudioPlayer();
      onCompleteCtrl  = StreamController<void>.broadcast();

      when( () => audioPlayer.onComplete ).thenAnswer( ( _ ) => onCompleteCtrl.stream );
      when( () => audioPlayer.play( any() ) ).thenAnswer( ( _ ) async {} );
      when( () => audioPlayer.stop()    ).thenAnswer( ( _ ) async {} );
      when( () => audioPlayer.dispose() ).thenAnswer( ( _ ) async {} );

      // Dio post is invoked only by `speak()`. These tests exercise the
      // WS-event path directly, but mock the call for completeness.
      when( () => dio.post<Map<String, dynamic>>(
        any(),
        data        : any( named: 'data' ),
        queryParameters: any( named: 'queryParameters' ),
        options     : any( named: 'options' ),
        cancelToken : any( named: 'cancelToken' ),
        onSendProgress    : any( named: 'onSendProgress' ),
        onReceiveProgress : any( named: 'onReceiveProgress' ),
      ) ).thenAnswer( ( _ ) async => Response(
        data            : <String, dynamic>{ 'status': 'ok' },
        statusCode      : 200,
        requestOptions  : RequestOptions( path: '' ),
      ) );
    } );

    tearDown( () async {
      await player?.dispose();
      await onCompleteCtrl.close();
    } );

    // Simulate the WS event sequence the backend actually emits:
    //   status(loading) → chunk(pcm) → status(streaming) → complete
    void feedAudioChunksThenComplete( {
      required StreamingTtsPlayer p,
      required List<int>          pcmBytes,
    } ) {
      p.handleWsEvent( AppConstants.eventAudioStreamingStatus,
        <String, dynamic>{ 'status': 'loading' } );
      p.handleWsEvent( AppConstants.eventAudioStreamingChunk,
        <String, dynamic>{ 'data': pcmBytes } );
      p.handleWsEvent( AppConstants.eventAudioStreamingComplete,
        <String, dynamic>{ 'status': 'success' } );
    }

    Future<void> activate( StreamingTtsPlayer p ) async {
      // `speak()` flips the internal `_isActive` flag that gates chunk
      // events. Without it, `handleWsEvent` filters chunk/complete out
      // as stray events.
      await p.speak( text: "hello", sessionId: "wise penguin" );
    }

    test( "complete is NOT fired until the audio player's onComplete fires", () async {
      player = StreamingTtsPlayer( dio, player: audioPlayer );
      await activate( player! );

      final emitted = <TtsCompleteEvent>[];
      player!.completeStream.listen( emitted.add );

      // Feed the full WS sequence (status → chunk → complete).
      feedAudioChunksThenComplete(
        p       : player!,
        pcmBytes: List<int>.filled( 100, 0 ),
      );
      // Let the microtask queue drain so `_playPcmBuffer` progresses
      // to `await myCompleter.future`.
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      // audioPlayer.play WAS called (sync part of _playPcmBuffer ran).
      verify( () => audioPlayer.play( any() ) ).called( 1 );
      // But onComplete hasn't fired yet — so the player MUST NOT have
      // emitted a TtsCompleteEvent. This is the whole point of the fix.
      expect( emitted, isEmpty, reason:
        "Complete event fired before audio playback finished — would cause "
        "FIFO overlap when orchestrator starts the next utterance." );

      // Now fire onComplete (simulating audio playback end).
      onCompleteCtrl.add( null );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      expect( emitted.length, 1 );
    } );

    test( "complete IS fired after onComplete even if WS complete arrived much earlier", () async {
      player = StreamingTtsPlayer( dio, player: audioPlayer );
      await activate( player! );

      final emitted = <TtsCompleteEvent>[];
      player!.completeStream.listen( emitted.add );

      feedAudioChunksThenComplete(
        p       : player!,
        pcmBytes: List<int>.filled( 100, 0 ),
      );
      // Simulate a long-playing utterance: 100ms of silence between WS
      // complete and actual playback end.
      await Future<void>.delayed( const Duration( milliseconds: 100 ) );
      expect( emitted, isEmpty );

      onCompleteCtrl.add( null );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      expect( emitted.length, 1 );
    } );

    test( "empty buffer + WS complete → complete fires immediately (defensive)", () async {
      player = StreamingTtsPlayer( dio, player: audioPlayer );
      await activate( player! );

      final emitted = <TtsCompleteEvent>[];
      player!.completeStream.listen( emitted.add );

      // WS complete without any prior chunks — should still signal
      // complete so the orchestrator advances its FIFO.
      player!.handleWsEvent( AppConstants.eventAudioStreamingComplete,
        <String, dynamic>{ 'status': 'success' } );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      expect( emitted.length, 1 );
      // And audioPlayer.play was NOT called (nothing to play).
      verifyNever( () => audioPlayer.play( any() ) );
    } );

    test( "stop() during playback does NOT emit a complete event", () async {
      player = StreamingTtsPlayer( dio, player: audioPlayer );
      await activate( player! );

      final emitted = <TtsCompleteEvent>[];
      player!.completeStream.listen( emitted.add );

      feedAudioChunksThenComplete(
        p       : player!,
        pcmBytes: List<int>.filled( 100, 0 ),
      );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      // audioPlayer.play ran; _playPcmBuffer is awaiting onComplete.
      verify( () => audioPlayer.play( any() ) ).called( 1 );

      // Caller preempts (urgent path). stop() wakes the hung completer
      // but the identity check inside _playPcmBuffer must suppress the
      // complete emission.
      await player!.stop();
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      expect( emitted, isEmpty, reason:
        "stop() must not cause a stray complete event — otherwise the "
        "orchestrator would advance its FIFO mid-preempt." );
    } );

    test( "stop() → subsequent utterance completes normally after its own onComplete", () async {
      player = StreamingTtsPlayer( dio, player: audioPlayer );

      final emitted = <TtsCompleteEvent>[];
      player!.completeStream.listen( emitted.add );

      // First utterance, then preempted.
      await activate( player! );
      feedAudioChunksThenComplete(
        p       : player!,
        pcmBytes: List<int>.filled( 100, 0 ),
      );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );
      await player!.stop();
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );
      expect( emitted, isEmpty, reason: "preempt path must not emit complete" );

      // Second utterance arrives (preempting one). It should emit exactly
      // one complete AFTER its own onComplete fires.
      await activate( player! );
      feedAudioChunksThenComplete(
        p       : player!,
        pcmBytes: List<int>.filled( 100, 0 ),
      );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );
      expect( emitted, isEmpty, reason:
        "new utterance must not emit complete until its playback ends" );

      onCompleteCtrl.add( null );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      expect( emitted.length, 1, reason:
        "new utterance's complete fires exactly once after its playback ends" );
    } );

    test( "isPlaying is true during playback and false after onComplete", () async {
      player = StreamingTtsPlayer( dio, player: audioPlayer );
      await activate( player! );

      feedAudioChunksThenComplete(
        p       : player!,
        pcmBytes: List<int>.filled( 100, 0 ),
      );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      expect( player!.isPlaying, isTrue,
        reason: "isPlaying must remain true while audio is playing" );

      onCompleteCtrl.add( null );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      expect( player!.isPlaying, isFalse );
    } );

    test( "chunk events are ignored before speak() (stray-event filter)", () async {
      player = StreamingTtsPlayer( dio, player: audioPlayer );

      final emitted = <TtsCompleteEvent>[];
      player!.completeStream.listen( emitted.add );

      // Note: no `activate()` call — session hasn't issued a speak yet.
      player!.handleWsEvent( AppConstants.eventAudioStreamingChunk,
        <String, dynamic>{ 'data': List<int>.filled( 100, 0 ) } );
      player!.handleWsEvent( AppConstants.eventAudioStreamingComplete,
        <String, dynamic>{ 'status': 'success' } );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      expect( emitted, isEmpty );
      verifyNever( () => audioPlayer.play( any() ) );
    } );

    test( "simulateTtsError=true → POST body includes debug_simulate_error: true", () async {
      player = StreamingTtsPlayer( dio, player: audioPlayer, simulateTtsError: true );
      await player!.speak( text: "hello", sessionId: "wise penguin" );

      final captured = verify( () => dio.post<Map<String, dynamic>>(
        any(),
        data              : captureAny( named: 'data' ),
        queryParameters   : any( named: 'queryParameters' ),
        options           : any( named: 'options' ),
        cancelToken       : any( named: 'cancelToken' ),
        onSendProgress    : any( named: 'onSendProgress' ),
        onReceiveProgress : any( named: 'onReceiveProgress' ),
      ) ).captured;
      final data = captured.first as Map<String, dynamic>;
      expect( data[ 'debug_simulate_error' ], isTrue );
      expect( data[ 'session_id' ], 'wise penguin' );
      expect( data[ 'text' ], 'hello' );
    } );

    test( "simulateTtsError=false (default in tests) → POST body omits debug_simulate_error", () async {
      player = StreamingTtsPlayer( dio, player: audioPlayer, simulateTtsError: false );
      await player!.speak( text: "hello", sessionId: "wise penguin" );

      final captured = verify( () => dio.post<Map<String, dynamic>>(
        any(),
        data              : captureAny( named: 'data' ),
        queryParameters   : any( named: 'queryParameters' ),
        options           : any( named: 'options' ),
        cancelToken       : any( named: 'cancelToken' ),
        onSendProgress    : any( named: 'onSendProgress' ),
        onReceiveProgress : any( named: 'onReceiveProgress' ),
      ) ).captured;
      final data = captured.first as Map<String, dynamic>;
      expect( data.containsKey( 'debug_simulate_error' ), isFalse );
    } );

    test( "tts_error mid-stream clears the PCM buffer and emits an error event", () async {
      player = StreamingTtsPlayer( dio, player: audioPlayer );
      await activate( player! );

      final errs = <TtsErrorEvent>[];
      final done = <TtsCompleteEvent>[];
      player!.errorStream   .listen( errs.add );
      player!.completeStream.listen( done.add );

      player!.handleWsEvent( AppConstants.eventAudioStreamingChunk,
        <String, dynamic>{ 'data': List<int>.filled( 50, 0 ) } );
      player!.handleWsEvent( 'tts_error',
        <String, dynamic>{ 'error_code': 'quota_exceeded', 'text': 'out' } );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      expect( errs.length, 1 );
      expect( errs.first.errorCode, 'quota_exceeded' );
      expect( done, isEmpty );
      verifyNever( () => audioPlayer.play( any() ) );
    } );

    // Phase 4 (voice-persona milestone) — voiceId pipe-through tests per
    // 04-testing-validation.md rows 4.1, 4.2, 4.3.

    test( "4.1 — voiceId present in POST body when speak() is called with voiceId", () async {
      player = StreamingTtsPlayer( dio, player: audioPlayer );
      await player!.speak(
        text      : "hello",
        sessionId : "wise penguin",
        voiceId   : "pNInz6obpgDQGcFmaJgB",
      );

      final captured = verify( () => dio.post<Map<String, dynamic>>(
        any(),
        data              : captureAny( named: 'data' ),
        queryParameters   : any( named: 'queryParameters' ),
        options           : any( named: 'options' ),
        cancelToken       : any( named: 'cancelToken' ),
        onSendProgress    : any( named: 'onSendProgress' ),
        onReceiveProgress : any( named: 'onReceiveProgress' ),
      ) ).captured;
      final data = captured.first as Map<String, dynamic>;
      expect( data[ 'voice_id' ], 'pNInz6obpgDQGcFmaJgB' );
      expect( data[ 'session_id' ], 'wise penguin' );
      expect( data[ 'text' ],       'hello' );
    } );

    test( "4.2 — voiceId omitted from POST body when speak() is called without voiceId", () async {
      player = StreamingTtsPlayer( dio, player: audioPlayer );
      await player!.speak( text: "hello", sessionId: "wise penguin" );

      final captured = verify( () => dio.post<Map<String, dynamic>>(
        any(),
        data              : captureAny( named: 'data' ),
        queryParameters   : any( named: 'queryParameters' ),
        options           : any( named: 'options' ),
        cancelToken       : any( named: 'cancelToken' ),
        onSendProgress    : any( named: 'onSendProgress' ),
        onReceiveProgress : any( named: 'onReceiveProgress' ),
      ) ).captured;
      final data = captured.first as Map<String, dynamic>;
      // Server's "absent → Sam" fallback contract requires the key to be
      // OMITTED, not sent as null. Per Q3 (FROZEN 2026-05-06).
      expect( data.containsKey( 'voice_id' ), isFalse );
    } );

    test( "4.3 — borrowed persona body shape unchanged (server treats borrowed identically)", () async {
      player = StreamingTtsPlayer( dio, player: audioPlayer );
      // borrowed=true on the persona is a UI concern (dashed border), not a
      // server concern. The body that hits the wire is identical to the
      // borrowed=false case — only `voice_id` matters at the network layer.
      await player!.speak(
        text      : "borrowed-narration",
        sessionId : "wise penguin",
        voiceId   : "pNInz6obpgDQGcFmaJgB",
      );

      final captured = verify( () => dio.post<Map<String, dynamic>>(
        any(),
        data              : captureAny( named: 'data' ),
        queryParameters   : any( named: 'queryParameters' ),
        options           : any( named: 'options' ),
        cancelToken       : any( named: 'cancelToken' ),
        onSendProgress    : any( named: 'onSendProgress' ),
        onReceiveProgress : any( named: 'onReceiveProgress' ),
      ) ).captured;
      final data = captured.first as Map<String, dynamic>;

      // Body keys: session_id, text, voice_id. No "borrowed", no persona-name,
      // no decoration metadata. Only the voice_id is on the wire.
      expect( data.keys.toSet(), { 'session_id', 'text', 'voice_id' } );
      expect( data[ 'voice_id' ], 'pNInz6obpgDQGcFmaJgB' );
    } );
  } );
}
