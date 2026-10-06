// Row b69dbf0b: main() must start the lifecycle and connectivity services and the coordinator; the connectivity
// timers must stop while the app is in the background.

import 'dart:io';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/network/network_connectivity_service.dart';
import 'package:lupin_mobile/services/websocket/ws_reconnect_coordinator.dart';

import '../../../_helpers/source_text.dart';

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

  test( "main() calls startReconnectServices with the registered coordinator", () {
    final code = stripComments( File( "lib/main.dart" ).readAsStringSync() );
    expect( code, contains( "startReconnectServices( ServiceLocator.get<WsReconnectCoordinator>() )" ) );
  } );

  test( "the service locator registers the coordinator", () {
    final code = stripComments( File( "lib/core/di/service_locator.dart" ).readAsStringSync() );
    expect( code, contains( "registerSingleton<WsReconnectCoordinator>" ) );
  } );

  test( "startReconnectServices starts the services and the coordinator; connectivity timers follow the lifecycle", () async {
    ConnectivityPlatform.instance = _FakeConnectivity();
    NetworkConnectivityService().internetProbe = () async => true;
    final coordinator = WsReconnectCoordinator.forApp( _NeverConnectedTarget() );
    addTearDown( coordinator.stop );

    startReconnectServices( coordinator );
    await Future<void>.delayed( const Duration( milliseconds: 50 ) );

    expect( coordinator.isLoopRunning, isTrue, reason: "the coordinator started, on screen" );
    expect( NetworkConnectivityService().isMonitoring, isTrue, reason: "the connectivity service was initialized" );

    binding.handleAppLifecycleStateChanged( AppLifecycleState.paused );
    await Future<void>.delayed( Duration.zero );
    expect( NetworkConnectivityService().isMonitoring, isFalse, reason: "no DNS timers in the background" );
    expect( coordinator.isLoopRunning, isFalse );

    binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
    await Future<void>.delayed( Duration.zero );
    expect( NetworkConnectivityService().isMonitoring, isTrue );
    expect( coordinator.isLoopRunning, isTrue );
  } );
}
