// Row 1b192f22, Rick's ruling 2026-10-09: "has internet" means the configured Lupin server answered,
// not that google.com, cloudflare.com or 8.8.8.8 resolved.

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/core/constants/app_constants.dart';
import 'package:lupin_mobile/services/network/network_connectivity_service.dart';

class _FakeConnectivity extends ConnectivityPlatform {
  final StreamController<ConnectivityResult> events = StreamController<ConnectivityResult>.broadcast();

  @override
  Future<ConnectivityResult> checkConnectivity() async => ConnectivityResult.wifi;

  @override
  Stream<ConnectivityResult> get onConnectivityChanged => events.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group( "reachability is a check of the configured Lupin server", () {
    final fake        = _FakeConnectivity();
    final requested   = <String>[];
    late HttpServer   server;
    late int          port;
    late String       savedBaseUrl;

    setUpAll( () async {
      // The test binding answers every HttpClient request with 400; this test needs the real client.
      HttpOverrides.global = null;
      savedBaseUrl         = AppConstants.apiBaseUrl;
      server               = await HttpServer.bind( InternetAddress.loopbackIPv4, 0 );
      port                 = server.port;
      server.listen( ( request ) {
        requested.add( "${request.method} ${request.uri.path}" );
        request.response
          ..statusCode = 200
          ..write( '{"status":"ok"}' );
        request.response.close();
      } );
      AppConstants.apiBaseUrl = "http://127.0.0.1:$port";
      ConnectivityPlatform.instance = fake;
    } );

    tearDownAll( () async {
      AppConstants.apiBaseUrl = savedBaseUrl;
      await server.close( force: true );
    } );

    test( "a Wi-Fi interface plus a Lupin server that answers reads connected, and the server saw GET /health", () async {
      final network = NetworkConnectivityService();
      await network.initialize();
      network.pauseMonitoring();

      expect( network.currentState, NetworkState.connected );
      expect( requested, contains( "GET /health" ) );
    } );

    test( "a Wi-Fi interface plus a Lupin server that does not answer reads limited", () async {
      final network = NetworkConnectivityService();
      await server.close( force: true );

      fake.events.add( ConnectivityResult.wifi );
      await Future<void>.delayed( const Duration( milliseconds: 500 ) );

      expect( network.currentState, NetworkState.limited );
    } );
  } );

  test( "no file in lib/ looks up google.com, cloudflare.com or 8.8.8.8", () {
    final banned = <String>[ "google.com", "cloudflare.com", "8.8.8.8", "InternetAddress.lookup" ];
    final hits   = <String>[];

    for ( final entity in Directory( "lib" ).listSync( recursive: true ) ) {
      if ( entity is! File || !entity.path.endsWith( ".dart" ) ) continue;
      final lines = entity.readAsLinesSync();
      for ( var i = 0; i < lines.length; i++ ) {
        for ( final word in banned ) {
          if ( lines[ i ].contains( word ) ) hits.add( "${entity.path}:${i + 1} $word" );
        }
      }
    }

    expect( hits, isEmpty, reason: "reachability must ask the Lupin server, not a third party" );
  } );
}
