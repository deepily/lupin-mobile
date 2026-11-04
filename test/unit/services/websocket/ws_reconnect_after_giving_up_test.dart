// Row b69dbf0b: reproduction. After the first connect and five retries fail, the socket gives up,
// and nothing but a new login brings it back. The server then returns, the app resumes and the
// network is restored, and the socket must come back. Today it does not.
//
// Both triggers are pumped on the real singletons: AppLifecycleService through the test binding,
// NetworkConnectivityService through a fake connectivity_plus platform. The connectivity service's reachability
// check is replaced through its internetProbe seam, so the test needs no network.

import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:lupin_mobile/core/logging/logger.dart';
import 'package:lupin_mobile/services/auth/auth_token_provider.dart';
import 'package:lupin_mobile/services/lifecycle/app_lifecycle_service.dart';
import 'package:lupin_mobile/services/network/network_connectivity_service.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';
import 'package:lupin_mobile/services/websocket/ws_reconnect_coordinator.dart';
import 'package:lupin_mobile/services/websocket/ws_resume_store.dart';

class _SessionAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch( RequestOptions o, Stream<List<int>>? s, Future<void>? c ) async =>
      ResponseBody.fromString( jsonEncode( { "session_id": "wise penguin" } ), 200,
          headers: { Headers.contentTypeHeader: [ "application/json" ] } );

  @override
  void close( { bool force = false } ) {}
}

class _FakeChannel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  final _in = StreamController<dynamic>();
  late final WebSocketSink _sink = _FakeSink();

  @override Stream<dynamic> get stream => _in.stream;
  @override WebSocketSink   get sink   => _sink;
  @override Future<void>    get ready  => Future.value();
  @override int?    get closeCode   => null;
  @override String? get closeReason => null;
  @override String? get protocol    => null;
}

class _FakeSink implements WebSocketSink {
  @override void add( dynamic data ) {}
  @override void addError( Object e, [ StackTrace? st ] ) {}
  @override Future<void> addStream( Stream<dynamic> s ) => s.forEach( add );
  @override Future<void> close( [ int? code, String? reason ] ) async {}
  @override Future<void> get done => Future.value();
}

class _FakeConnectivity extends ConnectivityPlatform {
  final StreamController<ConnectivityResult> changes = StreamController<ConnectivityResult>.broadcast();

  @override
  Future<ConnectivityResult> checkConnectivity() async => ConnectivityResult.none;

  @override
  Stream<ConnectivityResult> get onConnectivityChanged => changes.stream;
}

Future<void> _wait( int ms ) => Future<void>.delayed( Duration( milliseconds: ms ) );

void main() {
  final binding  = TestWidgetsFlutterBinding.ensureInitialized();
  final platform = _FakeConnectivity();

  late WebSocketService       ws;
  late WsReconnectCoordinator coordinator;
  late int              connectAttempts;
  late bool             serverUp;

  setUpAll( () async {
    ConnectivityPlatform.instance = platform;
    AppLifecycleService().initialize();
    NetworkConnectivityService().internetProbe = () async => true;
    await NetworkConnectivityService().initialize();
  } );

  setUp( () {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Logger.resetForTesting();
    readAccessToken = () => "tok";
    connectAttempts = 0;
    serverUp        = false;
    binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
    ws = WebSocketService(
      Dio()..httpClientAdapter = _SessionAdapter(),
      store              : WsResumeStore(),
      reconnectBaseDelay : const Duration( milliseconds: 1 ),
      channelFactory     : ( Uri _ ) {
        connectAttempts++;
        if ( !serverUp ) throw Exception( "server down" );
        return _FakeChannel();
      },
    );
    coordinator = WsReconnectCoordinator(
      target              : ws,
      lifecycle           : AppLifecycleService().lifecycleStream,
      network             : NetworkConnectivityService().networkStateStream,
      initiallyForeground : true,
      networkDebounce     : const Duration( milliseconds: 100 ),
    )..start();
  } );

  tearDown( () async {
    coordinator.stop();
    await ws.disconnect();
    Logger.resetForTesting();
  } );

  /// Fails the first connect and all five retries, then confirms the service has stopped trying.
  Future<void> failSixConnectsAndGiveUp() async {
    await ws.connect( userId: "u1" );
    await _wait( 400 );
    expect( connectAttempts, 6, reason: "one connect and five retries" );
    expect( ws.isConnected, isFalse );

    await _wait( 200 );
    expect( connectAttempts, 6, reason: "the service has given up: no seventh try on its own" );
  }

  test( "the server returns and the app resumes: the socket reconnects", () async {
    await failSixConnectsAndGiveUp();

    serverUp = true;
    binding.handleAppLifecycleStateChanged( AppLifecycleState.paused );
    binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
    await _wait( 400 );

    expect( ws.isConnected, isTrue, reason: "a resume after the outage should bring the socket back" );
  } );

  test( "the server returns and the network is restored: the socket reconnects", () async {
    await failSixConnectsAndGiveUp();

    serverUp = true;
    platform.changes.add( ConnectivityResult.none );
    platform.changes.add( ConnectivityResult.wifi );
    await _wait( 600 );

    expect( ws.isConnected, isTrue, reason: "connectivity restored should bring the socket back" );
  } );
}
