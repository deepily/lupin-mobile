// Row e0f0faf0, finding sections G and H: the phone's socket service lets a channel it has replaced
// speak for the live one, takes a session id before the socket is up, and counts one failure twice.
//
// Each test drives fake channels by hand: the test decides when a handshake completes and when
// an error or a close arrives, including a close that arrives late.

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

/// Hands out one session id per request, in order; the last one repeats.
class _SessionAdapter implements HttpClientAdapter {
  final List<String> ids;
  int requests = 0;

  _SessionAdapter( this.ids );

  @override
  Future<ResponseBody> fetch( RequestOptions o, Stream<List<int>>? s, Future<void>? c ) async {
    final id = ids[ requests < ids.length ? requests : ids.length - 1 ];
    requests++;
    return ResponseBody.fromString( jsonEncode( { "session_id": id } ), 200,
        headers: { Headers.contentTypeHeader: [ "application/json" ] } );
  }

  @override
  void close( { bool force = false } ) {}
}

class _RecordingSink implements WebSocketSink {
  int? closedWith;
  bool closed = false;

  @override void add( dynamic data ) {}
  @override void addError( Object e, [ StackTrace? st ] ) {}
  @override Future<void> addStream( Stream<dynamic> s ) => s.forEach( add );
  @override Future<void> close( [ int? code, String? reason ] ) async {
    closed     = true;
    closedWith = code;
  }
  @override Future<void> get done => Future.value();
}

/// A channel the test drives: it completes the handshake, injects errors, and closes with a chosen code.
class _FakeChannel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  final _in      = StreamController<dynamic>();
  final _ready   = Completer<void>();
  final _sink    = _RecordingSink();
  int? code;

  @override Stream<dynamic> get stream => _in.stream;
  @override WebSocketSink   get sink   => _sink;
  @override Future<void>    get ready  => _ready.future;
  @override int?    get closeCode   => code;
  @override String? get closeReason => null;
  @override String? get protocol    => null;

  bool get wasClosedByClient => _sink.closed;

  void handshake() => _ready.complete();
  void fail( Object e ) => _in.addError( e );

  /// The close arrives as the server's frame would: the code is set, then the stream ends.
  void closeWith( int c ) {
    code = c;
    _in.close();
  }
}

Future<void> _settle() => Future<void>.delayed( const Duration( milliseconds: 30 ) );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WebSocketService   ws;
  late _SessionAdapter    sessions;
  late List<_FakeChannel> channels;
  late bool               serverUp;

  WebSocketService build( { Duration delay = const Duration( milliseconds: 1 ), List<String>? ids } ) {
    sessions = _SessionAdapter( ids ?? [ "wise penguin", "clever dolphin", "happy turtle" ] );
    return WebSocketService(
      Dio()..httpClientAdapter = sessions,
      store              : WsResumeStore(),
      reconnectBaseDelay : delay,
      channelFactory     : ( Uri _ ) {
        if ( !serverUp ) throw Exception( "server down" );
        final c = _FakeChannel();
        channels.add( c );
        return c;
      },
    );
  }

  setUp( () {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Logger.resetForTesting();
    readAccessToken = () => "tok";
    channels = [];
    serverUp = true;
    ws       = build();
  } );

  tearDown( () async {
    await ws.disconnect();
    Logger.resetForTesting();
  } );

  /// Connects and completes the handshake of the channel the attempt just opened.
  Future<_FakeChannel> connectFirst() async {
    final pending = ws.connect( userId: "u1" );
    await _settle();
    channels.last.handshake();
    await pending;
    return channels.last;
  }

  /// Waits for the channel the next retry opens, then completes its handshake.
  Future<_FakeChannel> admitNext() async {
    final before = channels.length;
    for ( var i = 0; i < 100 && channels.length == before; i++ ) {
      await Future<void>.delayed( const Duration( milliseconds: 5 ) );
    }
    expect( channels.length, before + 1, reason: "a retry should have opened a channel" );
    channels.last.handshake();
    await _settle();
    return channels.last;
  }

  group( "stale listener", () {
    test( "a late close from a replaced channel does not take the live socket down", () async {
      final first = await connectFirst();
      expect( ws.isConnected, isTrue );

      // The first channel errors; the service reconnects to a second one, which comes up.
      first.fail( Exception( "reset by peer" ) );
      final second = await admitNext();
      expect( ws.isConnected, isTrue );
      expect( identical( second, first ), isFalse );

      // The first channel's done arrives late, after the second is live.
      first.closeWith( 1006 );
      await _settle();

      expect( ws.isConnected, isTrue, reason: "a done from a channel that is no longer current must not touch the live one" );
      expect( ws.isRetryPending, isFalse, reason: "and it must not schedule a reconnect" );
      expect( channels.length, 2 );
    } );

    test( "a late 4004 on the old channel, read against the new channel's null close code, is not mistaken for a plain drop", () async {
      final first = await connectFirst();
      first.fail( Exception( "reset by peer" ) );
      final second = await admitNext();

      first.closeWith( kSuperseded );
      await _settle();

      // The old code read second.closeCode (null) here, so it cleared the live connected flag and scheduled a reconnect.
      expect( second.closeCode, isNull );
      expect( ws.isConnected, isTrue );
      expect( ws.isRetryPending, isFalse );
      expect( channels.length, 2, reason: "no third socket may be opened" );
    } );

    test( "a close with 4004 on the current channel is recognised and not retried", () async {
      final first = await connectFirst();

      first.closeWith( kSuperseded );
      await _settle();
      await Future<void>.delayed( const Duration( milliseconds: 40 ) );

      expect( ws.isConnected, isFalse );
      expect( ws.wantsConnection, isFalse, reason: "4004 is permanent: a newer socket holds the slot" );
      expect( ws.isRetryPending, isFalse );
      expect( channels.length, 1 );
    } );

    test( "the previous channel is closed when a new one opens", () async {
      final first = await connectFirst();
      first.fail( Exception( "reset by peer" ) );
      await admitNext();

      expect( first.wasClosedByClient, isTrue, reason: "an errored channel must not stay open behind the new one" );
    } );
  } );

  group( "session id", () {
    test( "a failed attempt leaves the earlier id, not the one just fetched", () async {
      final first = await connectFirst();
      expect( ws.sessionId, "wise penguin" );

      serverUp = false;
      first.fail( Exception( "reset by peer" ) );
      await Future<void>.delayed( const Duration( milliseconds: 60 ) );

      expect( sessions.requests, greaterThanOrEqualTo( 2 ), reason: "a second id was requested" );
      expect( ws.isConnected, isFalse );
      expect( ws.sessionId, "wise penguin", reason: "an id fetched for a socket that never opened must not replace the held one" );
    } );

    test( "a first attempt that fails leaves no id at all", () async {
      serverUp = false;
      await ws.connect( userId: "u1" );
      await Future<void>.delayed( const Duration( milliseconds: 30 ) );

      expect( sessions.requests, greaterThanOrEqualTo( 1 ) );
      expect( ws.sessionId, isNull );
    } );

    test( "the id is taken once the socket is up", () async {
      await connectFirst();
      expect( ws.sessionId, "wise penguin" );
    } );
  } );

  group( "one failure, one reconnect", () {
    test( "an error followed by a done on the same channel counts once toward the cap", () async {
      ws = build( delay: const Duration( milliseconds: 60 ) );
      final first = await connectFirst();
      expect( ws.reconnectAttempts, 0 );

      first.fail( Exception( "reset by peer" ) );
      first.closeWith( 1006 );
      await _settle();

      expect( ws.reconnectAttempts, 1, reason: "the error and the done are one failure" );
      expect( ws.isRetryPending, isTrue );
    } );

    test( "an error and a done open exactly one new channel", () async {
      final first = await connectFirst();

      first.fail( Exception( "reset by peer" ) );
      first.closeWith( 1006 );
      await _settle();
      await _settle();

      expect( channels.length, 2 );
    } );
  } );
}

/// Same value as [WebSocketService.closeCodeSuperseded], named so the test body reads as the server's frame.
const int kSuperseded = WebSocketService.closeCodeSuperseded;
