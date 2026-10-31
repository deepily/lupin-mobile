import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/artifacts/podcast_play.dart';
import 'package:lupin_mobile/features/notifications/presentation/podcast_done_actions.dart';
import 'package:lupin_mobile/services/artifacts/io_file_service.dart';
import 'package:lupin_mobile/services/audio/podcast_player_service.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:mocktail/mocktail.dart';
import '../../helpers/fake_podcast_engine.dart';

/// P4: Play on a podcast-done card.

const String _oneLanguage =
    "**Podcast Activity Report**\n\n**Segments**: 4\n"
    "**English**: [📝 Script](/app/docs?path=io%2Fa.md) | [▶️ Play Here](/app/audio?path=io%2Fa.mp3&embed=1) | "
    "[🎧 Listen](/app/audio?path=io%2Fa.mp3) | [⬇️ Download](/api/io/file?path=io%2Fa.mp3&download=true)\n";

const String _twoLanguages =
    "$_oneLanguage"
    "**Mexican Spanish**: [▶️ Play Here](/app/audio?path=io%2Fb.mp3&embed=1)\n";

const String _twoSameLabel =
    "**English**: [▶️ Play Here](/app/audio?path=io%2Ffirst.mp3&embed=1)\n"
    "**English**: [▶️ Play Here](/app/audio?path=io%2Fsecond.mp3&embed=1)\n";

class _MockIo  extends Mock implements IoFileService {}
class _MockTts extends Mock implements TtsOrchestrator {}
class _File    extends Fake implements File {
  @override final String path;
  _File( this.path );
}

void main() {
  Future<List<List<String>>> pump(
    WidgetTester tester, {
    required String? abstractText,
  } ) async {
    final played = <List<String>>[];
    await tester.pumpWidget( MaterialApp(
      home: Scaffold(
        body: PodcastDoneActions(
          abstractText: abstractText,
          onPlay      : ( url, title ) async => played.add( [ url, title ] ),
        ),
      ),
    ) );
    return played;
  }

  testWidgets( "Play is present and hands the audio link and a title to the player", ( tester ) async {
    final played = await pump( tester, abstractText: _oneLanguage );
    expect( find.text( "Play" ), findsOneWidget );

    await tester.tap( find.byKey( const Key( "${TestKeys.podcastPlayPrefix}0" ) ) );
    expect( played, [ [ "io/a.mp3", "English" ] ] );
  } );

  testWidgets( "one Play per language when there are several", ( tester ) async {
    final played = await pump( tester, abstractText: _twoLanguages );
    expect( find.text( "Play English" ), findsOneWidget );
    expect( find.text( "Play Mexican Spanish" ), findsOneWidget );

    await tester.tap( find.byKey( const Key( "${TestKeys.podcastPlayPrefix}1" ) ) );
    expect( played.single.first, "io/b.mp3" );
  } );

  testWidgets( "an abstract with no audio renders nothing", ( tester ) async {
    await pump( tester, abstractText: "**Segments**: 4" );
    expect( find.byType( FilledButton ), findsNothing );
  } );

  group( "Play through the app-wide player", () {
    late FakeEngine           engine;
    late _MockIo              io;
    late _MockTts             tts;
    late PodcastPlayerService svc;

    setUp( () {
      engine = FakeEngine();
      io     = _MockIo();
      tts    = _MockTts();
      svc    = PodcastPlayerService( engineFactory: () => engine, ioFactory: () => io, ttsFactory: () => tts );
      when( () => tts.stopAll() ).thenAnswer( ( _ ) async {} );
      when( () => io.downloadToCache( any(), any() ) ).thenAnswer( ( inv ) async => _File( "/tmp/${inv.positionalArguments[ 1 ]}" ) );
    } );

    tearDown( () => svc.dispose() );

    Future<void> pumpCards( WidgetTester tester, String abstractText ) => tester.pumpWidget( MaterialApp(
      home: Scaffold( body: PodcastDoneActions( abstractText: abstractText, onPlay: podcastPlayFor( service: svc ) ) ),
    ) );

    testWidgets( "Play downloads the server path and plays it under the path's own id", ( tester ) async {
      await pumpCards( tester, _oneLanguage );
      await tester.tap( find.byKey( const Key( "${TestKeys.podcastPlayPrefix}0" ) ) );
      await tester.pump();

      verify( () => io.downloadToCache( "io/a.mp3", "io-a.mp3" ) ).called( 1 );
      expect( svc.trackId, "io-a" );
      expect( svc.title, "English" );
      expect( svc.isPlaying, isTrue );
    } );

    testWidgets( "two cards with the same label play two different podcasts", ( tester ) async {
      await pumpCards( tester, _twoSameLabel );

      await tester.tap( find.byKey( const Key( "${TestKeys.podcastPlayPrefix}0" ) ) );
      await tester.pump();
      expect( svc.trackId, "io-first" );

      await tester.tap( find.byKey( const Key( "${TestKeys.podcastPlayPrefix}1" ) ) );
      await tester.pump();
      expect( svc.trackId, "io-second" );
      verify( () => io.downloadToCache( "io/second.mp3", "io-second.mp3" ) ).called( 1 );
      expect( engine.calls.where( ( c ) => c.startsWith( "load:" ) ).length, 2 );
    } );

    testWidgets( "tapping the same card again resumes without a second download", ( tester ) async {
      await pumpCards( tester, _oneLanguage );
      final play = find.byKey( const Key( "${TestKeys.podcastPlayPrefix}0" ) );
      await tester.tap( play );
      await tester.pump();
      await tester.tap( play );
      await tester.pump();

      verify( () => io.downloadToCache( any(), any() ) ).called( 1 );
    } );
  } );

  group( "parsing", () {
    test( "audio parsing handles null, empty, a bare download link and a line without a label", () {
      expect( parsePodcastAudio( null ), isEmpty );
      expect( parsePodcastAudio( "" ), isEmpty );
      final bare = parsePodcastAudio( "[⬇️ Download](/api/io/file?path=io%2Fz.mp3&download=true)" );
      expect( bare.single.label, "Podcast" );
      expect( bare.single.url, "io/z.mp3" );
    } );

    test( "the cache name follows the server path, not the title", () {
      expect( podcastCacheName( "io/podcast/a.mp3" ), "io-podcast-a" );
      expect( podcastCacheName( "io/podcast/b.mp3" ), "io-podcast-b" );
      expect( podcastCacheName( "/api/io/file?path=io%2Fpodcast%2Fa.mp3" ), "io-podcast-a" );
      expect( podcastCacheName( "" ), "podcast" );
    } );

    test( "audioPathOf decodes the path query and leaves a bare path alone", () {
      expect( audioPathOf( "/api/io/file?path=io%2Fa.mp3" ), "io/a.mp3" );
      expect( audioPathOf( "io/a.mp3" ), "io/a.mp3" );
    } );
  } );
}
