// Row 1b192f22: a pause that arrives before initialize() has run must still keep the timers unarmed.

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
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

  test( "pauseMonitoring before initialize() keeps the timers unarmed; resumeMonitoring arms them", () async {
    ConnectivityPlatform.instance = _FakeConnectivity();
    final network = NetworkConnectivityService();
    network.internetProbe = () async => true;

    network.pauseMonitoring();
    await network.initialize();
    expect( network.isMonitoring, isFalse );

    network.resumeMonitoring();
    expect( network.isMonitoring, isTrue );
  } );
}
