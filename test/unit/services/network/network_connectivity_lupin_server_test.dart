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

  group( "the third-party scan", () {
    test( "catches the spellings that dodge a plain text match", () {
      final dodges = <String>[
        "x = 'goo' 'gle.com';",
        "x = 'Google.COM';",
        "x = 'google.' + 'com';",
        "x = 'cloud' 'flare.com';",
        'x = "Cloud" + "Flare.Com";',
        "await InternetAddress . lookup( h );",
        "await InternetAddress\n  .lookup( h );",
        "x = '8.8.8.8';",
      ];
      for ( final dodge in dodges ) {
        expect( thirdPartyHits( dodge ), isNotEmpty, reason: dodge );
      }
      expect( thirdPartyHits( "x = '\${AppConstants.apiBaseUrl}/health';" ), isEmpty );
    } );

    test( "no file in lib/ looks up google.com, cloudflare.com or 8.8.8.8", () {
      final hits = <String>[];

      for ( final entity in Directory( "lib" ).listSync( recursive: true ) ) {
        if ( entity is! File || !entity.path.endsWith( ".dart" ) ) continue;
        for ( final hit in thirdPartyHits( entity.readAsStringSync() ) ) {
          hits.add( "${entity.path}: $hit" );
        }
      }

      expect( hits, isEmpty, reason: "reachability must ask the Lupin server, not a third party" );
    } );
  } );
}

/// Returns the banned third-party names found in [source], ignoring case and whitespace around the dot of a lookup.
///
/// Adjacent string literals and literals joined with `+` are merged first, so `'goo' 'gle.com'` and
/// `'google.' + 'com'` are caught. A host name assembled at run time (from a list, a join, a decode) cannot be
/// caught by a text scan, and this scan does not try. The real guard is the behavioural test above: the loopback
/// server saw `GET /health`, and the answer came from it.
List<String> thirdPartyHits( String source ) {
  final merged  = source.replaceAll( RegExp( r"""['"]\s*(\+\s*)?['"]""" ), "" );
  final banned  = <RegExp>[
    RegExp( r"google\.com", caseSensitive: false ),
    RegExp( r"cloudflare\.com", caseSensitive: false ),
    RegExp( r"8\.8\.8\.8" ),
    RegExp( r"InternetAddress\s*\.\s*lookup", caseSensitive: false ),
  ];
  return <String>[ for ( final pattern in banned ) if ( pattern.hasMatch( merged ) ) pattern.pattern ];
}
