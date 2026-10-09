// Row 1b192f22: a Lupin server that accepts the connection and never answers must read limited after the 5 s
// reachability timeout, not hang the check. Own file: each test file gets its own copy of the singleton.

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/core/constants/app_constants.dart';
import 'package:lupin_mobile/services/network/network_connectivity_service.dart';

class _FakeConnectivity extends ConnectivityPlatform {
  @override
  Future<ConnectivityResult> checkConnectivity() async => ConnectivityResult.wifi;

  @override
  Stream<ConnectivityResult> get onConnectivityChanged => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test( "a server that accepts and never answers reads limited after about 5 seconds", () async {
    HttpOverrides.global = null;
    final saved  = AppConstants.apiBaseUrl;
    final server = await HttpServer.bind( InternetAddress.loopbackIPv4, 0 );
    final held   = <HttpRequest>[];
    server.listen( held.add );
    AppConstants.apiBaseUrl       = "http://127.0.0.1:${server.port}";
    ConnectivityPlatform.instance = _FakeConnectivity();
    addTearDown( () async {
      AppConstants.apiBaseUrl = saved;
      await server.close( force: true );
    } );

    final network   = NetworkConnectivityService();
    final stopwatch = Stopwatch()..start();
    await network.initialize();
    stopwatch.stop();
    network.pauseMonitoring();

    expect( held, isNotEmpty, reason: "the request reached the server and was left unanswered" );
    expect( network.currentState, NetworkState.limited );
    expect( stopwatch.elapsedMilliseconds, inInclusiveRange( 4500, 9000 ), reason: "the 5 s timeout ended the wait" );
  } );
}
