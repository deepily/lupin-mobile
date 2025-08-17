import 'dart:async';
import 'dart:math';
import '../network/network_connectivity_service.dart';
import '../lifecycle/app_lifecycle_service.dart';

/// Adaptive connection management that intelligently adjusts WebSocket behavior
/// based on network conditions, app lifecycle state, and usage patterns.
/// 
/// Provides optimized connection strategies, resource management, and automatic
/// recovery for mobile environments with varying connectivity and power constraints.
class AdaptiveConnectionManager {
  static final AdaptiveConnectionManager _instance = AdaptiveConnectionManager._internal();
  factory AdaptiveConnectionManager() => _instance;
  AdaptiveConnectionManager._internal();

  // Service dependencies
  final NetworkConnectivityService _networkService = NetworkConnectivityService();
  final AppLifecycleService _lifecycleService = AppLifecycleService();
  
  // Stream controllers for adaptive behavior events
  final StreamController<AdaptiveStrategy> _strategyController =
      StreamController<AdaptiveStrategy>.broadcast();
  final StreamController<ConnectionOptimization> _optimizationController =
      StreamController<ConnectionOptimization>.broadcast();
  
  // Current state
  AdaptiveStrategy _currentStrategy = AdaptiveStrategy.standard;
  ConnectionOptimization _currentOptimization = ConnectionOptimization.balanced;
  DateTime? _lastStrategyUpdate;
  
  // Adaptation history for learning
  final List<AdaptationEvent> _adaptationHistory = [];
  final Map<String, int> _strategyEffectiveness = {};
  
  // Configuration
  static const Duration strategyUpdateCooldown = Duration(seconds: 30);
  static const int adaptationHistorySize = 100;
  
  // Subscriptions
  StreamSubscription<NetworkState>? _networkSubscription;
  StreamSubscription<ConnectionQuality>? _qualitySubscription;
  StreamSubscription<AppUsageState>? _lifecycleSubscription;
  
  // Public getters
  AdaptiveStrategy get currentStrategy => _currentStrategy;
  ConnectionOptimization get currentOptimization => _currentOptimization;
  Stream<AdaptiveStrategy> get strategyStream => _strategyController.stream;
  Stream<ConnectionOptimization> get optimizationStream => _optimizationController.stream;
  
  /// Initialize adaptive connection management
  Future<void> initialize() async {
    print('[AdaptiveManager] Initializing adaptive connection management');
    
    // Initialize dependent services
    await _networkService.initialize();
    _lifecycleService.initialize();
    
    // Subscribe to state changes
    _networkSubscription = _networkService.networkStateStream.listen(_handleNetworkStateChange);
    _qualitySubscription = _networkService.connectionQualityStream.listen(_handleQualityChange);
    _lifecycleSubscription = _lifecycleService.usageStateStream.listen(_handleLifecycleChange);
    
    // Set initial strategy
    await _updateAdaptiveStrategy();
    
    print('[AdaptiveManager] Adaptive connection management initialized');
  }
  
  /// Handle network state changes
  void _handleNetworkStateChange(NetworkState state) {
    print('[AdaptiveManager] Network state changed: $state');
    _recordAdaptationEvent('network_state_change', state.toString());
    _updateAdaptiveStrategy();
  }
  
  /// Handle connection quality changes
  void _handleQualityChange(ConnectionQuality quality) {
    print('[AdaptiveManager] Connection quality changed: $quality');
    _recordAdaptationEvent('quality_change', quality.toString());
    _updateAdaptiveStrategy();
  }
  
  /// Handle app lifecycle changes
  void _handleLifecycleChange(AppUsageState state) {
    print('[AdaptiveManager] App usage state changed: $state');
    _recordAdaptationEvent('lifecycle_change', state.toString());
    _updateAdaptiveStrategy();
  }
  
  /// Update adaptive strategy based on current conditions
  Future<void> _updateAdaptiveStrategy() async {
    // Prevent rapid strategy changes
    if (_lastStrategyUpdate != null) {
      final timeSinceUpdate = DateTime.now().difference(_lastStrategyUpdate!);
      if (timeSinceUpdate < strategyUpdateCooldown) {
        return;
      }
    }
    
    final previousStrategy = _currentStrategy;
    final previousOptimization = _currentOptimization;
    
    // Determine optimal strategy based on current conditions
    _currentStrategy = _calculateOptimalStrategy();
    _currentOptimization = _calculateOptimalOptimization();
    
    _lastStrategyUpdate = DateTime.now();
    
    // Broadcast changes if different
    if (_currentStrategy != previousStrategy) {
      print('[AdaptiveManager] Strategy changed: $previousStrategy -> $_currentStrategy');
      _strategyController.add(_currentStrategy);
      _recordAdaptationEvent('strategy_change', _currentStrategy.toString());
    }
    
    if (_currentOptimization != previousOptimization) {
      print('[AdaptiveManager] Optimization changed: $previousOptimization -> $_currentOptimization');
      _optimizationController.add(_currentOptimization);
      _recordAdaptationEvent('optimization_change', _currentOptimization.toString());
    }
  }
  
  /// Calculate optimal connection strategy
  AdaptiveStrategy _calculateOptimalStrategy() {
    final networkState = _networkService.currentState;
    final connectionQuality = _networkService.currentQuality;
    final appState = _lifecycleService.currentUsageState;
    
    // No connection available
    if (networkState == NetworkState.disconnected || 
        connectionQuality == ConnectionQuality.offline) {
      return AdaptiveStrategy.offline;
    }
    
    // Background states
    if (appState == AppUsageState.backgroundLong || 
        appState == AppUsageState.shutdown) {
      return AdaptiveStrategy.powerSaver;
    }
    
    if (appState == AppUsageState.background) {
      return AdaptiveStrategy.background;
    }
    
    // Poor connection conditions
    if (connectionQuality == ConnectionQuality.poor) {
      return AdaptiveStrategy.conservative;
    }
    
    // Recovering from background
    if (appState == AppUsageState.recovering) {
      return AdaptiveStrategy.aggressive;
    }
    
    // High quality connections
    if (connectionQuality == ConnectionQuality.excellent && 
        appState == AppUsageState.active) {
      return AdaptiveStrategy.performance;
    }
    
    // Default balanced approach
    return AdaptiveStrategy.standard;
  }
  
  /// Calculate optimal connection optimization
  ConnectionOptimization _calculateOptimalOptimization() {
    final networkQuality = _networkService.currentQuality;
    final isWifi = _networkService.isWifi;
    final appState = _lifecycleService.currentUsageState;
    
    // Battery saving for background or poor conditions
    if (appState == AppUsageState.background || 
        appState == AppUsageState.backgroundLong ||
        networkQuality == ConnectionQuality.poor) {
      return ConnectionOptimization.batterySaver;
    }
    
    // Performance optimization for excellent conditions
    if (networkQuality == ConnectionQuality.excellent && 
        isWifi && 
        appState == AppUsageState.active) {
      return ConnectionOptimization.performance;
    }
    
    // Data saving for mobile networks with fair/poor quality
    if (!isWifi && networkQuality != ConnectionQuality.excellent) {
      return ConnectionOptimization.dataSaver;
    }
    
    // Default balanced optimization
    return ConnectionOptimization.balanced;
  }
  
  /// Get comprehensive connection configuration
  AdaptiveConnectionConfig getConnectionConfig() {
    final networkStrategy = _networkService.getConnectionStrategy();
    final appStrategy = _lifecycleService.getConnectionStrategy();
    
    return AdaptiveConnectionConfig(
      // Basic connection parameters
      reconnectDelay: _combineReconnectDelay(networkStrategy, appStrategy),
      maxReconnectAttempts: _combineMaxAttempts(networkStrategy, appStrategy),
      pingInterval: _combinePingInterval(networkStrategy, appStrategy),
      
      // Connection optimization
      enableKeepalive: _shouldEnableKeepalive(networkStrategy, appStrategy),
      enableCompression: _shouldEnableCompression(),
      bufferSize: _calculateOptimalBufferSize(networkStrategy),
      
      // App-specific behavior
      maintainConnection: appStrategy.maintainConnection,
      enableAudioStreaming: appStrategy.enableAudioStreaming,
      bufferAudioInBackground: appStrategy.bufferAudioInBackground,
      maxConcurrentConnections: appStrategy.maxConcurrentConnections,
      
      // Adaptive parameters
      strategy: _currentStrategy,
      optimization: _currentOptimization,
      adaptationTimestamp: DateTime.now(),
    );
  }
  
  /// Combine reconnect delays from network and app strategies
  Duration _combineReconnectDelay(
      WebSocketConnectionStrategy network, 
      AppStateConnectionStrategy app) {
    
    switch (_currentStrategy) {
      case AdaptiveStrategy.aggressive:
        return Duration(milliseconds: min(network.reconnectDelay.inMilliseconds, 1000));
      case AdaptiveStrategy.performance:
        return network.reconnectDelay;
      case AdaptiveStrategy.conservative:
        return Duration(milliseconds: max(network.reconnectDelay.inMilliseconds, 5000));
      case AdaptiveStrategy.background:
        return Duration(seconds: 30);
      case AdaptiveStrategy.powerSaver:
        return Duration(minutes: 2);
      case AdaptiveStrategy.offline:
        return Duration(minutes: 5);
      case AdaptiveStrategy.standard:
        return Duration(milliseconds: 
            (network.reconnectDelay.inMilliseconds * 1.5).round());
    }
  }
  
  /// Combine max reconnect attempts
  int _combineMaxAttempts(
      WebSocketConnectionStrategy network, 
      AppStateConnectionStrategy app) {
    
    switch (_currentStrategy) {
      case AdaptiveStrategy.aggressive:
        return max(network.maxReconnectAttempts, 15);
      case AdaptiveStrategy.performance:
        return network.maxReconnectAttempts;
      case AdaptiveStrategy.conservative:
        return min(network.maxReconnectAttempts, 3);
      case AdaptiveStrategy.background:
        return 2;
      case AdaptiveStrategy.powerSaver:
        return 1;
      case AdaptiveStrategy.offline:
        return 0;
      case AdaptiveStrategy.standard:
        return network.maxReconnectAttempts;
    }
  }
  
  /// Combine ping intervals
  Duration _combinePingInterval(
      WebSocketConnectionStrategy network, 
      AppStateConnectionStrategy app) {
    
    if (!app.enableHeartbeat) {
      return const Duration(minutes: 10); // Disabled
    }
    
    switch (_currentStrategy) {
      case AdaptiveStrategy.aggressive:
        return const Duration(seconds: 15);
      case AdaptiveStrategy.performance:
        return network.pingInterval;
      case AdaptiveStrategy.conservative:
        return Duration(seconds: max(network.pingInterval.inSeconds, 60));
      case AdaptiveStrategy.background:
        return app.heartbeatInterval;
      case AdaptiveStrategy.powerSaver:
        return const Duration(minutes: 5);
      case AdaptiveStrategy.offline:
        return const Duration(minutes: 10);
      case AdaptiveStrategy.standard:
        return Duration(seconds: 
            ((network.pingInterval.inSeconds + app.heartbeatInterval.inSeconds) / 2).round());
    }
  }
  
  /// Determine if keepalive should be enabled
  bool _shouldEnableKeepalive(
      WebSocketConnectionStrategy network, 
      AppStateConnectionStrategy app) {
    
    return network.enableKeepalive && 
           app.maintainConnection && 
           _currentStrategy != AdaptiveStrategy.powerSaver &&
           _currentStrategy != AdaptiveStrategy.offline;
  }
  
  /// Determine if compression should be enabled
  bool _shouldEnableCompression() {
    switch (_currentOptimization) {
      case ConnectionOptimization.performance:
        return true;
      case ConnectionOptimization.dataSaver:
        return true;
      case ConnectionOptimization.batterySaver:
        return false;
      case ConnectionOptimization.balanced:
        return _networkService.currentQuality != ConnectionQuality.poor;
    }
  }
  
  /// Calculate optimal buffer size
  int _calculateOptimalBufferSize(WebSocketConnectionStrategy network) {
    switch (_currentOptimization) {
      case ConnectionOptimization.performance:
        return max(network.bufferSize, 32768);
      case ConnectionOptimization.dataSaver:
        return min(network.bufferSize, 4096);
      case ConnectionOptimization.batterySaver:
        return min(network.bufferSize, 2048);
      case ConnectionOptimization.balanced:
        return network.bufferSize;
    }
  }
  
  /// Record adaptation event for learning
  void _recordAdaptationEvent(String type, String value) {
    final event = AdaptationEvent(
      timestamp: DateTime.now(),
      type: type,
      value: value,
      networkState: _networkService.currentState,
      connectionQuality: _networkService.currentQuality,
      appState: _lifecycleService.currentUsageState,
      strategy: _currentStrategy,
      optimization: _currentOptimization,
    );
    
    _adaptationHistory.add(event);
    if (_adaptationHistory.length > adaptationHistorySize) {
      _adaptationHistory.removeAt(0);
    }
  }
  
  /// Get adaptation analytics
  Map<String, dynamic> getAdaptationAnalytics() {
    final now = DateTime.now();
    final recentEvents = _adaptationHistory.where(
        (event) => now.difference(event.timestamp) < const Duration(hours: 1)
    ).toList();
    
    return {
      'current_strategy': _currentStrategy.toString(),
      'current_optimization': _currentOptimization.toString(),
      'last_strategy_update': _lastStrategyUpdate?.toIso8601String(),
      'adaptation_events_count': _adaptationHistory.length,
      'recent_events_count': recentEvents.length,
      'strategy_effectiveness': Map.from(_strategyEffectiveness),
      'network_info': _networkService.getNetworkInfo(),
      'lifecycle_info': _lifecycleService.getUsageStatistics(),
      'adaptation_history': _adaptationHistory.map((e) => e.toMap()).toList(),
    };
  }
  
  /// Force strategy recalculation (for testing)
  void forceStrategyUpdate() {
    _lastStrategyUpdate = null;
    _updateAdaptiveStrategy();
  }
  
  /// Dispose of resources
  void dispose() {
    print('[AdaptiveManager] Disposing adaptive connection manager');
    
    _networkSubscription?.cancel();
    _qualitySubscription?.cancel();
    _lifecycleSubscription?.cancel();
    
    _strategyController.close();
    _optimizationController.close();
    
    _networkService.dispose();
    _lifecycleService.dispose();
  }
}

/// Adaptive connection strategies
enum AdaptiveStrategy {
  aggressive,   // Fast reconnection, high resource usage
  performance,  // Optimized for speed and responsiveness
  standard,     // Balanced approach
  conservative, // Slower reconnection, reduced resource usage
  background,   // Background-optimized behavior
  powerSaver,   // Minimal resource usage
  offline,      // No connection attempts
}

/// Connection optimization modes
enum ConnectionOptimization {
  performance,   // Maximum speed and responsiveness
  balanced,      // Balance between performance and efficiency
  dataSaver,     // Minimize data usage
  batterySaver,  // Minimize battery consumption
}

/// Comprehensive adaptive connection configuration
class AdaptiveConnectionConfig {
  final Duration reconnectDelay;
  final int maxReconnectAttempts;
  final Duration pingInterval;
  final bool enableKeepalive;
  final bool enableCompression;
  final int bufferSize;
  final bool maintainConnection;
  final bool enableAudioStreaming;
  final bool bufferAudioInBackground;
  final int maxConcurrentConnections;
  final AdaptiveStrategy strategy;
  final ConnectionOptimization optimization;
  final DateTime adaptationTimestamp;
  
  const AdaptiveConnectionConfig({
    required this.reconnectDelay,
    required this.maxReconnectAttempts,
    required this.pingInterval,
    required this.enableKeepalive,
    required this.enableCompression,
    required this.bufferSize,
    required this.maintainConnection,
    required this.enableAudioStreaming,
    required this.bufferAudioInBackground,
    required this.maxConcurrentConnections,
    required this.strategy,
    required this.optimization,
    required this.adaptationTimestamp,
  });
  
  @override
  String toString() {
    return 'AdaptiveConnectionConfig('
        'strategy: $strategy, '
        'optimization: $optimization, '
        'reconnectDelay: $reconnectDelay, '
        'maxReconnectAttempts: $maxReconnectAttempts, '
        'pingInterval: $pingInterval, '
        'maintainConnection: $maintainConnection)';
  }
}

/// Adaptation event for learning and analytics
class AdaptationEvent {
  final DateTime timestamp;
  final String type;
  final String value;
  final NetworkState networkState;
  final ConnectionQuality connectionQuality;
  final AppUsageState appState;
  final AdaptiveStrategy strategy;
  final ConnectionOptimization optimization;
  
  const AdaptationEvent({
    required this.timestamp,
    required this.type,
    required this.value,
    required this.networkState,
    required this.connectionQuality,
    required this.appState,
    required this.strategy,
    required this.optimization,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'type': type,
      'value': value,
      'network_state': networkState.toString(),
      'connection_quality': connectionQuality.toString(),
      'app_state': appState.toString(),
      'strategy': strategy.toString(),
      'optimization': optimization.toString(),
    };
  }
}