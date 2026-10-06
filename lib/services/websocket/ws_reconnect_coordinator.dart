import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../core/logging/logger.dart';
import '../lifecycle/app_lifecycle_service.dart';
import '../network/network_connectivity_service.dart';

/// Starts what the reconnect triggers listen to, then [coordinator].
///
/// Neither the lifecycle nor the connectivity service does anything until its `initialize()` runs. The connectivity
/// timers are paused while the app is not on screen, so a backgrounded app makes no DNS lookups.
void startReconnectServices( WsReconnectCoordinator coordinator ) {
  AppLifecycleService().initialize();
  unawaited( NetworkConnectivityService().initialize() );
  AppLifecycleService().lifecycleStream.listen( ( state ) {
    final network = NetworkConnectivityService();
    if ( state == AppLifecycleState.resumed ) {
      network.resumeMonitoring();
    } else if ( state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached ) {
      network.pauseMonitoring();
    }
  } );
  coordinator.start();
}

/// What the coordinator needs from the socket service.
///
/// [WebSocketService] implements it; tests supply a fake.
abstract class WsReconnectTarget {
  /// True while the socket is connected.
  bool get isConnected;

  /// True while a connect attempt is running.
  bool get isConnecting;

  /// True while the service's own retry timer is waiting to fire.
  bool get isRetryPending;

  /// True when the service may open a socket on its own: signed in, not disconnected, not superseded.
  bool get wantsConnection;

  /// Makes one guarded attempt; false means nothing was started.
  Future<bool> reconnectNow();
}

/// Brings the WebSocket back after the service has given up, from four triggers.
///
/// The triggers are app resume, network restored (debounced), a foreground push wake-up and a slow retry loop.
/// The loop runs only while the app is on screen. Every trigger goes through [WsReconnectTarget.reconnectNow],
/// which refuses when a connect is running or the service was signed out or superseded.
class WsReconnectCoordinator {
  final WsReconnectTarget         _target;
  final Stream<AppLifecycleState> _lifecycle;
  final Stream<NetworkState>      _network;
  final Duration                  _networkDebounce;
  final Duration                  _loopBase;
  final Duration                  _loopCap;
  final double Function()         _random;

  /// Jitter applied to each loop delay: the delay is scaled by a factor in 1 +/- this fraction.
  static const double loopJitter = 0.2;

  bool                             _foreground;
  int                              _loopStep = 0;
  Timer?                           _loopTimer;
  Timer?                           _networkTimer;
  StreamSubscription<AppLifecycleState>? _lifecycleSub;
  StreamSubscription<NetworkState>?      _networkSub;

  /// Creates a stopped coordinator; call [start] to listen.
  ///
  /// [initiallyForeground] says whether the app is on screen now. [random] returns values in [0, 1).
  WsReconnectCoordinator( {
    required WsReconnectTarget         target,
    required Stream<AppLifecycleState> lifecycle,
    required Stream<NetworkState>      network,
    required bool                      initiallyForeground,
    Duration                           networkDebounce = const Duration( seconds: 2 ),
    Duration                           loopBase        = const Duration( seconds: 30 ),
    Duration                           loopCap         = const Duration( minutes: 5 ),
    double Function()?                 random,
  } )  : _target          = target,
        _lifecycle        = lifecycle,
        _network          = network,
        _foreground       = initiallyForeground,
        _networkDebounce  = networkDebounce,
        _loopBase         = loopBase,
        _loopCap          = loopCap,
        _random           = random ?? Random().nextDouble;

  /// Builds the coordinator on the app's lifecycle and connectivity singletons.
  factory WsReconnectCoordinator.forApp( WsReconnectTarget target ) {
    final state = WidgetsBinding.instance.lifecycleState;
    return WsReconnectCoordinator(
      target              : target,
      lifecycle           : AppLifecycleService().lifecycleStream,
      network             : NetworkConnectivityService().networkStateStream,
      initiallyForeground : state == null || state == AppLifecycleState.resumed || state == AppLifecycleState.inactive,
    );
  }

  /// True while the retry loop has a timer armed.
  bool get isLoopRunning => _loopTimer != null;

  /// Starts listening and, when the app is on screen, arms the retry loop.
  void start() {
    if ( _lifecycleSub != null ) return;
    _lifecycleSub = _lifecycle.listen( _onLifecycle );
    _networkSub   = _network.listen( _onNetwork );
    if ( _foreground ) _armLoop();
  }

  /// Stops listening and cancels every timer.
  void stop() {
    _lifecycleSub?.cancel();
    _networkSub?.cancel();
    _lifecycleSub = null;
    _networkSub   = null;
    _networkTimer?.cancel();
    _networkTimer = null;
    _cancelLoop();
  }

  /// The foreground push trigger: the socket is down although a push says the server has something.
  Future<void> onForegroundPush() => _attempt( "foreground push" );

  void _onLifecycle( AppLifecycleState state ) {
    if ( state == AppLifecycleState.resumed ) {
      _foreground = true;
      _loopStep   = 0;
      _armLoop();
      _attempt( "app resume" );
    } else if ( state == AppLifecycleState.paused || state == AppLifecycleState.detached || state == AppLifecycleState.hidden ) {
      _foreground = false;
      _networkTimer?.cancel();
      _networkTimer = null;
      _cancelLoop();
    }
  }

  /// An interface coming up counts, including `limited`: the server may be on a LAN with no internet.
  void _onNetwork( NetworkState state ) {
    if ( state != NetworkState.connected && state != NetworkState.limited ) return;
    _networkTimer?.cancel();
    _networkTimer = Timer( _networkDebounce, () {
      _networkTimer = null;
      if ( _foreground ) _attempt( "network restored" );
    } );
  }

  Future<void> _attempt( String trigger ) async {
    if ( _target.isConnected ) return;
    try {
      final started = await _target.reconnectNow();
      if ( started ) Logger.info( "Reconnect attempt from $trigger: ${ _target.isConnected ? 'connected' : 'failed' }", tag: "WsReconnect" );
    } catch ( e, st ) {
      Logger.error( "Reconnect attempt from $trigger threw", tag: "WsReconnect", error: e, stackTrace: st );
    }
  }

  Duration _nextLoopDelay() {
    final base   = _loopBase * pow( 2, _loopStep ).toInt();
    final capped = base > _loopCap ? _loopCap : base;
    final factor = 1 - loopJitter + 2 * loopJitter * _random();
    return Duration( microseconds: ( capped.inMicroseconds * factor ).round() );
  }

  void _armLoop() {
    _loopTimer?.cancel();
    if ( !_foreground ) return;
    _loopTimer = Timer( _nextLoopDelay(), _onLoopTick );
  }

  Future<void> _onLoopTick() async {
    _loopTimer = null;
    if ( !_foreground ) return;
    if ( _target.isConnected || !_target.wantsConnection ) {
      _loopStep = 0;
    } else if ( !_target.isConnecting && !_target.isRetryPending ) {
      await _attempt( "retry loop" );
      if ( _target.isConnected ) { _loopStep = 0; } else { _loopStep++; }
    }
    if ( _foreground && _lifecycleSub != null ) _armLoop();
  }

  void _cancelLoop() {
    _loopTimer?.cancel();
    _loopTimer = null;
  }
}
