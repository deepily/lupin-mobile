// Row 1b192f22: a Bluetooth-only connection is limited by design and is never re-checked against the server.
// Own file: each test file gets its own copy of the singleton.

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/network/network_connectivity_service.dart';

class _BluetoothOnly extends ConnectivityPlatform {
  @override
  Future<ConnectivityResult> checkConnectivity() async => ConnectivityResult.bluetooth;

  @override
  Stream<ConnectivityResult> get onConnectivityChanged => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test( "a Bluetooth-only connection stays limited and the 30 s re-check never asks the server", () {
    fakeAsync( ( async ) {
      ConnectivityPlatform.instance = _BluetoothOnly();
      final network = NetworkConnectivityService();
      var   probes  = 0;
      network.internetProbe = () async { probes++; return true; };

      network.initialize();
      async.flushMicrotasks();
      expect( network.currentState, NetworkState.limited );
      expect( network.isMonitoring, isTrue, reason: "the timers are armed, so the guard is what holds the re-check back" );

      async.elapse( NetworkConnectivityService.periodicCheckInterval * 4 );

      expect( probes, 0, reason: "no health request on Bluetooth" );
      expect( network.currentState, NetworkState.limited );

      network.pauseMonitoring();
    } );
  } );
}
