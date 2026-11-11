// NetworkCache emits the one CacheEvent family and returns the one CacheStats,
// carrying its own fields in `details` and `extras`.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/cache/cache_manager.dart';
import 'package:lupin_mobile/core/cache/cache_policy.dart';
import 'package:lupin_mobile/core/cache/network_cache.dart';
import 'package:lupin_mobile/core/storage/storage_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_helpers/drain_event_loop.dart';

/// Awaited cache calls and stream events are pure async work: turns, not time.
Future<void> settle() => drainEventLoop();

/// Returns once a 1 ms TTL, stored before this call, has run out.
///
/// The cache stamps each entry with DateTime.now() when it is stored.
/// An entry stored earlier is therefore older than 1 ms once the clock has moved 1 ms on.
/// This waits for that outcome on the clock the cache reads, however slow the machine is.
Future<void> waitPastOneMsTtl() async {
  final since = DateTime.now();
  await waitUntil( () => DateTime.now().difference( since ) > const Duration( milliseconds: 1 ), "the 1 ms TTL to run out" );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory     tmp;
  late NetworkCache  network;

  Response<dynamic> okResponse( String path ) =>
      Response<dynamic>( requestOptions: RequestOptions( path: path ), statusCode: 200, data: { "ok": true } );

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
      await waitPastOneMsTtl();

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
      await waitPastOneMsTtl();

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

    test( "invalidateMethod removes only that method and emits CacheInvalidateEvent with the method as pattern", () async {
      await network.clearAll();
      await network.cacheGetResponse( "/family/m1", null, okResponse( "/family/m1" ) );
      await network.cachePostResponse( "/family/m2", { "k": 1 }, okResponse( "/family/m2" ) );

      final seen = <CacheEvent>[];
      final sub  = network.events.listen( seen.add );
      await network.invalidateMethod( "POST" );
      await settle();
      await sub.cancel();

      expect( seen.single, isA<CacheInvalidateEvent>() );
      expect( ( seen.single as CacheInvalidateEvent ).pattern, "POST" );
      expect( ( await network.getStats() ).toJson()[ "method_stats" ], { "GET": 1 } );
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

  group( "CacheStats.withExtras", () {
    test( "keeps the base figures and merges extras into toJson", () {
      const base  = CacheStats( itemCount: 3, totalSizeBytes: 9, expiredCount: 1, hitRate: 0.5, policy: CachePolicy.defaultPolicy );
      final extra = base.withExtras( { "a": 1 } ).withExtras( { "b": 2 } );

      expect( extra.itemCount, 3 );
      expect( extra.toJson()[ "a" ], 1 );
      expect( extra.toJson()[ "b" ], 2 );
      expect( base.toJson().containsKey( "a" ), isFalse );
    } );

    test( "an extras key that matches a standard key does not overwrite it", () {
      const base  = CacheStats( itemCount: 3, totalSizeBytes: 9, expiredCount: 1, hitRate: 0.5, policy: CachePolicy.defaultPolicy );
      final json  = base.withExtras( { "item_count": 99, "extra": 1 } ).toJson();

      expect( json[ "item_count" ], 3 );
      expect( json[ "extra" ], 1 );
    } );
  } );
}
