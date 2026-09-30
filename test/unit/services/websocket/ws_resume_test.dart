/// Row 281a10d6 — the /ws/queue client half of dc446601: stable device_id,
/// close-code handling (4004 = do not reconnect), last_seq resume, and ack.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:lupin_mobile/services/auth/auth_token_provider.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';
import 'package:lupin_mobile/services/websocket/ws_resume_store.dart';

/// Answers `/api/get-session-id` without a network.
class _SessionAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch( RequestOptions o, Stream<List<int>>? s, Future<void>? c ) async =>
      ResponseBody.fromString( jsonEncode( { 'session_id': 'wise penguin' } ), 200,
          headers: { Headers.contentTypeHeader: [ 'application/json' ] } );
  @override
  void close( { bool force = false } ) {}
}

/// A socket the test drives: `serverSends` plays a server frame, `serverCloses`
/// plays a close with a code, and `sent` records what the client wrote.
class _FakeChannel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  final _in   = StreamController<dynamic>();
  final sent  = <Map<String, dynamic>>[];
  int?  _closeCode;
  late final WebSocketSink _sink = _FakeSink( this );

  void serverSends( Map<String, dynamic> frame ) => _in.add( jsonEncode( frame ) );
  Future<void> serverCloses( int code ) async { _closeCode = code; await _in.close(); }

  @override Stream<dynamic> get stream => _in.stream;
  @override WebSocketSink   get sink   => _sink;
  @override Future<void>    get ready  => Future.value();
  @override int?    get closeCode   => _closeCode;
  @override String? get closeReason => null;
  @override String? get protocol    => null;
}

class _FakeSink implements WebSocketSink {
  final _FakeChannel _c;
  _FakeSink( this._c );
  @override void add( dynamic data ) => _c.sent.add( jsonDecode( data as String ) as Map<String, dynamic> );
  @override void addError( Object e, [ StackTrace? st ] ) {}
  @override Future<void> addStream( Stream<dynamic> s ) => s.forEach( add );
  @override Future<void> close( [ int? code, String? reason ] ) async {}
  @override Future<void> get done => Future.value();
}

Future<void> settle() => Future<void>.delayed( const Duration( milliseconds: 60 ) );

void main() {
  late List<_FakeChannel> channels;
  late WebSocketService   ws;
  late WsResumeStore      store;

  setUp( () {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    readAccessToken = () => 'tok';
    channels = [];
    store    = WsResumeStore();
    final dio = Dio()..httpClientAdapter = _SessionAdapter();
    ws = WebSocketService(
      dio,
      store              : store,
      reconnectBaseDelay : const Duration( milliseconds: 5 ),
      channelFactory     : ( Uri _ ) { final c = _FakeChannel(); channels.add( c ); return c; },
    );
  } );

  tearDown( () async { await ws.disconnect(); } );

  Map<String, dynamic> authOf( _FakeChannel c ) => c.sent.firstWhere( ( m ) => m[ 'type' ] == 'auth_request' );

  group( 'device_id', () {
    test( 'is sent in auth_request and is stable across service restarts', () async {
      await ws.connect( userId: 'u1' );
      await settle();
      final first = authOf( channels[ 0 ] )[ 'device_id' ] as String;
      expect( first, matches( RegExp( r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' ) ) );
      await ws.disconnect();

      // "Restart": brand-new store and service over the same backing prefs.
      final ws2 = WebSocketService( Dio()..httpClientAdapter = _SessionAdapter(),
          store: WsResumeStore(), channelFactory: ( Uri _ ) { final c = _FakeChannel(); channels.add( c ); return c; } );
      await ws2.connect( userId: 'u1' );
      await settle();
      expect( authOf( channels.last )[ 'device_id' ], first );
      await ws2.disconnect();
    } );
  } );

  group( 'close codes', () {
    Future<int> connectionsAfterClose( int code ) async {
      await ws.connect( userId: 'u1' );
      await settle();
      await channels[ 0 ].serverCloses( code );
      await settle();
      await Future<void>.delayed( const Duration( milliseconds: 100 ) );
      return channels.length;
    }

    test( '4004 superseded → NO reconnect', () async {
      expect( await connectionsAfterClose( 4004 ), 1 );
      expect( ws.isConnected, isFalse );
    } );

    test( '4001 → reconnects and re-authenticates with the CURRENT token (auth path as today)', () async {
      await ws.connect( userId: 'u1' );
      await settle();
      readAccessToken = () => 'refreshed';
      await channels[ 0 ].serverCloses( 4001 );
      await Future<void>.delayed( const Duration( milliseconds: 150 ) );
      expect( channels.length, 2 );
      expect( authOf( channels[ 1 ] )[ 'token' ], 'Bearer refreshed' );
    } );

    test( '4003 → reconnects as today', () async => expect( await connectionsAfterClose( 4003 ), 2 ) );
    test( '1006 → reconnects', ()            async => expect( await connectionsAfterClose( 1006 ), 2 ) );
    test( '1001 → reconnects', ()            async => expect( await connectionsAfterClose( 1001 ), 2 ) );
  } );

  group( 'last_seq resume and ack', () {
    test( 'fresh install sends no last_seq', () async {
      await ws.connect( userId: 'u1' );
      await settle();
      expect( authOf( channels[ 0 ] ).containsKey( 'last_seq' ), isFalse );
    } );

    test( "resume_complete.seq is the SERVER's seq: adopted, persisted, sent on the next auth", () async {
      await store.setLastSeq( 5 );
      await ws.connect( userId: 'u1' );
      await settle();
      expect( authOf( channels[ 0 ] )[ 'last_seq' ], 5 );

      channels[ 0 ].serverSends( { 'type': 'resume_complete', 'replayed': 2, 'gap': false, 'seq': 42 } );
      await settle();
      expect( await store.lastSeq(), 42 );

      await channels[ 0 ].serverCloses( 1006 );
      await Future<void>.delayed( const Duration( milliseconds: 150 ) );
      expect( authOf( channels[ 1 ] )[ 'last_seq' ], 42 );
    } );

    test( 'resume_complete is forwarded to listeners (the dispatcher acts on gap)', () async {
      final seen = <dynamic>[];
      ws.stream.listen( seen.add );
      await ws.connect( userId: 'u1' );
      await settle();
      channels[ 0 ].serverSends( { 'type': 'resume_complete', 'replayed': 0, 'gap': true, 'seq': 7 } );
      await settle();
      expect( seen.where( ( m ) => m is Map && m[ 'type' ] == 'resume_complete' && m[ 'gap' ] == true ), hasLength( 1 ) );
    } );

    test( 'a live frame with seq is forwarded, persisted, and acked', () async {
      final seen = <dynamic>[];
      ws.stream.listen( seen.add );
      await ws.connect( userId: 'u1' );
      await settle();
      channels[ 0 ].serverSends( { 'type': 'notification_queue_update', 'seq': 9 } );
      await settle();
      expect( seen.where( ( m ) => m is Map && m[ 'seq' ] == 9 ), hasLength( 1 ) );
      expect( await store.lastSeq(), 9 );
      expect( channels[ 0 ].sent.where( ( m ) => m[ 'type' ] == 'ack' && m[ 'seq' ] == 9 ), hasLength( 1 ) );
    } );

    test( 'a frame with no seq (web-style) sends no ack', () async {
      await ws.connect( userId: 'u1' );
      await settle();
      channels[ 0 ].serverSends( { 'type': 'notification_queue_update' } );
      await settle();
      expect( channels[ 0 ].sent.where( ( m ) => m[ 'type' ] == 'ack' ), isEmpty );
    } );

    test( 'last_seq is read from the async store on each auth, not cached (FCM isolate may have advanced it)', () async {
      await ws.connect( userId: 'u1' );
      await settle();
      await store.setLastSeq( 77 );   // "the other isolate" wrote it
      await channels[ 0 ].serverCloses( 1006 );
      await Future<void>.delayed( const Duration( milliseconds: 150 ) );
      expect( authOf( channels[ 1 ] )[ 'last_seq' ], 77 );
    } );
  } );

  group( 'auth payload shape', () {
    test( 'device_id and last_seq are omitted when not supplied (legacy fixture unchanged)', () {
      final m = WebSocketService.buildAuthRequestMessage( bearerToken: 'Bearer t', sessionId: 's' );
      expect( m.containsKey( 'device_id' ), isFalse );
      expect( m.containsKey( 'last_seq' ), isFalse );
    } );
  } );
}
