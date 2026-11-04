import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/artifacts/podcast_play.dart';
import 'package:lupin_mobile/features/podcasts/data/podcast_drive_repository.dart';
import 'package:lupin_mobile/features/podcasts/podcast_list_screen.dart';
import 'package:lupin_mobile/services/audio/podcast_catalog.dart';
import 'package:lupin_mobile/services/audio/podcast_link.dart';
import 'package:lupin_mobile/services/audio/podcast_player_service.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

import '../../helpers/fake_podcast_cache.dart';
import '../../helpers/fake_podcast_engine.dart';

class _MockTts extends Mock implements TtsOrchestrator {}

/// A Drive repository that always answers with [folders] and counts its lists.
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

final _name    = podcastCacheName( _stream );
final _folders = [
  DrivePodcastFolder(
    jobFolder: "pg-1",
    title    : "Desktop explainer",
    created  : DateTime( 2026, 11, 1, 14, 5 ),
    files    : const [ DrivePodcastFile( name: "d1.mp3", mime: "audio/mpeg", size: 1, driveFileId: "d1", streamUrl: _stream ) ],
  ),
];

Finder _key( String prefix ) => find.byKey( Key( "$prefix$_rowId" ) );

/// Rick's four rulings for the Drive row's Download / Delete button.
void main() {
  late FakePodcastCache cache;

  Future<void> open( WidgetTester t, { FakePodcastCache? withCache, PodcastPlayerService? player } ) async {
    final c = withCache ?? cache;
    await t.pumpWidget( MaterialApp( home: PodcastListScreen(
      catalog  : PodcastCatalog( c ),
      drive    : _FakeDrive( _folders ),
      cache    : c,
      player   : player,
      linkProbe: () async => PodcastLink.unmetered,
      onPlay   : ( _, __ ) async {},
    ) ) );
    await t.pumpAndSettle();
  }

  /// Lets the five-second Undo window end and the snackbar leave.
  Future<void> pastUndo( WidgetTester t ) async {
    await t.pump( const Duration( seconds: 6 ) );
    await t.pumpAndSettle();
  }

  setUp( () => cache = FakePodcastCache() );

  testWidgets( "ruling 1: one button per row, Download off the phone and Delete on it", ( t ) async {
    await open( t );
    expect( _key( TestKeys.podcastDriveDownloadPrefix ), findsOneWidget );
    expect( _key( TestKeys.podcastDriveDeletePrefix ), findsNothing );

    await t.tap( _key( TestKeys.podcastDriveDownloadPrefix ) );
    await t.pumpAndSettle();
    expect( _key( TestKeys.podcastDriveDeletePrefix ), findsOneWidget );
    expect( _key( TestKeys.podcastDriveDownloadPrefix ), findsNothing );
  } );

  testWidgets( "ruling 1: Delete removes the phone copy only, after the Undo window", ( t ) async {
    cache.files[ _name ] = PathFile( "/tmp/x.mp3" );
    await open( t );

    await t.tap( _key( TestKeys.podcastDriveDeletePrefix ) );
    await t.pumpAndSettle();
    expect( cache.deleted, isEmpty );

    await pastUndo( t );
    expect( cache.deleted, [ _name ] );
    expect( _key( TestKeys.podcastDriveDownloadPrefix ), findsOneWidget );
    // The Drive row itself is still listed, so the Drive file was not touched.
    expect( _key( TestKeys.podcastDriveRowPrefix ), findsOneWidget );
  } );

  testWidgets( "ruling 2: no confirmation dialog, a snackbar with Undo, and Undo keeps the copy", ( t ) async {
    cache.files[ _name ] = PathFile( "/tmp/x.mp3" );
    await open( t );

    await t.tap( _key( TestKeys.podcastDriveDeletePrefix ) );
    await t.pump();
    expect( find.byType( AlertDialog ), findsNothing );
    expect( find.byType( Dialog ), findsNothing );
    expect( find.byKey( const Key( TestKeys.podcastDriveDeleteUndo ) ), findsOneWidget );

    await t.pumpAndSettle( const Duration( milliseconds: 300 ) );
    await t.tap( find.byKey( const Key( TestKeys.podcastDriveDeleteUndo ) ) );
    await pastUndo( t );

    expect( cache.deleted, isEmpty );
    expect( cache.isCached( _name ), isTrue );
    expect( _key( TestKeys.podcastDriveDeletePrefix ), findsOneWidget );
  } );

  testWidgets( "ruling 2: tapping Download inside the Undo window keeps the copy and fetches nothing", ( t ) async {
    cache.files[ _name ] = PathFile( "/tmp/x.mp3" );
    await open( t );

    await t.tap( _key( TestKeys.podcastDriveDeletePrefix ) );
    await t.pump();
    await t.tap( _key( TestKeys.podcastDriveDownloadPrefix ) );
    await pastUndo( t );

    expect( cache.deleted, isEmpty );
    expect( cache.fetched, isEmpty );
    expect( _key( TestKeys.podcastDriveDeletePrefix ), findsOneWidget );
  } );

  testWidgets( "ruling 3: deleting the playing podcast keeps it playing, shows Download now, and deletes when it stops", ( t ) async {
    final engine = FakeEngine()..playEnds = Completer<void>();
    final tts    = _MockTts();
    when( () => tts.stopAll() ).thenAnswer( ( _ ) async {} );
    final svc    = PodcastPlayerService( engineFactory: () => engine, cacheFactory: () => cache, linkProbe: () async => PodcastLink.unmetered, ttsFactory: () => tts );
    cache.files[ _name ] = PathFile( "/tmp/x.mp3" );
    await open( t, player: svc );
    await svc.playFile( cache.files[ _name ]!, "Desktop explainer", id: _name );

    await t.tap( _key( TestKeys.podcastDriveDeletePrefix ) );
    await t.pumpAndSettle();
    expect( _key( TestKeys.podcastDriveDownloadPrefix ), findsOneWidget );

    await pastUndo( t );
    expect( svc.isPlaying, isTrue );
    expect( cache.deleted, isEmpty, reason: "the file is in use, so it must outlive the Undo window" );
    expect( _key( TestKeys.podcastDriveDownloadPrefix ), findsOneWidget );

    await svc.stop();
    await t.pumpAndSettle();
    expect( cache.deleted, [ _name ] );
    expect( _key( TestKeys.podcastDriveDownloadPrefix ), findsOneWidget );
    svc.dispose();
  } );

  testWidgets( "ruling 3: the copy also goes when the player moves on to another podcast", ( t ) async {
    final engine = FakeEngine()..playEnds = Completer<void>();
    final tts    = _MockTts();
    when( () => tts.stopAll() ).thenAnswer( ( _ ) async {} );
    final svc    = PodcastPlayerService( engineFactory: () => engine, cacheFactory: () => cache, linkProbe: () async => PodcastLink.unmetered, ttsFactory: () => tts );
    cache.files[ _name ]  = PathFile( "/tmp/x.mp3" );
    cache.files[ "other" ] = PathFile( "/tmp/o.mp3" );
    await open( t, player: svc );
    await svc.playFile( cache.files[ _name ]!, "Desktop explainer", id: _name );

    await t.tap( _key( TestKeys.podcastDriveDeletePrefix ) );
    await t.pumpAndSettle();
    await pastUndo( t );
    expect( cache.deleted, isEmpty );

    await svc.playFile( cache.files[ "other" ]!, "Other", id: "other" );
    await t.pumpAndSettle();
    expect( cache.deleted, [ _name ] );
    svc.dispose();
  } );

  testWidgets( "ruling 4: a progress ring sits on the button while it downloads", ( t ) async {
    final slow = _SlowCache();
    await open( t, withCache: slow );

    await t.tap( _key( TestKeys.podcastDriveDownloadPrefix ) );
    await t.pump();
    await t.pump();
    expect( find.descendant( of: _key( TestKeys.podcastDriveDownloadingPrefix ), matching: find.byType( CircularProgressIndicator ) ), findsOneWidget );
    expect( _key( TestKeys.podcastDriveDownloadPrefix ), findsNothing );
    expect( _key( TestKeys.podcastDriveDeletePrefix ), findsNothing );

    slow.gate.complete();
    await t.pumpAndSettle();
    expect( _key( TestKeys.podcastDriveDeletePrefix ), findsOneWidget );
  } );

  testWidgets( "delete, keep via Download, delete again: the first snackbar's close must not delete the copy", ( t ) async {
    cache.files[ _name ] = PathFile( "/tmp/x.mp3" );
    await open( t );

    await t.tap( _key( TestKeys.podcastDriveDeletePrefix ) );
    await t.pumpAndSettle( const Duration( milliseconds: 300 ) );
    await t.tap( _key( TestKeys.podcastDriveDownloadPrefix ) );
    await t.pumpAndSettle( const Duration( milliseconds: 300 ) );
    await t.tap( _key( TestKeys.podcastDriveDeletePrefix ) );
    await t.pumpAndSettle( const Duration( milliseconds: 300 ) );

    expect( cache.deleted, isEmpty, reason: "file went before the second Undo window ended" );
    await t.tap( find.byKey( const Key( TestKeys.podcastDriveDeleteUndo ) ) );
    await pastUndo( t );
    expect( cache.deleted, isEmpty );
    expect( cache.isCached( _name ), isTrue );
  } );
}
