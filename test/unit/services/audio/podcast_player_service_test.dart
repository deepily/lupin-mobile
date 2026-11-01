import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/services/audio/podcast_link.dart';
import 'package:lupin_mobile/services/audio/podcast_player_service.dart';
import '../../../helpers/fake_podcast_cache.dart';
import '../../../helpers/fake_podcast_engine.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockTts extends Mock implements TtsOrchestrator {}
class _FakeFile extends Fake implements File {
  final String name;
  _FakeFile( [this.name = "/tmp/a.mp3"] );
  @override
  String get path => name;
}

void main() {
  late FakeEngine engine;
  late FakePodcastCache cache;
  late PodcastLink      link;
  late _MockTts   tts;
  late PodcastPlayerService svc;
  var built = 0;

  setUp( () {
    built  = 0;
    engine = FakeEngine();
    cache  = FakePodcastCache();
    link   = PodcastLink.unmetered;
    tts    = _MockTts();
    when( () => tts.stopAll() ).thenAnswer( ( _ ) async {} );
    svc = PodcastPlayerService(
      engineFactory : () { built++; return engine; },
      cacheFactory  : () => cache,
      linkProbe     : () async => link,
      ttsFactory    : () => tts,
    );
  } );

  tearDown( () => svc.dispose() );

  group( "skipBack and restart", () {
    Future<void> loaded( int seconds ) async {
      await svc.playFile( _FakeFile(), "Episode 1", id: "pg-1" );
      engine.pos.add( Duration( seconds: seconds ) );
      await Future<void>.delayed( Duration.zero );
      engine.calls.clear();
    }

    test( "skipBack backs up 15 seconds", () async {
      await loaded( 100 );
      await svc.skipBack();
      expect( engine.calls, [ "seek:85" ] );
      expect( svc.position, const Duration( seconds: 85 ) );
    } );

    test( "skipBack clamps at the start", () async {
      await loaded( 10 );
      await svc.skipBack();
      expect( engine.calls, [ "seek:0" ] );
      expect( svc.position, Duration.zero );
    } );

    test( "skipBack keeps a paused track paused", () async {
      await loaded( 60 );
      await svc.pause();
      engine.calls.clear();
      await svc.skipBack();
      expect( engine.calls, [ "seek:45" ] );
      expect( svc.status, PodcastPlayerStatus.paused );
    } );

    test( "restart goes to the start", () async {
      await loaded( 100 );
      await svc.restart();
      expect( engine.calls, [ "seek:0" ] );
      expect( svc.position, Duration.zero );
    } );

    test( "both do nothing with no track loaded", () async {
      await svc.skipBack();
      await svc.restart();
      expect( engine.calls, isEmpty );
      expect( built, 0 );
    } );

    test( "the media-button interval matches the button", () {
      expect( PodcastPlayerService.skipBackInterval, const Duration( seconds: 15 ) );
    } );
  } );

  test( "starts idle and builds no engine", () {
    expect( svc.status,   PodcastPlayerStatus.idle );
    expect( svc.hasTrack, isFalse );
    expect( svc.isPlaying, isFalse );
    expect( built, 0 );
  } );

  test( "playFile stops TTS, loads and plays, exposing the track", () async {
    await svc.playFile( _FakeFile(), "Episode 1", id: "pg-1" );
    verifyInOrder( [ () => tts.stopAll() ] );
    expect( engine.calls, [ "load:pg-1:Episode 1:/tmp/a.mp3", "play" ] );
    expect( svc.status,  PodcastPlayerStatus.playing );
    expect( svc.trackId, "pg-1" );
    expect( svc.title,   "Episode 1" );
    expect( svc.file!.path, "/tmp/a.mp3" );
    expect( svc.error,   isNull );
  } );

  test( "pause then resume keeps the track and does not reload", () async {
    await svc.playFile( _FakeFile(), "E", id: "pg-1" );
    await svc.pause();
    expect( svc.status, PodcastPlayerStatus.paused );
    await svc.resume();
    expect( svc.status, PodcastPlayerStatus.playing );
    expect( engine.calls.where( ( c ) => c.startsWith( "load" ) ).length, 1 );
    expect( engine.calls, containsAllInOrder( [ "pause", "play" ] ) );
  } );

  test( "pause and resume are no-ops in the wrong state", () async {
    await svc.pause();
    await svc.resume();
    expect( engine.calls, isEmpty );
    expect( svc.status, PodcastPlayerStatus.idle );
  } );

  test( "playFile of the loaded track while playing changes nothing", () async {
    await svc.playFile( _FakeFile(), "E", id: "pg-1" );
    await svc.playFile( _FakeFile(), "E", id: "pg-1" );
    expect( engine.calls.where( ( c ) => c.startsWith( "load" ) ).length, 1 );
  } );

  test( "playFile of the loaded track while paused resumes it", () async {
    await svc.playFile( _FakeFile(), "E", id: "pg-1" );
    await svc.pause();
    await svc.playFile( _FakeFile(), "E", id: "pg-1" );
    expect( svc.status, PodcastPlayerStatus.playing );
    expect( engine.calls.where( ( c ) => c.startsWith( "load" ) ).length, 1 );
  } );

  test( "switching track loads the new one and resets position", () async {
    await svc.playFile( _FakeFile(), "One", id: "pg-1" );
    engine.pos.add( const Duration( seconds: 30 ) );
    await Future<void>.delayed( Duration.zero );
    expect( svc.position, const Duration( seconds: 30 ) );
    await svc.playFile( _FakeFile( "/tmp/b.mp3" ), "Two", id: "pg-2" );
    expect( svc.trackId,  "pg-2" );
    expect( svc.title,    "Two" );
    expect( svc.position, Duration.zero );
    expect( built, 1, reason: "one engine serves every track" );
    expect( engine.calls.last, "play" );
    expect( engine.calls, contains( "load:pg-2:Two:/tmp/b.mp3" ) );
  } );

  test( "play downloads by job id then plays", () async {
    final seen = <PodcastPlayerStatus>[];
    svc.addListener( () => seen.add( svc.status ) );
    await svc.play( "/io/p/podcast.mp3", "Ep", id: "pg-9" );
    expect( cache.fetched, [ [ "/io/p/podcast.mp3", "pg-9" ] ] );
    expect( seen.first, PodcastPlayerStatus.loading );
    expect( svc.status, PodcastPlayerStatus.playing );
    expect( svc.trackDownloaded, isTrue );
  } );

  test( "play of a downloaded podcast makes no network call, whatever the link", () async {
    cache.files[ "pg-9" ] = PathFile( "/kept/pg-9.mp3" );
    for ( final l in PodcastLink.values ) {
      link = l;
      await svc.stop();
      await svc.play( "/io/p/podcast.mp3", "Ep", id: "pg-9" );
      expect( svc.status, PodcastPlayerStatus.playing, reason: "$l" );
      expect( svc.file!.path, "/kept/pg-9.mp3" );
    }
    expect( cache.fetched, isEmpty );
  } );

  test( "play on mobile data asks first and downloads only on yes", () async {
    link = PodcastLink.metered;
    var asked = 0;
    await svc.play( "/io/x.mp3", "Ep", id: "pg-1", confirmMobileData: () async { asked++; return true; } );
    expect( asked, 1 );
    expect( cache.fetched, [ [ "/io/x.mp3", "pg-1" ] ] );
    expect( svc.status, PodcastPlayerStatus.playing );
  } );

  test( "play on mobile data does nothing when declined, and keeps the current track", () async {
    await svc.playFile( PathFile( "/tmp/cur.mp3" ), "Current", id: "cur" );
    link = PodcastLink.metered;
    await svc.play( "/io/x.mp3", "Ep", id: "pg-1", confirmMobileData: () async => false );
    expect( cache.fetched, isEmpty );
    expect( svc.trackId, "cur" );
    expect( svc.status, PodcastPlayerStatus.playing );
  } );

  test( "play on mobile data with nobody to ask declines", () async {
    link = PodcastLink.metered;
    await svc.play( "/io/x.mp3", "Ep", id: "pg-1" );
    expect( cache.fetched, isEmpty );
    expect( svc.status, PodcastPlayerStatus.idle );
  } );

  test( "play offline with nothing downloaded fails without a download", () async {
    link = PodcastLink.offline;
    await svc.play( "/io/x.mp3", "Ep", id: "pg-1" );
    expect( cache.fetched, isEmpty );
    expect( svc.status, PodcastPlayerStatus.error );
    expect( svc.error, contains( "no connection" ) );
  } );

  test( "trackDownloaded is false with nothing loaded", () {
    expect( svc.trackDownloaded, isFalse );
  } );

  test( "play of the loaded track resumes without downloading", () async {
    await svc.playFile( PathFile( "/tmp/a.mp3" ), "E", id: "pg-1" );
    await svc.pause();
    await svc.play( "/io/x.mp3", "E", id: "pg-1" );
    expect( cache.fetched, isEmpty );
    expect( svc.status, PodcastPlayerStatus.playing );
  } );

  test( "play with an empty path fails without downloading", () async {
    await svc.play( "", "E", id: "pg-1" );
    expect( svc.status, PodcastPlayerStatus.error );
    expect( svc.error,  contains( "No audio path" ) );
    expect( cache.fetched, isEmpty );
  } );

  test( "play reports a download failure", () async {
    cache.failWith = StateError( "dropped" );
    await svc.play( "/io/x.mp3", "E", id: "pg-1" );
    expect( svc.status, PodcastPlayerStatus.error );
    expect( svc.error,  contains( "Download failed" ) );
  } );

  test( "a load failure becomes an error state", () async {
    engine.failLoad = true;
    await svc.playFile( _FakeFile(), "E", id: "pg-1" );
    expect( svc.status, PodcastPlayerStatus.error );
    expect( svc.error,  contains( "Playback failed" ) );
  } );

  test( "stop clears the track and the mini-player", () async {
    await svc.playFile( _FakeFile(), "E", id: "pg-1" );
    await svc.stop();
    expect( svc.status,   PodcastPlayerStatus.idle );
    expect( svc.trackId,  isNull );
    expect( svc.title,    isNull );
    expect( svc.file,     isNull );
    expect( svc.duration, Duration.zero );
    expect( engine.calls.last, "stop" );
  } );

  test( "stop with no engine is a safe no-op", () async {
    await svc.stop();
    expect( svc.status, PodcastPlayerStatus.idle );
    expect( built, 0 );
  } );

  test( "duration events update, and a null duration reads as zero", () async {
    await svc.playFile( _FakeFile(), "E", id: "pg-1" );
    engine.dur.add( const Duration( minutes: 5 ) );
    await Future<void>.delayed( Duration.zero );
    expect( svc.duration, const Duration( minutes: 5 ) );
    engine.dur.add( null );
    await Future<void>.delayed( Duration.zero );
    expect( svc.duration, Duration.zero );
  } );

  test( "lock-screen pause and play follow the engine", () async {
    await svc.playFile( _FakeFile(), "E", id: "pg-1" );
    engine.playing.add( false );
    await Future<void>.delayed( Duration.zero );
    expect( svc.status, PodcastPlayerStatus.paused );
    engine.playing.add( true );
    await Future<void>.delayed( Duration.zero );
    expect( svc.status, PodcastPlayerStatus.playing );
  } );

  test( "engine playing events are ignored when no track is loaded", () async {
    await svc.playFile( _FakeFile(), "E", id: "pg-1" );
    await svc.stop();
    engine.playing.add( true );
    await Future<void>.delayed( Duration.zero );
    expect( svc.status, PodcastPlayerStatus.idle );
  } );

  test( "reaching the end pauses and rewinds, keeping the track", () async {
    await svc.playFile( _FakeFile(), "E", id: "pg-1" );
    engine.pos.add( const Duration( minutes: 4 ) );
    engine.complete.add( null );
    await Future<void>.delayed( Duration.zero );
    expect( svc.status,   PodcastPlayerStatus.paused );
    expect( svc.position, Duration.zero );
    expect( svc.trackId,  "pg-1" );
    expect( engine.calls.takeLast2, [ "pause", "rewind" ] );
  } );

  test( "survives the screen that started it: no widget involved, still playing", () async {
    // The service is app-scoped; nothing a screen does can dispose it.
    await svc.playFile( _FakeFile(), "E", id: "pg-1" );
    await Future<void>.delayed( const Duration( milliseconds: 10 ) );
    expect( svc.isPlaying, isTrue );
    expect( engine.calls, isNot( contains( "stop" ) ) );
  } );

  group( "audio focus for spoken TTS", () {
    test( "followSpeech pauses on speaking and resumes when it ends", () async {
      final speaking = StreamController<bool>.broadcast();
      svc.followSpeech( speaking.stream );
      await svc.playFile( _FakeFile(), "E", id: "pg-1" );

      speaking.add( true );
      await Future<void>.delayed( Duration.zero );
      expect( svc.status, PodcastPlayerStatus.paused );

      speaking.add( false );
      await Future<void>.delayed( Duration.zero );
      expect( svc.status, PodcastPlayerStatus.playing );
      await speaking.close();
    } );

    test( "a second followSpeech replaces the first", () async {
      final first  = StreamController<bool>.broadcast();
      final second = StreamController<bool>.broadcast();
      svc.followSpeech( first.stream );
      svc.followSpeech( second.stream );
      await svc.playFile( _FakeFile(), "E", id: "pg-1" );

      first.add( true );
      await Future<void>.delayed( Duration.zero );
      expect( svc.status, PodcastPlayerStatus.playing, reason: "the replaced source is ignored" );
      second.add( true );
      await Future<void>.delayed( Duration.zero );
      expect( svc.status, PodcastPlayerStatus.paused );
      await first.close();
      await second.close();
    } );

    test( "pauseForSpeech pauses a playing track and resumeAfterSpeech continues it without cutting the speech", () async {
      await svc.playFile( _FakeFile(), "E", id: "pg-1" );
      clearInteractions( tts );
      await svc.pauseForSpeech();
      expect( svc.status, PodcastPlayerStatus.paused );
      await svc.resumeAfterSpeech();
      expect( svc.status, PodcastPlayerStatus.playing );
      expect( engine.calls.takeLast2, [ "pause", "play" ] );
      verifyNever( () => tts.stopAll() );
    } );

    test( "pauseForSpeech does nothing when not playing", () async {
      await svc.pauseForSpeech();
      await svc.resumeAfterSpeech();
      expect( engine.calls, isEmpty );
      await svc.playFile( _FakeFile(), "E", id: "pg-1" );
      await svc.pause();
      await svc.pauseForSpeech();
      await svc.resumeAfterSpeech();
      expect( svc.status, PodcastPlayerStatus.paused, reason: "the listener's own pause is not undone" );
    } );

    test( "a listener who resumes, stops or switches during speech is not overridden", () async {
      await svc.playFile( _FakeFile(), "E", id: "pg-1" );
      await svc.pauseForSpeech();
      await svc.stop();
      await svc.resumeAfterSpeech();
      expect( svc.status, PodcastPlayerStatus.idle );

      await svc.playFile( _FakeFile(), "E", id: "pg-1" );
      await svc.pauseForSpeech();
      await svc.resume();
      await svc.pause();
      await svc.resumeAfterSpeech();
      expect( svc.status, PodcastPlayerStatus.paused );

      await svc.pauseForSpeech();
      await svc.playFile( _FakeFile(), "E2", id: "pg-2" );
      await svc.pause();
      await svc.resumeAfterSpeech();
      expect( svc.status, PodcastPlayerStatus.paused );
    } );
  } );
}

extension on List<String> {
  List<String> get takeLast2 => sublist( length - 2 );
}
