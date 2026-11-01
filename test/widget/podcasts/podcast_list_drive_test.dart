import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/artifacts/podcast_play.dart';
import 'package:lupin_mobile/features/podcasts/data/podcast_drive_repository.dart';
import 'package:lupin_mobile/features/podcasts/podcast_list_screen.dart';
import 'package:lupin_mobile/services/audio/podcast_catalog.dart';

import '../../helpers/fake_podcast_cache.dart';

/// A Drive repository that answers from a queue of canned results, one per call.
class _FakeDrive implements PodcastDriveRepository {
  final List<Object> answers;
  int calls = 0;
  _FakeDrive( this.answers );

  @override
  Future<List<DrivePodcastFolder>> list() async {
    final a = answers[ calls < answers.length ? calls : answers.length - 1 ];
    calls++;
    if ( a is PodcastDriveException ) throw a;
    return a as List<DrivePodcastFolder>;
  }
}

DrivePodcastFile _audio( String id, { String mime = "audio/mpeg" } ) => DrivePodcastFile(
  name: "$id.mp3", mime: mime, size: 1, driveFileId: id, streamUrl: "/api/podcast-drive/stream/$id",
);

DrivePodcastFolder _folder( String job, String title, List<DrivePodcastFile> files ) =>
    DrivePodcastFolder( jobFolder: job, title: title, created: DateTime( 2026, 11, 1, 14, 5 ), files: files );

void main() {
  late FakePodcastCache cache;
  late PodcastCatalog   catalog;
  final played = <List<String>>[];

  setUp( () {
    cache   = FakePodcastCache();
    catalog = PodcastCatalog( cache );
    played.clear();
  } );

  Future<void> open( WidgetTester t, _FakeDrive drive ) async {
    await t.pumpWidget( MaterialApp( home: PodcastListScreen(
      catalog: catalog,
      drive  : drive,
      onPlay : ( url, title ) async { played.add( [ url, title ] ); },
    ) ) );
    await t.pumpAndSettle();
  }

  testWidgets( "Drive podcasts list under their own header below the phone's rows", ( t ) async {
    catalog.record( "**Podcast**: [x](/app/audio?path=io/new.mp3)", title: "On the phone", at: DateTime( 2026, 10, 31 ) );
    await open( t, _FakeDrive( [ [ _folder( "pg-07ffadef", "Desktop explainer", [ _audio( "d1" ) ] ) ] ] ) );

    expect( find.byKey( const Key( TestKeys.podcastDriveHeader ) ), findsOneWidget );
    expect( find.byKey( const Key( "${TestKeys.podcastDriveRowPrefix}pg-07ffadef/d1" ) ), findsOneWidget );
    final phoneY  = t.getTopLeft( find.text( "On the phone" ) ).dy;
    final headerY = t.getTopLeft( find.byKey( const Key( TestKeys.podcastDriveHeader ) ) ).dy;
    final driveY  = t.getTopLeft( find.text( "Desktop explainer" ) ).dy;
    expect( phoneY, lessThan( headerY ) );
    expect( headerY, lessThan( driveY ) );
  } );

  testWidgets( "Play on a Drive row plays its stream path and saves its title for the download", ( t ) async {
    await open( t, _FakeDrive( [ [ _folder( "pg-1", "Desktop explainer", [ _audio( "d1" ) ] ) ] ] ) );

    await t.tap( find.byKey( const Key( "${TestKeys.podcastDrivePlayPrefix}pg-1/d1" ) ) );
    await t.pumpAndSettle();

    expect( played, [ [ "/api/podcast-drive/stream/d1", "Desktop explainer" ] ] );
    expect( cache.savedTitles[ podcastCacheName( "/api/podcast-drive/stream/d1" ) ], "Desktop explainer" );
  } );

  testWidgets( "a 403 shows the reason in the Drive section and the phone's rows still show", ( t ) async {
    catalog.record( "**Podcast**: [x](/app/audio?path=io/new.mp3)", title: "On the phone", at: DateTime( 2026, 10, 31 ) );
    await open( t, _FakeDrive( [ const PodcastDriveException( "Only the login that owns the Drive link can see the Drive podcasts.", statusCode: 403 ) ] ) );

    expect( find.text( "On the phone" ), findsOneWidget );
    expect( find.byKey( const Key( TestKeys.podcastDriveError ) ), findsOneWidget );
    expect( find.textContaining( "owns the Drive link" ), findsOneWidget );
    expect( find.byType( CircularProgressIndicator ), findsNothing );
  } );

  testWidgets( "pulling down after a failure loads the Drive list", ( t ) async {
    final drive = _FakeDrive( [
      const PodcastDriveException( "Could not reach the server: offline" ),
      [ _folder( "pg-1", "Back again", [ _audio( "d1" ) ] ) ],
    ] );
    await open( t, drive );
    expect( find.byKey( const Key( TestKeys.podcastDriveError ) ), findsOneWidget );

    await t.fling( find.byKey( const Key( TestKeys.podcastList ) ), const Offset( 0, 400 ), 1000 );
    await t.pumpAndSettle();

    expect( drive.calls, 2 );
    expect( find.byKey( const Key( TestKeys.podcastDriveError ) ), findsNothing );
    expect( find.text( "Back again" ), findsOneWidget );
  } );

  testWidgets( "an empty Drive says so, and an empty phone says so too", ( t ) async {
    await open( t, _FakeDrive( [ <DrivePodcastFolder>[] ] ) );

    expect( find.byKey( const Key( TestKeys.podcastDriveEmpty ) ), findsOneWidget );
    expect( find.byKey( const Key( TestKeys.podcastListEmpty ) ), findsOneWidget );
  } );

  testWidgets( "a folder with two audio files gets one row each, named by file; non-audio is skipped", ( t ) async {
    await open( t, _FakeDrive( [ [ _folder( "pg-1", "Two parts", [ _audio( "p1" ), _audio( "p2" ), _audio( "notes", mime: "text/plain" ) ] ) ] ] ) );

    expect( find.text( "Two parts (p1.mp3)" ), findsOneWidget );
    expect( find.text( "Two parts (p2.mp3)" ), findsOneWidget );
    expect( find.byKey( const Key( "${TestKeys.podcastDriveRowPrefix}pg-1/notes" ) ), findsNothing );
  } );

  testWidgets( "the same Drive file in two folders gets two distinct rows", ( t ) async {
    await open( t, _FakeDrive( [ [ _folder( "pg-a", "First", [ _audio( "same" ) ] ), _folder( "pg-b", "Second", [ _audio( "same" ) ] ) ] ] ) );

    expect( t.takeException(), isNull );
    expect( find.byKey( const Key( "${TestKeys.podcastDriveRowPrefix}pg-a/same" ) ), findsOneWidget );
    expect( find.byKey( const Key( "${TestKeys.podcastDriveRowPrefix}pg-b/same" ) ), findsOneWidget );
  } );
}
