import 'dart:collection';

/// Performance alert levels
enum AlertLevel {
  /// The info level.
  info,
  /// The warning level.
  warning,
  /// The error level.
  error,
  /// The critical level.
  critical,
}

/// Performance alert
class PerformanceAlert {
  /// Severity of the alert.
  final AlertLevel level;
  /// What happened.
  final String message;
  /// When it happened.
  final DateTime timestamp;
  /// Extra structured detail, or null.
  final Map<String, dynamic>? details;
  
  /// Creates an alert.
  PerformanceAlert({
    required this.level,
    required this.message,
    DateTime? timestamp,
    this.details,
  }) : timestamp = timestamp ?? DateTime.now();
  
  /// Builds the info variant.
  factory PerformanceAlert.info(String message, {Map<String, dynamic>? details}) {
    return PerformanceAlert(
      level: AlertLevel.info,
      message: message,
      details: details,
    );
  }
  
  /// Builds the warning variant.
  factory PerformanceAlert.warning(String message, {Map<String, dynamic>? details}) {
    return PerformanceAlert(
      level: AlertLevel.warning,
      message: message,
      details: details,
    );
  }
  
  /// Builds the error variant.
  factory PerformanceAlert.error(String message, {Map<String, dynamic>? details}) {
    return PerformanceAlert(
      level: AlertLevel.error,
      message: message,
      details: details,
    );
  }
  
  /// Builds the critical variant.
  factory PerformanceAlert.critical(String message, {Map<String, dynamic>? details}) {
    return PerformanceAlert(
      level: AlertLevel.critical,
      message: message,
      details: details,
    );
  }
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'level': level.name,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'details': details,
    };
  }
}

/// System snapshot for monitoring
class SystemSnapshot {
  /// When it happened.
  final DateTime timestamp;
  /// Memory usage, in megabytes.
  final double memoryUsageMB;
  /// Cpu usage, in percent.
  final double cpuUsagePercent;
  /// Number of isolates running.
  final int activeIsolates;
  /// Extra platform data, or null.
  final Map<String, dynamic>? additionalData;
  
  /// Creates a system snapshot.
  const SystemSnapshot({
    required this.timestamp,
    required this.memoryUsageMB,
    required this.cpuUsagePercent,
    required this.activeIsolates,
    this.additionalData,
  });
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'memory_usage_mb': memoryUsageMB,
      'cpu_usage_percent': cpuUsagePercent,
      'active_isolates': activeIsolates,
      'additional_data': additionalData,
    };
  }
  
  /// Builds the from json variant.
  factory SystemSnapshot.fromJson(Map<String, dynamic> json) {
    return SystemSnapshot(
      timestamp: DateTime.parse(json['timestamp']),
      memoryUsageMB: (json['memory_usage_mb'] as num).toDouble(),
      cpuUsagePercent: (json['cpu_usage_percent'] as num).toDouble(),
      activeIsolates: json['active_isolates'] as int,
      additionalData: json['additional_data'] as Map<String, dynamic>?,
    );
  }
}

/// Network request metrics
class NetworkRequestMetrics {
  /// Host the metrics are for.
  final String host;
  /// Total requests.
  int totalRequests = 0;
  /// Requests with a status from 200 to 399 and no error.
  int successfulRequests = 0;
  /// Requests that failed: any other status, or an error.
  int failedRequests = 0;
  /// Total bytes transferred.
  int totalBytes = 0;
  /// Total duration, in milliseconds.
  double totalDurationMs = 0.0;
  /// Shortest request or event duration, in milliseconds; infinite until one is recorded.
  double minDurationMs = double.infinity;
  /// Max duration, in milliseconds.
  double maxDurationMs = 0.0;
  /// Request count per HTTP status code.
  final Map<String, int> statusCodes = {};
  /// Request count per HTTP method.
  final Map<String, int> methods = {};
  /// The most recent error messages, up to ten.
  final List<String> recentErrors = [];
  
  /// Creates metrics for [host].
  NetworkRequestMetrics({required this.host});
  
  /// Records one request: counts, bytes, duration, status, method and any error.
  void addRequest({
    required String method,
    required int statusCode,
    required Duration duration,
    required int bytes,
    String? error,
  }) {
    totalRequests++;
    totalBytes += bytes;
    
    final durationMs = duration.inMilliseconds.toDouble();
    totalDurationMs += durationMs;
    minDurationMs = durationMs < minDurationMs ? durationMs : minDurationMs;
    maxDurationMs = durationMs > maxDurationMs ? durationMs : maxDurationMs;
    
    if (statusCode >= 200 && statusCode < 400 && error == null) {
      successfulRequests++;
    } else {
      failedRequests++;
      if (error != null) {
        recentErrors.add(error);
        if (recentErrors.length > 10) {
          recentErrors.removeAt(0);
        }
      }
    }
    
    statusCodes[statusCode.toString()] = (statusCodes[statusCode.toString()] ?? 0) + 1;
    methods[method] = (methods[method] ?? 0) + 1;
  }
  
  /// Mean duration, in milliseconds.
  double get averageDurationMs => 
      totalRequests > 0 ? totalDurationMs / totalRequests : 0.0;
  
  /// Share of requests that succeeded, from 0 to 1.
  double get successRate => 
      totalRequests > 0 ? successfulRequests / totalRequests : 0.0;
  
  /// Mean bytes transferred per request.
  double get averageBytesPerRequest => 
      totalRequests > 0 ? totalBytes / totalRequests : 0.0;
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'total_requests': totalRequests,
      'successful_requests': successfulRequests,
      'failed_requests': failedRequests,
      'success_rate': successRate,
      'total_bytes': totalBytes,
      'average_bytes_per_request': averageBytesPerRequest,
      'total_duration_ms': totalDurationMs,
      'average_duration_ms': averageDurationMs,
      'min_duration_ms': minDurationMs == double.infinity ? 0.0 : minDurationMs,
      'max_duration_ms': maxDurationMs,
      'status_codes': statusCodes,
      'methods': methods,
      'recent_errors': recentErrors,
    };
  }
}

/// Custom metric types
enum MetricType {
  /// The counter type.
  counter,
  /// The gauge type.
  gauge,
  /// The histogram type.
  histogram,
}

/// Custom metric
class CustomMetric {
  /// Name of the metric.
  final String name;
  /// Kind of metric; it decides how values accumulate.
  final MetricType type;
  /// Unit of the metric's values, or null.
  final String? unit;
  final Queue<MetricValue> _values = Queue();
  double _currentValue = 0.0;
  
  /// Creates a metric; the type defaults to histogram.
  CustomMetric({
    required this.name,
    this.type = MetricType.histogram,
    this.unit,
  });
  
  /// Records [value] and updates the current value by metric type.
  ///
  /// A counter adds it and a gauge replaces the current value. History keeps the last 1000 values.
  void addValue(double value) {
    final metricValue = MetricValue(
      value: value,
      timestamp: DateTime.now(),
    );
    
    _values.add(metricValue);
    
    if (type == MetricType.counter) {
      _currentValue += value;
    } else if (type == MetricType.gauge) {
      _currentValue = value;
    }
    
    // Limit history size
    if (_values.length > 1000) {
      _values.removeFirst();
    }
  }
  
  /// Sets the current value to [value] and records it.
  void setValue(double value) {
    _currentValue = value;
    addValue(value);
  }
  
  /// Current value of the metric.
  double get currentValue => _currentValue;
  
  /// Summary of the metric: name, type, unit and current value.
  ///
  /// When values exist it also has count, min, max, average, p50 and p95.
  Map<String, dynamic> getSummary() {
    if (_values.isEmpty) {
      return {
        'name': name,
        'type': type.name,
        'unit': unit,
        'current_value': _currentValue,
        'value_count': 0,
      };
    }
    
    final values = _values.map((v) => v.value).toList();
    values.sort();
    
    return {
      'name': name,
      'type': type.name,
      'unit': unit,
      'current_value': _currentValue,
      'value_count': values.length,
      'min': values.first,
      'max': values.last,
      'average': values.reduce((a, b) => a + b) / values.length,
      'p50': values[values.length ~/ 2],
      'p95': values[(values.length * 0.95).floor()],
    };
  }
  
  /// The summary plus further analytics over the recorded values.
  Map<String, dynamic> getAnalytics() {
    final summary = getSummary();
    
    if (_values.isEmpty) {
      return summary;
    }
    
    // Calculate trend (simple linear regression slope)
    final n = _values.length;
    if (n < 2) {
      return {...summary, 'trend': 'insufficient_data'};
    }
    
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    
    for (int i = 0; i < n; i++) {
      final x = i.toDouble();
      final y = _values.elementAt(i).value;
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
    }
    
    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    
    String trend;
    if (slope > 0.01) {
      trend = 'increasing';
    } else if (slope < -0.01) {
      trend = 'decreasing';
    } else {
      trend = 'stable';
    }
    
    return {
      ...summary,
      'trend': trend,
      'trend_slope': slope,
    };
  }
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type.name,
      'unit': unit,
      'current_value': _currentValue,
      'values': _values.map((v) => v.toJson()).toList(),
    };
  }
}

/// Metric value with timestamp
class MetricValue {
  /// The recorded value.
  final double value;
  /// When it happened.
  final DateTime timestamp;
  
  /// Creates a metric value.
  const MetricValue({
    required this.value,
    required this.timestamp,
  });
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Network summary
class NetworkSummary {
  /// Total requests.
  final int totalRequests;
  /// Failed requests.
  final int failedRequests;
  /// Total bytes transferred.
  final int totalBytesTransferred;
  /// Hosts that were contacted.
  final List<String> hosts;
  
  /// Creates a network summary.
  const NetworkSummary({
    required this.totalRequests,
    required this.failedRequests,
    required this.totalBytesTransferred,
    required this.hosts,
  });
  
  /// Share of requests that succeeded, from 0 to 1.
  double get successRate => totalRequests > 0 
      ? (totalRequests - failedRequests) / totalRequests 
      : 0.0;
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'total_requests': totalRequests,
      'failed_requests': failedRequests,
      'success_rate': successRate,
      'total_bytes_transferred': totalBytesTransferred,
      'hosts': hosts,
    };
  }
}

/// Performance summary
class PerformanceSummary {
  /// Whether monitoring is running.
  final bool isMonitoring;
  /// Time since monitoring started.
  final Duration uptime;
  /// Number of events recorded.
  final int totalEvents;
  /// Memory usage, in megabytes.
  final double memoryUsageMB;
  /// Cpu usage, in percent.
  final double cpuUsagePercent;
  /// Network request summary.
  final NetworkSummary networkRequests;
  /// Mean event duration per category, in milliseconds.
  final Map<String, double> averageEventDurations;
  /// Summaries of the custom metrics.
  final Map<String, dynamic> customMetrics;
  /// Alerts raised.
  final List<PerformanceAlert> alerts;
  
  /// Creates a performance summary.
  const PerformanceSummary({
    required this.isMonitoring,
    required this.uptime,
    required this.totalEvents,
    required this.memoryUsageMB,
    required this.cpuUsagePercent,
    required this.networkRequests,
    required this.averageEventDurations,
    required this.customMetrics,
    required this.alerts,
  });
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'is_monitoring': isMonitoring,
      'uptime_seconds': uptime.inSeconds,
      'total_events': totalEvents,
      'memory_usage_mb': memoryUsageMB,
      'cpu_usage_percent': cpuUsagePercent,
      'network_requests': networkRequests.toJson(),
      'average_event_durations': averageEventDurations,
      'custom_metrics': customMetrics,
      'alerts': alerts.map((a) => a.toJson()).toList(),
    };
  }
}

/// Event analysis
class EventAnalysis {
  /// Number of events recorded.
  final int totalEvents;
  /// Mean event duration, in milliseconds.
  final double averageDurationMs;
  /// Shortest event duration, in milliseconds.
  final double minDurationMs;
  /// Longest event duration, in milliseconds.
  final double maxDurationMs;
  /// Median event duration, in milliseconds.
  final double p50DurationMs;
  /// 95th percentile event duration, in milliseconds.
  final double p95DurationMs;
  /// Number of events that carried an error.
  final int errorCount;
  
  /// Creates an event analysis.
  const EventAnalysis({
    required this.totalEvents,
    required this.averageDurationMs,
    required this.minDurationMs,
    required this.maxDurationMs,
    required this.p50DurationMs,
    required this.p95DurationMs,
    required this.errorCount,
  });
  
  /// Share of events with an error, from 0 to 1.
  double get errorRate => totalEvents > 0 ? errorCount / totalEvents : 0.0;
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'total_events': totalEvents,
      'average_duration_ms': averageDurationMs,
      'min_duration_ms': minDurationMs,
      'max_duration_ms': maxDurationMs,
      'p50_duration_ms': p50DurationMs,
      'p95_duration_ms': p95DurationMs,
      'error_count': errorCount,
      'error_rate': errorRate,
    };
  }
}

/// Network analytics
class NetworkAnalytics {
  /// Total requests.
  final int totalRequests;
  /// Failed requests.
  final int failedRequests;
  /// Share of requests that succeeded, from 0 to 1.
  final double successRate;
  /// Total bytes transferred.
  final int totalBytesTransferred;
  /// Metrics per host.
  final Map<String, NetworkRequestMetrics> hostMetrics;
  
  /// Creates a network analytics.
  const NetworkAnalytics({
    required this.totalRequests,
    required this.failedRequests,
    required this.successRate,
    required this.totalBytesTransferred,
    required this.hostMetrics,
  });
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'total_requests': totalRequests,
      'failed_requests': failedRequests,
      'success_rate': successRate,
      'total_bytes_transferred': totalBytesTransferred,
      'host_metrics': hostMetrics.map((key, value) => 
          MapEntry(key, value.toJson())),
    };
  }
}

/// System analytics
class SystemAnalytics {
  /// Mean memory usage, in megabytes.
  final double averageMemoryUsageMB;
  /// Peak memory usage, in megabytes.
  final double peakMemoryUsageMB;
  /// Mean CPU usage, in percent.
  final double averageCpuUsagePercent;
  /// Peak CPU usage, in percent.
  final double peakCpuUsagePercent;
  /// Number of system snapshots the figures come from.
  final int systemSnapshots;
  
  /// Creates a system analytics.
  const SystemAnalytics({
    required this.averageMemoryUsageMB,
    required this.peakMemoryUsageMB,
    required this.averageCpuUsagePercent,
    required this.peakCpuUsagePercent,
    required this.systemSnapshots,
  });
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'average_memory_usage_mb': averageMemoryUsageMB,
      'peak_memory_usage_mb': peakMemoryUsageMB,
      'average_cpu_usage_percent': averageCpuUsagePercent,
      'peak_cpu_usage_percent': peakCpuUsagePercent,
      'system_snapshots': systemSnapshots,
    };
  }
}

/// Performance analytics
class PerformanceAnalytics {
  /// Window the analytics cover, or null for all recorded data.
  final Duration? timeWindow;
  /// Event categories included.
  final List<String> categories;
  /// Analysis per event category.
  final Map<String, EventAnalysis> eventBreakdown;
  /// Network analytics.
  final NetworkAnalytics networkAnalytics;
  /// System analytics.
  final SystemAnalytics systemAnalytics;
  /// Summaries of the custom metrics.
  final Map<String, dynamic> customMetricsAnalytics;
  /// Suggested actions.
  final List<String> recommendations;
  
  /// Creates a performance analytics.
  const PerformanceAnalytics({
    this.timeWindow,
    required this.categories,
    required this.eventBreakdown,
    required this.networkAnalytics,
    required this.systemAnalytics,
    required this.customMetricsAnalytics,
    required this.recommendations,
  });
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'time_window_seconds': timeWindow?.inSeconds,
      'categories': categories,
      'event_breakdown': eventBreakdown.map((key, value) => 
          MapEntry(key, value.toJson())),
      'network_analytics': networkAnalytics.toJson(),
      'system_analytics': systemAnalytics.toJson(),
      'custom_metrics_analytics': customMetricsAnalytics,
      'recommendations': recommendations,
    };
  }
}

/// System stats
class SystemStats {
  /// Memory usage, in megabytes.
  final double memoryUsageMB;
  /// Cpu usage, in percent.
  final double cpuUsagePercent;
  /// When it happened.
  final DateTime timestamp;
  /// Platform details.
  final Map<String, dynamic> platformInfo;
  
  /// Creates a system stats.
  const SystemStats({
    required this.memoryUsageMB,
    required this.cpuUsagePercent,
    required this.timestamp,
    required this.platformInfo,
  });
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'memory_usage_mb': memoryUsageMB,
      'cpu_usage_percent': cpuUsagePercent,
      'timestamp': timestamp.toIso8601String(),
      'platform_info': platformInfo,
    };
  }
}