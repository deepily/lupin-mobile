// NetworkCache and AudioCache emit the one CacheEvent family and return the one
// CacheStats, carrying their own fields in `details` and `extras`.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/cache/audio_cache.dart';
import 'package:lupin_mobile/core/cache/cache_manager.dart';
import 'package:lupin_mobile/core/cache/cache_policy.dart';
import 'package:lupin_mobile/core/cache/network_cache.dart';
import 'package:lupin_mobile/core/storage/storage_manager.dart';
import 'package:lupin_mobile/shared/models/audio_chunk.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle() => Future<void>.delayed( const Duration( milliseconds: 50 ) );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory     tmp;
  late NetworkCache  network;
  late AudioCache    audio;

  Response<dynamic> okResponse( String path ) =>
      Response<dynamic>( requestOptions: RequestOptions( path: path ), statusCode: 200, data: { "ok": true } );

  AudioChunk chunk( String id ) => AudioChunk( id: id, type: AudioChunkType.tts, data: Uint8List( 4 ), timestamp: DateTime( 2026 ) );

  setUpAll( () async {
    tmp = await Directory.systemTemp.createTemp( "lupin_cache_family_" );
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler( const MethodChannel( "plugins.flutter.io/path_provider" ), ( _ ) async => tmp.path );
    messenger.setMockMethodCallHandler( const MethodChannel( "dev.fluttercommunity.plus/connectivity" ), ( _ ) async => "wifi" );
    messenger.setMockStreamHandler(
      const EventChannel( "dev.fluttercommunity.plus/connectivity_status" ),
      MockStreamHandler.inline( onListen: ( _, __ ) {} ),
    );
    SharedPreferences.setMockInitialValues( { "offline_mode": false } );
    await StorageManager.getInstance();
    network = await NetworkCache.getInstance();
    audio   = await AudioCache.getInstance();
    await settle();
  } );

  tearDownAll( () async {
    if ( tmp.existsSync() ) await tmp.delete( recursive: true );
  } );

  group( "NetworkCache events", () {
    test( "miss, store, hit and clear arrive as CacheEvent subclasses with method and url", () async {
      final seen = <CacheEvent>[];
      final sub  = network.events.listen( seen.add );

      await network.getCachedGetResponse( "/family/a", null );
      await network.cacheGetResponse( "/family/a", null, okResponse( "/family/a" ) );
      await network.getCachedGetResponse( "/family/a", null );
      await network.clearAll();
      await settle();
      await sub.cancel();

      expect( seen.map( ( e ) => e.runtimeType ), [ CacheMissEvent, CachePutEvent, CacheHitEvent, CacheClearEvent ] );
      expect( ( seen[ 0 ] as CacheMissEvent ).key, "GET /family/a" );
      expect( seen[ 0 ].details, { "method": "GET", "url": "/family/a" } );
      expect( seen[ 1 ].details, { "method": "GET", "url": "/family/a", "status_code": 200 } );
      expect( seen[ 2 ].details[ "status_code" ], 200 );
      expect( ( seen[ 1 ] as CachePutEvent ).key, "GET /family/a" );
      expect( ( seen[ 1 ] as CachePutEvent ).sizeBytes, isNull );
      expect( ( seen[ 2 ] as CacheHitEvent ).key, "GET /family/a" );
      expect( seen[ 2 ].details, { "method": "GET", "url": "/family/a", "status_code": 200 } );
      expect( seen[ 3 ].details, isEmpty );
    } );

    test( "an entry past its own TTL emits CacheExpiredEvent with method and url, and the lookup returns null", () async {
      await network.clearAll();
      await network.cacheGetResponse( "/family/ttl", null, okResponse( "/family/ttl" ), ttl: const Duration( milliseconds: 1 ) );
      await Future<void>.delayed( const Duration( milliseconds: 30 ) );

      final seen = <CacheEvent>[];
      final sub  = network.events.listen( seen.add );
      final got  = await network.getCachedGetResponse( "/family/ttl", null );
      await settle();
      await sub.cancel();

      expect( got, isNull );
      expect( seen, hasLength( 1 ) );
      expect( seen.single, isA<CacheExpiredEvent>() );
      expect( ( seen.single as CacheExpiredEvent ).key, "GET /family/ttl" );
      expect( seen.single.details, { "method": "GET", "url": "/family/ttl" } );
    } );

    test( "clearExpired emits one CacheCleanupEvent counting only the expired entries, and 0 on a second sweep", () async {
      await network.clearAll();
      await network.cacheGetResponse( "/family/x1", null, okResponse( "/family/x1" ), ttl: const Duration( milliseconds: 1 ) );
      await network.cacheGetResponse( "/family/x2", null, okResponse( "/family/x2" ), ttl: const Duration( milliseconds: 1 ) );
      await network.cacheGetResponse( "/family/live", null, okResponse( "/family/live" ), ttl: const Duration( hours: 1 ) );
      await Future<void>.delayed( const Duration( milliseconds: 30 ) );

      final seen = <CacheEvent>[];
      final sub  = network.events.listen( seen.add );
      await network.clearExpired();
      await network.clearExpired();
      await settle();
      await sub.cancel();

      final cleanups = seen.whereType<CacheCleanupEvent>().toList();
      expect( cleanups.map( ( e ) => e.itemsRemoved ), [ 2, 0 ] );
      expect( ( await network.getStats() ).itemCount, 1 );
      expect( await network.getCachedGetResponse( "/family/live", null ), isNotNull );
    } );

    test( "invalidateUrl emits CacheInvalidateEvent with the pattern", () async {
      final seen = <CacheEvent>[];
      final sub  = network.events.listen( seen.add );
      await network.invalidateUrl( "/family" );
      await settle();
      await sub.cancel();

      expect( seen.single, isA<CacheInvalidateEvent>() );
      expect( ( seen.single as CacheInvalidateEvent ).pattern, "/family" );
    } );
  } );

  group( "NetworkCache stats", () {
    test( "getStats returns CacheStats with method and status counts as extras", () async {
      await network.clearAll();
      await network.cacheGetResponse( "/family/s1", null, okResponse( "/family/s1" ) );
      await network.cachePostResponse( "/family/s2", { "k": 1 }, okResponse( "/family/s2" ) );

      final CacheStats stats = await network.getStats();
      final json            = stats.toJson();

      expect( stats.itemCount, 2 );
      expect( json[ "method_stats" ], { "GET": 1, "POST": 1 } );
      expect( json[ "status_stats" ], { "200": 2 } );
      expect( json[ "item_count" ], 2 );
    } );
  } );

  group( "AudioCache events and stats", () {
    test( "miss, store and hit carry provider and chunk count", () async {
      final seen = <CacheEvent>[];
      final sub  = audio.events.listen( seen.add );

      await audio.getCachedAudioForText( "hello family", "elevenlabs" );
      await audio.cacheAudioForText( "hello family", "elevenlabs", [ chunk( "c1" ), chunk( "c2" ) ] );
      await audio.getCachedAudioForText( "hello family", "elevenlabs" );
      await settle();
      await sub.cancel();

      expect( seen.map( ( e ) => e.runtimeType ), [ CacheMissEvent, CachePutEvent, CacheHitEvent ] );
      expect( seen[ 0 ].details, { "provider": "elevenlabs" } );
      expect( seen[ 1 ].details, { "provider": "elevenlabs", "chunk_count": 2 } );
      expect( ( seen[ 1 ] as CachePutEvent ).key, "hello family" );
      expect( ( seen[ 1 ] as CachePutEvent ).sizeBytes, isNull );
      expect( ( seen[ 2 ] as CacheHitEvent ).key, "hello family" );
      expect( seen[ 2 ].details, { "provider": "elevenlabs", "chunk_count": 2 } );
    } );

    test( "precache, provider clear and optimize map onto the family", () async {
      await audio.clearAll();
      await audio.cacheAudioForText( "stored phrase", "voicex", [ chunk( "p1" ) ] );

      final seen = <CacheEvent>[];
      final sub  = audio.events.listen( seen.add );

      await audio.precacheCommonPhrases( [ "never cached phrase" ], "voicex" );
      await audio.clearProviderCache( "voicex" );
      await audio.clearAll();
      await audio.optimize();
      await settle();
      await sub.cancel();

      final precache = seen.whereType<CachePrecacheRequestEvent>().single;
      expect( precache.key, "never cached phrase" );
      expect( precache.details, { "provider": "voicex" } );

      final clears = seen.whereType<CacheClearEvent>().toList();
      expect( clears.map( ( e ) => e.details ), [
        { "provider": "voicex", "removed_count": 1 },
        { "provider": "all",    "removed_count": 0 },
      ] );

      final optimize = seen.whereType<CacheOptimizeEvent>().single;
      expect( optimize.details, isEmpty );
    } );

    test( "getStats returns CacheStats with metadata count and provider counts as extras", () async {
      await audio.clearAll();
      await audio.cacheAudioForText( "stats phrase", "elevenlabs", [ chunk( "s1" ) ] );

      final CacheStats stats = await audio.getStats();
      final json            = stats.toJson();

      expect( stats.itemCount, 1 );
      expect( json[ "total_metadata" ], 1 );
      expect( json[ "provider_stats" ], { "elevenlabs": 1 } );
      expect( json.containsKey( "metadata_hit_rate" ), isTrue );
    } );
  } );

  group( "CacheStats.withExtras", () {
    test( "keeps the base figures and merges extras into toJson", () {
      const base  = CacheStats( itemCount: 3, totalSizeBytes: 9, expiredCount: 1, hitRate: 0.5, policy: CachePolicy.defaultPolicy );
      final extra = base.withExtras( { "a": 1 } ).withExtras( { "b": 2 } );

      expect( extra.itemCount, 3 );
      expect( extra.toJson()[ "a" ], 1 );
      expect( extra.toJson()[ "b" ], 2 );
      expect( base.toJson().containsKey( "a" ), isFalse );
    } );
  } );
}
