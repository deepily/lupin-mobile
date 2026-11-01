import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/features/artifacts/podcast_play.dart';
import 'package:lupin_mobile/services/audio/podcast_catalog.dart';

import '../../../helpers/fake_podcast_cache.dart';

String abs( String path, [ String label = "Podcast" ] ) => "**$label**: [Listen](/app/audio?path=$path)";

void main() {
  late FakePodcastCache cache;
  late PodcastCatalog   catalog;

  setUp( () {
    cache   = FakePodcastCache();
    catalog = PodcastCatalog( cache );
  } );

  test( "empty cache and no notifications give an empty list", () async {
    expect( await catalog.entries(), isEmpty );
  } );

  test( "a downloaded file with no notification is listed from its file name, dated by file time", () async {
    final name = podcastCacheName( "io/podcast/my-show.mp3" );
    cache.files[ name ]    = PathFile( "/x" );
    cache.modified[ name ] = DateTime( 2026, 10, 30 );
    final rows = await catalog.entries();
    expect( rows.single.title, "my-show" );
    expect( rows.single.audioPath, "io/podcast/my-show.mp3" );
    expect( rows.single.downloaded, isTrue );
    expect( rows.single.date, DateTime( 2026, 10, 30 ) );
  } );

  test( "a held notification not yet downloaded is listed with downloaded false", () async {
    catalog.record( abs( "io/a.mp3" ), title: "Quantum news", at: DateTime( 2026, 10, 31 ) );
    final row = ( await catalog.entries() ).single;
    expect( row.title, "Quantum news" );
    expect( row.downloaded, isFalse );
  } );

  test( "a notification and its file merge into one downloaded row with the notification's title", () async {
    cache.files[ podcastCacheName( "io/a.mp3" ) ] = PathFile( "/x" );
    catalog.record( abs( "io/a.mp3" ), title: "Quantum news", at: DateTime( 2026, 10, 31 ) );
    final rows = await catalog.entries();
    expect( rows, hasLength( 1 ) );
    expect( rows.single.title, "Quantum news" );
    expect( rows.single.downloaded, isTrue );
  } );

  test( "a blank title falls back to the link label", () async {
    catalog.record( abs( "io/a.mp3", "Mexican Spanish" ), title: "  ", at: DateTime( 2026, 10, 31 ) );
    expect( ( await catalog.entries() ).single.title, "Mexican Spanish" );
  } );

  test( "rows are newest first across both sources", () async {
    final old = podcastCacheName( "io/old.mp3" );
    cache.files[ old ]    = PathFile( "/x" );
    cache.modified[ old ] = DateTime( 2026, 10, 1 );
    catalog.record( abs( "io/new.mp3" ), title: "New", at: DateTime( 2026, 10, 31 ) );
    expect( ( await catalog.entries() ).map( ( e ) => e.title ), [ "New", "old" ] );
  } );

  test( "text without audio is ignored and does not notify; recording does notify", () {
    var heard = 0;
    catalog.addListener( () => heard++ );
    catalog.record( null, at: DateTime.now() );
    catalog.record( "nothing here", at: DateTime.now() );
    expect( heard, 0 );
    catalog.record( abs( "io/a.mp3" ), at: DateTime.now() );
    expect( heard, 1 );
  } );

  test( "a cache change notifies the catalog's listeners", () {
    var heard = 0;
    catalog.addListener( () => heard++ );
    cache.notifyListeners();
    expect( heard, 1 );
  } );

  test( "recording the same audio twice keeps one row", () async {
    catalog.record( abs( "io/a.mp3" ), title: "First", at: DateTime( 2026, 10, 30 ) );
    catalog.record( abs( "io/a.mp3" ), title: "Second", at: DateTime( 2026, 10, 31 ) );
    final rows = await catalog.entries();
    expect( rows.single.title, "Second" );
  } );
}
