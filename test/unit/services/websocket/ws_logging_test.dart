// WebSocketService failure paths log through the app Logger with the
// WebSocket tag, at the level the design table gives each one.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:lupin_mobile/core/logging/logger.dart';
import 'package:lupin_mobile/services/auth/auth_token_provider.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';
import 'package:lupin_mobile/services/websocket/ws_resume_store.dart';

// Synthetic JWT, structurally valid and made up.
const String _jwt =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    ".eyJzdWIiOiJ0ZXN0LXVzZXItaWQiLCJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20ifQ"
    ".ZmFrZXNpZ25hdHVyZUZPUlRFU1RTT05MWQ";

class _Capture implements LogDestination {
  final List<LogEntry> entries = [];

  @override
  void write( LogEntry entry ) => entries.add( entry );

  @override
  Future<void> flush() async {}
}

class _SessionAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch( RequestOptions o, Stream<List<int>>? s, Future<void>? c ) async =>
      ResponseBody.fromString( jsonEncode( { "session_id": "wise penguin" } ), 200,
          headers: { Headers.contentTypeHeader: [ "application/json" ] } );

  @override
  void close( { bool force = false } ) {}
}

class _SocketGone implements Exception {
  @override
  String toString() => "socket gone";
}

class _ExplodingError implements Exception {
  @override
  String toString() => throw StateError( "toString exploded" );
}

class _FakeChannel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  final _in = StreamController<dynamic>();
  bool failSends = false;
  late final WebSocketSink _sink = _FakeSink( this );

  void serverSendsRaw( String raw )              => _in.add( raw );
  void serverSends( Map<String, dynamic> frame ) => _in.add( jsonEncode( frame ) );
  void serverErrors( Object error )              => _in.addError( error );

  @override Stream<dynamic> get stream => _in.stream;
  @override WebSocketSink   get sink   => _sink;
  @override Future<void>    get ready  => Future.value();
  @override int?    get closeCode   => null;
  @override String? get closeReason => null;
  @override String? get protocol    => null;
}

class _FakeSink implements WebSocketSink {
  final _FakeChannel _c;
  _FakeSink( this._c );

  @override
  void add( dynamic data ) {
    if ( _c.failSends ) throw _SocketGone();
  }

  @override void addError( Object e, [ StackTrace? st ] ) {}
  @override Future<void> addStream( Stream<dynamic> s ) => s.forEach( add );
  @override Future<void> close( [ int? code, String? reason ] ) async {}
  @override Future<void> get done => Future.value();
}

class _FailingStore extends WsResumeStore {
  bool failLastSeq = false;
  bool failSetSeq  = false;
  bool explode     = false;

  @override
  Future<int> lastSeq() async {
    if ( failLastSeq ) throw StateError( "prefs unavailable" );
    return super.lastSeq();
  }

  @override
  Future<void> setLastSeq( int seq ) async {
    if ( failSetSeq ) throw ( explode ? _ExplodingError() : StateError( "prefs unavailable" ) );
    return super.setLastSeq( seq );
  }
}

Future<void> settle() => Future<void>.delayed( const Duration( milliseconds: 60 ) );

void main() {
  late _Capture        capture;
  late _FailingStore   store;
  late List<_FakeChannel> channels;
  late WebSocketService ws;
  Object? factoryError;

  WebSocketService build( { Duration delay = const Duration( hours: 1 ) } ) => WebSocketService(
        Dio()..httpClientAdapter = _SessionAdapter(),
        store              : store,
        reconnectBaseDelay : delay,
        channelFactory     : ( Uri _ ) {
          if ( factoryError != null ) throw factoryError!;
          final c = _FakeChannel();
          channels.add( c );
          return c;
        },
      );

  Iterable<LogEntry> entries( LogLevel level ) =>
      capture.entries.where( ( e ) => e.tag == "WebSocket" && e.level == level );

  setUp( () {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Logger.resetForTesting();
    capture = _Capture();
    Logger.addDestination( capture );
    readAccessToken = () => "tok";
    store        = _FailingStore();
    channels     = [];
    factoryError = null;
    ws           = build();
  } );

  tearDown( () async {
    await ws.disconnect();
    Logger.resetForTesting();
  } );

  test( "Connection failed: error entry with the exception, no token", () async {
    factoryError = Exception( "refused Authorization: Bearer $_jwt" );

    await ws.connect( userId: "u1" );
    await settle();

    final found = entries( LogLevel.error ).where( ( e ) => e.message == "Connection failed" );
    expect( found, hasLength( 1 ) );
    expect( found.single.error, contains( "refused" ) );
    expect( found.single.stackTrace, isNotNull );
    expect( jsonEncode( found.single.toJson() ), isNot( contains( _jwt ) ) );
  } );

  test( "Max reconnect attempts: warning, once the attempts run out", () async {
    ws.disconnect();
    ws = build( delay: const Duration( milliseconds: 1 ) );
    factoryError = Exception( "refused" );

    await ws.connect( userId: "u1" );
    await Future<void>.delayed( const Duration( milliseconds: 400 ) );

    final found = entries( LogLevel.warning ).where( ( e ) => e.message.startsWith( "Max reconnect attempts" ) );
    expect( found, hasLength( 1 ) );
  } );

  test( "No access token: warning, auth skipped", () async {
    readAccessToken = () => null;

    await ws.connect( userId: "u1" );
    await settle();

    expect( entries( LogLevel.warning ).where( ( e ) => e.message.startsWith( "No access token" ) ), hasLength( 1 ) );
  } );

  test( "Authentication failed: error entry when auth cannot be built", () async {
    store.failLastSeq = true;

    await ws.connect( userId: "u1" );
    await settle();

    final found = entries( LogLevel.error ).where( ( e ) => e.message == "Authentication failed" );
    expect( found, hasLength( 1 ) );
    expect( found.single.error, contains( "prefs unavailable" ) );
  } );

  test( "Authentication rejected by server: warning with the server's message", () async {
    await ws.connect( userId: "u1" );
    await settle();

    channels.single.serverSends( { "type": "auth_error", "message": "bad token" } );
    await settle();

    final found = entries( LogLevel.warning ).where( ( e ) => e.message.startsWith( "Authentication rejected" ) );
    expect( found, hasLength( 1 ) );
    expect( found.single.message, contains( "bad token" ) );
  } );

  test( "Message parsing error: a warning, because the frame is still forwarded; carries the session and a stack", () async {
    await ws.connect( userId: "u1" );
    await settle();

    channels.single.serverSendsRaw( "this is not json" );
    await settle();

    expect( entries( LogLevel.error ).where( ( e ) => e.message == "Message parsing error" ), isEmpty );
    final found = entries( LogLevel.warning ).where( ( e ) => e.message == "Message parsing error" );
    expect( found, hasLength( 1 ) );
    expect( found.single.stackTrace, isNotNull );
    expect( found.single.context!.sessionId, "wise penguin" );
  } );

  test( "a form-encoded refresh token quoted in a parse error is masked", () async {
    await ws.connect( userId: "u1" );
    await settle();

    channels.single.serverSendsRaw( "refresh_token=opaque-RT&x=1" );
    await settle();

    final found = entries( LogLevel.warning ).where( ( e ) => e.message == "Message parsing error" );
    expect( found, hasLength( 1 ) );
    expect( jsonEncode( found.single.toJson() ), isNot( contains( "opaque-RT" ) ) );
  } );

  test( "a form-encoded refresh token in the server's auth_error text is masked", () async {
    await ws.connect( userId: "u1" );
    await settle();

    channels.single.serverSends( { "type": "auth_error", "message": "bad refresh_token=opaque-RT $_jwt" } );
    await settle();

    final found = entries( LogLevel.warning ).where( ( e ) => e.message.startsWith( "Authentication rejected" ) );
    expect( found, hasLength( 1 ) );
    expect( jsonEncode( found.single.toJson() ), isNot( contains( "opaque-RT" ) ) );
    expect( jsonEncode( found.single.toJson() ), isNot( contains( _jwt ) ) );
  } );

  test( "a persist failure whose toString throws is still logged, with the runtime type", () async {
    await ws.connect( userId: "u1" );
    await settle();
    store.failSetSeq = true;
    store.explode    = true;

    channels.single.serverSends( { "type": "queue_update", "seq": 9 } );
    await settle();

    final found = entries( LogLevel.warning ).where( ( e ) => e.message == "last_seq persist failed" );
    expect( found, hasLength( 1 ) );
    expect( found.single.error, contains( "_ExplodingError" ) );
  } );

  test( "Stream error: error entry", () async {
    await ws.connect( userId: "u1" );
    await settle();

    channels.single.serverErrors( Exception( "reset by peer" ) );
    await settle();

    final found = entries( LogLevel.error ).where( ( e ) => e.message == "Stream error" );
    expect( found, hasLength( 1 ) );
    expect( found.single.error, contains( "reset by peer" ) );
  } );

  test( "Failed to send message: error entry, and the exception still reaches the caller", () async {
    await ws.connect( userId: "u1" );
    await settle();
    channels.single.failSends = true;

    await expectLater( ws.sendMessage( { "type": "ping" } ), throwsA( isA<_SocketGone>() ) );

    expect( entries( LogLevel.error ).where( ( e ) => e.message == "Failed to send message" ), hasLength( 1 ) );
  } );

  test( "Failed to send binary data: error entry, and the exception still reaches the caller", () async {
    await ws.connect( userId: "u1" );
    await settle();
    channels.single.failSends = true;

    await expectLater( ws.sendBinary( [ 1, 2, 3 ] ), throwsA( isA<_SocketGone>() ) );

    expect( entries( LogLevel.error ).where( ( e ) => e.message == "Failed to send binary data" ), hasLength( 1 ) );
  } );

  test( "last_seq persist failed: warning", () async {
    await ws.connect( userId: "u1" );
    await settle();
    store.failSetSeq = true;

    channels.single.serverSends( { "type": "queue_update", "seq": 7 } );
    await settle();

    final found = entries( LogLevel.warning ).where( ( e ) => e.message == "last_seq persist failed" );
    expect( found, hasLength( 1 ) );
    expect( found.single.error, contains( "prefs unavailable" ) );
  } );

  test( "ack failed: warning", () async {
    await ws.connect( userId: "u1" );
    await settle();
    channels.single.failSends = true;

    channels.single.serverSends( { "type": "queue_update", "seq": 8 } );
    await settle();

    final found = entries( LogLevel.warning ).where( ( e ) => e.message == "ack failed" );
    expect( found, hasLength( 1 ) );
    expect( found.single.error, contains( "socket gone" ) );
  } );
}
