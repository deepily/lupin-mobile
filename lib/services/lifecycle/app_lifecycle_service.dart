import 'dart:async';
import 'package:flutter/widgets.dart';

/// App lifecycle management service for mobile applications.
/// 
/// Handles app state transitions (foreground/background/paused), provides
/// adaptive behavior for WebSocket connections, and manages resource optimization
/// based on app visibility and user interaction patterns.
class AppLifecycleService with WidgetsBindingObserver {
  static final AppLifecycleService _instance = AppLifecycleService._internal();
  factory AppLifecycleService() => _instance;
  AppLifecycleService._internal();

  // Stream controllers for lifecycle events
  final StreamController<AppLifecycleState> _lifecycleController = 
      StreamController<AppLifecycleState>.broadcast();
  final StreamController<AppUsageState> _usageStateController =
      StreamController<AppUsageState>.broadcast();
  
  // Current state tracking
  AppLifecycleState _currentLifecycleState = AppLifecycleState.resumed;
  AppUsageState _currentUsageState = AppUsageState.active;
  DateTime? _lastStateChange;
  DateTime? _lastUserInteraction;
  DateTime? _backgroundTime;
  DateTime? _foregroundTime;
  
  // State duration tracking
  Duration _totalBackgroundTime = Duration.zero;
  Duration _totalForegroundTime = Duration.zero;
  Duration _currentSessionDuration = Duration.zero;
  
  // Configuration
  static const Duration inactivityThreshold = Duration(minutes: 2);
  static const Duration backgroundThreshold = Duration(minutes: 5);
  static const Duration longBackgroundThreshold = Duration(minutes: 30);
  
  // Timers for state management
  Timer? _inactivityTimer;
  Timer? _backgroundTimer;
  Timer? _sessionTimer;
  
  // Public getters
  AppLifecycleState get currentLifecycleState => _currentLifecycleState;
  AppUsageState get currentUsageState => _currentUsageState;
  Stream<AppLifecycleState> get lifecycleStream => _lifecycleController.stream;
  Stream<AppUsageState> get usageStateStream => _usageStateController.stream;
  Duration get backgroundDuration => _backgroundTime != null ? 
      DateTime.now().difference(_backgroundTime!) : Duration.zero;
  Duration get foregroundDuration => _foregroundTime != null ?
      DateTime.now().difference(_foregroundTime!) : Duration.zero;
  Duration get sessionDuration => _currentSessionDuration;
  bool get isInBackground => _currentLifecycleState != AppLifecycleState.resumed;
  bool get isLongBackground => backgroundDuration > longBackgroundThreshold;
  bool get isUserActive => _currentUsageState == AppUsageState.active;
  
  /// Initialize app lifecycle monitoring
  void initialize() {
    print('[LifecycleService] Initializing app lifecycle monitoring');
    
    // Register as observer
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize state
    _currentLifecycleState = AppLifecycleState.resumed;
    _currentUsageState = AppUsageState.active;
    _lastStateChange = DateTime.now();
    _lastUserInteraction = DateTime.now();
    _foregroundTime = DateTime.now();
    
    // Start session timer
    _startSessionTimer();
    
    // Start inactivity monitoring
    _startInactivityMonitoring();
    
    print('[LifecycleService] App lifecycle monitoring initialized');
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('[LifecycleService] Lifecycle state changed: $_currentLifecycleState -> $state');
    
    final previousState = _currentLifecycleState;
    final now = DateTime.now();
    
    // Update durations based on previous state
    if (_lastStateChange != null) {
      final stateDuration = now.difference(_lastStateChange!);
      
      if (previousState == AppLifecycleState.resumed) {
        _totalForegroundTime += stateDuration;
      } else {
        _totalBackgroundTime += stateDuration;
      }
    }
    
    _currentLifecycleState = state;
    _lastStateChange = now;
    
    // Handle specific state transitions
    switch (state) {
      case AppLifecycleState.resumed:
        _handleAppResumed();
        break;
      case AppLifecycleState.paused:
        _handleAppPaused();
        break;
      case AppLifecycleState.inactive:
        _handleAppInactive();
        break;
      case AppLifecycleState.detached:
        _handleAppDetached();
        break;
      case AppLifecycleState.hidden:
        _handleAppHidden();
        break;
    }
    
    // Broadcast lifecycle change
    _lifecycleController.add(state);
    
    // Update usage state based on lifecycle
    _updateUsageState();
  }
  
  /// Handle app resuming to foreground
  void _handleAppResumed() {
    print('[LifecycleService] App resumed to foreground');
    
    final now = DateTime.now();
    
    // Calculate background duration if coming from background
    if (_backgroundTime != null) {
      final backgroundDuration = now.difference(_backgroundTime!);
      print('[LifecycleService] Was in background for ${backgroundDuration.inSeconds}s');
      
      // Trigger background recovery actions based on duration
      if (backgroundDuration > longBackgroundThreshold) {
        _triggerLongBackgroundRecovery();
      } else if (backgroundDuration > backgroundThreshold) {
        _triggerShortBackgroundRecovery();
      }
    }
    
    _foregroundTime = now;
    _backgroundTime = null;
    
    // Resume active monitoring
    _startInactivityMonitoring();
  }
  
  /// Handle app going to background
  void _handleAppPaused() {
    print('[LifecycleService] App paused to background');
    
    _backgroundTime = DateTime.now();
    _foregroundTime = null;
    
    // Stop inactivity monitoring in background
    _inactivityTimer?.cancel();
    
    // Start background duration monitoring
    _startBackgroundMonitoring();
  }
  
  /// Handle app becoming inactive (e.g., during phone calls)
  void _handleAppInactive() {
    print('[LifecycleService] App became inactive');
    // App is still visible but not interactive
    // Keep connections alive but reduce activity
  }
  
  /// Handle app being detached (rare, usually during shutdown)
  void _handleAppDetached() {
    print('[LifecycleService] App detached');
    // Prepare for shutdown
    _prepareForShutdown();
  }
  
  /// Handle app being hidden (iOS specific)
  void _handleAppHidden() {
    print('[LifecycleService] App hidden');
    // Similar to paused but potentially temporary
  }
  
  /// Start monitoring user inactivity
  void _startInactivityMonitoring() {
    _inactivityTimer?.cancel();
    
    _inactivityTimer = Timer(inactivityThreshold, () {
      if (_currentUsageState == AppUsageState.active) {
        print('[LifecycleService] User inactive for ${inactivityThreshold.inMinutes} minutes');
        _setUsageState(AppUsageState.inactive);
      }
    });
  }
  
  /// Start monitoring background duration
  void _startBackgroundMonitoring() {
    _backgroundTimer?.cancel();
    
    _backgroundTimer = Timer(backgroundThreshold, () {
      print('[LifecycleService] App in background for ${backgroundThreshold.inMinutes} minutes');
      _setUsageState(AppUsageState.backgroundLong);
    });
  }
  
  /// Start session duration timer
  void _startSessionTimer() {
    _sessionTimer?.cancel();
    
    _sessionTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _currentSessionDuration = Duration(minutes: timer.tick);
    });
  }
  
  /// Record user interaction to reset inactivity timer
  void recordUserInteraction() {
    _lastUserInteraction = DateTime.now();
    
    if (_currentUsageState != AppUsageState.active && 
        _currentLifecycleState == AppLifecycleState.resumed) {
      _setUsageState(AppUsageState.active);
    }
    
    // Restart inactivity monitoring
    if (_currentLifecycleState == AppLifecycleState.resumed) {
      _startInactivityMonitoring();
    }
  }
  
  /// Update usage state based on current conditions
  void _updateUsageState() {
    switch (_currentLifecycleState) {
      case AppLifecycleState.resumed:
        // Check if user was recently active
        final timeSinceInteraction = _lastUserInteraction != null ?
            DateTime.now().difference(_lastUserInteraction!) : Duration.zero;
        
        if (timeSinceInteraction < inactivityThreshold) {
          _setUsageState(AppUsageState.active);
        } else {
          _setUsageState(AppUsageState.inactive);
        }
        break;
        
      case AppLifecycleState.paused:
        _setUsageState(AppUsageState.background);
        break;
        
      case AppLifecycleState.inactive:
        _setUsageState(AppUsageState.inactive);
        break;
        
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _setUsageState(AppUsageState.background);
        break;
    }
  }
  
  /// Set usage state and broadcast if changed
  void _setUsageState(AppUsageState newState) {
    if (_currentUsageState != newState) {
      print('[LifecycleService] Usage state changed: $_currentUsageState -> $newState');
      _currentUsageState = newState;
      _usageStateController.add(newState);
    }
  }
  
  /// Handle recovery from long background duration
  void _triggerLongBackgroundRecovery() {
    print('[LifecycleService] Triggering long background recovery');
    // Full reconnection and state refresh required
    _setUsageState(AppUsageState.recovering);
  }
  
  /// Handle recovery from short background duration
  void _triggerShortBackgroundRecovery() {
    print('[LifecycleService] Triggering short background recovery');
    // Quick state validation and reconnection
    _setUsageState(AppUsageState.active);
  }
  
  /// Prepare app for shutdown
  void _prepareForShutdown() {
    print('[LifecycleService] Preparing for app shutdown');
    _setUsageState(AppUsageState.shutdown);
  }
  
  /// Get connection strategy based on current app state
  AppStateConnectionStrategy getConnectionStrategy() {
    switch (_currentUsageState) {
      case AppUsageState.active:
        return AppStateConnectionStrategy(
          maintainConnection: true,
          enableHeartbeat: true,
          heartbeatInterval: const Duration(seconds: 30),
          reconnectImmediately: true,
          maxConcurrentConnections: 2,
          enableAudioStreaming: true,
          bufferAudioInBackground: false,
        );
        
      case AppUsageState.inactive:
        return AppStateConnectionStrategy(
          maintainConnection: true,
          enableHeartbeat: true,
          heartbeatInterval: const Duration(minutes: 1),
          reconnectImmediately: true,
          maxConcurrentConnections: 1,
          enableAudioStreaming: false,
          bufferAudioInBackground: false,
        );
        
      case AppUsageState.background:
        return AppStateConnectionStrategy(
          maintainConnection: true,
          enableHeartbeat: true,
          heartbeatInterval: const Duration(minutes: 2),
          reconnectImmediately: false,
          maxConcurrentConnections: 1,
          enableAudioStreaming: false,
          bufferAudioInBackground: true,
        );
        
      case AppUsageState.backgroundLong:
        return AppStateConnectionStrategy(
          maintainConnection: false,
          enableHeartbeat: false,
          heartbeatInterval: const Duration(minutes: 5),
          reconnectImmediately: false,
          maxConcurrentConnections: 0,
          enableAudioStreaming: false,
          bufferAudioInBackground: true,
        );
        
      case AppUsageState.recovering:
        return AppStateConnectionStrategy(
          maintainConnection: true,
          enableHeartbeat: true,
          heartbeatInterval: const Duration(seconds: 15),
          reconnectImmediately: true,
          maxConcurrentConnections: 2,
          enableAudioStreaming: true,
          bufferAudioInBackground: false,
        );
        
      case AppUsageState.shutdown:
        return AppStateConnectionStrategy(
          maintainConnection: false,
          enableHeartbeat: false,
          heartbeatInterval: const Duration(minutes: 10),
          reconnectImmediately: false,
          maxConcurrentConnections: 0,
          enableAudioStreaming: false,
          bufferAudioInBackground: false,
        );
    }
  }
  
  /// Get app usage statistics
  Map<String, dynamic> getUsageStatistics() {
    final now = DateTime.now();
    
    return {
      'current_lifecycle_state': _currentLifecycleState.toString(),
      'current_usage_state': _currentUsageState.toString(),
      'session_duration_minutes': _currentSessionDuration.inMinutes,
      'total_foreground_minutes': _totalForegroundTime.inMinutes,
      'total_background_minutes': _totalBackgroundTime.inMinutes,
      'current_background_duration_seconds': backgroundDuration.inSeconds,
      'current_foreground_duration_seconds': foregroundDuration.inSeconds,
      'last_user_interaction': _lastUserInteraction?.toIso8601String(),
      'last_state_change': _lastStateChange?.toIso8601String(),
      'is_long_background': isLongBackground,
      'is_user_active': isUserActive,
    };
  }
  
  /// Dispose of resources
  void dispose() {
    print('[LifecycleService] Disposing app lifecycle service');
    
    WidgetsBinding.instance.removeObserver(this);
    
    _inactivityTimer?.cancel();
    _backgroundTimer?.cancel();
    _sessionTimer?.cancel();
    
    _lifecycleController.close();
    _usageStateController.close();
  }
}

/// App usage states for adaptive behavior
enum AppUsageState {
  active,        // User actively using the app
  inactive,      // App in foreground but user not interacting
  background,    // App in background (short duration)
  backgroundLong, // App in background for extended period
  recovering,    // Recovering from background state
  shutdown,      // App shutting down
}

/// Connection strategy based on app state
class AppStateConnectionStrategy {
  final bool maintainConnection;
  final bool enableHeartbeat;
  final Duration heartbeatInterval;
  final bool reconnectImmediately;
  final int maxConcurrentConnections;
  final bool enableAudioStreaming;
  final bool bufferAudioInBackground;
  
  const AppStateConnectionStrategy({
    required this.maintainConnection,
    required this.enableHeartbeat,
    required this.heartbeatInterval,
    required this.reconnectImmediately,
    required this.maxConcurrentConnections,
    required this.enableAudioStreaming,
    required this.bufferAudioInBackground,
  });
  
  @override
  String toString() {
    return 'AppStateConnectionStrategy('
        'maintainConnection: $maintainConnection, '
        'enableHeartbeat: $enableHeartbeat, '
        'heartbeatInterval: $heartbeatInterval, '
        'reconnectImmediately: $reconnectImmediately, '
        'maxConcurrentConnections: $maxConcurrentConnections, '
        'enableAudioStreaming: $enableAudioStreaming, '
        'bufferAudioInBackground: $bufferAudioInBackground)';
  }
}