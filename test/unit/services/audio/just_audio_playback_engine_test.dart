import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/services/audio/just_audio_playback_engine.dart';
import 'package:lupin_mobile/services/audio/lupin_media_handler.dart';

class _MockPlayer extends Mock implements AudioPlayer {}
class _FakeSource extends Fake implements AudioSource {}

void main() {
  late _MockPlayer                      player;
  late LupinMediaHandler                handler;
  late JustAudioPlaybackEngine          engine;
  late StreamController<PlaybackEvent>  events;
  late StreamController<bool>           playingCtl;
  late StreamController<Duration?>      durations;

  setUpAll( () => registerFallbackValue( _FakeSource() ) );

  setUp( () {
    player     = _MockPlayer();
    handler    = LupinMediaHandler( rewindInterval: const Duration( seconds: 15 ) );
    events     = StreamController<PlaybackEvent>.broadcast();
    playingCtl = StreamController<bool>.broadcast();
    durations  = StreamController<Duration?>.broadcast();
    when( () => player.playbackEventStream ).thenAnswer( ( _ ) => events.stream );
    when( () => player.playingStream       ).thenAnswer( ( _ ) => playingCtl.stream );
    when( () => player.durationStream      ).thenAnswer( ( _ ) => durations.stream );
    when( () => player.playing             ).thenReturn( false );
    when( () => player.processingState     ).thenReturn( ProcessingState.ready );
    when( () => player.position            ).thenReturn( const Duration( seconds: 3 ) );
    when( () => player.bufferedPosition    ).thenReturn( const Duration( seconds: 9 ) );
    engine = JustAudioPlaybackEngine( handler: handler, player: player );
  } );

  test( "default constructor builds its own player lazily-safe", () {
    // AudioPlayer() needs a platform channel only when used; construction alone must not throw in the
    // test binding. Guarded so the line is covered without touching the platform.
    TestWidgetsFlutterBinding.ensureInitialized();
    expect( () => JustAudioPlaybackEngine( handler: handler ), returnsNormally );
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

  test( "load sets a file source and shows the track; transport calls pass through", () async {
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

    expect( handler.mediaItem.value, const MediaItem( id: "pg-1", title: "Episode" ) );
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

  test( "each player event reports the player's state to the media session", () async {
    when( () => player.playing ).thenReturn( true );
    playingCtl.add( true );
    await Future<void>.delayed( Duration.zero );

    final state = handler.playbackState.value;
    expect( state.playing, isTrue );
    expect( state.processingState, AudioProcessingState.ready );
    expect( state.updatePosition, const Duration( seconds: 3 ) );
    expect( state.bufferedPosition, const Duration( seconds: 9 ) );

    when( () => player.processingState ).thenReturn( ProcessingState.completed );
    events.add( PlaybackEvent() );
    await Future<void>.delayed( Duration.zero );
    expect( handler.playbackState.value.processingState, AudioProcessingState.completed );
    expect( handler.playbackState.value.playing, isFalse );
  } );

  test( "the earbud and lock-screen buttons reach the player through the handler", () async {
    when( () => player.play() ).thenAnswer( ( _ ) async {} );
    when( () => player.seek( Duration.zero ) ).thenAnswer( ( _ ) async {} );
    await handler.click();
    await handler.rewind();
    expect( engine.position, const Duration( seconds: 3 ) );
    verify( () => player.play() ).called( 1 );
    verify( () => player.seek( Duration.zero ) ).called( 1 );
  } );

  test( "the track's length, once known, is added to the card", () async {
    when( () => player.setAudioSource( any() ) ).thenAnswer( ( _ ) async => null );
    await engine.load( File( "/tmp/a.mp3" ), "pg-1", "Episode" );
    durations..add( null )..add( const Duration( minutes: 12 ) );
    await Future<void>.delayed( Duration.zero );
    expect( handler.mediaItem.value?.duration, const Duration( minutes: 12 ) );
  } );
}
