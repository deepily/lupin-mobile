import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/artifacts/podcast_play.dart';
import 'package:lupin_mobile/features/podcasts/data/podcast_drive_repository.dart';
import 'package:lupin_mobile/features/podcasts/podcast_list_screen.dart';
import 'package:lupin_mobile/services/audio/podcast_catalog.dart';
import 'package:lupin_mobile/services/audio/podcast_link.dart';

import '../../helpers/fake_podcast_cache.dart';

/// A Drive repository that always answers with [folders].
class _FakeDrive implements PodcastDriveRepository {
  final List<DrivePodcastFolder> folders;
  _FakeDrive( this.folders );

  @override
  Future<List<DrivePodcastFolder>> list() async => folders;
}

/// A cache whose downloads finish only when the test completes [gate].
class _SlowCache extends FakePodcastCache {
  final Completer<void> gate = Completer<void>();

  @override
  Future<File> fetch( String serverPath, String name ) async {
    await gate.future;
    return super.fetch( serverPath, name );
  }
}

const _stream = "/api/podcast-drive/stream/d1";
const _rowId  = "pg-1/d1";

final _folders = [
  DrivePodcastFolder(
    jobFolder: "pg-1",
    title    : "Desktop explainer",
    created  : DateTime( 2026, 11, 1, 14, 5 ),
    files    : const [ DrivePodcastFile( name: "d1.mp3", mime: "audio/mpeg", size: 1, driveFileId: "d1", streamUrl: _stream ) ],
  ),
];

Finder _key( String prefix ) => find.byKey( Key( "$prefix$_rowId" ) );

void main() {
  late FakePodcastCache cache;
  late PodcastLink      link;

  Future<void> open( WidgetTester t, { FakePodcastCache? withCache, bool settle = true } ) async {
    final c = withCache ?? cache;
    await t.pumpWidget( MaterialApp( home: PodcastListScreen(
      catalog  : PodcastCatalog( c ),
      drive    : _FakeDrive( _folders ),
      cache    : c,
      linkProbe: () async => link,
      onPlay   : ( _, __ ) async {},
    ) ) );
    if ( settle ) await t.pumpAndSettle();
  }

  setUp( () {
    cache = FakePodcastCache();
    link  = PodcastLink.unmetered;
  } );

  testWidgets( "on Wi-Fi, download keeps the podcast on the phone and the row shows it is there", ( t ) async {
    await open( t );
    expect( _key( TestKeys.podcastDriveDownloadedPrefix ), findsNothing );

    await t.tap( _key( TestKeys.podcastDriveDownloadPrefix ) );
    await t.pumpAndSettle();

    final name = podcastCacheName( _stream );
    expect( cache.fetched, [ [ _stream, name ] ] );
    expect( cache.savedTitles[ name ], "Desktop explainer" );
    expect( _key( TestKeys.podcastDriveDownloadedPrefix ), findsOneWidget );
    expect( _key( TestKeys.podcastDriveDownloadPrefix ), findsNothing );
    expect( find.byKey( Key( "${TestKeys.podcastListRowPrefix}$name" ) ), findsOneWidget );
  } );

  testWidgets( "the mark appears as soon as the cache reports the file", ( t ) async {
    await open( t );

    await cache.fetch( _stream, podcastCacheName( _stream ) );
    await t.pumpAndSettle();

    expect( _key( TestKeys.podcastDriveDownloadedPrefix ), findsOneWidget );
  } );

  testWidgets( "two quick taps on mobile data open one sheet, not two", ( t ) async {
    link = PodcastLink.metered;
    await open( t );

    await t.tap( _key( TestKeys.podcastDriveDownloadPrefix ) );
    await t.tap( _key( TestKeys.podcastDriveDownloadPrefix ) );
    await t.pumpAndSettle();
    expect( find.byKey( const Key( TestKeys.podcastDataSheet ) ), findsOneWidget );
  } );

  testWidgets( "a connection check that throws says so and the button comes back", ( t ) async {
    await t.pumpWidget( MaterialApp( home: PodcastListScreen(
      catalog  : PodcastCatalog( cache ),
      drive    : _FakeDrive( _folders ),
      cache    : cache,
      linkProbe: () async => throw Exception( "no plugin" ),
      onPlay   : ( _, __ ) async {},
    ) ) );
    await t.pumpAndSettle();

    await t.tap( _key( TestKeys.podcastDriveDownloadPrefix ) );
    await t.pumpAndSettle();

    expect( find.textContaining( "Could not check the connection" ), findsOneWidget );
    expect( _key( TestKeys.podcastDriveDownloadPrefix ), findsOneWidget );
    expect( cache.fetched, isEmpty );
  } );

  testWidgets( "a podcast already on the phone shows the mark and no download button", ( t ) async {
    cache.files[ podcastCacheName( _stream ) ] = PathFile( "/tmp/x.mp3" );
    await open( t );

    expect( _key( TestKeys.podcastDriveDownloadedPrefix ), findsOneWidget );
    expect( _key( TestKeys.podcastDriveDownloadPrefix ), findsNothing );
    expect( _key( TestKeys.podcastDrivePlayPrefix ), findsOneWidget );
  } );

  testWidgets( "while it downloads the row shows a spinner in place of the button, then the mark", ( t ) async {
    final slow = _SlowCache();
    await open( t, withCache: slow );

    await t.tap( _key( TestKeys.podcastDriveDownloadPrefix ) );
    await t.pump();
    await t.pump();
    expect( _key( TestKeys.podcastDriveDownloadingPrefix ), findsOneWidget );
    expect( _key( TestKeys.podcastDriveDownloadPrefix ), findsNothing );

    slow.gate.complete();
    await t.pumpAndSettle();
    expect( _key( TestKeys.podcastDriveDownloadingPrefix ), findsNothing );
    expect( _key( TestKeys.podcastDriveDownloadedPrefix ), findsOneWidget );
    expect( slow.fetched.length, 1 );
  } );

  testWidgets( "on mobile data it asks first, and Cancel downloads nothing", ( t ) async {
    link = PodcastLink.metered;
    await open( t );

    await t.tap( _key( TestKeys.podcastDriveDownloadPrefix ) );
    await t.pumpAndSettle();
    expect( find.byKey( const Key( TestKeys.podcastDataSheet ) ), findsOneWidget );

    await t.tap( find.byKey( const Key( TestKeys.podcastDataNo ) ) );
    await t.pumpAndSettle();
    expect( cache.fetched, isEmpty );
    expect( _key( TestKeys.podcastDriveDownloadPrefix ), findsOneWidget );
  } );

  testWidgets( "on mobile data, tapping Download in the sheet downloads it", ( t ) async {
    link = PodcastLink.metered;
    await open( t );

    await t.tap( _key( TestKeys.podcastDriveDownloadPrefix ) );
    await t.pumpAndSettle();
    await t.tap( find.byKey( const Key( TestKeys.podcastDataYes ) ) );
    await t.pumpAndSettle();

    expect( cache.fetched.length, 1 );
    expect( _key( TestKeys.podcastDriveDownloadedPrefix ), findsOneWidget );
  } );

  testWidgets( "with no connection it says so and downloads nothing", ( t ) async {
    link = PodcastLink.offline;
    await open( t );

    await t.tap( _key( TestKeys.podcastDriveDownloadPrefix ) );
    await t.pumpAndSettle();

    expect( find.textContaining( "no connection" ), findsOneWidget );
    expect( cache.fetched, isEmpty );
  } );

  testWidgets( "a failed download says so and the button comes back to try again", ( t ) async {
    cache.failWith = Exception( "503" );
    await open( t );

    await t.tap( _key( TestKeys.podcastDriveDownloadPrefix ) );
    await t.pumpAndSettle();

    expect( find.textContaining( "Could not download Desktop explainer" ), findsOneWidget );
    expect( _key( TestKeys.podcastDriveDownloadPrefix ), findsOneWidget );
    expect( _key( TestKeys.podcastDriveDownloadedPrefix ), findsNothing );

    cache.failWith = null;
    await t.tap( _key( TestKeys.podcastDriveDownloadPrefix ) );
    await t.pumpAndSettle();
    expect( _key( TestKeys.podcastDriveDownloadedPrefix ), findsOneWidget );
  } );

  testWidgets( "with no cache given or registered, Drive rows have no download button", ( t ) async {
    await t.pumpWidget( MaterialApp( home: PodcastListScreen(
      catalog: PodcastCatalog( cache ),
      drive  : _FakeDrive( _folders ),
      onPlay : ( _, __ ) async {},
    ) ) );
    await t.pumpAndSettle();

    expect( _key( TestKeys.podcastDrivePlayPrefix ), findsOneWidget );
    expect( _key( TestKeys.podcastDriveDownloadPrefix ), findsNothing );
  } );
}
