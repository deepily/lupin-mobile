import 'dart:async';
import 'dart:math';
import '../network/network_connectivity_service.dart';
import '../lifecycle/app_lifecycle_service.dart';

/// Chooses WebSocket connection settings from network quality and app lifecycle state.
///
/// App-wide singleton. It listens to [NetworkConnectivityService] and [AppLifecycleService],
/// recomputes a strategy and an optimization mode on each change, and publishes both on streams.
class AdaptiveConnectionManager {
  static final AdaptiveConnectionManager _instance = AdaptiveConnectionManager._internal();
  /// Returns the shared instance.
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
  /// Minimum time between strategy recomputations.
  static const Duration strategyUpdateCooldown = Duration(seconds: 30);
  /// Number of adaptation events kept; the oldest is dropped past this.
  static const int adaptationHistorySize = 100;
  
  // Subscriptions
  StreamSubscription<NetworkState>? _networkSubscription;
  StreamSubscription<ConnectionQuality>? _qualitySubscription;
  StreamSubscription<AppUsageState>? _lifecycleSubscription;
  
  // Public getters
  /// Strategy currently in force.
  AdaptiveStrategy get currentStrategy => _currentStrategy;
  /// Optimization mode currently in force.
  ConnectionOptimization get currentOptimization => _currentOptimization;
  /// Emits each time [currentStrategy] changes.
  Stream<AdaptiveStrategy> get strategyStream => _strategyController.stream;
  /// Emits each time [currentOptimization] changes.
  Stream<ConnectionOptimization> get optimizationStream => _optimizationController.stream;
  
  /// Starts the dependent services, subscribes to their streams and sets the first strategy.
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
  
  /// Recomputes strategy and optimization, skipping changes inside [strategyUpdateCooldown].
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
      if (!_strategyController.isClosed) _strategyController.add(_currentStrategy);
      _recordAdaptationEvent('strategy_change', _currentStrategy.toString());
    }

    if (_currentOptimization != previousOptimization) {
      print('[AdaptiveManager] Optimization changed: $previousOptimization -> $_currentOptimization');
      if (!_optimizationController.isClosed) _optimizationController.add(_currentOptimization);
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
  
  /// Combines the network, lifecycle and adaptive settings into one connection config.
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
  
  /// Snapshot of current settings, recent event counts and the full event history.
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
  
  /// Recomputes the strategy immediately, ignoring the cooldown. Intended for tests.
  void forceStrategyUpdate() {
    _lastStrategyUpdate = null;
    _updateAdaptiveStrategy();
  }
  
  /// Cancels the subscriptions, closes both streams and disposes both dependent services.
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

/// How hard the app tries to keep the WebSocket connected.
enum AdaptiveStrategy {
  /// Fast reconnection at the cost of higher resource usage.
  aggressive,

  /// Optimized for speed and responsiveness.
  performance,

  /// Balanced approach.
  standard,

  /// Slower reconnection and reduced resource usage.
  conservative,

  /// Behavior tuned for the app being in the background.
  background,

  /// Minimal resource usage.
  powerSaver,

  /// No connection attempts.
  offline,
}

/// What the connection settings trade off: speed, data use or battery.
enum ConnectionOptimization {
  /// Maximum speed and responsiveness.
  performance,

  /// Balance between performance and efficiency.
  balanced,

  /// Minimize data usage.
  dataSaver,

  /// Minimize battery consumption.
  batterySaver,
}

/// One computed set of WebSocket connection settings, with the strategy that produced it.
class AdaptiveConnectionConfig {
  /// Wait before the first reconnect attempt.
  final Duration reconnectDelay;

  /// Reconnect attempts before giving up; zero means never reconnect.
  final int maxReconnectAttempts;

  /// Interval between keepalive pings.
  final Duration pingInterval;

  /// Whether keepalive pings are sent.
  final bool enableKeepalive;

  /// Whether messages are compressed.
  final bool enableCompression;

  /// Buffer size in bytes.
  final int bufferSize;

  /// Whether the connection is kept open while the app is not in the foreground.
  final bool maintainConnection;

  /// Whether audio is streamed over the connection.
  final bool enableAudioStreaming;

  /// Whether audio is buffered while the app is in the background.
  final bool bufferAudioInBackground;

  /// Upper bound on simultaneous connections.
  final int maxConcurrentConnections;

  /// Strategy in force when this config was computed.
  final AdaptiveStrategy strategy;

  /// Optimization mode in force when this config was computed.
  final ConnectionOptimization optimization;

  /// When this config was computed.
  final DateTime adaptationTimestamp;

  /// Creates a config; every field is required.
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

/// One recorded input change, with the network, app and strategy state at that moment.
class AdaptationEvent {
  /// When the change was recorded.
  final DateTime timestamp;

  /// Kind of change, for example `network_state_change` or `strategy_change`.
  final String type;

  /// The new value, as text.
  final String value;

  /// Network state at the time of the event.
  final NetworkState networkState;

  /// Connection quality at the time of the event.
  final ConnectionQuality connectionQuality;

  /// App usage state at the time of the event.
  final AppUsageState appState;

  /// Strategy in force at the time of the event.
  final AdaptiveStrategy strategy;

  /// Optimization mode in force at the time of the event.
  final ConnectionOptimization optimization;

  /// Creates an event; every field is required.
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
  
  /// Serializes the event with snake_case keys and an ISO-8601 timestamp.
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