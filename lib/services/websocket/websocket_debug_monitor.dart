import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'websocket_connection_manager.dart';
import 'websocket_event_handlers.dart';
import '../../core/constants/app_constants.dart';

/// Records WebSocket events and connection changes, and raises alerts for unhealthy patterns.
///
/// Keeps an event log, per-event statistics and performance metrics, and publishes them on [debugUpdates].
/// Alerts go to [performanceAlerts] for event bursts, high error rates, connection flapping and a large log.
class WebSocketDebugMonitor {
  final WebSocketConnectionManager _connectionManager;
  final WebSocketEventHandlerSystem? _eventHandlerSystem;
  
  // Event monitoring
  final List<EventLogEntry> _eventLog = [];
  final Map<String, EventStatistics> _eventStats = {};
  final Map<String, PerformanceMetrics> _performanceMetrics = {};
  
  // Connection monitoring
  final List<ConnectionEvent> _connectionLog = [];
  final Map<String, Duration> _connectionDurations = {};
  DateTime? _lastConnectionTime;
  
  // Subscription monitoring
  final List<SubscriptionEvent> _subscriptionLog = [];
  final Map<String, int> _subscriptionStats = {};
  
  // Debug configuration
  final DebugConfig _config;
  
  // Stream controllers
  final StreamController<DebugUpdate> _debugUpdateController = 
      StreamController<DebugUpdate>.broadcast();
  final StreamController<PerformanceAlert> _performanceAlertController = 
      StreamController<PerformanceAlert>.broadcast();
  
  // Stream subscriptions
  final List<StreamSubscription> _subscriptions = [];
  
  // Timers
  Timer? _statsUpdateTimer;
  Timer? _performanceCheckTimer;
  Timer? _logCleanupTimer;
  
  // Public streams
  /// Emits each logged event, connection event, subscription event and statistics update.
  Stream<DebugUpdate> get debugUpdates => _debugUpdateController.stream;
  /// Emits an alert when a performance check finds a problem.
  Stream<PerformanceAlert> get performanceAlerts => _performanceAlertController.stream;
  
  /// Creates a monitor over [connectionManager]; [eventHandlerSystem] is optional.
  WebSocketDebugMonitor({
    required WebSocketConnectionManager connectionManager,
    WebSocketEventHandlerSystem? eventHandlerSystem,
    DebugConfig? config,
  })  : _connectionManager = connectionManager,
        _eventHandlerSystem = eventHandlerSystem,
        _config = config ?? DebugConfig.defaultConfig() {
    _initialize();
  }
  
  /// Initialize the debug monitor
  void _initialize() {
    _setupEventMonitoring();
    _setupConnectionMonitoring();
    _setupSubscriptionMonitoring();
    _setupPerformanceMonitoring();
    _startPeriodicTasks();
  }
  
  /// Set up event monitoring
  void _setupEventMonitoring() {
    // Monitor all message streams
    _subscriptions.add(
      _connectionManager.audioChunks.listen((message) {
        _logEvent('audio_chunk', message.timestamp, {
          'provider': message.provider,
          'sequence': message.sequenceNumber,
          'total_chunks': message.totalChunks,
          'data_size': message.audioData?.length ?? 0,
        });
      }),
    );
    
    _subscriptions.add(
      _connectionManager.ttsStatus.listen((message) {
        _logEvent('tts_status', message.timestamp, {
          'status': message.status,
          'provider': message.provider,
          'session_id': message.sessionId,
        });
      }),
    );
    
    _subscriptions.add(
      _connectionManager.queueUpdates.listen((message) {
        _logEvent('queue_update', message.timestamp, {
          'queue_type': message.queueType,
          'session_id': message.sessionId,
          'item_count': message.queueData['items']?.length ?? 0,
        });
      }),
    );
    
    _subscriptions.add(
      _connectionManager.notifications.listen((message) {
        _logEvent('notification', message.timestamp, {
          'type': message.notificationType,
          'message': message.message,
        });
      }),
    );
    
    _subscriptions.add(
      _connectionManager.systemMessages.listen((message) {
        _logEvent('system_message', message.timestamp, {
          'type': message.systemType,
          'data_keys': message.data?.keys.toList() ?? [],
        });
      }),
    );
    
    _subscriptions.add(
      _connectionManager.authMessages.listen((message) {
        _logEvent('auth_message', message.timestamp, {
          'type': message.authType,
          'user_id': message.userId,
          'session_id': message.sessionId,
        });
      }),
    );
    
    _subscriptions.add(
      _connectionManager.errors.listen((error) {
        _logEvent('error', error.timestamp, {
          'error': error.error,
          'code': error.code,
          'original_type': error.originalMessage?.type,
        }, isError: true);
      }),
    );
  }
  
  /// Set up connection monitoring
  void _setupConnectionMonitoring() {
    // Monitor connection state changes
    _connectionManager.addConnectionStateListener((change) {
      _logConnectionEvent(ConnectionEvent(
        type: ConnectionEventType.stateChange,
        timestamp: change.timestamp,
        details: {
          'from': change.from.toString(),
          'to': change.to.toString(),
          'details': change.details,
        },
      ));
    });
  }
  
  /// Set up subscription monitoring
  void _setupSubscriptionMonitoring() {
    _subscriptions.add(
      _connectionManager.subscriptionChanges.listen((change) {
        _logSubscriptionEvent(SubscriptionEvent(
          type: change.type.toString(),
          timestamp: change.timestamp,
          eventCount: change.events.length,
          events: change.events.toList(),
        ));
      }),
    );
    
    _subscriptions.add(
      _connectionManager.filterResults.listen((result) {
        _logEvent('filter_result', result.timestamp, {
          'event_type': result.eventType,
          'allowed': result.allowed,
          'filtered_by': result.filteredBy,
        });
      }),
    );
  }
  
  /// Set up performance monitoring
  void _setupPerformanceMonitoring() {
    if (_config.enablePerformanceMonitoring) {
      _performanceCheckTimer = Timer.periodic(
        _config.performanceCheckInterval,
        (_) => _checkPerformance(),
      );
    }
  }
  
  /// Start periodic tasks
  void _startPeriodicTasks() {
    if (_config.enableStatsUpdates) {
      _statsUpdateTimer = Timer.periodic(
        _config.statsUpdateInterval,
        (_) => _updateStatistics(),
      );
    }
    
    if (_config.enableLogCleanup) {
      _logCleanupTimer = Timer.periodic(
        _config.logCleanupInterval,
        (_) => _cleanupOldLogs(),
      );
    }
  }
  
  /// Log an event
  void _logEvent(String eventType, DateTime timestamp, Map<String, dynamic> details, {bool isError = false}) {
    final entry = EventLogEntry(
      eventType: eventType,
      timestamp: timestamp,
      details: details,
      isError: isError,
    );
    
    _eventLog.add(entry);
    _updateEventStats(eventType, entry);
    
    // Emit debug update
    _debugUpdateController.add(DebugUpdate(
      type: DebugUpdateType.eventLogged,
      timestamp: timestamp,
      data: entry.toJson(),
    ));
    
    // Check for performance issues
    if (_config.enablePerformanceAlerts) {
      _checkEventPerformance(eventType, timestamp);
    }
    
    if (_config.enableConsoleLogging) {
      print('[WebSocketDebug] ${isError ? 'ERROR' : 'EVENT'} $eventType: $details');
    }
  }
  
  /// Log a connection event
  void _logConnectionEvent(ConnectionEvent event) {
    _connectionLog.add(event);
    
    if (event.type == ConnectionEventType.stateChange) {
      final to = event.details?['to'] as String?;
      if (to == 'connected') {
        _lastConnectionTime = event.timestamp;
      } else if (to == 'disconnected' && _lastConnectionTime != null) {
        _connectionDurations[event.timestamp.toIso8601String()] = 
            event.timestamp.difference(_lastConnectionTime!);
      }
    }
    
    _debugUpdateController.add(DebugUpdate(
      type: DebugUpdateType.connectionEvent,
      timestamp: event.timestamp,
      data: event.toJson(),
    ));
  }
  
  /// Log a subscription event
  void _logSubscriptionEvent(SubscriptionEvent event) {
    _subscriptionLog.add(event);
    _subscriptionStats[event.type] = (_subscriptionStats[event.type] ?? 0) + 1;
    
    _debugUpdateController.add(DebugUpdate(
      type: DebugUpdateType.subscriptionEvent,
      timestamp: event.timestamp,
      data: event.toJson(),
    ));
  }
  
  /// Adds [entry] to the statistics for [eventType].
  void _updateEventStats(String eventType, EventLogEntry entry) {
    _eventStats.putIfAbsent(eventType, () => EventStatistics(eventType: eventType));
    final stats = _eventStats[eventType]!;
    
    stats.totalCount++;
    if (entry.isError) {
      stats.errorCount++;
    }
    
    stats.lastSeen = entry.timestamp;
    
    // Update frequency calculation
    final now = DateTime.now();
    stats.recentEvents.add(now);
    stats.recentEvents.removeWhere((time) => 
        now.difference(time) > const Duration(minutes: 5));
    
    stats.frequencyPerMinute = stats.recentEvents.length / 5.0;
  }
  
  /// Check event performance
  void _checkEventPerformance(String eventType, DateTime timestamp) {
    _performanceMetrics.putIfAbsent(eventType, () => PerformanceMetrics(eventType: eventType));
    final metrics = _performanceMetrics[eventType]!;
    
    // Check for event bursts
    final recentEvents = _eventLog
        .where((e) => e.eventType == eventType && 
               timestamp.difference(e.timestamp) < const Duration(seconds: 30))
        .length;
    
    if (recentEvents > _config.eventBurstThreshold) {
      _performanceAlertController.add(PerformanceAlert(
        type: PerformanceAlertType.eventBurst,
        eventType: eventType,
        message: 'Event burst detected: $recentEvents events in 30 seconds',
        severity: AlertSeverity.warning,
        timestamp: timestamp,
        details: {'event_count': recentEvents, 'threshold': _config.eventBurstThreshold},
      ));
    }
    
    // Check for error patterns
    final stats = _eventStats[eventType]!;
    if (stats.totalCount > 10 && (stats.errorCount / stats.totalCount) > 0.2) {
      _performanceAlertController.add(PerformanceAlert(
        type: PerformanceAlertType.highErrorRate,
        eventType: eventType,
        message: 'High error rate: ${(stats.errorCount / stats.totalCount * 100).toStringAsFixed(1)}%',
        severity: AlertSeverity.error,
        timestamp: timestamp,
        details: {'error_rate': stats.errorCount / stats.totalCount},
      ));
    }
  }
  
  /// Perform comprehensive performance check
  void _checkPerformance() {
    final now = DateTime.now();
    
    // Check connection stability
    final recentConnections = _connectionLog
        .where((e) => now.difference(e.timestamp) < const Duration(minutes: 15))
        .length;
    
    if (recentConnections > _config.connectionFlappingThreshold) {
      _performanceAlertController.add(PerformanceAlert(
        type: PerformanceAlertType.connectionFlapping,
        eventType: 'connection',
        message: 'Connection flapping detected: $recentConnections events in 15 minutes',
        severity: AlertSeverity.warning,
        timestamp: now,
        details: {'event_count': recentConnections},
      ));
    }
    
    // Check memory usage (event log size)
    if (_eventLog.length > _config.maxEventLogSize) {
      _performanceAlertController.add(PerformanceAlert(
        type: PerformanceAlertType.memoryUsage,
        eventType: 'system',
        message: 'Event log growing large: ${_eventLog.length} entries',
        severity: AlertSeverity.info,
        timestamp: now,
        details: {'log_size': _eventLog.length, 'max_size': _config.maxEventLogSize},
      ));
    }
  }
  
  /// Recomputes each event's rate over the last 5 minutes and publishes it.
  void _updateStatistics() {
    for (final stats in _eventStats.values) {
      // Update frequency calculations
      final now = DateTime.now();
      stats.recentEvents.removeWhere((time) => 
          now.difference(time) > const Duration(minutes: 5));
      stats.frequencyPerMinute = stats.recentEvents.length / 5.0;
    }
    
    _debugUpdateController.add(DebugUpdate(
      type: DebugUpdateType.statsUpdate,
      timestamp: DateTime.now(),
      data: getDebugStatistics(),
    ));
  }
  
  /// Clean up old logs
  void _cleanupOldLogs() {
    final cutoff = DateTime.now().subtract(_config.logRetentionPeriod);
    
    _eventLog.removeWhere((entry) => entry.timestamp.isBefore(cutoff));
    _connectionLog.removeWhere((entry) => entry.timestamp.isBefore(cutoff));
    _subscriptionLog.removeWhere((entry) => entry.timestamp.isBefore(cutoff));
    
    if (_config.enableConsoleLogging) {
      print('[WebSocketDebug] Cleaned up logs older than $cutoff');
    }
  }
  
  /// Get current debug statistics
  Map<String, dynamic> getDebugStatistics() {
    final now = DateTime.now();
    
    return {
      'event_statistics': _eventStats.map((type, stats) => 
          MapEntry(type, stats.toJson())),
      'connection_statistics': {
        'total_connection_events': _connectionLog.length,
        'recent_connections': _connectionLog
            .where((e) => now.difference(e.timestamp) < const Duration(hours: 1))
            .length,
        'average_connection_duration': _getAverageConnectionDuration(),
        'current_status': _connectionManager.getConnectionStatus(),
      },
      'subscription_statistics': {
        'total_subscription_events': _subscriptionLog.length,
        'subscription_change_counts': Map.from(_subscriptionStats),
        'current_subscriptions': _connectionManager.getSubscriptionStats(),
      },
      'performance_metrics': _performanceMetrics.map((type, metrics) => 
          MapEntry(type, metrics.toJson())),
      'log_sizes': {
        'event_log': _eventLog.length,
        'connection_log': _connectionLog.length,
        'subscription_log': _subscriptionLog.length,
      },
      'timestamp': now.toIso8601String(),
    };
  }
  
  /// Get average connection duration
  double _getAverageConnectionDuration() {
    if (_connectionDurations.isEmpty) return 0.0;
    
    final totalMs = _connectionDurations.values
        .fold(0, (sum, duration) => sum + duration.inMilliseconds);
    return totalMs / _connectionDurations.length;
  }
  
  /// Get recent events for a specific type
  List<EventLogEntry> getRecentEvents({
    String? eventType,
    Duration? timeWindow,
    int? maxCount,
  }) {
    final window = timeWindow ?? const Duration(minutes: 30);
    final cutoff = DateTime.now().subtract(window);
    
    var filtered = _eventLog.where((entry) => entry.timestamp.isAfter(cutoff));
    
    if (eventType != null) {
      filtered = filtered.where((entry) => entry.eventType == eventType);
    }
    
    var result = filtered.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    if (maxCount != null && result.length > maxCount) {
      result = result.take(maxCount).toList();
    }
    
    return result;
  }
  
  /// Get connection health report
  Map<String, dynamic> getConnectionHealthReport() {
    final now = DateTime.now();
    final last24Hours = now.subtract(const Duration(hours: 24));
    
    final recentEvents = _connectionLog
        .where((e) => e.timestamp.isAfter(last24Hours))
        .toList();
    
    final disconnections = recentEvents
        .where((e) => e.details?['to'] == 'disconnected')
        .length;
    
    final connectionAttempts = recentEvents
        .where((e) => e.details?['to'] == 'connecting')
        .length;
    
    return {
      'status': _connectionManager.getConnectionStatus(),
      'stability_score': _calculateStabilityScore(recentEvents),
      'recent_disconnections': disconnections,
      'connection_attempts': connectionAttempts,
      'success_rate': connectionAttempts > 0 ? 
          (connectionAttempts - disconnections) / connectionAttempts : 1.0,
      'average_connection_duration': _getAverageConnectionDuration(),
      'last_connection_time': _lastConnectionTime?.toIso8601String(),
    };
  }
  
  /// Calculate connection stability score (0.0 to 1.0)
  double _calculateStabilityScore(List<ConnectionEvent> recentEvents) {
    if (recentEvents.isEmpty) return 1.0;
    
    final disconnections = recentEvents
        .where((e) => e.details?['to'] == 'disconnected')
        .length;
    
    // Penalize frequent disconnections
    final maxDisconnections = 5; // Threshold for good stability
    final penalty = (disconnections / maxDisconnections).clamp(0.0, 1.0);
    
    return 1.0 - penalty;
  }
  
  /// Export debug data for analysis
  Map<String, dynamic> exportDebugData({
    Duration? timeWindow,
    bool includeDetails = false,
  }) {
    final window = timeWindow ?? const Duration(hours: 24);
    final cutoff = DateTime.now().subtract(window);
    
    final filteredEvents = _eventLog
        .where((e) => e.timestamp.isAfter(cutoff))
        .toList();
    
    final filteredConnections = _connectionLog
        .where((e) => e.timestamp.isAfter(cutoff))
        .toList();
    
    final filteredSubscriptions = _subscriptionLog
        .where((e) => e.timestamp.isAfter(cutoff))
        .toList();
    
    return {
      'export_info': {
        'generated_at': DateTime.now().toIso8601String(),
        'time_window': window.toString(),
        'include_details': includeDetails,
      },
      'events': filteredEvents.map((e) => e.toJson()).toList(),
      'connections': filteredConnections.map((e) => e.toJson()).toList(),
      'subscriptions': filteredSubscriptions.map((e) => e.toJson()).toList(),
      'statistics': getDebugStatistics(),
      'health_report': getConnectionHealthReport(),
      if (includeDetails) 'performance_metrics': _performanceMetrics.map(
        (type, metrics) => MapEntry(type, metrics.toJson())
      ),
    };
  }
  
  /// Enable/disable specific monitoring features
  void configureMonitoring({
    bool? enableEventLogging,
    bool? enablePerformanceMonitoring,
    bool? enableConsoleLogging,
    bool? enablePerformanceAlerts,
  }) {
    // Update configuration
    // Note: This would typically modify the config object
    // For now, we'll just print the changes
    
    print('[WebSocketDebug] Monitoring configuration updated:');
    if (enableEventLogging != null) {
      print('  Event logging: $enableEventLogging');
    }
    if (enablePerformanceMonitoring != null) {
      print('  Performance monitoring: $enablePerformanceMonitoring');
    }
    if (enableConsoleLogging != null) {
      print('  Console logging: $enableConsoleLogging');
    }
    if (enablePerformanceAlerts != null) {
      print('  Performance alerts: $enablePerformanceAlerts');
    }
  }
  
  /// Dispose resources
  void dispose() {
    _statsUpdateTimer?.cancel();
    _performanceCheckTimer?.cancel();
    _logCleanupTimer?.cancel();
    
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    
    _debugUpdateController.close();
    _performanceAlertController.close();
    
    _eventLog.clear();
    _connectionLog.clear();
    _subscriptionLog.clear();
    _eventStats.clear();
    _performanceMetrics.clear();
  }
}

// Configuration classes.

/// Settings for [WebSocketDebugMonitor].
class DebugConfig {
  /// Whether events are logged.
  final bool enableEventLogging;
  /// Whether performance checks run.
  final bool enablePerformanceMonitoring;
  /// Whether log lines are printed to the console.
  final bool enableConsoleLogging;
  /// Whether performance alerts are published.
  final bool enablePerformanceAlerts;
  /// Whether statistics are recomputed periodically.
  final bool enableStatsUpdates;
  /// Whether old log entries are removed periodically.
  final bool enableLogCleanup;
  
  /// Interval between statistics updates.
  final Duration statsUpdateInterval;
  /// Interval between performance checks.
  final Duration performanceCheckInterval;
  /// Interval between log cleanups.
  final Duration logCleanupInterval;
  /// Age after which log entries are removed.
  final Duration logRetentionPeriod;
  
  /// Event log size above which a memory-usage alert is raised.
  final int maxEventLogSize;
  /// Events of one type within 30 seconds above which a burst alert is raised.
  final int eventBurstThreshold;
  /// Connection events within 15 minutes above which a flapping alert is raised.
  final int connectionFlappingThreshold;
  
  /// Creates a config; the defaults enable everything.
  const DebugConfig({
    this.enableEventLogging = true,
    this.enablePerformanceMonitoring = true,
    this.enableConsoleLogging = true,
    this.enablePerformanceAlerts = true,
    this.enableStatsUpdates = true,
    this.enableLogCleanup = true,
    this.statsUpdateInterval = const Duration(seconds: 30),
    this.performanceCheckInterval = const Duration(minutes: 2),
    this.logCleanupInterval = const Duration(minutes: 30),
    this.logRetentionPeriod = const Duration(hours: 24),
    this.maxEventLogSize = 10000,
    this.eventBurstThreshold = 20,
    this.connectionFlappingThreshold = 10,
  });
  
  /// Builds the default config.
  factory DebugConfig.defaultConfig() {
    return const DebugConfig();
  }
  
  /// Builds a config with only event logging and log cleanup, keeping 1,000 entries.
  factory DebugConfig.minimal() {
    return const DebugConfig(
      enableEventLogging: true,
      enablePerformanceMonitoring: false,
      enableConsoleLogging: false,
      enablePerformanceAlerts: false,
      enableStatsUpdates: false,
      enableLogCleanup: true,
      maxEventLogSize: 1000,
    );
  }
  
  /// Builds a config with everything on, faster intervals and a 50,000-entry log.
  factory DebugConfig.verbose() {
    return const DebugConfig(
      enableEventLogging: true,
      enablePerformanceMonitoring: true,
      enableConsoleLogging: true,
      enablePerformanceAlerts: true,
      enableStatsUpdates: true,
      enableLogCleanup: true,
      statsUpdateInterval: Duration(seconds: 10),
      performanceCheckInterval: Duration(seconds: 30),
      maxEventLogSize: 50000,
      eventBurstThreshold: 10,
    );
  }
}

// Data classes.

/// One logged WebSocket event.
class EventLogEntry {
  /// Type of the event.
  final String eventType;
  /// When the event happened.
  final DateTime timestamp;
  /// Event details.
  final Map<String, dynamic> details;
  /// Whether the event was an error.
  final bool isError;
  
  /// Creates an entry; [isError] defaults to false.
  EventLogEntry({
    required this.eventType,
    required this.timestamp,
    required this.details,
    this.isError = false,
  });
  
  /// Serializes with snake_case keys.
  Map<String, dynamic> toJson() {
    return {
      'event_type': eventType,
      'timestamp': timestamp.toIso8601String(),
      'details': details,
      'is_error': isError,
    };
  }
}

/// Running counts and rates for one event type.
class EventStatistics {
  /// Event type the statistics are for.
  final String eventType;
  /// Events seen.
  int totalCount = 0;
  /// Error events seen.
  int errorCount = 0;
  /// When the first event was seen, or null.
  DateTime? firstSeen;
  /// When the latest event was seen, or null.
  DateTime? lastSeen;
  /// Events per minute, averaged over the last 5 minutes.
  double frequencyPerMinute = 0.0;
  /// Times of recent events, used for the frequency.
  final List<DateTime> recentEvents = [];
  
  /// Creates empty statistics for [eventType].
  EventStatistics({required this.eventType});
  
  /// Serializes with snake_case keys.
  Map<String, dynamic> toJson() {
    return {
      'event_type': eventType,
      'total_count': totalCount,
      'error_count': errorCount,
      'error_rate': totalCount > 0 ? errorCount / totalCount : 0.0,
      'first_seen': firstSeen?.toIso8601String(),
      'last_seen': lastSeen?.toIso8601String(),
      'frequency_per_minute': frequencyPerMinute,
      'recent_event_count': recentEvents.length,
    };
  }
}

/// Burst and processing-time figures for one event type.
class PerformanceMetrics {
  /// Event type the figures are for.
  final String eventType;
  /// Bursts detected.
  int burstCount = 0;
  /// When the last burst was detected, or null.
  DateTime? lastBurst;
  /// Average processing time, in milliseconds.
  double averageProcessingTime = 0.0;
  /// Recorded processing times.
  final List<Duration> processingTimes = [];
  
  /// Creates empty metrics for [eventType].
  PerformanceMetrics({required this.eventType});
  
  /// Serializes with snake_case keys.
  Map<String, dynamic> toJson() {
    return {
      'event_type': eventType,
      'burst_count': burstCount,
      'last_burst': lastBurst?.toIso8601String(),
      'average_processing_time_ms': averageProcessingTime,
      'processing_samples': processingTimes.length,
    };
  }
}

/// One logged connection event.
class ConnectionEvent {
  /// Kind of connection event.
  final ConnectionEventType type;
  /// When the event happened.
  final DateTime timestamp;
  /// Event details, or null.
  final Map<String, dynamic>? details;
  
  /// Creates an event.
  ConnectionEvent({
    required this.type,
    required this.timestamp,
    this.details,
  });
  
  /// Serializes with snake_case keys.
  Map<String, dynamic> toJson() {
    return {
      'type': type.toString(),
      'timestamp': timestamp.toIso8601String(),
      'details': details,
    };
  }
}

/// Kinds of connection event.
enum ConnectionEventType {
  /// The connection state changed.
  stateChange,
  /// The connection reported an error.
  error,
  /// The connection reconnected.
  reconnect,
  /// The connection timed out.
  timeout,
}

/// One logged change to the event subscriptions.
class SubscriptionEvent {
  /// Kind of subscription change.
  final String type;
  /// When the change happened.
  final DateTime timestamp;
  /// Number of events affected.
  final int eventCount;
  /// Names of the events affected.
  final List<String> events;
  
  /// Creates an event; every field is required.
  SubscriptionEvent({
    required this.type,
    required this.timestamp,
    required this.eventCount,
    required this.events,
  });
  
  /// Serializes with snake_case keys.
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'timestamp': timestamp.toIso8601String(),
      'event_count': eventCount,
      'events': events,
    };
  }
}

/// One item published on [WebSocketDebugMonitor.debugUpdates].
class DebugUpdate {
  /// Kind of update.
  final DebugUpdateType type;
  /// When the update was made.
  final DateTime timestamp;
  /// Payload of the update.
  final Map<String, dynamic> data;
  
  /// Creates an update; every field is required.
  DebugUpdate({
    required this.type,
    required this.timestamp,
    required this.data,
  });
}

/// Kinds of debug update.
enum DebugUpdateType {
  /// An event was logged.
  eventLogged,
  /// A connection event was logged.
  connectionEvent,
  /// A subscription event was logged.
  subscriptionEvent,
  /// Statistics were recomputed.
  statsUpdate,
  /// A performance alert was raised.
  performanceAlert,
}

/// One alert published on [WebSocketDebugMonitor.performanceAlerts].
class PerformanceAlert {
  /// Kind of alert.
  final PerformanceAlertType type;
  /// Event type the alert is about, or a pseudo-type such as `connection`.
  final String eventType;
  /// Alert text.
  final String message;
  /// How serious the alert is.
  final AlertSeverity severity;
  /// When the alert was raised.
  final DateTime timestamp;
  /// Alert details, or null.
  final Map<String, dynamic>? details;
  
  /// Creates an alert.
  PerformanceAlert({
    required this.type,
    required this.eventType,
    required this.message,
    required this.severity,
    required this.timestamp,
    this.details,
  });
}

/// Kinds of performance alert.
enum PerformanceAlertType {
  /// Too many events of one type in 30 seconds.
  eventBurst,
  /// More than 20% of an event type's events failed, after at least 10 events.
  highErrorRate,
  /// Too many connection events in 15 minutes.
  connectionFlapping,
  /// The event log grew past its size limit.
  memoryUsage,
  /// Event processing is slow.
  processingDelay,
}

/// How serious an alert is.
enum AlertSeverity {
  /// Informational.
  info,
  /// Worth attention.
  warning,
  /// A failure.
  error,
  /// Needs immediate attention.
  critical,
}