// CachedHttpService failure paths log through the app Logger with the HTTP tag.
// The offline queue key holds the query and the POST body, so no log line may carry it.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/cache/network_cache.dart';
import 'package:lupin_mobile/core/cache/offline_manager.dart';
import 'package:lupin_mobile/core/logging/logger.dart';
import 'package:lupin_mobile/core/storage/storage_manager.dart';
import 'package:lupin_mobile/services/network/cached_http_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Capture implements LogDestination {
  final List<LogEntry> entries = [];

  @override
  void write( LogEntry entry ) => entries.add( entry );

  @override
  Future<void> flush() async {}
}

/// Fails every request except the paths in [okPaths]; [before] runs first, so a test can seed the cache mid-request.
class _ScriptedAdapter implements HttpClientAdapter {
  final Set<String> okPaths = {};
  Future<void> Function( RequestOptions )? before;

  @override
  Future<ResponseBody> fetch( RequestOptions options, Stream<Uint8List>? requestStream, Future? cancelFuture ) async {
    if ( before != null ) await before!( options );
    if ( okPaths.any( options.path.startsWith ) ) {
      return ResponseBody.fromString( jsonEncode( { "ok": true } ), 200,
          headers: { Headers.contentTypeHeader: [ Headers.jsonContentType ] } );
    }
    throw Exception( "network down" );
  }

  @override
  void close( { bool force = false } ) {}
}

Future<void> settle() => Future<void>.delayed( const Duration( milliseconds: 60 ) );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Capture         capture;
  late _ScriptedAdapter adapter;
  late CachedHttpService service;
  late NetworkCache     networkCache;
  late OfflineManager   offline;
  late DebugPrintCallback originalDebugPrint;
  late List<String>     debugLines;

  Iterable<LogEntry> httpEntries( LogLevel level ) =>
      capture.entries.where( ( e ) => e.tag == "HTTP" && e.level == level );

  Response<dynamic> okResponse( String path ) =>
      Response<dynamic>( requestOptions: RequestOptions( path: path ), statusCode: 200, data: { "cached": true } );

  setUpAll( () async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler( const MethodChannel( "plugins.flutter.io/path_provider" ), ( _ ) async => Uri.file( "/tmp" ).toFilePath() );
    messenger.setMockMethodCallHandler( const MethodChannel( "dev.fluttercommunity.plus/connectivity" ), ( _ ) async => "wifi" );
    messenger.setMockStreamHandler(
      const EventChannel( "dev.fluttercommunity.plus/connectivity_status" ),
      MockStreamHandler.inline( onListen: ( _, __ ) {} ),
    );
    SharedPreferences.setMockInitialValues( { "offline_mode": false } );
    await StorageManager.getInstance();
    offline      = await OfflineManager.getInstance();
    networkCache = await NetworkCache.getInstance();
    await settle();
  } );

  setUp( () async {
    Logger.resetForTesting();
    capture = _Capture();
    Logger.addDestination( capture );
    originalDebugPrint = debugPrint;
    debugLines         = [];
    debugPrint         = ( String? message, { int? wrapWidth } ) => debugLines.add( message ?? "" );

    adapter = _ScriptedAdapter();
    service = CachedHttpService( Dio()..httpClientAdapter = adapter );
    await settle();
  } );

  tearDown( () {
    debugPrint = originalDebugPrint;
    Logger.resetForTesting();
  } );

  final failures = <String, ( String, Future<Object?> Function( CachedHttpService ) )>{
    "Session ID request failed"      : ( "/api/get-session-id", ( s ) => s.getSessionId() ),
    "ElevenLabs TTS request failed"  : ( "/api/get-speech-elevenlabs", ( s ) => s.requestElevenLabsTTS( sessionId: "s", text: "t" ) ),
    "OpenAI TTS request failed"      : ( "/api/get-speech", ( s ) => s.requestOpenAITTS( sessionId: "s", text: "t" ) ),
  };

  for ( final failure in failures.entries ) {
    final ( path, call ) = failure.value;

    test( "${failure.key}: one error entry with the path and a stack; the exception reaches the caller", () async {
      await expectLater( call( service ), throwsA( isA<DioException>() ) );

      final found = httpEntries( LogLevel.error ).where( ( e ) => e.message == failure.key );
      expect( found, hasLength( 1 ) );
      expect( found.single.context!.metadata![ "path" ], path );
      expect( found.single.stackTrace, isNotNull );
      expect( found.single.error, isNotNull );
    } );
  }

  test( "Health check failed: error entry, returns false", () async {
    expect( await service.checkHealth(), isFalse );

    final found = httpEntries( LogLevel.error ).where( ( e ) => e.message == "Health check failed" );
    expect( found, hasLength( 1 ) );
    expect( found.single.context!.metadata![ "path" ], "/health" );
  } );

  test( "GET served from cache after a network error: a warning with the path and the cause", () async {
    adapter.before = ( options ) => networkCache.cacheGetResponse( "/stale", null, okResponse( "/stale" ) );

    final response = await service.get<dynamic>( "/stale" );

    expect( response.data, { "cached": true } );
    final found = httpEntries( LogLevel.warning ).where( ( e ) => e.message == "Using stale cache due to network error" );
    expect( found, hasLength( 1 ) );
    expect( found.single.context!.metadata![ "path" ], "/stale" );
    expect( found.single.error, contains( "network down" ) );
  } );

  test( "POST served from cache after a network error: a warning with the path", () async {
    adapter.before = ( options ) => networkCache.cachePostResponse( "/stale-post", { "k": 1 }, okResponse( "/stale-post" ) );

    final response = await service.post<dynamic>( "/stale-post", data: { "k": 1 }, useCache: true );

    expect( response.data, { "cached": true } );
    final found = httpEntries( LogLevel.warning ).where( ( e ) => e.message == "Using stale cache due to network error" );
    expect( found, hasLength( 1 ) );
    expect( found.single.context!.metadata![ "path" ], "/stale-post" );
  } );

  group( "processQueuedRequests", () {
    const failKey = "POST_/q?secret=query-secret_{note: body-secret}";
    const okKey   = "GET_/ok?token=ok-secret_null";

    test( "a failure logs method and path only; neither the queue key, query nor body reaches any log", () async {
      adapter.okPaths.add( "/ok" );
      await offline.queueRequest( failKey, {
        "method": "POST", "path": "/q?secret=query-secret", "data": { "note": "body-secret" }, "queryParameters": null,
      } );
      await offline.queueRequest( okKey, {
        "method": "GET", "path": "/ok?token=ok-secret", "queryParameters": null,
      } );
      capture.entries.clear();
      debugLines.clear();

      await service.processQueuedRequests();

      final found = httpEntries( LogLevel.error ).where( ( e ) => e.message == "Failed to process queued request" );
      expect( found, hasLength( 1 ) );
      expect( found.single.context!.metadata, { "method": "POST", "path": "/q" } );
      expect( found.single.stackTrace, isNotNull );

      final everything = jsonEncode( capture.entries.map( ( e ) => e.toJson() ).toList() ) + debugLines.join( "\n" );
      for ( final secret in [ "query-secret", "body-secret", "ok-secret", failKey, okKey ] ) {
        expect( everything, isNot( contains( secret ) ), reason: secret );
      }
      expect( debugLines.any( ( l ) => l.contains( "Successfully processed queued request: GET /ok" ) ), isTrue );
    } );
  } );
}
