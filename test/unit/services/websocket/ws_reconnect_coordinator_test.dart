// Row b69dbf0b: the four reconnect triggers and the retry loop, on a fake socket target and a fake clock.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/network/network_connectivity_service.dart';
import 'package:lupin_mobile/services/websocket/ws_reconnect_coordinator.dart';

class _FakeTarget implements WsReconnectTarget {
  @override bool isConnected    = false;
  @override bool isConnecting   = false;
  @override bool isRetryPending = false;
  @override bool wantsConnection = true;
  int  calls      = 0;
  bool succeeds   = false;

  @override
  Future<bool> reconnectNow() async {
    if ( isConnected || isConnecting || !wantsConnection ) return false;
    calls++;
    if ( succeeds ) isConnected = true;
    return true;
  }
}

void main() {
  late _FakeTarget                          target;
  late StreamController<AppLifecycleState>  life;
  late StreamController<NetworkState>       net;
  late WsReconnectCoordinator               coordinator;

  /// Runs [body] under a fake clock with a started coordinator whose jitter is neutral (factor 1.0).
  void scenario( String name, void Function( FakeAsync async ) body, { bool foreground = true } ) {
    test( name, () {
      fakeAsync( ( async ) {
        target = _FakeTarget();
        life   = StreamController<AppLifecycleState>.broadcast( sync: true );
        net    = StreamController<NetworkState>.broadcast( sync: true );
        coordinator = WsReconnectCoordinator(
          target              : target,
          lifecycle           : life.stream,
          network             : net.stream,
          initiallyForeground : foreground,
          random              : () => 0.5,
        )..start();
        body( async );
        coordinator.stop();
      } );
    } );
  }

  group( "triggers", () {
    scenario( "app resume with the socket down: one try", ( async ) {
      life.add( AppLifecycleState.paused );
      life.add( AppLifecycleState.resumed );
      async.flushMicrotasks();
      expect( target.calls, 1 );
    } );

    scenario( "app resume with the socket up: no try", ( async ) {
      target.isConnected = true;
      life.add( AppLifecycleState.resumed );
      async.flushMicrotasks();
      expect( target.calls, 0 );
    } );

    scenario( "network restored: one try, after the 2 s debounce", ( async ) {
      net.add( NetworkState.connected );
      async.elapse( const Duration( milliseconds: 1900 ) );
      expect( target.calls, 0 );
      async.elapse( const Duration( milliseconds: 200 ) );
      expect( target.calls, 1 );
    } );

    scenario( "network flapping inside the debounce window: still one try", ( async ) {
      net.add( NetworkState.connected );
      async.elapse( const Duration( seconds: 1 ) );
      net.add( NetworkState.disconnected );
      net.add( NetworkState.connected );
      async.elapse( const Duration( seconds: 1 ) );
      net.add( NetworkState.connected );
      async.elapse( const Duration( seconds: 3 ) );
      expect( target.calls, 1 );
    } );

    scenario( "a LAN with no internet (limited) also counts as restored", ( async ) {
      net.add( NetworkState.limited );
      async.elapse( const Duration( seconds: 3 ) );
      expect( target.calls, 1 );
    } );

    scenario( "network going down triggers nothing", ( async ) {
      net.add( NetworkState.disconnected );
      async.elapse( const Duration( seconds: 3 ) );
      expect( target.calls, 0 );
    } );

    scenario( "foreground push with the socket down: reconnects", ( async ) {
      coordinator.onForegroundPush();
      async.flushMicrotasks();
      expect( target.calls, 1 );
    } );

    scenario( "foreground push with the socket up: ignored", ( async ) {
      target.isConnected = true;
      coordinator.onForegroundPush();
      async.flushMicrotasks();
      expect( target.calls, 0 );
    } );

    scenario( "a network event is dropped when the app went to the background in the debounce window", ( async ) {
      net.add( NetworkState.connected );
      life.add( AppLifecycleState.paused );
      async.elapse( const Duration( seconds: 3 ) );
      expect( target.calls, 0 );
    } );
  } );

  group( "refusals", () {
    scenario( "signed out: no trigger reaches a connect", ( async ) {
      target.wantsConnection = false;
      life.add( AppLifecycleState.resumed );
      net.add( NetworkState.connected );
      coordinator.onForegroundPush();
      async.elapse( const Duration( minutes: 10 ) );
      expect( target.calls, 0 );
    } );

    scenario( "a connect already running: triggers start nothing", ( async ) {
      target.isConnecting = true;
      life.add( AppLifecycleState.resumed );
      coordinator.onForegroundPush();
      async.elapse( const Duration( minutes: 2 ) );
      expect( target.calls, 0 );
    } );

    scenario( "the loop leaves the service's own retry timer alone", ( async ) {
      target.isRetryPending = true;
      async.elapse( const Duration( minutes: 2 ) );
      expect( target.calls, 0 );
    } );
  } );

  group( "retry loop", () {
    scenario( "runs on screen with backoff 30 s, 60 s, 120 s, 240 s, then the 300 s cap", ( async ) {
      final at = <int>[];
      for ( var s = 1; s <= 1300; s++ ) {
        final before = target.calls;
        async.elapse( const Duration( seconds: 1 ) );
        if ( target.calls > before ) at.add( s );
      }
      expect( at, [ 30, 90, 210, 450, 750, 1050 ] );
    } );

    scenario( "jitter spreads each delay by up to 20 percent either way", ( async ) {
      coordinator.stop();
      var draw = 0.0;
      coordinator = WsReconnectCoordinator(
        target: target, lifecycle: life.stream, network: net.stream, initiallyForeground: true, random: () => draw,
      )..start();
      async.elapse( const Duration( seconds: 23 ) );
      expect( target.calls, 0, reason: "lowest draw: 24 s, not yet" );
      async.elapse( const Duration( seconds: 2 ) );
      expect( target.calls, 1 );
      coordinator.stop();
    } );

    scenario( "stops on pause and makes no try in the background", ( async ) {
      life.add( AppLifecycleState.paused );
      expect( coordinator.isLoopRunning, isFalse );
      async.elapse( const Duration( minutes: 30 ) );
      expect( target.calls, 0 );
    } );

    scenario( "restarts on resume, from the shortest delay", ( async ) {
      async.elapse( const Duration( seconds: 100 ) );          // two loop tries, delay now 120 s
      final before = target.calls;
      life.add( AppLifecycleState.paused );
      async.elapse( const Duration( minutes: 10 ) );
      expect( target.calls, before );

      life.add( AppLifecycleState.resumed );
      async.flushMicrotasks();
      expect( target.calls, before + 1, reason: "the resume trigger itself" );
      expect( coordinator.isLoopRunning, isTrue );
      async.elapse( const Duration( seconds: 31 ) );
      expect( target.calls, before + 2, reason: "the loop is back at 30 s" );
    } );

    scenario( "does not start when the app begins in the background", ( async ) {
      expect( coordinator.isLoopRunning, isFalse );
      async.elapse( const Duration( minutes: 10 ) );
      expect( target.calls, 0 );
    }, foreground: false );

    scenario( "a successful try resets the backoff", ( async ) {
      async.elapse( const Duration( seconds: 100 ) );          // 30 s and 60 s tries failed
      target.succeeds = true;
      async.elapse( const Duration( seconds: 130 ) );          // the 120 s try succeeds
      expect( target.isConnected, isTrue );
      final before = target.calls;
      async.elapse( const Duration( minutes: 10 ) );
      expect( target.calls, before, reason: "connected: the loop only idles" );
      target.isConnected = false;                              // the socket drops again
      async.elapse( const Duration( seconds: 31 ) );
      expect( target.calls, before + 1, reason: "back at the 30 s delay" );
    } );
  } );
}
