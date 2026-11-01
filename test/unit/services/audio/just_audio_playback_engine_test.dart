import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/services/audio/just_audio_playback_engine.dart';

class _MockPlayer extends Mock implements AudioPlayer {}
class _FakeSource extends Fake implements AudioSource {}

void main() {
  late _MockPlayer player;
  late JustAudioPlaybackEngine engine;

  setUpAll( () => registerFallbackValue( _FakeSource() ) );

  setUp( () {
    player = _MockPlayer();
    engine = JustAudioPlaybackEngine( player: player );
  } );

  test( "default constructor builds its own player lazily-safe", () {
    // AudioPlayer() needs a platform channel only when used; construction alone must not throw in the
    // test binding. Guarded so the line is covered without touching the platform.
    TestWidgetsFlutterBinding.ensureInitialized();
    expect( () => JustAudioPlaybackEngine(), returnsNormally );
  } );

  test( "streams map to the player's streams", () async {
    final pos  = StreamController<Duration>();
    final dur  = StreamController<Duration?>();
    final play = StreamController<bool>();
    final proc = StreamController<ProcessingState>();
    when( () => player.positionStream ).thenAnswer( ( _ ) => pos.stream );
    when( () => player.durationStream ).thenAnswer( ( _ ) => dur.stream );
    when( () => player.playingStream  ).thenAnswer( ( _ ) => play.stream );
    when( () => player.processingStateStream ).thenAnswer( ( _ ) => proc.stream );

    expect( engine.onPosition, emits( const Duration( seconds: 1 ) ) );
    expect( engine.onDuration, emits( const Duration( seconds: 9 ) ) );
    expect( engine.onPlaying,  emits( true ) );
    // Only the completed state counts as "complete".
    expect( engine.onComplete.length, completion( 1 ) );

    pos.add( const Duration( seconds: 1 ) );
    dur.add( const Duration( seconds: 9 ) );
    play.add( true );
    proc..add( ProcessingState.ready )..add( ProcessingState.completed );
    await proc.close();
  } );

  test( "load sets a tagged file source; transport calls pass through", () async {
    when( () => player.setAudioSource( any() ) ).thenAnswer( ( _ ) async => null );
    when( () => player.play()  ).thenAnswer( ( _ ) async {} );
    when( () => player.pause() ).thenAnswer( ( _ ) async {} );
    when( () => player.seek( Duration.zero ) ).thenAnswer( ( _ ) async {} );
    when( () => player.stop()  ).thenAnswer( ( _ ) async {} );

    await engine.load( File( "/tmp/a.mp3" ), "pg-1", "Episode" );
    await engine.play();
    await engine.pause();
    await engine.rewind();
    await engine.stop();

    verify( () => player.setAudioSource( any() ) ).called( 1 );
    verify( () => player.play() ).called( 1 );
    verify( () => player.pause() ).called( 1 );
    verify( () => player.seek( Duration.zero ) ).called( 1 );
    verify( () => player.stop() ).called( 1 );
  } );

  test( "seek passes the position to the player", () async {
    when( () => player.seek( const Duration( seconds: 7 ) ) ).thenAnswer( ( _ ) async {} );
    await engine.seek( const Duration( seconds: 7 ) );
    verify( () => player.seek( const Duration( seconds: 7 ) ) ).called( 1 );
  } );
}
