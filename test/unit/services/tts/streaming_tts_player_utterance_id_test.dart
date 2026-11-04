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

  group( "StreamingTtsPlayer — utterance id", () {
    late _MockDio               dio;
    late _MockAudioPlayer       audioPlayer;
    late StreamController<void> onCompleteCtrl;
    late List<Map<String, dynamic>> sentBodies;
    late StreamingTtsPlayer     player;

    setUp( () {
      dio            = _MockDio();
      audioPlayer    = _MockAudioPlayer();
      onCompleteCtrl = StreamController<void>.broadcast();
      sentBodies     = [];

      when( () => audioPlayer.onComplete ).thenAnswer( ( _ ) => onCompleteCtrl.stream );
      when( () => audioPlayer.play( any() ) ).thenAnswer( ( _ ) async {} );
      when( () => audioPlayer.stop()    ).thenAnswer( ( _ ) async {} );
      when( () => audioPlayer.dispose() ).thenAnswer( ( _ ) async {} );

      when( () => dio.post<Map<String, dynamic>>(
        any(),
        data              : any( named: 'data' ),
        queryParameters   : any( named: 'queryParameters' ),
        options           : any( named: 'options' ),
        cancelToken       : any( named: 'cancelToken' ),
        onSendProgress    : any( named: 'onSendProgress' ),
        onReceiveProgress : any( named: 'onReceiveProgress' ),
      ) ).thenAnswer( ( inv ) async {
        sentBodies.add( inv.namedArguments[ #data ] as Map<String, dynamic> );
        return Response(
          data           : <String, dynamic>{ 'status': 'ok' },
          statusCode     : 200,
          requestOptions : RequestOptions( path: '' ),
        );
      } );

      player = StreamingTtsPlayer( dio, player: audioPlayer );
    } );

    tearDown( () async {
      await player.dispose();
      await onCompleteCtrl.close();
    } );

    Future<String> speakAndGetId() async {
      await player.speak( text: "hello", sessionId: "wise penguin" );
      return sentBodies.last[ 'utterance_id' ] as String;
    }

    void feedChunk() => player.handleWsEvent(
      AppConstants.eventAudioStreamingChunk,
      <String, dynamic>{ 'data': List<int>.filled( 100, 0 ) },
    );

    test( "each speak request carries a fresh non-empty utterance_id", () async {
      final first  = await speakAndGetId();
      final second = await speakAndGetId();

      expect( first,  isNotEmpty );
      expect( first.length, lessThanOrEqualTo( 255 ) );
      expect( second, isNot( first ) );
    } );

    test( "a stale completion from an abandoned stream does not end the current utterance", () async {
      final abandoned = await speakAndGetId();
      final current   = await speakAndGetId();
      expect( current, isNot( abandoned ) );

      final emitted = <TtsCompleteEvent>[];
      player.completeStream.listen( emitted.add );

      feedChunk();
      player.handleWsEvent( AppConstants.eventAudioStreamingComplete,
        <String, dynamic>{ 'status': 'success', 'utterance_id': abandoned } );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      expect( player.isPlaying, isTrue, reason: "current utterance must still be pending" );
      verifyNever( () => audioPlayer.play( any() ) );
      expect( emitted, isEmpty );

      // The current utterance's own completion still plays and finishes.
      player.handleWsEvent( AppConstants.eventAudioStreamingComplete,
        <String, dynamic>{ 'status': 'success', 'utterance_id': current } );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );
      verify( () => audioPlayer.play( any() ) ).called( 1 );
      onCompleteCtrl.add( null );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );
      expect( emitted.length, 1 );
    } );

    test( "a stale error from an abandoned stream does not end the current utterance", () async {
      final abandoned = await speakAndGetId();
      await speakAndGetId();

      final errors = <TtsErrorEvent>[];
      player.errorStream.listen( errors.add );

      feedChunk();
      player.handleWsEvent( 'tts_error', <String, dynamic>{
        'error_code': 'quota_exceeded', 'utterance_id': abandoned,
      } );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      expect( errors, isEmpty );
      expect( player.isPlaying, isTrue );
    } );

    test( "an error naming the current utterance is delivered", () async {
      final current = await speakAndGetId();

      final errors = <TtsErrorEvent>[];
      player.errorStream.listen( errors.add );

      player.handleWsEvent( 'tts_error', <String, dynamic>{
        'error_code': 'quota_exceeded', 'utterance_id': current,
      } );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );

      expect( errors.length, 1 );
      expect( errors.single.errorCode, 'quota_exceeded' );
      expect( player.isPlaying, isFalse );
    } );

    test( "a frame with no utterance_id (old server) keeps the old behaviour", () async {
      await speakAndGetId();

      final errors   = <TtsErrorEvent>[];
      final complete = <TtsCompleteEvent>[];
      player.errorStream.listen( errors.add );
      player.completeStream.listen( complete.add );

      player.handleWsEvent( AppConstants.eventAudioStreamingComplete,
        <String, dynamic>{ 'status': 'success' } );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );
      expect( complete.length, 1, reason: "no id on the frame: complete is honoured" );
      expect( complete.single.played, isFalse );

      await speakAndGetId();
      player.handleWsEvent( 'tts_error', <String, dynamic>{ 'error_code': 'rate_limit' } );
      await Future<void>.delayed( const Duration( milliseconds: 10 ) );
      expect( errors.length, 1 );
      expect( errors.single.errorCode, 'rate_limit' );
    } );
  } );
}
