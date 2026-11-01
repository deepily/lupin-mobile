import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/services/artifacts/io_file_service.dart';
import 'package:lupin_mobile/services/audio/podcast_cache.dart';

class _MockIo extends Mock implements IoFileService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory    tmp;
  late Directory    dir;
  late _MockIo      io;
  late PodcastCache cache;
  var   clock = DateTime( 2026, 10, 31 );

  setUpAll( () => registerFallbackValue( File( "x" ) ) );

  setUp( () {
    tmp   = Directory.systemTemp.createTempSync( "podcast_cache_test" );
    dir   = Directory( "${tmp.path}/podcasts" );
    io    = _MockIo();
    clock = DateTime( 2026, 10, 31 );
    cache = PodcastCache( ioFactory: () => io, dirFactory: () async => dir, now: () => clock );
  } );

  tearDown( () => tmp.deleteSync( recursive: true ) );

  /// Stubs a download that writes [bytes] to the file it is given.
  void downloadWrites( String bytes ) => when( () => io.downloadTo( any(), any() ) ).thenAnswer( ( inv ) async {
    await ( inv.positionalArguments[ 1 ] as File ).writeAsString( bytes );
  } );

  test( "entries lists whole mp3 files newest first and skips .part files", () async {
    dir.createSync( recursive: true );
    File( "${dir.path}/old.mp3" )..writeAsStringSync( "x" )..setLastModifiedSync( DateTime( 2026, 10, 1 ) );
    File( "${dir.path}/new.mp3" )..writeAsStringSync( "x" )..setLastModifiedSync( DateTime( 2026, 10, 20 ) );
    File( "${dir.path}/half.mp3.part" ).writeAsStringSync( "x" );
    final rows = await cache.entries();
    expect( rows.map( ( e ) => e.name ), [ "new", "old" ] );
    expect( rows.first.modified, DateTime( 2026, 10, 20 ) );
  } );

  test( "fetch writes a whole file under its final name and marks it downloaded", () async {
    downloadWrites( "mp3" );
    var heard = 0;
    cache.addListener( () => heard++ );
    final file = await cache.fetch( "io/a.mp3", "a" );

    expect( file.path, "${dir.path}/a.mp3" );
    expect( await file.readAsString(), "mp3" );
    expect( cache.isCached( "a" ), isTrue );
    expect( heard, 1 );
    expect( dir.listSync().map( ( e ) => e.path.split( "/" ).last ), [ "a.mp3" ], reason: "no .part left behind" );
  } );

  test( "a download that drops half way leaves nothing that counts as cached", () async {
    when( () => io.downloadTo( any(), any() ) ).thenAnswer( ( inv ) async {
      await ( inv.positionalArguments[ 1 ] as File ).writeAsString( "half" );
      throw const IoFileException( "dropped" );
    } );

    await expectLater( cache.fetch( "io/a.mp3", "a" ), throwsA( isA<IoFileException>() ) );

    expect( cache.isCached( "a" ), isFalse );
    expect( await cache.lookup( "a" ), isNull );
    expect( dir.listSync(), isEmpty, reason: "the partial file is removed" );
  } );

  test( "a failure before any byte arrives also leaves nothing", () async {
    when( () => io.downloadTo( any(), any() ) ).thenThrow( const IoFileException( "refused", statusCode: 503 ) );
    await expectLater( cache.fetch( "io/a.mp3", "a" ), throwsA( isA<IoFileException>() ) );
    expect( dir.listSync(), isEmpty );
  } );

  test( "two fetches of one name share a single download, and a later one may retry", () async {
    downloadWrites( "mp3" );
    final first  = cache.fetch( "io/a.mp3", "a" );
    final second = cache.fetch( "io/a.mp3", "a" );
    expect( identical( first, second ), isTrue );
    await Future.wait( [ first, second ] );
    verify( () => io.downloadTo( any(), any() ) ).called( 1 );

    when( () => io.downloadTo( any(), any() ) ).thenThrow( const IoFileException( "x" ) );
    await expectLater( cache.fetch( "io/b.mp3", "b" ), throwsA( isA<IoFileException>() ) );
    downloadWrites( "ok" );
    expect( ( await cache.fetch( "io/b.mp3", "b" ) ).path, endsWith( "b.mp3" ) );
  } );

  test( "lookup finds a file on disk without any network call, and forgets one that was deleted", () async {
    dir.createSync( recursive: true );
    File( "${dir.path}/a.mp3" ).writeAsStringSync( "mp3" );
    var heard = 0;
    cache.addListener( () => heard++ );

    expect( ( await cache.lookup( "a" ) )!.path, "${dir.path}/a.mp3" );
    expect( cache.isCached( "a" ), isTrue );
    expect( heard, 1 );
    expect( ( await cache.lookup( "a" ) ), isNotNull );
    expect( heard, 1, reason: "no change, no notification" );
    verifyNever( () => io.downloadTo( any(), any() ) );

    File( "${dir.path}/a.mp3" ).deleteSync();
    expect( await cache.lookup( "a" ), isNull );
    expect( cache.isCached( "a" ), isFalse );
    expect( heard, 2 );
    expect( await cache.lookup( "never-there" ), isNull );
    expect( heard, 2 );
  } );

  test( "load learns finished files, deletes .part leftovers and ignores other entries", () async {
    dir.createSync( recursive: true );
    File( "${dir.path}/a.mp3" ).writeAsStringSync( "x" );
    File( "${dir.path}/b.mp3.part" ).writeAsStringSync( "x" );
    File( "${dir.path}/notes.txt" ).writeAsStringSync( "x" );
    Directory( "${dir.path}/sub" ).createSync();
    var heard = 0;
    cache.addListener( () => heard++ );

    await cache.load();

    expect( cache.isCached( "a" ), isTrue );
    expect( cache.isCached( "b" ), isFalse );
    expect( File( "${dir.path}/b.mp3.part" ).existsSync(), isFalse );
    expect( File( "${dir.path}/notes.txt" ).existsSync(), isTrue );
    expect( heard, 1 );
  } );

  test( "deleteOlderThan removes files and stale .part files older than the age and keeps newer ones", () async {
    dir.createSync( recursive: true );
    final old   = File( "${dir.path}/old.mp3" )..writeAsStringSync( "x" );
    final fresh = File( "${dir.path}/fresh.mp3" )..writeAsStringSync( "x" );
    final part  = File( "${dir.path}/dead.mp3.part" )..writeAsStringSync( "x" );
    Directory( "${dir.path}/sub" ).createSync();
    old.setLastModifiedSync( clock.subtract( const Duration( days: 31 ) ) );
    part.setLastModifiedSync( clock.subtract( const Duration( days: 40 ) ) );
    fresh.setLastModifiedSync( clock.subtract( const Duration( days: 29 ) ) );
    await cache.lookup( "old" );
    await cache.lookup( "fresh" );
    var heard = 0;
    cache.addListener( () => heard++ );

    expect( await cache.deleteOlderThan( kPodcastCacheMaxAge ), 2 );

    expect( old.existsSync(), isFalse );
    expect( part.existsSync(), isFalse );
    expect( fresh.existsSync(), isTrue );
    expect( cache.isCached( "old" ), isFalse );
    expect( cache.isCached( "fresh" ), isTrue );
    expect( heard, 1 );
    expect( await cache.deleteOlderThan( kPodcastCacheMaxAge ), 0 );
    expect( heard, 1, reason: "nothing removed, nothing announced" );
  } );

  test( "the age limit is thirty days", () => expect( kPodcastCacheMaxAge, const Duration( days: 30 ) ) );

  test( "preparePodcastCache purges, then loads; a failure is swallowed", () async {
    dir.createSync( recursive: true );
    File( "${dir.path}/old.mp3" ).writeAsStringSync( "x" );
    File( "${dir.path}/old.mp3" ).setLastModifiedSync( clock.subtract( const Duration( days: 45 ) ) );
    File( "${dir.path}/new.mp3" ).writeAsStringSync( "x" );
    await preparePodcastCache( cache );
    expect( cache.isCached( "new" ), isTrue );
    expect( cache.isCached( "old" ), isFalse );

    final broken = PodcastCache( ioFactory: () => io, dirFactory: () async => throw StateError( "no disk" ) );
    await preparePodcastCache( broken );
  } );

  test( "podcastCacheDirectory is a podcasts folder under the app support directory", () async {
    const channel   = MethodChannel( "plugins.flutter.io/path_provider" );
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler( channel, ( call ) async => call.method == "getApplicationSupportDirectory" ? tmp.path : null );
    addTearDown( () => messenger.setMockMethodCallHandler( channel, null ) );

    expect( ( await podcastCacheDirectory() ).path, "${tmp.path}/podcasts" );
  } );
}
