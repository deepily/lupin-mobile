// Row 1b192f22: the connectivity timers must not arm while the app is paused, whatever the order of start-up and
// the first pause. Each test file gets its own copy of the singleton, so each ordering lives in its own file.

import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/network/network_connectivity_service.dart';
import 'package:lupin_mobile/services/websocket/ws_reconnect_coordinator.dart';

class _SlowConnectivity extends ConnectivityPlatform {
  final Completer<ConnectivityResult> first = Completer<ConnectivityResult>();

  @override
  Future<ConnectivityResult> checkConnectivity() => first.future;

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

  test( "a pause during the first connectivity check leaves the timers unarmed until the next resume", () async {
    final platform = _SlowConnectivity();
    ConnectivityPlatform.instance = platform;
    NetworkConnectivityService().internetProbe = () async => true;
    final coordinator = WsReconnectCoordinator.forApp( _NeverConnectedTarget() );
    addTearDown( coordinator.stop );

    startReconnectServices( coordinator );
    await Future<void>.delayed( Duration.zero );

    binding.handleAppLifecycleStateChanged( AppLifecycleState.paused );
    await Future<void>.delayed( Duration.zero );

    platform.first.complete( ConnectivityResult.wifi );
    await Future<void>.delayed( const Duration( milliseconds: 50 ) );
    expect( NetworkConnectivityService().isMonitoring, isFalse, reason: "initialize() finished while paused" );

    binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
    await Future<void>.delayed( Duration.zero );
    expect( NetworkConnectivityService().isMonitoring, isTrue, reason: "armed on the next resume" );
  } );
}
