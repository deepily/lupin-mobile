// Row 1b192f22 follow-up (Pocholo): a pause that arrives before startReconnectServices registers the lifecycle
// observer (main() is still awaiting AppInitialization.initialize) was lost, because the lifecycle service
// assumed "resumed" at init. The connectivity timers then armed in the background.

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/lifecycle/app_lifecycle_service.dart';
import 'package:lupin_mobile/services/network/network_connectivity_service.dart';
import 'package:lupin_mobile/services/websocket/ws_reconnect_coordinator.dart';

class _FakeConnectivity extends ConnectivityPlatform {
  @override
  Future<ConnectivityResult> checkConnectivity() async => ConnectivityResult.wifi;

  @override
  Stream<ConnectivityResult> get onConnectivityChanged => const Stream.empty();
}

class _NeverConnectedTarget implements WsReconnectTarget {
  @override bool get isConnected     => false;
  @override bool get isConnecting    => false;
  @override bool get isRetryPending  => false;
  @override bool get wantsConnection => false;
  @override Future<bool> reconnectNow() async => false;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test( "a pause before the services start keeps the connectivity timers unarmed until the next resume", () async {
    ConnectivityPlatform.instance = _FakeConnectivity();
    NetworkConnectivityService().internetProbe = () async => true;

    binding.handleAppLifecycleStateChanged( AppLifecycleState.paused );

    final coordinator = WsReconnectCoordinator.forApp( _NeverConnectedTarget() );
    addTearDown( coordinator.stop );
    startReconnectServices( coordinator );
    await Future<void>.delayed( const Duration( milliseconds: 50 ) );

    expect( AppLifecycleService().currentLifecycleState, AppLifecycleState.paused, reason: "first state comes from the binding" );
    expect( NetworkConnectivityService().isMonitoring, isFalse, reason: "no DNS timers in the background" );
    expect( coordinator.isLoopRunning, isFalse );

    binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
    await Future<void>.delayed( Duration.zero );
    expect( NetworkConnectivityService().isMonitoring, isTrue, reason: "armed on the next resume" );
  } );
}
