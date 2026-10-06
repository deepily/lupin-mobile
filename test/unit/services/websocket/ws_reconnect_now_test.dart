// Row b69dbf0b: the guarded entry point every reconnect trigger goes through.
//
// Three rules: one connect in flight, a reset retry counter, and no revival after sign-out or a 4004 close.

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

class _SessionAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch( RequestOptions o, Stream<List<int>>? s, Future<void>? c ) async =>
      ResponseBody.fromString( jsonEncode( { "session_id": "wise penguin" } ), 200,
          headers: { Headers.contentTypeHeader: [ "application/json" ] } );

  @override
  void close( { bool force = false } ) {}
}

/// A channel whose handshake the test completes by hand, and whose close code it can set.
class _FakeChannel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  final _in    = StreamController<dynamic>();
  final ready_ = Completer<void>();
  int? code;

  @override Stream<dynamic> get stream => _in.stream;
  @override WebSocketSink   get sink   => _FakeSink();
  @override Future<void>    get ready  => ready_.future;
  @override int?    get closeCode   => code;
  @override String? get closeReason => null;
  @override String? get protocol    => null;

  void closeWith( int c ) {
    code = c;
    _in.close();
  }
}

class _FakeSink implements WebSocketSink {
  @override void add( dynamic data ) {}
  @override void addError( Object e, [ StackTrace? st ] ) {}
  @override Future<void> addStream( Stream<dynamic> s ) => s.forEach( add );
  @override Future<void> close( [ int? code, String? reason ] ) async {}
  @override Future<void> get done => Future.value();
}

Future<void> _settle() => Future<void>.delayed( const Duration( milliseconds: 20 ) );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WebSocketService    ws;
  late List<_FakeChannel>  channels;
  late bool                serverUp;
  late bool                autoReady;

  setUp( () {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Logger.resetForTesting();
    readAccessToken = () => "tok";
    channels  = [];
    serverUp  = true;
    autoReady = true;
    ws = WebSocketService(
      Dio()..httpClientAdapter = _SessionAdapter(),
      store              : WsResumeStore(),
      reconnectBaseDelay : const Duration( milliseconds: 1 ),
      channelFactory     : ( Uri _ ) {
        if ( !serverUp ) throw Exception( "server down" );
        final c = _FakeChannel();
        if ( autoReady ) c.ready_.complete();
        channels.add( c );
        return c;
      },
    );
  } );

  tearDown( () async {
    await ws.disconnect();
    Logger.resetForTesting();
  } );

  /// Connect with the server down so the service burns its budget and gives up.
  Future<void> giveUp() async {
    serverUp = false;
    await ws.connect( userId: "u1" );
    await Future<void>.delayed( const Duration( milliseconds: 200 ) );
    expect( ws.isConnected, isFalse );
    expect( ws.isRetryPending, isFalse, reason: "the service has given up" );
  }

  test( "before any connect, a trigger does nothing", () async {
    expect( await ws.reconnectNow(), isFalse );
    expect( channels, isEmpty );
  } );

  test( "after giving up, a trigger reconnects", () async {
    await giveUp();
    serverUp = true;
    expect( await ws.reconnectNow(), isTrue );
    expect( ws.isConnected, isTrue );
  } );

  test( "rule 1: triggers during an in-flight connect open no second channel", () async {
    await giveUp();
    serverUp  = true;
    autoReady = false;

    final first = ws.reconnectNow();
    await _settle();
    expect( ws.isConnecting, isTrue );
    expect( channels.length, 1 );

    expect( await ws.reconnectNow(), isFalse );
    await ws.connect( userId: "u1" );
    expect( channels.length, 1, reason: "neither a second trigger nor a plain connect() may open another channel" );

    channels.single.ready_.complete();
    expect( await first, isTrue );
    expect( ws.isConnected, isTrue );
    expect( channels.length, 1 );
  } );

  test( "rule 1: a trigger while a retry timer is pending cancels the timer, so one channel opens", () async {
    final slow = WebSocketService(
      Dio()..httpClientAdapter = _SessionAdapter(),
      store              : WsResumeStore(),
      reconnectBaseDelay : const Duration( milliseconds: 300 ),
      channelFactory     : ( Uri _ ) {
        if ( !serverUp ) throw Exception( "server down" );
        final c = _FakeChannel()..ready_.complete();
        channels.add( c );
        return c;
      },
    );
    addTearDown( slow.disconnect );
    serverUp = false;
    await slow.connect( userId: "u1" );
    expect( slow.isRetryPending, isTrue );

    serverUp = true;
    expect( await slow.reconnectNow(), isTrue );
    expect( slow.isRetryPending, isFalse );
    await Future<void>.delayed( const Duration( milliseconds: 400 ) );
    expect( channels.length, 1, reason: "the cancelled timer must not open a second channel" );
  } );

  test( "rule 2: a trigger resets the retry counter", () async {
    await giveUp();                       // budget spent: 5 retries used
    serverUp = false;
    expect( await ws.reconnectNow(), isTrue );
    // With the counter reset the failed attempt schedules a fresh retry; with a spent budget it would not.
    expect( ws.isRetryPending, isTrue );
  } );

  test( "rule 3: no reconnect after sign-out", () async {
    await giveUp();
    await ws.disconnect();
    serverUp = true;
    expect( await ws.reconnectNow(), isFalse );
    expect( channels, isEmpty );
  } );

  test( "rule 3: sign-out during an in-flight connect is not undone by it", () async {
    await giveUp();
    serverUp  = true;
    autoReady = false;
    final pending = ws.reconnectNow();
    await _settle();

    await ws.disconnect();
    channels.single.ready_.complete();
    await pending;
    await _settle();

    expect( ws.isConnected, isFalse );
    expect( await ws.reconnectNow(), isFalse );
  } );

  test( "rule 3: no reconnect after a 4004 close", () async {
    await ws.connect( userId: "u1" );
    expect( ws.isConnected, isTrue );

    channels.single.closeWith( WebSocketService.closeCodeSuperseded );
    await _settle();
    expect( ws.isConnected, isFalse );

    expect( await ws.reconnectNow(), isFalse );
    expect( channels.length, 1 );
  } );
}
