import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Network connectivity monitoring service for mobile apps.
/// 
/// Provides real-time network state monitoring, adaptive behavior based on
/// connection type, and intelligent reconnection strategies for WebSocket services.
/// Integrates with app lifecycle to optimize connectivity management.
class NetworkConnectivityService {
  static final NetworkConnectivityService _instance = NetworkConnectivityService._internal();
  factory NetworkConnectivityService() => _instance;
  NetworkConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  
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
  static const Duration qualityTestInterval = Duration(minutes: 2);
  static const Duration periodicCheckInterval = Duration(seconds: 30);
  static const int latencyHistorySize = 10;
  static const int reachabilityHistorySize = 20;
  static const int goodLatencyThreshold = 100; // ms
  static const int poorLatencyThreshold = 500; // ms
  
  // Public getters
  NetworkState get currentState => _currentState;
  ConnectionQuality get currentQuality => _currentQuality;
  Stream<NetworkState> get networkStateStream => _networkStateController.stream;
  Stream<ConnectionQuality> get connectionQualityStream => _connectionQualityController.stream;
  bool get isConnected => _currentState == NetworkState.connected;
  bool get isWifi => _lastConnectivityResult == ConnectivityResult.wifi;
  bool get isMobile => _lastConnectivityResult == ConnectivityResult.mobile;
  
  /// Initialize network monitoring service
  Future<void> initialize() async {
    print('[NetworkService] Initializing network connectivity monitoring');
    
    // Get initial connectivity state
    try {
      final result = await _connectivity.checkConnectivity();
      await _handleConnectivityChange(result);
    } catch (e) {
      print('[NetworkService] Error getting initial connectivity: $e');
      _currentState = NetworkState.unknown;
    }
    
    // Subscribe to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivityChange,
      onError: (error) {
        print('[NetworkService] Connectivity subscription error: $error');
      },
    );
    
    // Start periodic quality monitoring
    _startQualityMonitoring();
    
    print('[NetworkService] Network monitoring initialized');
  }
  
  /// Handle connectivity state changes
  Future<void> _handleConnectivityChange(ConnectivityResult result) async {
    print('[NetworkService] Connectivity changed: $result');
    
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
      print('[NetworkService] Network state changed: $previousState -> $_currentState');
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
      print('[NetworkService] Internet connectivity test failed: $e');
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
        print('[NetworkService] Connection quality changed: $previousQuality -> $_currentQuality');
        _connectionQualityController.add(_currentQuality);
      }
      
      print('[NetworkService] Quality test: latency=${latency}ms, quality=$_currentQuality');
      
    } catch (e) {
      print('[NetworkService] Quality test failed: $e');
      _currentQuality = ConnectionQuality.poor;
      _connectionQualityController.add(_currentQuality);
    }
  }
  
  /// Measure network latency to reliable endpoint
  Future<int> _measureLatency() async {
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
        return WebSocketConnectionStrategy(
          reconnectDelay: const Duration(seconds: 1),
          maxReconnectAttempts: 10,
          pingInterval: const Duration(seconds: 30),
          enableKeepalive: true,
          bufferSize: 16384,
          enableCompression: true,
        );
      case ConnectionQuality.good:
        return WebSocketConnectionStrategy(
          reconnectDelay: const Duration(seconds: 2),
          maxReconnectAttempts: 8,
          pingInterval: const Duration(seconds: 45),
          enableKeepalive: true,
          bufferSize: 8192,
          enableCompression: true,
        );
      case ConnectionQuality.fair:
        return WebSocketConnectionStrategy(
          reconnectDelay: const Duration(seconds: 5),
          maxReconnectAttempts: 5,
          pingInterval: const Duration(seconds: 60),
          enableKeepalive: true,
          bufferSize: 4096,
          enableCompression: false,
        );
      case ConnectionQuality.poor:
        return WebSocketConnectionStrategy(
          reconnectDelay: const Duration(seconds: 10),
          maxReconnectAttempts: 3,
          pingInterval: const Duration(seconds: 90),
          enableKeepalive: false,
          bufferSize: 2048,
          enableCompression: false,
        );
      case ConnectionQuality.offline:
      case ConnectionQuality.unknown:
        return WebSocketConnectionStrategy(
          reconnectDelay: const Duration(seconds: 30),
          maxReconnectAttempts: 2,
          pingInterval: const Duration(seconds: 120),
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
    print('[NetworkService] Disposing network connectivity service');
    _connectivitySubscription?.cancel();
    _qualityTestTimer?.cancel();
    _periodicCheckTimer?.cancel();
    _networkStateController.close();
    _connectionQualityController.close();
  }
}

/// Network connectivity states
enum NetworkState {
  unknown,     // Initial or error state
  disconnected, // No network connectivity
  limited,     // Network interface available but no internet
  connected,   // Full internet connectivity
}

/// Connection quality levels
enum ConnectionQuality {
  unknown,   // Quality not yet determined
  offline,   // No connection
  poor,      // High latency, unreliable
  fair,      // Moderate latency, mostly reliable
  good,      // Low latency, reliable
  excellent, // Very low latency, highly reliable
}

/// WebSocket connection strategy based on network quality
class WebSocketConnectionStrategy {
  final Duration reconnectDelay;
  final int maxReconnectAttempts;
  final Duration pingInterval;
  final bool enableKeepalive;
  final int bufferSize;
  final bool enableCompression;
  
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