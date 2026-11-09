import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/artifacts/podcast_play.dart';
import 'package:lupin_mobile/features/notifications/presentation/podcast_done_actions.dart';
import 'package:lupin_mobile/services/audio/podcast_link.dart';
import 'package:lupin_mobile/services/audio/podcast_player_service.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:mocktail/mocktail.dart';
import '../../helpers/fake_podcast_cache.dart';
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

class _MockTts extends Mock implements TtsOrchestrator {}
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
    late FakePodcastCache     cache;
    late PodcastLink          link;
    late _MockTts             tts;
    late PodcastPlayerService svc;

    setUp( () {
      engine = FakeEngine();
      cache  = FakePodcastCache();
      link   = PodcastLink.unmetered;
      tts    = _MockTts();
      svc    = PodcastPlayerService( engineFactory: () => engine, cacheFactory: () => cache, linkProbe: () async => link, ttsFactory: () => tts );
      when( () => tts.stopAll() ).thenAnswer( ( _ ) async {} );
    } );

    tearDown( () => svc.dispose() );

    Future<void> pumpCards( WidgetTester tester, String abstractText ) => tester.pumpWidget( MaterialApp(
      home: Scaffold( body: PodcastDoneActions( abstractText: abstractText, onPlay: podcastPlayFor( service: svc ) ) ),
    ) );

    testWidgets( "Play downloads the server path and plays it under the path's own id", ( tester ) async {
      await pumpCards( tester, _oneLanguage );
      await tester.tap( find.byKey( const Key( "${TestKeys.podcastPlayPrefix}0" ) ) );
      await tester.pump();

      expect( cache.fetched, [ [ "io/a.mp3", "io%2Fa.mp3" ] ] );
      expect( svc.trackId, "io%2Fa.mp3" );
      expect( svc.title, "English" );
      expect( svc.isPlaying, isTrue );
    } );

    testWidgets( "two cards with the same label play two different podcasts", ( tester ) async {
      await pumpCards( tester, _twoSameLabel );

      await tester.tap( find.byKey( const Key( "${TestKeys.podcastPlayPrefix}0" ) ) );
      await tester.pump();
      expect( svc.trackId, "io%2Ffirst.mp3" );

      await tester.tap( find.byKey( const Key( "${TestKeys.podcastPlayPrefix}1" ) ) );
      await tester.pump();
      expect( svc.trackId, "io%2Fsecond.mp3" );
      expect( cache.fetched.last, [ "io/second.mp3", "io%2Fsecond.mp3" ] );
      expect( engine.calls.where( ( c ) => c.startsWith( "load:" ) ).length, 2 );
    } );

    testWidgets( "tapping the same card again resumes without a second download", ( tester ) async {
      await pumpCards( tester, _oneLanguage );
      final play = find.byKey( const Key( "${TestKeys.podcastPlayPrefix}0" ) );
      await tester.tap( play );
      await tester.pump();
      await tester.tap( play );
      await tester.pump();

      expect( cache.fetched.length, 1 );
    } );
  } );

  group( "downloads and mobile data", () {
    late FakeEngine           engine;
    late FakePodcastCache     cache;
    late PodcastLink          link;
    late PodcastPlayerService svc;

    setUp( () {
      engine = FakeEngine();
      cache  = FakePodcastCache();
      link   = PodcastLink.metered;
      final tts = _MockTts();
      when( () => tts.stopAll() ).thenAnswer( ( _ ) async {} );
      svc = PodcastPlayerService( engineFactory: () => engine, cacheFactory: () => cache, linkProbe: () async => link, ttsFactory: () => tts );
    } );

    tearDown( () => svc.dispose() );

    Future<void> pumpCard( WidgetTester tester, {bool wired = true} ) => tester.pumpWidget( MaterialApp(
      home: Scaffold( body: Builder( builder: ( context ) => PodcastDoneActions(
        abstractText: _oneLanguage,
        cache       : cache,
        onPlay      : podcastPlayFor( service: svc, context: context ),
      ) ) ),
    ) );

    final play = find.byKey( const Key( "${TestKeys.podcastPlayPrefix}0" ) );

    testWidgets( "Play on mobile data asks in an in-app sheet and downloads nothing until Download", ( tester ) async {
      await pumpCard( tester );
      await tester.tap( play );
      await tester.pumpAndSettle();

      expect( find.byKey( const Key( TestKeys.podcastDataSheet ) ), findsOneWidget );
      expect( find.text( "Download over mobile data?" ), findsOneWidget );
      expect( cache.fetched, isEmpty );

      await tester.tap( find.byKey( const Key( TestKeys.podcastDataYes ) ) );
      await tester.pumpAndSettle();
      expect( cache.fetched, [ [ "io/a.mp3", "io%2Fa.mp3" ] ] );
      expect( svc.isPlaying, isTrue );
    } );

    testWidgets( "Cancel on the sheet downloads nothing and plays nothing", ( tester ) async {
      await pumpCard( tester );
      await tester.tap( play );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.podcastDataNo ) ) );
      await tester.pumpAndSettle();

      expect( cache.fetched, isEmpty );
      expect( svc.hasTrack, isFalse );
      expect( find.byKey( const Key( TestKeys.podcastDataSheet ) ), findsNothing );
    } );

    testWidgets( "dismissing the sheet counts as no", ( tester ) async {
      await pumpCard( tester );
      await tester.tap( play );
      await tester.pumpAndSettle();
      await tester.tapAt( const Offset( 5, 5 ) );
      await tester.pumpAndSettle();

      expect( cache.fetched, isEmpty );
    } );

    testWidgets( "a card whose screen is gone before the answer is needed declines quietly", ( tester ) async {
      await pumpCard( tester );
      final onPlay = podcastPlayFor( service: svc, context: tester.element( find.byType( PodcastDoneActions ) ) );
      await tester.pumpWidget( const SizedBox() );
      await onPlay( "io/a.mp3", "English" );
      expect( cache.fetched, isEmpty );
    } );

    testWidgets( "Play on Wi-Fi downloads with no sheet", ( tester ) async {
      link = PodcastLink.unmetered;
      await pumpCard( tester );
      await tester.tap( play );
      await tester.pumpAndSettle();

      expect( find.byKey( const Key( TestKeys.podcastDataSheet ) ), findsNothing );
      expect( cache.fetched.length, 1 );
    } );

    testWidgets( "a downloaded podcast plays with no sheet even on mobile data", ( tester ) async {
      cache.files[ "io%2Fa.mp3" ] = PathFile( "/kept/a.mp3" );
      await pumpCard( tester );
      await tester.tap( play );
      await tester.pumpAndSettle();

      expect( find.byKey( const Key( TestKeys.podcastDataSheet ) ), findsNothing );
      expect( cache.fetched, isEmpty );
      expect( svc.isPlaying, isTrue );
    } );

    testWidgets( "the downloaded marker shows only for downloaded audio and appears when a download finishes", ( tester ) async {
      await pumpCard( tester );
      const marker = Key( "${TestKeys.podcastDownloadedPrefix}0" );
      expect( find.byKey( marker ), findsNothing );

      await cache.fetch( "io/a.mp3", "io%2Fa.mp3" );
      await tester.pump();
      expect( find.byKey( marker ), findsOneWidget );
    } );

    testWidgets( "without a cache the card still shows Play and no marker", ( tester ) async {
      await tester.pumpWidget( MaterialApp( home: Scaffold( body: PodcastDoneActions( abstractText: _oneLanguage, onPlay: ( _, __ ) async {} ) ) ) );
      expect( find.text( "Play" ), findsOneWidget );
      expect( find.byIcon( Icons.download_done ), findsNothing );
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

    test( "the cache name is one-to-one with the server path", () {
      expect( podcastCacheName( "io/a-b.mp3" ), isNot( podcastCacheName( "io/a/b.mp3" ) ) );
      expect( podcastCacheName( "io/a.mp3" ), isNot( podcastCacheName( "io/a" ) ) );
      expect( podcastCacheName( "io/u@x.y/pg-1/podcast.mp3" ), "io%2Fu%40x.y%2Fpg-1%2Fpodcast.mp3" );
      expect( podcastCacheName( "/api/io/file?path=io%2Fa.mp3" ), podcastCacheName( "io/a.mp3" ) );
      expect( podcastCacheName( "io/a.mp3" ), isNot( contains( "/" ) ) );
      expect( podcastCacheName( "" ), "podcast" );
    } );

    test( "audioPathOf decodes the path query and leaves a bare path alone", () {
      expect( audioPathOf( "/api/io/file?path=io%2Fa.mp3" ), "io/a.mp3" );
      expect( audioPathOf( "io/a.mp3" ), "io/a.mp3" );
    } );
  } );
}
