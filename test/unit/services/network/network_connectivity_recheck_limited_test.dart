// Row 1b192f22, Tiffany's ruling 2026-10-09: the 30 s re-check also runs while the state is limited, so a Lupin
// server that comes back is seen without an OS network event. The re-check still stops on pause and re-arms on resume.
// Own file: each test file gets its own copy of the singleton.

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/network/network_connectivity_service.dart';

class _FakeConnectivity extends ConnectivityPlatform {
  @override
  Future<ConnectivityResult> checkConnectivity() async => ConnectivityResult.wifi;

  @override
  Stream<ConnectivityResult> get onConnectivityChanged => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test( "a server that is down then up: limited returns to connected within one re-check, none while paused", () {
    fakeAsync( ( async ) {
      ConnectivityPlatform.instance = _FakeConnectivity();
      final network   = NetworkConnectivityService();
      var   serverUp  = false;
      network.internetProbe = () async => serverUp;

      network.initialize();
      async.flushMicrotasks();
      expect( network.currentState, NetworkState.limited, reason: "Wi-Fi is up, the server does not answer" );

      network.pauseMonitoring();
      serverUp = true;
      async.elapse( NetworkConnectivityService.periodicCheckInterval * 3 );
      expect( network.currentState, NetworkState.limited, reason: "paused: no re-check runs" );

      network.resumeMonitoring();
      async.elapse( NetworkConnectivityService.periodicCheckInterval + const Duration( seconds: 1 ) );
      expect( network.currentState, NetworkState.connected, reason: "one re-check after resume sees the server" );

      network.pauseMonitoring();
    } );
  } );
}
