import 'dart:async';
import 'dart:math';
import 'websocket_subscription_manager.dart';
import 'websocket_connection_manager.dart';
import 'websocket_message_router.dart';
import '../../core/constants/app_constants.dart';

/// Adjusts event subscriptions from app state, observed usage and server recommendations.
///
/// It aims to cut bandwidth while making sure critical events are never missed.
class WebSocketDynamicSubscriptionController {
  final WebSocketConnectionManager _connectionManager;
  final WebSocketSubscriptionManager _subscriptionManager;
  
  // Dynamic subscription state
  final Map<String, SubscriptionContext> _contextSubscriptions = {};
  final Map<String, int> _eventUsageStats = {};
  final Map<String, DateTime> _lastEventReceived = {};
  
  // Adaptive learning
  final Map<String, double> _eventPriorities = {};
  final Map<String, List<DateTime>> _eventHistory = {};
  
  // Timers and periodic tasks
  Timer? _adaptiveAnalysisTimer;
  Timer? _subscriptionOptimizationTimer;
  Timer? _usageReportTimer;
  
  // Configuration
  final DynamicSubscriptionConfig _config;
  
  // Stream controllers
  final StreamController<SubscriptionRecommendation> _recommendationController = 
      StreamController<SubscriptionRecommendation>.broadcast();
  final StreamController<SubscriptionOptimization> _optimizationController = 
      StreamController<SubscriptionOptimization>.broadcast();
  
  // Public streams
  /// Emits the recommendations the adaptive analysis produces.
  Stream<SubscriptionRecommendation> get recommendations => _recommendationController.stream;
  /// Emits the result of each optimization pass.
  Stream<SubscriptionOptimization> get optimizations => _optimizationController.stream;
  
  /// Creates a controller on [connectionManager] and starts its periodic tasks.
  ///
  /// [config] defaults to [DynamicSubscriptionConfig.defaultConfig].
  WebSocketDynamicSubscriptionController({
    required WebSocketConnectionManager connectionManager,
    DynamicSubscriptionConfig? config,
  })  : _connectionManager = connectionManager,
        _subscriptionManager = connectionManager.subscriptionManager,
        _config = config ?? DynamicSubscriptionConfig.defaultConfig() {
    _initialize();
  }
  
  /// Sets default event priorities, wires listeners and starts the periodic tasks.
  void _initialize() {
    _initializeEventPriorities();
    _setupEventListeners();
    _startPeriodicTasks();
  }
  
  /// Initialize default event priorities
  void _initializeEventPriorities() {
    // Critical events (always needed)
    _eventPriorities[AppConstants.eventAuthSuccess] = 1.0;
    _eventPriorities[AppConstants.eventAuthError] = 1.0;
    _eventPriorities[AppConstants.eventConnect] = 1.0;
    _eventPriorities[AppConstants.eventSysPing] = 0.9;
    _eventPriorities[AppConstants.eventSysPong] = 0.9;
    
    // Audio events (high priority for TTS app)
    _eventPriorities[AppConstants.eventAudioStreamingChunk] = 0.9;
    _eventPriorities[AppConstants.eventAudioStreamingStatus] = 0.8;
    _eventPriorities[AppConstants.eventAudioStreamingComplete] = 0.8;
    _eventPriorities[AppConstants.eventTtsJobRequest] = 0.7;
    
    // Notification events (medium-high priority)
    _eventPriorities[AppConstants.eventNotificationQueueUpdate] = 0.7;
    _eventPriorities[AppConstants.eventNotificationPlaySound] = 0.6;
    
    // Queue events (medium priority, depends on context)
    _eventPriorities[AppConstants.eventQueueTodoUpdate] = 0.5;
    _eventPriorities[AppConstants.eventQueueRunningUpdate] = 0.6;
    _eventPriorities[AppConstants.eventQueueDoneUpdate] = 0.4;
    _eventPriorities[AppConstants.eventQueueDeadUpdate] = 0.3;
    
    // System events (lower priority)
    _eventPriorities[AppConstants.eventSysTimeUpdate] = 0.3;
  }
  
  /// Set up event listeners for dynamic behavior
  void _setupEventListeners() {
    // Listen to all message streams to track usage
    _connectionManager.audioChunks.listen(_trackEventUsage);
    _connectionManager.ttsStatus.listen(_trackEventUsage);
    _connectionManager.queueUpdates.listen(_trackEventUsage);
    _connectionManager.notifications.listen(_trackEventUsage);
    _connectionManager.systemMessages.listen(_trackEventUsage);
    _connectionManager.authMessages.listen(_trackEventUsage);
    
    // Listen to subscription changes
    _connectionManager.subscriptionChanges.listen(_handleSubscriptionChange);
  }
  
  /// Start periodic analysis and optimization tasks
  void _startPeriodicTasks() {
    if (_config.enableAdaptiveLearning) {
      _adaptiveAnalysisTimer = Timer.periodic(
        _config.adaptiveAnalysisInterval,
        (_) => _performAdaptiveAnalysis(),
      );
    }
    
    if (_config.enableSubscriptionOptimization) {
      _subscriptionOptimizationTimer = Timer.periodic(
        _config.optimizationInterval,
        (_) => _performSubscriptionOptimization(),
      );
    }
    
    if (_config.enableUsageReporting) {
      _usageReportTimer = Timer.periodic(
        _config.usageReportInterval,
        (_) => _generateUsageReport(),
      );
    }
  }
  
  /// Add a context-based subscription
  Future<void> addContextualSubscription(SubscriptionContext context) async {
    _contextSubscriptions[context.name] = context;
    
    if (context.isActive) {
      await _subscriptionManager.addEventSubscriptions(context.eventTypes);
      
      // Apply context-specific filters
      for (final filterEntry in context.filters.entries) {
        _subscriptionManager.registerEventFilter(filterEntry.key, filterEntry.value);
      }
      
      print('[DynamicSubscription] Added contextual subscription: ${context.name}');
    }
  }
  
  /// Remove a context-based subscription
  Future<void> removeContextualSubscription(String contextName) async {
    final context = _contextSubscriptions.remove(contextName);
    
    if (context != null) {
      await _subscriptionManager.removeEventSubscriptions(context.eventTypes);
      
      // Remove context-specific filters
      for (final eventType in context.filters.keys) {
        _subscriptionManager.removeEventFilter(eventType);
      }
      
      print('[DynamicSubscription] Removed contextual subscription: $contextName');
    }
  }
  
  /// Activate a contextual subscription
  Future<void> activateContext(String contextName) async {
    final context = _contextSubscriptions[contextName];
    if (context != null && !context.isActive) {
      context.isActive = true;
      await _subscriptionManager.addEventSubscriptions(context.eventTypes);
      
      print('[DynamicSubscription] Activated context: $contextName');
    }
  }
  
  /// Deactivate a contextual subscription
  Future<void> deactivateContext(String contextName) async {
    final context = _contextSubscriptions[contextName];
    if (context != null && context.isActive) {
      context.isActive = false;
      await _subscriptionManager.removeEventSubscriptions(context.eventTypes);
      
      print('[DynamicSubscription] Deactivated context: $contextName');
    }
  }
  
  /// Auto-adjust subscriptions based on app state
  Future<void> adjustSubscriptionsForAppState(AppState appState) async {
    switch (appState) {
      case AppState.ttsActive:
        await _activateTTSSubscriptions();
        break;
        
      case AppState.voiceInput:
        await _activateVoiceInputSubscriptions();
        break;
        
      case AppState.queueMonitoring:
        await _activateQueueMonitoringSubscriptions();
        break;
        
      case AppState.background:
        await _activateBackgroundSubscriptions();
        break;
        
      case AppState.foreground:
        await _activateForegroundSubscriptions();
        break;
    }
  }
  
  /// Activate TTS-focused subscriptions
  Future<void> _activateTTSSubscriptions() async {
    await addContextualSubscription(SubscriptionContext(
      name: 'tts_active',
      eventTypes: {
        AppConstants.eventAudioStreamingChunk,
        AppConstants.eventAudioStreamingStatus,
        AppConstants.eventAudioStreamingComplete,
        AppConstants.eventTtsJobRequest,
      },
      priority: SubscriptionPriority.high,
      isActive: true,
    ));
  }
  
  /// Activate voice input subscriptions
  Future<void> _activateVoiceInputSubscriptions() async {
    await addContextualSubscription(SubscriptionContext(
      name: 'voice_input',
      eventTypes: {
        'voice_input',
        'voice_start',
        'voice_stop',
        'transcription',
      },
      priority: SubscriptionPriority.high,
      isActive: true,
    ));
  }
  
  /// Activate queue monitoring subscriptions
  Future<void> _activateQueueMonitoringSubscriptions() async {
    await addContextualSubscription(SubscriptionContext(
      name: 'queue_monitoring',
      eventTypes: {
        AppConstants.eventQueueTodoUpdate,
        AppConstants.eventQueueRunningUpdate,
        AppConstants.eventQueueDoneUpdate,
        AppConstants.eventNotificationQueueUpdate,
      },
      priority: SubscriptionPriority.medium,
      isActive: true,
    ));
  }
  
  /// Activate minimal background subscriptions
  Future<void> _activateBackgroundSubscriptions() async {
    await _subscriptionManager.subscribeToEvents({
      AppConstants.eventAuthSuccess,
      AppConstants.eventAuthError,
      AppConstants.eventSysPing,
      AppConstants.eventNotificationPlaySound,
    });
  }
  
  /// Activate full foreground subscriptions
  Future<void> _activateForegroundSubscriptions() async {
    await _subscriptionManager.subscribeToAll();
  }
  
  /// Track event usage for adaptive learning
  void _trackEventUsage(dynamic event) {
    String eventType = 'unknown';
    
    // Extract event type from different message types
    if (event is QueueUpdateMessage) {
      eventType = 'queue_${event.queueType}_update';
    } else if (event is NotificationMessage) {
      eventType = 'notification_${event.notificationType}';
    } else if (event is SystemMessage) {
      eventType = 'sys_${event.systemType}';
    } else if (event is AuthMessage) {
      eventType = 'auth_${event.authType}';
    } else {
      eventType = event.runtimeType.toString().toLowerCase();
    }
    
    // Update usage statistics
    _eventUsageStats[eventType] = (_eventUsageStats[eventType] ?? 0) + 1;
    _lastEventReceived[eventType] = DateTime.now();
    
    // Update event history for pattern analysis
    _eventHistory.putIfAbsent(eventType, () => []).add(DateTime.now());
    
    // Keep only recent history
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    _eventHistory[eventType]!.removeWhere((time) => time.isBefore(cutoff));
  }
  
  /// Handle subscription changes
  void _handleSubscriptionChange(SubscriptionChange change) {
    print('[DynamicSubscription] Subscription changed: ${change.type} - ${change.events.length} events');
  }
  
  /// Perform adaptive analysis to learn usage patterns
  void _performAdaptiveAnalysis() {
    if (!_config.enableAdaptiveLearning) return;
    
    final now = DateTime.now();
    final recommendations = <String>[];
    
    // Analyze event frequency patterns
    for (final entry in _eventHistory.entries) {
      final eventType = entry.key;
      final history = entry.value;
      
      if (history.length >= 3) {
        final frequency = _calculateEventFrequency(history);
        final currentPriority = _eventPriorities[eventType] ?? 0.5;
        
        // Adjust priority based on usage frequency
        if (frequency > _config.highFrequencyThreshold) {
          _eventPriorities[eventType] = min(1.0, currentPriority + 0.1);
          if (currentPriority < 0.7) {
            recommendations.add('Increase priority for high-frequency event: $eventType');
          }
        } else if (frequency < _config.lowFrequencyThreshold) {
          _eventPriorities[eventType] = max(0.1, currentPriority - 0.05);
          if (currentPriority > 0.3) {
            recommendations.add('Consider reducing priority for low-frequency event: $eventType');
          }
        }
      }
    }
    
    // Generate recommendations
    if (recommendations.isNotEmpty) {
      _recommendationController.add(SubscriptionRecommendation(
        recommendations: recommendations,
        analysisType: 'adaptive_learning',
        confidence: 0.8,
        timestamp: now,
      ));
    }
  }
  
  /// Calculate event frequency (events per hour)
  double _calculateEventFrequency(List<DateTime> history) {
    if (history.isEmpty) return 0.0;
    
    final now = DateTime.now();
    final oneHourAgo = now.subtract(const Duration(hours: 1));
    final recentEvents = history.where((time) => time.isAfter(oneHourAgo)).length;
    
    return recentEvents.toDouble();
  }
  
  /// Perform subscription optimization
  Future<void> _performSubscriptionOptimization() async {
    if (!_config.enableSubscriptionOptimization) return;
    
    final optimizations = <String>[];
    final now = DateTime.now();
    
    // Find unused events (subscribed but not received recently)
    final subscribedEvents = _subscriptionManager.subscribedEvents;
    final unusedEvents = <String>{};
    
    for (final eventType in subscribedEvents) {
      final lastReceived = _lastEventReceived[eventType];
      if (lastReceived == null || 
          now.difference(lastReceived) > _config.unusedEventThreshold) {
        unusedEvents.add(eventType);
      }
    }
    
    // Find heavily used events that might need higher priority
    final heavyEvents = <String>{};
    for (final entry in _eventUsageStats.entries) {
      if (entry.value > _config.heavyUsageThreshold) {
        heavyEvents.add(entry.key);
      }
    }
    
    // Generate optimization suggestions
    if (unusedEvents.isNotEmpty) {
      optimizations.add('Consider unsubscribing from unused events: ${unusedEvents.take(5).join(", ")}');
    }
    
    if (heavyEvents.isNotEmpty) {
      optimizations.add('High usage events detected: ${heavyEvents.take(3).join(", ")}');
    }
    
    // Auto-optimize if enabled
    if (_config.enableAutoOptimization && unusedEvents.length > 3) {
      await _subscriptionManager.removeEventSubscriptions(unusedEvents.take(3).toSet());
      optimizations.add('Auto-removed 3 unused event subscriptions');
    }
    
    if (optimizations.isNotEmpty) {
      _optimizationController.add(SubscriptionOptimization(
        optimizations: optimizations,
        unusedEventCount: unusedEvents.length,
        heavyEventCount: heavyEvents.length,
        timestamp: now,
      ));
    }
  }
  
  /// Generate usage report
  void _generateUsageReport() {
    final report = {
      'total_events_received': _eventUsageStats.values.fold(0, (a, b) => a + b),
      'unique_event_types': _eventUsageStats.length,
      'most_frequent_events': _getMostFrequentEvents(5),
      'subscription_efficiency': _calculateSubscriptionEfficiency(),
      'active_contexts': _contextSubscriptions.values.where((c) => c.isActive).length,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    print('[DynamicSubscription] Usage Report: $report');
  }
  
  /// Get most frequent events
  List<Map<String, dynamic>> _getMostFrequentEvents(int count) {
    final sortedEvents = _eventUsageStats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sortedEvents.take(count).map((entry) => {
      'event_type': entry.key,
      'count': entry.value,
      'priority': _eventPriorities[entry.key] ?? 0.5,
    }).toList();
  }
  
  /// Calculate subscription efficiency (received events / subscribed events)
  double _calculateSubscriptionEfficiency() {
    final subscribedCount = _subscriptionManager.subscribedEvents.length;
    final receivedCount = _eventUsageStats.length;
    
    if (subscribedCount == 0) return 0.0;
    return receivedCount / subscribedCount;
  }
  
  /// Get current subscription analytics
  Map<String, dynamic> getSubscriptionAnalytics() {
    return {
      'event_priorities': Map.from(_eventPriorities),
      'usage_stats': Map.from(_eventUsageStats),
      'active_contexts': _contextSubscriptions.values
          .where((c) => c.isActive)
          .map((c) => c.toJson())
          .toList(),
      'subscription_efficiency': _calculateSubscriptionEfficiency(),
      'total_events_received': _eventUsageStats.values.fold(0, (a, b) => a + b),
    };
  }
  
  /// Dispose resources
  void dispose() {
    _adaptiveAnalysisTimer?.cancel();
    _subscriptionOptimizationTimer?.cancel();
    _usageReportTimer?.cancel();
    
    _recommendationController.close();
    _optimizationController.close();
    
    _contextSubscriptions.clear();
    _eventUsageStats.clear();
    _lastEventReceived.clear();
    _eventPriorities.clear();
    _eventHistory.clear();
  }
}

/// Tuning for [WebSocketDynamicSubscriptionController]: which analyses run, and thresholds.
class DynamicSubscriptionConfig {
  /// Whether the adaptive analysis adjusts event priorities from usage.
  final bool enableAdaptiveLearning;
  /// Whether the periodic optimization pass runs.
  final bool enableSubscriptionOptimization;
  /// Whether usage reports are produced.
  final bool enableUsageReporting;
  /// Whether an optimization pass applies its changes itself.
  ///
  /// When false it only reports them.
  final bool enableAutoOptimization;
  
  /// Time between adaptive analyses.
  final Duration adaptiveAnalysisInterval;
  /// Time between optimization passes.
  final Duration optimizationInterval;
  /// Time between usage reports.
  final Duration usageReportInterval;
  /// An event not received for this long counts as unused.
  final Duration unusedEventThreshold;
  
  /// Events in the last hour above which an event counts as high-frequency.
  final double highFrequencyThreshold;
  /// Events in the last hour below which an event counts as low-frequency.
  final double lowFrequencyThreshold;
  /// Event count above which an event counts as heavily used.
  final int heavyUsageThreshold;
  
  /// Creates a config; the defaults match [DynamicSubscriptionConfig.defaultConfig].
  const DynamicSubscriptionConfig({
    this.enableAdaptiveLearning = true,
    this.enableSubscriptionOptimization = true,
    this.enableUsageReporting = true,
    this.enableAutoOptimization = false,
    this.adaptiveAnalysisInterval = const Duration(minutes: 10),
    this.optimizationInterval = const Duration(minutes: 5),
    this.usageReportInterval = const Duration(minutes: 15),
    this.unusedEventThreshold = const Duration(minutes: 30),
    this.highFrequencyThreshold = 10.0,
    this.lowFrequencyThreshold = 1.0,
    this.heavyUsageThreshold = 50,
  });
  
  /// The default config: all analyses on, auto-optimization off.
  factory DynamicSubscriptionConfig.defaultConfig() {
    return const DynamicSubscriptionConfig();
  }
  
  /// Auto-optimization on, with shorter intervals and lower frequency thresholds.
  factory DynamicSubscriptionConfig.aggressive() {
    return const DynamicSubscriptionConfig(
      enableAutoOptimization: true,
      adaptiveAnalysisInterval: Duration(minutes: 5),
      optimizationInterval: Duration(minutes: 2),
      highFrequencyThreshold: 5.0,
      lowFrequencyThreshold: 0.5,
    );
  }
  
  /// Auto-optimization off, with longer intervals and higher frequency thresholds.
  factory DynamicSubscriptionConfig.conservative() {
    return const DynamicSubscriptionConfig(
      enableAutoOptimization: false,
      adaptiveAnalysisInterval: Duration(minutes: 30),
      optimizationInterval: Duration(minutes: 15),
      highFrequencyThreshold: 20.0,
      lowFrequencyThreshold: 2.0,
    );
  }
}

/// A named group of event types, filters and a priority that can be switched on together.
class SubscriptionContext {
  /// Name of the context.
  final String name;
  /// Event types the context subscribes to.
  final Set<String> eventTypes;
  /// Importance of the context.
  final SubscriptionPriority priority;
  /// Filters applied to the context's events, by name.
  final Map<String, EventFilter> filters;
  /// Free-form data attached to the context.
  final Map<String, dynamic> metadata;
  /// Whether the context is currently switched on.
  bool isActive;
  
  /// Creates a context; it starts inactive.
  SubscriptionContext({
    required this.name,
    required this.eventTypes,
    this.priority = SubscriptionPriority.medium,
    this.filters = const {},
    this.metadata = const {},
    this.isActive = false,
  });
  
  /// Serializes the context with snake_case keys; filters are reported only as a count.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'event_types': eventTypes.toList(),
      'priority': priority.toString(),
      'is_active': isActive,
      'filter_count': filters.length,
      'metadata': metadata,
    };
  }
}

/// App states that drive subscription adjustments.
enum AppState {
  /// Speech is being played.
  ttsActive,
  /// The microphone is recording.
  voiceInput,
  /// The user is watching the queue.
  queueMonitoring,
  /// The app is in the background.
  background,
  /// The app is in the foreground.
  foreground,
}

/// How important a subscription context is.
enum SubscriptionPriority {
  /// Least important.
  low,
  /// Normal importance.
  medium,
  /// Important.
  high,
  /// Never to be dropped.
  critical,
}

/// A suggestion from the adaptive analysis, with how confident it is.
class SubscriptionRecommendation {
  /// Human-readable recommendations.
  final List<String> recommendations;
  /// Which analysis produced them.
  final String analysisType;
  /// Confidence in the recommendations, from 0 to 1.
  final double confidence;
  /// When the analysis ran.
  final DateTime timestamp;
  
  /// Creates a recommendation; every field is required.
  SubscriptionRecommendation({
    required this.recommendations,
    required this.analysisType,
    required this.confidence,
    required this.timestamp,
  });
}

/// The outcome of one optimization pass over unused and heavily used events.
class SubscriptionOptimization {
  /// Human-readable descriptions of the changes found.
  final List<String> optimizations;
  /// Number of events counted as unused.
  final int unusedEventCount;
  /// Number of events counted as heavily used.
  final int heavyEventCount;
  /// When the pass ran.
  final DateTime timestamp;
  
  /// Creates a result; every field is required.
  SubscriptionOptimization({
    required this.optimizations,
    required this.unusedEventCount,
    required this.heavyEventCount,
    required this.timestamp,
  });
}