// StorageManager, CacheManager and OfflineManager failure paths log through the
// app Logger. The five StorageManager file operations the log file destination
// itself calls must NOT log, or a failing disk would feed itself.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/cache/cache_manager.dart';
import 'package:lupin_mobile/core/cache/cache_policy.dart';
import 'package:lupin_mobile/core/cache/offline_manager.dart';
import 'package:lupin_mobile/core/logging/logger.dart';
import 'package:lupin_mobile/core/storage/storage_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Capture implements LogDestination {
  final List<LogEntry> entries = [];

  @override
  void write( LogEntry entry ) => entries.add( entry );

  @override
  Future<void> flush() async {}
}

Future<void> settle() => Future<void>.delayed( const Duration( milliseconds: 50 ) );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory       tmp;
  late StorageManager  storage;
  late _Capture        capture;

  Iterable<LogEntry> entriesFor( String tag ) => capture.entries.where( ( e ) => e.tag == tag );

  setUpAll( () async {
    tmp = await Directory.systemTemp.createTemp( "lupin_storage_logging_" );
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler( const MethodChannel( "plugins.flutter.io/path_provider" ), ( _ ) async => tmp.path );
    messenger.setMockMethodCallHandler( const MethodChannel( "dev.fluttercommunity.plus/connectivity" ), ( _ ) async => "wifi" );
    messenger.setMockStreamHandler(
      const EventChannel( "dev.fluttercommunity.plus/connectivity_status" ),
      MockStreamHandler.inline( onListen: ( _, __ ) {} ),
    );
    SharedPreferences.setMockInitialValues( {} );
    storage = await StorageManager.getInstance();
  } );

  tearDownAll( () async {
    if ( tmp.existsSync() ) await tmp.delete( recursive: true );
  } );

  setUp( () {
    Logger.resetForTesting();
    capture = _Capture();
    Logger.addDestination( capture );
  } );

  tearDown( Logger.resetForTesting );

  group( "StorageManager", () {
    test( "getJson on corrupt JSON: error entry, tag StorageManager, returns null", () async {
      await storage.setString( "bad_json", "alice@example.com private note {not json" );

      expect( storage.getJson( "bad_json" ), isNull );

      final found = entriesFor( "StorageManager" ).where( ( e ) => e.level == LogLevel.error );
      expect( found, hasLength( 1 ) );
      expect( found.single.message, "Error parsing JSON for key bad_json" );
      expect( found.single.stackTrace, isNotNull );
      expect( found.single.context!.metadata![ "key" ], "bad_json" );
      expect( found.single.error, startsWith( "FormatException" ) );
      expect( jsonEncode( found.single.toJson() ), isNot( contains( "alice@example.com" ) ), reason: "stored text stays out of the log" );
    } );

    test( "getJsonList on a JSON object: error entry, tag StorageManager, returns null", () async {
      await storage.setString( "not_a_list", "{\"email\": \"alice@example.com\"}" );

      expect( storage.getJsonList( "not_a_list" ), isNull );

      final found = entriesFor( "StorageManager" ).where( ( e ) => e.level == LogLevel.error );
      expect( found, hasLength( 1 ) );
      expect( found.single.message, "Error parsing JSON list for key not_a_list" );
      expect( found.single.stackTrace, isNotNull );
      expect( found.single.context!.metadata![ "key" ], "not_a_list" );
      expect( jsonEncode( found.single.toJson() ), isNot( contains( "alice@example.com" ) ) );
    } );

    test( "readFile on undecodable bytes: error entry, returns null", () async {
      await File( "${tmp.path}/binary.bin" ).writeAsBytes( [ 0xff, 0xfe, 0xfd ] );

      expect( await storage.readFile( "binary.bin" ), isNull );

      final found = entriesFor( "StorageManager" ).where( ( e ) => e.level == LogLevel.error );
      expect( found, hasLength( 1 ) );
      expect( found.single.message, "Failed to read file binary.bin" );
      expect( found.single.stackTrace, isNotNull );
      expect( found.single.context!.metadata![ "file" ], "binary.bin" );
      expect( found.single.error, "FileSystemException" );
    } );

    test( "writeFile into a missing directory: error entry, and the exception still reaches the caller", () async {
      await expectLater( storage.writeFile( "no/such/dir/out.txt", "x" ), throwsA( isA<FileSystemException>() ) );

      final found = entriesFor( "StorageManager" ).where( ( e ) => e.level == LogLevel.error );
      expect( found, hasLength( 1 ) );
      expect( found.single.message, "Failed to write file no/such/dir/out.txt" );
      expect( found.single.stackTrace, isNotNull );
      expect( found.single.context!.metadata![ "file" ], "no/such/dir/out.txt" );
    } );

    test( "appendToFile failure does not reach Logger (the log file destination calls it)", () async {
      await expectLater( storage.appendToFile( "no/such/dir/out.log", "x" ), throwsA( isA<FileSystemException>() ) );

      expect( entriesFor( "StorageManager" ), isEmpty );
    } );

    test( "renameFile failure does not reach Logger", () async {
      await Directory( "${tmp.path}/occupied" ).create();
      await File( "${tmp.path}/to_rename.txt" ).writeAsString( "x" );

      await expectLater( storage.renameFile( "to_rename.txt", "occupied" ), throwsA( isA<FileSystemException>() ) );

      expect( entriesFor( "StorageManager" ), isEmpty );
    } );
  } );

  group( "CacheManager", () {
    Map<String, dynamic> toJson( Map<String, dynamic> v ) => v;
    Map<String, dynamic> fromJson( Map<String, dynamic> j ) => j;

    CacheManager<Map<String, dynamic>> build( String cacheKey ) => CacheManager<Map<String, dynamic>>(
          cacheKey: cacheKey,
          toJson  : toJson,
          fromJson: fromJson,
          policy  : const CachePolicy( enableAutoCleanup: false ),
          storage : storage,
        );

    const badEntry = {
      "key"       : "k1",
      "value"     : <String, dynamic>{},
      "created_at": "alice@example.com",
    };

    test( "a corrupt entry in storage on get: error entry, tag CacheManager, treated as a miss", () async {
      final cache = build( "cache_get" );
      await settle();
      await storage.setJson( "cache_get_k1", badEntry );

      expect( await cache.get( "k1" ), isNull );

      final found = entriesFor( "CacheManager" ).where( ( e ) => e.level == LogLevel.error );
      expect( found, hasLength( 1 ) );
      expect( found.single.message, "Error loading entry from storage" );
      expect( found.single.stackTrace, isNotNull );
      expect( found.single.context!.metadata![ "storageKey" ], "cache_get_k1" );
      expect( jsonEncode( found.single.toJson() ), isNot( contains( "alice@example.com" ) ) );
      cache.dispose();
    } );

    test( "a corrupt entry on start-up load: error entry, tag CacheManager", () async {
      await storage.setJson( "cache_boot_k1", badEntry );

      final cache = build( "cache_boot" );
      await settle();

      final found = entriesFor( "CacheManager" ).where( ( e ) => e.level == LogLevel.error );
      expect( found, hasLength( 1 ) );
      expect( found.single.message, "Error loading cached entry" );
      expect( found.single.stackTrace, isNotNull );
      expect( found.single.context!.metadata![ "cacheKey" ], "cache_boot" );
      expect( jsonEncode( found.single.toJson() ), isNot( contains( "alice@example.com" ) ) );
      cache.dispose();
    } );
  } );

  group( "OfflineManager", () {
    test( "a queued request that fails to process: error entry without the request key, failure event still sent", () async {
      await storage.setBool( "offline_mode", false );
      final offline = await OfflineManager.getInstance();
      await settle();

      await offline.queueRequest( "req-good", { "path": "/x" } );
      // The payload cannot be encoded, so persisting the queue fails while "req-bad" is still in it.
      await expectLater( offline.queueRequest( "req-bad", { "o": Object() } ), throwsA( isA<Object>() ) );
      capture.entries.clear();
      final events = <OfflineEvent>[];
      final sub    = offline.events.listen( events.add );

      await offline.processQueuedRequests();
      await settle();
      await sub.cancel();

      final found = entriesFor( "OfflineManager" ).where( ( e ) => e.level == LogLevel.error );
      expect( found, hasLength( 1 ) );
      expect( found.single.message, "Error processing queued request" );
      expect( found.single.stackTrace, isNotNull );
      expect( jsonEncode( found.single.toJson() ), isNot( contains( "req-good" ) ), reason: "the request key can hold a query or body" );
      final processed = events.whereType<OfflineRequestProcessedEvent>().where( ( e ) => e.requestKey == "req-good" ).toList();
      expect( processed.last.success, isFalse, reason: "the last event must still report the failure" );
      expect( processed.where( ( e ) => !e.success ), hasLength( 1 ) );
      offline.dispose();
    } );
  } );
}
