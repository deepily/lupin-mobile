import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/logging/logger.dart';

/// Watches network connectivity and quality to drive WebSocket reconnection decisions.
///
/// App-wide singleton. It tracks the connection type, tests real reachability, keeps a history of latency
/// and reachability, and maps the resulting quality to a [WebSocketConnectionStrategy].
class NetworkConnectivityService {
  static final NetworkConnectivityService _instance = NetworkConnectivityService._internal();
  /// Returns the shared instance.
  factory NetworkConnectivityService() => _instance;
  NetworkConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();

  /// Replaces the reachability check and the latency probe; null means a real DNS lookup.
  ///
  /// Tests set it so they need no network. It is never set in the app.
  @visibleForTesting
  Future<bool> Function()? internetProbe;
  
  // Stream controllers for network state broadcasts
  final StreamController<NetworkState> _networkStateController = 
      StreamController<NetworkState>.broadcast();
  final StreamController<ConnectionQuality> _connectionQualityController =
      StreamController<ConnectionQuality>.broadcast();
  
  // Current state
  NetworkState _currentState = NetworkState.unknown;
  ConnectionQuality _currentQuality = ConnectionQuality.unknown;
  ConnectivityResult _lastConnectivityResult = ConnectivityResult.none;
  
  // Monitoring and testing
  Timer? _qualityTestTimer;
  Timer? _periodicCheckTimer;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  
  // Network quality metrics
  final List<int> _latencyHistory = [];
  final List<bool> _reachabilityHistory = [];
  DateTime? _lastQualityTest;
  
  // Configuration
  /// Time between connection quality tests.
  static const Duration qualityTestInterval = Duration(minutes: 2);
  /// Time between periodic connectivity checks.
  static const Duration periodicCheckInterval = Duration(seconds: 30);
  /// Number of latency samples kept.
  static const int latencyHistorySize = 10;
  /// Number of reachability results kept.
  static const int reachabilityHistorySize = 20;
  /// Latency at or below this counts as good, in milliseconds.
  static const int goodLatencyThreshold = 100;
  /// Latency at or above this counts as poor, in milliseconds.
  static const int poorLatencyThreshold = 500;
  
  // Public getters
  /// Latest network state.
  NetworkState get currentState => _currentState;
  /// Latest connection quality.
  ConnectionQuality get currentQuality => _currentQuality;
  /// Emits each change of [currentState].
  Stream<NetworkState> get networkStateStream => _networkStateController.stream;
  /// Emits each change of [currentQuality].
  Stream<ConnectionQuality> get connectionQualityStream => _connectionQualityController.stream;
  /// True when [currentState] is connected.
  bool get isConnected => _currentState == NetworkState.connected;
  /// True when the last connectivity result was Wi-Fi.
  bool get isWifi => _lastConnectivityResult == ConnectivityResult.wifi;
  /// True when the last connectivity result was mobile data.
  bool get isMobile => _lastConnectivityResult == ConnectivityResult.mobile;
  
  /// Initialize network monitoring service
  Future<void> initialize() async {
    if ( _connectivitySubscription != null ) return;
    debugPrint('[NetworkService] Initializing network connectivity monitoring');
    
    // Get initial connectivity state
    try {
      final result = await _connectivity.checkConnectivity();
      await _handleConnectivityChange(result);
    } catch (e, st) {
      Logger.error( 'Error getting initial connectivity', tag: 'NetworkService', error: e, stackTrace: st );
      _currentState = NetworkState.unknown;
    }
    
    // Subscribe to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivityChange,
      onError: (Object error, StackTrace st) {
        Logger.error( 'Connectivity subscription error', tag: 'NetworkService', error: error, stackTrace: st );
      },
    );
    
    // Start periodic quality monitoring
    _startQualityMonitoring();
    
    debugPrint('[NetworkService] Network monitoring initialized');
  }
  
  /// True while the quality and periodic-check timers are armed.
  @visibleForTesting
  bool get isMonitoring => _qualityTestTimer != null;

  /// Cancels the quality and periodic-check timers, so a backgrounded app makes no DNS lookups.
  ///
  /// The connectivity subscription stays on; it costs nothing.
  void pauseMonitoring() {
    _qualityTestTimer?.cancel();
    _periodicCheckTimer?.cancel();
    _qualityTestTimer   = null;
    _periodicCheckTimer = null;
  }

  /// Re-arms the timers after [pauseMonitoring]; a no-op before [initialize] or while already armed.
  void resumeMonitoring() {
    if ( _connectivitySubscription == null || isMonitoring ) return;
    _startQualityMonitoring();
  }

  /// Handle connectivity state changes
  Future<void> _handleConnectivityChange(ConnectivityResult result) async {
    debugPrint('[NetworkService] Connectivity changed: $result');
    
    _lastConnectivityResult = result;
    final previousState = _currentState;
    
    // Determine new network state
    switch (result) {
      case ConnectivityResult.wifi:
      case ConnectivityResult.mobile:
      case ConnectivityResult.ethernet:
        // Test actual internet connectivity
        final hasInternet = await _testInternetConnectivity();
        _currentState = hasInternet ? NetworkState.connected : NetworkState.limited;
        break;
      case ConnectivityResult.bluetooth:
        _currentState = NetworkState.limited;
        break;
      case ConnectivityResult.vpn:
        // VPN connections usually indicate connectivity
        final hasInternet = await _testInternetConnectivity();
        _currentState = hasInternet ? NetworkState.connected : NetworkState.limited;
        break;
      case ConnectivityResult.none:
        _currentState = NetworkState.disconnected;
        break;
      case ConnectivityResult.other:
        _currentState = NetworkState.unknown;
        break;
    }
    
    // Broadcast state change if different
    if (_currentState != previousState) {
      debugPrint('[NetworkService] Network state changed: $previousState -> $_currentState');
      _networkStateController.add(_currentState);
      
      // Trigger immediate quality test for connected state
      if (_currentState == NetworkState.connected) {
        await _performQualityTest();
      } else {
        _currentQuality = ConnectionQuality.offline;
        _connectionQualityController.add(_currentQuality);
      }
    }
  }
  
  /// Test actual internet connectivity beyond device network interface
  Future<bool> _testInternetConnectivity() async {
    final probe = internetProbe;
    if ( probe != null ) return probe();
    try {
      // Try multiple reliable endpoints
      final testUrls = [
        'google.com',
        'cloudflare.com',
        '8.8.8.8',
      ];
      
      for (final url in testUrls) {
        try {
          final result = await InternetAddress.lookup(url)
              .timeout(const Duration(seconds: 5));
          if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
            return true;
          }
        } catch (e) {
          continue; // Try next URL
        }
      }
      return false;
    } catch (e) {
      debugPrint('[NetworkService] Internet connectivity test failed: $e');
      return false;
    }
  }
  
  /// Start periodic connection quality monitoring
  void _startQualityMonitoring() {
    _qualityTestTimer?.cancel();
    _periodicCheckTimer?.cancel();
    
    // Immediate quality test
    if (_currentState == NetworkState.connected) {
      _performQualityTest();
    }
    
    // Schedule periodic quality tests
    _qualityTestTimer = Timer.periodic(qualityTestInterval, (timer) {
      if (_currentState == NetworkState.connected) {
        _performQualityTest();
      }
    });
    
    // Schedule periodic connectivity verification
    _periodicCheckTimer = Timer.periodic(periodicCheckInterval, (timer) async {
      if (_currentState == NetworkState.connected) {
        final hasInternet = await _testInternetConnectivity();
        if (!hasInternet && _currentState == NetworkState.connected) {
          await _handleConnectivityChange(_lastConnectivityResult);
        }
      }
    });
  }
  
  /// Perform network quality assessment
  Future<void> _performQualityTest() async {
    if (_currentState != NetworkState.connected) {
      return;
    }
    
    try {
      _lastQualityTest = DateTime.now();
      
      // Test latency to reliable server
      final latency = await _measureLatency();
      _latencyHistory.add(latency);
      if (_latencyHistory.length > latencyHistorySize) {
        _latencyHistory.removeAt(0);
      }
      
      // Test reachability
      final isReachable = await _testInternetConnectivity();
      _reachabilityHistory.add(isReachable);
      if (_reachabilityHistory.length > reachabilityHistorySize) {
        _reachabilityHistory.removeAt(0);
      }
      
      // Calculate quality metrics
      final previousQuality = _currentQuality;
      _currentQuality = _calculateConnectionQuality();
      
      if (_currentQuality != previousQuality) {
        debugPrint('[NetworkService] Connection quality changed: $previousQuality -> $_currentQuality');
        _connectionQualityController.add(_currentQuality);
      }
      
      debugPrint('[NetworkService] Quality test: latency=${latency}ms, quality=$_currentQuality');
      
    } catch (e) {
      debugPrint('[NetworkService] Quality test failed: $e');
      _currentQuality = ConnectionQuality.poor;
      _connectionQualityController.add(_currentQuality);
    }
  }
  
  /// Measure network latency to reliable endpoint
  Future<int> _measureLatency() async {
    if ( internetProbe != null ) return 0;
    final stopwatch = Stopwatch()..start();
    
    try {
      // Use DNS lookup as latency test (lightweight)
      await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      stopwatch.stop();
      return 9999; // Very high latency indicates poor connection
    }
  }
  
  /// Calculate connection quality based on metrics
  ConnectionQuality _calculateConnectionQuality() {
    if (_currentState != NetworkState.connected) {
      return ConnectionQuality.offline;
    }
    
    if (_latencyHistory.isEmpty || _reachabilityHistory.isEmpty) {
      return ConnectionQuality.unknown;
    }
    
    // Calculate average latency
    final avgLatency = _latencyHistory.fold(0, (sum, latency) => sum + latency) / 
                      _latencyHistory.length;
    
    // Calculate reachability success rate
    final reachabilityRate = _reachabilityHistory.where((r) => r).length / 
                            _reachabilityHistory.length;
    
    // Determine quality based on metrics and connection type
    if (reachabilityRate < 0.7) {
      return ConnectionQuality.poor;
    }
    
    if (isWifi) {
      // WiFi quality assessment
      if (avgLatency <= goodLatencyThreshold && reachabilityRate >= 0.95) {
        return ConnectionQuality.excellent;
      } else if (avgLatency <= poorLatencyThreshold && reachabilityRate >= 0.85) {
        return ConnectionQuality.good;
      } else {
        return ConnectionQuality.poor;
      }
    } else if (isMobile) {
      // Mobile network quality assessment (more lenient)
      if (avgLatency <= goodLatencyThreshold * 1.5 && reachabilityRate >= 0.9) {
        return ConnectionQuality.good;
      } else if (avgLatency <= poorLatencyThreshold * 1.5 && reachabilityRate >= 0.8) {
        return ConnectionQuality.fair;
      } else {
        return ConnectionQuality.poor;
      }
    } else {
      // Other connection types
      if (avgLatency <= poorLatencyThreshold && reachabilityRate >= 0.8) {
        return ConnectionQuality.fair;
      } else {
        return ConnectionQuality.poor;
      }
    }
  }
  
  /// Get connection recommendations for WebSocket behavior
  WebSocketConnectionStrategy getConnectionStrategy() {
    switch (_currentQuality) {
      case ConnectionQuality.excellent:
        return const WebSocketConnectionStrategy(
          reconnectDelay: Duration(seconds: 1),
          maxReconnectAttempts: 10,
          pingInterval: Duration(seconds: 30),
          enableKeepalive: true,
          bufferSize: 16384,
          enableCompression: true,
        );
      case ConnectionQuality.good:
        return const WebSocketConnectionStrategy(
          reconnectDelay: Duration(seconds: 2),
          maxReconnectAttempts: 8,
          pingInterval: Duration(seconds: 45),
          enableKeepalive: true,
          bufferSize: 8192,
          enableCompression: true,
        );
      case ConnectionQuality.fair:
        return const WebSocketConnectionStrategy(
          reconnectDelay: Duration(seconds: 5),
          maxReconnectAttempts: 5,
          pingInterval: Duration(seconds: 60),
          enableKeepalive: true,
          bufferSize: 4096,
          enableCompression: false,
        );
      case ConnectionQuality.poor:
        return const WebSocketConnectionStrategy(
          reconnectDelay: Duration(seconds: 10),
          maxReconnectAttempts: 3,
          pingInterval: Duration(seconds: 90),
          enableKeepalive: false,
          bufferSize: 2048,
          enableCompression: false,
        );
      case ConnectionQuality.offline:
      case ConnectionQuality.unknown:
        return const WebSocketConnectionStrategy(
          reconnectDelay: Duration(seconds: 30),
          maxReconnectAttempts: 2,
          pingInterval: Duration(seconds: 120),
          enableKeepalive: false,
          bufferSize: 1024,
          enableCompression: false,
        );
    }
  }
  
  /// Get detailed network information for debugging
  Map<String, dynamic> getNetworkInfo() {
    return {
      'state': _currentState.toString(),
      'quality': _currentQuality.toString(),
      'connectivity_type': _lastConnectivityResult.toString(),
      'is_wifi': isWifi,
      'is_mobile': isMobile,
      'avg_latency': _latencyHistory.isEmpty ? null : 
          _latencyHistory.fold(0, (sum, latency) => sum + latency) / _latencyHistory.length,
      'reachability_rate': _reachabilityHistory.isEmpty ? null :
          _reachabilityHistory.where((r) => r).length / _reachabilityHistory.length,
      'last_quality_test': _lastQualityTest?.toIso8601String(),
      'latency_history': List.from(_latencyHistory),
      'reachability_history': List.from(_reachabilityHistory),
    };
  }
  
  /// Dispose of resources
  void dispose() {
    debugPrint('[NetworkService] Disposing network connectivity service');
    _connectivitySubscription?.cancel();
    _qualityTestTimer?.cancel();
    _periodicCheckTimer?.cancel();
    _networkStateController.close();
    _connectionQualityController.close();
  }
}

/// Whether the device can reach the internet.
enum NetworkState {
  /// Initial state, or the state after an error.
  unknown,

  /// No network connectivity.
  disconnected,

  /// A network interface is up but there is no internet.
  limited,

  /// Full internet connectivity.
  connected,
}

/// How good the connection is, judged from latency and reachability.
enum ConnectionQuality {
  /// Quality not determined yet.
  unknown,

  /// No connection.
  offline,

  /// High latency and unreliable.
  poor,

  /// Moderate latency, mostly reliable.
  fair,

  /// Low latency and reliable.
  good,

  /// Very low latency and highly reliable.
  excellent,
}

/// WebSocket connection settings chosen for one [ConnectionQuality].
class WebSocketConnectionStrategy {
  /// Wait before the first reconnect attempt.
  final Duration reconnectDelay;
  /// Reconnect attempts before giving up.
  final int maxReconnectAttempts;
  /// Interval between keepalive pings.
  final Duration pingInterval;
  /// Whether keepalive pings are sent.
  final bool enableKeepalive;
  /// Buffer size in bytes.
  final int bufferSize;
  /// Whether messages are compressed.
  final bool enableCompression;
  
  /// Creates a strategy; every field is required.
  const WebSocketConnectionStrategy({
    required this.reconnectDelay,
    required this.maxReconnectAttempts,
    required this.pingInterval,
    required this.enableKeepalive,
    required this.bufferSize,
    required this.enableCompression,
  });
  
  @override
  String toString() {
    return 'WebSocketConnectionStrategy('
        'reconnectDelay: $reconnectDelay, '
        'maxReconnectAttempts: $maxReconnectAttempts, '
        'pingInterval: $pingInterval, '
        'enableKeepalive: $enableKeepalive, '
        'bufferSize: $bufferSize, '
        'enableCompression: $enableCompression)';
  }
}