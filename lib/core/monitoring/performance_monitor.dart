import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import '../storage/storage_manager.dart';
import 'monitoring_models.dart';

/// Comprehensive performance monitoring system
class PerformanceMonitor {
  static PerformanceMonitor? _instance;
  late final StorageManager _storage;
  
  // Monitoring state
  bool _isMonitoring = false;
  DateTime? _monitoringStartTime;
  
  // Performance metrics
  final Map<String, PerformanceMetrics> _metrics = {};
  final Map<String, List<PerformanceEvent>> _events = {};
  final Queue<SystemSnapshot> _systemSnapshots = Queue();
  
  // Timers and controllers
  Timer? _systemMonitorTimer;
  Timer? _metricsFlushTimer;
  final StreamController<PerformanceAlert> _alertController = 
      StreamController<PerformanceAlert>.broadcast();
  
  // Configuration
  final PerformanceMonitorConfig _config;
  
  // Memory and CPU tracking
  int _lastMemoryUsage = 0;
  double _lastCpuUsage = 0.0;
  final Queue<double> _memoryHistory = Queue();
  final Queue<double> _cpuHistory = Queue();
  
  // Network monitoring
  final Map<String, NetworkRequestMetrics> _networkMetrics = {};
  int _totalNetworkRequests = 0;
  int _failedNetworkRequests = 0;
  int _totalBytesTransferred = 0;
  
  // Custom metrics
  final Map<String, CustomMetric> _customMetrics = {};
  
  PerformanceMonitor._(this._config);
  
  /// Get singleton instance
  static Future<PerformanceMonitor> getInstance({
    PerformanceMonitorConfig? config,
  }) async {
    if (_instance == null) {
      _instance = PerformanceMonitor._(
        config ?? PerformanceMonitorConfig.defaultConfig(),
      );
      await _instance!._initialize();
    }
    return _instance!;
  }
  
  /// Initialize the performance monitor
  Future<void> _initialize() async {
    _storage = await StorageManager.getInstance();
    
    if (_config.enablePersistence) {
      await _loadPersistedMetrics();
    }
  }
  
  /// Start performance monitoring
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    
    _isMonitoring = true;
    _monitoringStartTime = DateTime.now();
    
    // Start system monitoring
    if (_config.enableSystemMonitoring) {
      _startSystemMonitoring();
    }
    
    // Start metrics flushing
    if (_config.enablePersistence) {
      _startMetricsFlush();
    }
    
    _emitAlert(PerformanceAlert.info(
      'Performance monitoring started',
      details: {'config': _config.toJson()},
    ));
  }
  
  /// Stop performance monitoring
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;
    
    _isMonitoring = false;
    
    // Stop timers
    _systemMonitorTimer?.cancel();
    _metricsFlushTimer?.cancel();
    
    // Flush final metrics
    if (_config.enablePersistence) {
      await _flushMetrics();
    }
    
    _emitAlert(PerformanceAlert.info(
      'Performance monitoring stopped',
      details: {
        'duration_minutes': DateTime.now()
            .difference(_monitoringStartTime!)
            .inMinutes,
      },
    ));
  }
  
  /// Record a performance event
  void recordEvent(PerformanceEvent event) {
    if (!_isMonitoring) return;
    
    _events.putIfAbsent(event.category, () => []).add(event);
    
    // Update metrics
    _updateMetrics(event);
    
    // Check for alerts
    _checkEventAlerts(event);
    
    // Limit event history
    final categoryEvents = _events[event.category]!;
    if (categoryEvents.length > _config.maxEventsPerCategory) {
      categoryEvents.removeAt(0);
    }
  }
  
  /// Start timing an operation
  PerformanceTimer startTimer(String operation, {String? category}) {
    return PerformanceTimer(
      operation: operation,
      category: category ?? 'general',
      onComplete: (event) => recordEvent(event),
    );
  }
  
  /// Record a network request
  void recordNetworkRequest({
    required String url,
    required String method,
    required int statusCode,
    required Duration duration,
    int? requestBytes,
    int? responseBytes,
    String? error,
  }) {
    _totalNetworkRequests++;
    
    if (statusCode >= 400 || error != null) {
      _failedNetworkRequests++;
    }
    
    final totalBytes = (requestBytes ?? 0) + (responseBytes ?? 0);
    _totalBytesTransferred += totalBytes;
    
    final host = Uri.parse(url).host;
    final metrics = _networkMetrics.putIfAbsent(
      host,
      () => NetworkRequestMetrics(host: host),
    );
    
    metrics.addRequest(
      method: method,
      statusCode: statusCode,
      duration: duration,
      bytes: totalBytes,
      error: error,
    );
    
    // Record as performance event
    recordEvent(PerformanceEvent(
      name: 'network_request',
      category: 'network',
      duration: duration,
      metadata: {
        'url': url,
        'method': method,
        'status_code': statusCode,
        'bytes': totalBytes,
        if (error != null) 'error': error,
      },
    ));
    
    // Check for slow requests
    if (duration.inMilliseconds > _config.slowNetworkThresholdMs) {
      _emitAlert(PerformanceAlert.warning(
        'Slow network request detected',
        details: {
          'url': url,
          'duration_ms': duration.inMilliseconds,
          'threshold_ms': _config.slowNetworkThresholdMs,
        },
      ));
    }
  }
  
  /// Record memory usage
  void recordMemoryUsage(int bytes) {
    _lastMemoryUsage = bytes;
    _memoryHistory.add(bytes / (1024 * 1024)); // Convert to MB
    
    if (_memoryHistory.length > _config.maxHistorySize) {
      _memoryHistory.removeFirst();
    }
    
    // Check for memory alerts
    final memoryMB = bytes / (1024 * 1024);
    if (memoryMB > _config.highMemoryThresholdMB) {
      _emitAlert(PerformanceAlert.warning(
        'High memory usage detected',
        details: {
          'current_mb': memoryMB,
          'threshold_mb': _config.highMemoryThresholdMB,
        },
      ));
    }
  }
  
  /// Record CPU usage
  void recordCpuUsage(double percentage) {
    _lastCpuUsage = percentage;
    _cpuHistory.add(percentage);
    
    if (_cpuHistory.length > _config.maxHistorySize) {
      _cpuHistory.removeFirst();
    }
    
    // Check for CPU alerts
    if (percentage > _config.highCpuThresholdPercent) {
      _emitAlert(PerformanceAlert.warning(
        'High CPU usage detected',
        details: {
          'current_percent': percentage,
          'threshold_percent': _config.highCpuThresholdPercent,
        },
      ));
    }
  }
  
  /// Add custom metric
  void addCustomMetric(String name, double value, {String? unit}) {
    final metric = _customMetrics.putIfAbsent(
      name,
      () => CustomMetric(name: name, unit: unit),
    );
    
    metric.addValue(value);
    
    recordEvent(PerformanceEvent(
      name: 'custom_metric',
      category: 'metrics',
      metadata: {
        'metric_name': name,
        'value': value,
        if (unit != null) 'unit': unit,
      },
    ));
  }
  
  /// Increment counter metric
  void incrementCounter(String name, {int value = 1}) {
    final metric = _customMetrics.putIfAbsent(
      name,
      () => CustomMetric(name: name, type: MetricType.counter),
    );
    
    metric.addValue(value.toDouble());
  }
  
  /// Record gauge metric
  void recordGauge(String name, double value, {String? unit}) {
    final metric = _customMetrics.putIfAbsent(
      name,
      () => CustomMetric(name: name, type: MetricType.gauge, unit: unit),
    );
    
    metric.setValue(value);
  }
  
  /// Get current performance summary
  PerformanceSummary getPerformanceSummary() {
    final now = DateTime.now();
    final uptime = _monitoringStartTime != null 
        ? now.difference(_monitoringStartTime!)
        : Duration.zero;
    
    return PerformanceSummary(
      isMonitoring: _isMonitoring,
      uptime: uptime,
      totalEvents: _getTotalEventCount(),
      memoryUsageMB: _lastMemoryUsage / (1024 * 1024),
      cpuUsagePercent: _lastCpuUsage,
      networkRequests: NetworkSummary(
        totalRequests: _totalNetworkRequests,
        failedRequests: _failedNetworkRequests,
        totalBytesTransferred: _totalBytesTransferred,
        hosts: _networkMetrics.keys.toList(),
      ),
      averageEventDurations: _getAverageEventDurations(),
      customMetrics: _getCustomMetricsSummary(),
      alerts: _getRecentAlerts(),
    );
  }
  
  /// Get detailed analytics
  PerformanceAnalytics getAnalytics({
    Duration? timeWindow,
    List<String>? categories,
  }) {
    final cutoff = timeWindow != null 
        ? DateTime.now().subtract(timeWindow)
        : null;
    
    final filteredEvents = <String, List<PerformanceEvent>>{};
    
    for (final entry in _events.entries) {
      if (categories != null && !categories.contains(entry.key)) {
        continue;
      }
      
      var events = entry.value;
      if (cutoff != null) {
        events = events.where((e) => e.timestamp.isAfter(cutoff)).toList();
      }
      
      if (events.isNotEmpty) {
        filteredEvents[entry.key] = events;
      }
    }
    
    return PerformanceAnalytics(
      timeWindow: timeWindow,
      categories: filteredEvents.keys.toList(),
      eventBreakdown: filteredEvents.map((category, events) => 
          MapEntry(category, _analyzeEvents(events))),
      networkAnalytics: _getNetworkAnalytics(),
      systemAnalytics: _getSystemAnalytics(),
      customMetricsAnalytics: _getCustomMetricsAnalytics(),
      recommendations: _generateRecommendations(filteredEvents),
    );
  }
  
  /// Export performance data
  Future<String> exportData({
    String format = 'json',
    Duration? timeWindow,
    List<String>? categories,
  }) async {
    final analytics = getAnalytics(
      timeWindow: timeWindow,
      categories: categories,
    );
    
    final summary = getPerformanceSummary();
    
    final exportData = {
      'export_timestamp': DateTime.now().toIso8601String(),
      'monitoring_config': _config.toJson(),
      'summary': summary.toJson(),
      'analytics': analytics.toJson(),
      'system_snapshots': _systemSnapshots
          .map((snapshot) => snapshot.toJson())
          .toList(),
    };
    
    if (format == 'csv') {
      return _exportToCSV(exportData);
    } else {
      return _exportToJSON(exportData);
    }
  }
  
  /// Stream of performance alerts
  Stream<PerformanceAlert> get alerts => _alertController.stream;
  
  /// Get real-time system stats
  Future<SystemStats> getCurrentSystemStats() async {
    return SystemStats(
      memoryUsageMB: _lastMemoryUsage / (1024 * 1024),
      cpuUsagePercent: _lastCpuUsage,
      timestamp: DateTime.now(),
      platformInfo: await _getPlatformInfo(),
    );
  }
  
  /// Clear all performance data
  void clearData() {
    _metrics.clear();
    _events.clear();
    _systemSnapshots.clear();
    _networkMetrics.clear();
    _customMetrics.clear();
    _memoryHistory.clear();
    _cpuHistory.clear();
    
    _totalNetworkRequests = 0;
    _failedNetworkRequests = 0;
    _totalBytesTransferred = 0;
    
    _emitAlert(PerformanceAlert.info('Performance data cleared'));
  }
  
  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _alertController.close();
  }
  
  // Private methods
  
  void _startSystemMonitoring() {
    _systemMonitorTimer = Timer.periodic(
      Duration(seconds: _config.systemMonitorIntervalSeconds),
      (_) => _captureSystemSnapshot(),
    );
  }
  
  void _startMetricsFlush() {
    _metricsFlushTimer = Timer.periodic(
      Duration(minutes: _config.metricsFlushIntervalMinutes),
      (_) => _flushMetrics(),
    );
  }
  
  Future<void> _captureSystemSnapshot() async {
    try {
      final snapshot = SystemSnapshot(
        timestamp: DateTime.now(),
        memoryUsageMB: _lastMemoryUsage / (1024 * 1024),
        cpuUsagePercent: _lastCpuUsage,
        activeIsolates: Isolate.current.hashCode, // Simplified
      );
      
      _systemSnapshots.add(snapshot);
      
      if (_systemSnapshots.length > _config.maxSystemSnapshots) {
        _systemSnapshots.removeFirst();
      }
      
    } catch (e) {
      _emitAlert(PerformanceAlert.error(
        'Failed to capture system snapshot',
        details: {'error': e.toString()},
      ));
    }
  }
  
  Future<void> _flushMetrics() async {
    try {
      final metricsData = {
        'timestamp': DateTime.now().toIso8601String(),
        'metrics': _metrics.map((key, value) => MapEntry(key, value.toJson())),
        'custom_metrics': _customMetrics.map((key, value) => 
            MapEntry(key, value.toJson())),
        'network_metrics': _networkMetrics.map((key, value) => 
            MapEntry(key, value.toJson())),
      };
      
      await _storage.setString(
        'performance_metrics_${DateTime.now().millisecondsSinceEpoch}',
        metricsData.toString(),
      );
      
    } catch (e) {
      _emitAlert(PerformanceAlert.error(
        'Failed to flush metrics',
        details: {'error': e.toString()},
      ));
    }
  }
  
  Future<void> _loadPersistedMetrics() async {
    // Implementation would load previously saved metrics
    // For now, this is a placeholder
  }
  
  void _updateMetrics(PerformanceEvent event) {
    final metrics = _metrics.putIfAbsent(
      event.category,
      () => PerformanceMetrics(category: event.category),
    );
    
    metrics.addEvent(event);
  }
  
  void _checkEventAlerts(PerformanceEvent event) {
    // Check for slow operations
    if (event.duration != null) {
      final durationMs = event.duration!.inMilliseconds;
      
      if (durationMs > _config.slowOperationThresholdMs) {
        _emitAlert(PerformanceAlert.warning(
          'Slow operation detected',
          details: {
            'operation': event.name,
            'category': event.category,
            'duration_ms': durationMs,
            'threshold_ms': _config.slowOperationThresholdMs,
          },
        ));
      }
    }
    
    // Check for error events
    if (event.metadata?['error'] != null) {
      _emitAlert(PerformanceAlert.error(
        'Error event recorded',
        details: {
          'operation': event.name,
          'category': event.category,
          'error': event.metadata!['error'],
        },
      ));
    }
  }
  
  void _emitAlert(PerformanceAlert alert) {
    _alertController.add(alert);
  }
  
  int _getTotalEventCount() {
    return _events.values.fold(0, (sum, events) => sum + events.length);
  }
  
  Map<String, double> _getAverageEventDurations() {
    final averages = <String, double>{};
    
    for (final entry in _events.entries) {
      final durations = entry.value
          .where((e) => e.duration != null)
          .map((e) => e.duration!.inMilliseconds)
          .toList();
      
      if (durations.isNotEmpty) {
        averages[entry.key] = durations.reduce((a, b) => a + b) / durations.length;
      }
    }
    
    return averages;
  }
  
  Map<String, dynamic> _getCustomMetricsSummary() {
    return _customMetrics.map((key, metric) => 
        MapEntry(key, metric.getSummary()));
  }
  
  List<PerformanceAlert> _getRecentAlerts() {
    // Implementation would return recent alerts
    // For now, return empty list
    return [];
  }
  
  EventAnalysis _analyzeEvents(List<PerformanceEvent> events) {
    final durations = events
        .where((e) => e.duration != null)
        .map((e) => e.duration!.inMilliseconds)
        .toList();
    
    durations.sort();
    
    return EventAnalysis(
      totalEvents: events.length,
      averageDurationMs: durations.isNotEmpty 
          ? durations.reduce((a, b) => a + b) / durations.length
          : 0.0,
      minDurationMs: durations.isNotEmpty ? durations.first.toDouble() : 0.0,
      maxDurationMs: durations.isNotEmpty ? durations.last.toDouble() : 0.0,
      p50DurationMs: durations.isNotEmpty 
          ? durations[durations.length ~/ 2].toDouble()
          : 0.0,
      p95DurationMs: durations.isNotEmpty 
          ? durations[(durations.length * 0.95).floor()].toDouble()
          : 0.0,
      errorCount: events.where((e) => e.metadata?['error'] != null).length,
    );
  }
  
  NetworkAnalytics _getNetworkAnalytics() {
    return NetworkAnalytics(
      totalRequests: _totalNetworkRequests,
      failedRequests: _failedNetworkRequests,
      successRate: _totalNetworkRequests > 0 
          ? (_totalNetworkRequests - _failedNetworkRequests) / _totalNetworkRequests
          : 0.0,
      totalBytesTransferred: _totalBytesTransferred,
      hostMetrics: Map.from(_networkMetrics),
    );
  }
  
  SystemAnalytics _getSystemAnalytics() {
    return SystemAnalytics(
      averageMemoryUsageMB: _memoryHistory.isNotEmpty
          ? _memoryHistory.reduce((a, b) => a + b) / _memoryHistory.length
          : 0.0,
      peakMemoryUsageMB: _memoryHistory.isNotEmpty
          ? _memoryHistory.reduce((a, b) => a > b ? a : b)
          : 0.0,
      averageCpuUsagePercent: _cpuHistory.isNotEmpty
          ? _cpuHistory.reduce((a, b) => a + b) / _cpuHistory.length
          : 0.0,
      peakCpuUsagePercent: _cpuHistory.isNotEmpty
          ? _cpuHistory.reduce((a, b) => a > b ? a : b)
          : 0.0,
      systemSnapshots: _systemSnapshots.length,
    );
  }
  
  Map<String, dynamic> _getCustomMetricsAnalytics() {
    return _customMetrics.map((key, metric) => 
        MapEntry(key, metric.getAnalytics()));
  }
  
  List<String> _generateRecommendations(
    Map<String, List<PerformanceEvent>> events,
  ) {
    final recommendations = <String>[];
    
    // Check for slow operations
    for (final entry in events.entries) {
      final slowEvents = entry.value.where((e) => 
          e.duration != null && 
          e.duration!.inMilliseconds > _config.slowOperationThresholdMs).length;
      
      if (slowEvents > entry.value.length * 0.1) {
        recommendations.add(
          'Consider optimizing ${entry.key} operations - ${slowEvents} slow events detected'
        );
      }
    }
    
    // Check memory usage
    if (_memoryHistory.isNotEmpty) {
      final avgMemory = _memoryHistory.reduce((a, b) => a + b) / _memoryHistory.length;
      if (avgMemory > _config.highMemoryThresholdMB * 0.8) {
        recommendations.add('Memory usage is approaching threshold - consider optimization');
      }
    }
    
    // Check network errors
    if (_totalNetworkRequests > 0) {
      final errorRate = _failedNetworkRequests / _totalNetworkRequests;
      if (errorRate > 0.05) {
        recommendations.add('High network error rate detected - check connectivity');
      }
    }
    
    return recommendations;
  }
  
  Future<Map<String, dynamic>> _getPlatformInfo() async {
    return {
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
      'is_debug': !const bool.fromEnvironment('dart.vm.product'),
    };
  }
  
  String _exportToJSON(Map<String, dynamic> data) {
    // Implementation would format as JSON
    return data.toString();
  }
  
  String _exportToCSV(Map<String, dynamic> data) {
    // Implementation would format as CSV
    return 'CSV export not implemented yet';
  }
}

/// Performance monitoring configuration
class PerformanceMonitorConfig {
  final bool enableSystemMonitoring;
  final bool enablePersistence;
  final int systemMonitorIntervalSeconds;
  final int metricsFlushIntervalMinutes;
  final int maxEventsPerCategory;
  final int maxHistorySize;
  final int maxSystemSnapshots;
  final int slowOperationThresholdMs;
  final int slowNetworkThresholdMs;
  final double highMemoryThresholdMB;
  final double highCpuThresholdPercent;
  
  const PerformanceMonitorConfig({
    this.enableSystemMonitoring = true,
    this.enablePersistence = true,
    this.systemMonitorIntervalSeconds = 10,
    this.metricsFlushIntervalMinutes = 5,
    this.maxEventsPerCategory = 1000,
    this.maxHistorySize = 100,
    this.maxSystemSnapshots = 100,
    this.slowOperationThresholdMs = 1000,
    this.slowNetworkThresholdMs = 3000,
    this.highMemoryThresholdMB = 500.0,
    this.highCpuThresholdPercent = 80.0,
  });
  
  factory PerformanceMonitorConfig.defaultConfig() {
    return const PerformanceMonitorConfig();
  }
  
  factory PerformanceMonitorConfig.production() {
    return const PerformanceMonitorConfig(
      systemMonitorIntervalSeconds = 30,
      metricsFlushIntervalMinutes = 10,
      maxEventsPerCategory = 500,
      slowOperationThresholdMs = 2000,
    );
  }
  
  factory PerformanceMonitorConfig.development() {
    return const PerformanceMonitorConfig(
      systemMonitorIntervalSeconds = 5,
      metricsFlushIntervalMinutes = 1,
      maxEventsPerCategory = 2000,
      slowOperationThresholdMs = 500,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'enable_system_monitoring': enableSystemMonitoring,
      'enable_persistence': enablePersistence,
      'system_monitor_interval_seconds': systemMonitorIntervalSeconds,
      'metrics_flush_interval_minutes': metricsFlushIntervalMinutes,
      'max_events_per_category': maxEventsPerCategory,
      'max_history_size': maxHistorySize,
      'max_system_snapshots': maxSystemSnapshots,
      'slow_operation_threshold_ms': slowOperationThresholdMs,
      'slow_network_threshold_ms': slowNetworkThresholdMs,
      'high_memory_threshold_mb': highMemoryThresholdMB,
      'high_cpu_threshold_percent': highCpuThresholdPercent,
    };
  }
}

/// Performance event
class PerformanceEvent {
  final String name;
  final String category;
  final Duration? duration;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
  
  PerformanceEvent({
    required this.name,
    required this.category,
    this.duration,
    DateTime? timestamp,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category': category,
      'duration_ms': duration?.inMilliseconds,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }
}

/// Performance timer for measuring operations
class PerformanceTimer {
  final String operation;
  final String category;
  final void Function(PerformanceEvent) onComplete;
  final DateTime _startTime;
  Map<String, dynamic>? _metadata;
  
  PerformanceTimer({
    required this.operation,
    required this.category,
    required this.onComplete,
  }) : _startTime = DateTime.now();
  
  /// Add metadata to the timer
  void addMetadata(String key, dynamic value) {
    _metadata ??= {};
    _metadata![key] = value;
  }
  
  /// Stop the timer and record the event
  void stop() {
    final duration = DateTime.now().difference(_startTime);
    final event = PerformanceEvent(
      name: operation,
      category: category,
      duration: duration,
      timestamp: _startTime,
      metadata: _metadata,
    );
    onComplete(event);
  }
}

/// Performance metrics for a category
class PerformanceMetrics {
  final String category;
  int eventCount = 0;
  int errorCount = 0;
  double totalDurationMs = 0.0;
  double minDurationMs = double.infinity;
  double maxDurationMs = 0.0;
  DateTime? firstEventTime;
  DateTime? lastEventTime;
  
  PerformanceMetrics({required this.category});
  
  void addEvent(PerformanceEvent event) {
    eventCount++;
    firstEventTime ??= event.timestamp;
    lastEventTime = event.timestamp;
    
    if (event.metadata?['error'] != null) {
      errorCount++;
    }
    
    if (event.duration != null) {
      final durationMs = event.duration!.inMilliseconds.toDouble();
      totalDurationMs += durationMs;
      minDurationMs = durationMs < minDurationMs ? durationMs : minDurationMs;
      maxDurationMs = durationMs > maxDurationMs ? durationMs : maxDurationMs;
    }
  }
  
  double get averageDurationMs => 
      eventCount > 0 ? totalDurationMs / eventCount : 0.0;
  
  double get errorRate => eventCount > 0 ? errorCount / eventCount : 0.0;
  
  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'event_count': eventCount,
      'error_count': errorCount,
      'error_rate': errorRate,
      'total_duration_ms': totalDurationMs,
      'average_duration_ms': averageDurationMs,
      'min_duration_ms': minDurationMs == double.infinity ? 0.0 : minDurationMs,
      'max_duration_ms': maxDurationMs,
      'first_event_time': firstEventTime?.toIso8601String(),
      'last_event_time': lastEventTime?.toIso8601String(),
    };
  }
}