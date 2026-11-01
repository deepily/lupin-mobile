import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/artifacts/podcast_play.dart';
import 'package:lupin_mobile/features/podcasts/podcast_list_screen.dart';
import 'package:lupin_mobile/services/audio/podcast_catalog.dart';

import '../../helpers/fake_podcast_cache.dart';

void main() {
  late FakePodcastCache cache;
  late PodcastCatalog   catalog;
  final played = <List<String>>[];

  setUp( () {
    cache   = FakePodcastCache();
    catalog = PodcastCatalog( cache );
    played.clear();
  } );

  Future<void> open( WidgetTester t ) async {
    await t.pumpWidget( MaterialApp( home: PodcastListScreen(
      catalog: catalog,
      onPlay : ( url, title ) async { played.add( [ url, title ] ); },
    ) ) );
    await t.pumpAndSettle();
  }

  testWidgets( "empty state shows a message", ( t ) async {
    await open( t );
    expect( find.byKey( const Key( TestKeys.podcastListEmpty ) ), findsOneWidget );
  } );

  testWidgets( "lists newest first with the downloaded mark only on downloaded rows", ( t ) async {
    final old = podcastCacheName( "io/old.mp3" );
    cache.files[ old ]    = PathFile( "/x" );
    cache.modified[ old ] = DateTime( 2026, 10, 1 );
    catalog.record( "**Podcast**: [x](/app/audio?path=io/new.mp3)", title: "New one", at: DateTime( 2026, 10, 31 ) );
    await open( t );

    final newY = t.getTopLeft( find.text( "New one" ) ).dy;
    final oldY = t.getTopLeft( find.text( "old" ) ).dy;
    expect( newY, lessThan( oldY ) );
    expect( find.byKey( Key( "${TestKeys.podcastListDownloadedPrefix}$old" ) ), findsOneWidget );
    expect( find.byKey( Key( "${TestKeys.podcastListDownloadedPrefix}${podcastCacheName( "io/new.mp3" )}" ) ), findsNothing );
  } );

  testWidgets( "Play hands the server path and title to the player", ( t ) async {
    catalog.record( "**Podcast**: [x](/app/audio?path=io/new.mp3)", title: "New one", at: DateTime( 2026, 10, 31 ) );
    await open( t );
    await t.tap( find.byKey( Key( "${TestKeys.podcastListPlayPrefix}${podcastCacheName( "io/new.mp3" )}" ) ) );
    expect( played, [ [ "io/new.mp3", "New one" ] ] );
  } );

  testWidgets( "a download finishing adds its mark without reopening", ( t ) async {
    catalog.record( "**Podcast**: [x](/app/audio?path=io/new.mp3)", title: "New one", at: DateTime( 2026, 10, 31 ) );
    await open( t );
    final name = podcastCacheName( "io/new.mp3" );
    expect( find.byKey( Key( "${TestKeys.podcastListDownloadedPrefix}$name" ) ), findsNothing );
    cache.files[ name ] = PathFile( "/x" );
    cache.notifyListeners();
    await t.pumpAndSettle();
    expect( find.byKey( Key( "${TestKeys.podcastListDownloadedPrefix}$name" ) ), findsOneWidget );
  } );

  testWidgets( "a reload keeps the old rows on screen instead of showing a spinner", ( t ) async {
    catalog.record( "**Podcast**: [x](/app/audio?path=io/new.mp3)", title: "New one", at: DateTime( 2026, 10, 31 ) );
    await open( t );
    catalog.record( "**Podcast**: [x](/app/audio?path=io/two.mp3)", title: "Two", at: DateTime( 2026, 10, 30 ) );
    await t.pump();
    expect( find.byType( CircularProgressIndicator ), findsNothing );
    expect( find.text( "New one" ), findsOneWidget );
    await t.pumpAndSettle();
    expect( find.text( "Two" ), findsOneWidget );
  } );
}
