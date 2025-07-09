import 'dart:collection';

/// Performance alert levels
enum AlertLevel {
  info,
  warning,
  error,
  critical,
}

/// Performance alert
class PerformanceAlert {
  final AlertLevel level;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic>? details;
  
  PerformanceAlert({
    required this.level,
    required this.message,
    DateTime? timestamp,
    this.details,
  }) : timestamp = timestamp ?? DateTime.now();
  
  factory PerformanceAlert.info(String message, {Map<String, dynamic>? details}) {
    return PerformanceAlert(
      level: AlertLevel.info,
      message: message,
      details: details,
    );
  }
  
  factory PerformanceAlert.warning(String message, {Map<String, dynamic>? details}) {
    return PerformanceAlert(
      level: AlertLevel.warning,
      message: message,
      details: details,
    );
  }
  
  factory PerformanceAlert.error(String message, {Map<String, dynamic>? details}) {
    return PerformanceAlert(
      level: AlertLevel.error,
      message: message,
      details: details,
    );
  }
  
  factory PerformanceAlert.critical(String message, {Map<String, dynamic>? details}) {
    return PerformanceAlert(
      level: AlertLevel.critical,
      message: message,
      details: details,
    );
  }
  
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
  final DateTime timestamp;
  final double memoryUsageMB;
  final double cpuUsagePercent;
  final int activeIsolates;
  final Map<String, dynamic>? additionalData;
  
  const SystemSnapshot({
    required this.timestamp,
    required this.memoryUsageMB,
    required this.cpuUsagePercent,
    required this.activeIsolates,
    this.additionalData,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'memory_usage_mb': memoryUsageMB,
      'cpu_usage_percent': cpuUsagePercent,
      'active_isolates': activeIsolates,
      'additional_data': additionalData,
    };
  }
  
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
  final String host;
  int totalRequests = 0;
  int successfulRequests = 0;
  int failedRequests = 0;
  int totalBytes = 0;
  double totalDurationMs = 0.0;
  double minDurationMs = double.infinity;
  double maxDurationMs = 0.0;
  final Map<String, int> statusCodes = {};
  final Map<String, int> methods = {};
  final List<String> recentErrors = [];
  
  NetworkRequestMetrics({required this.host});
  
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
  
  double get averageDurationMs => 
      totalRequests > 0 ? totalDurationMs / totalRequests : 0.0;
  
  double get successRate => 
      totalRequests > 0 ? successfulRequests / totalRequests : 0.0;
  
  double get averageBytesPerRequest => 
      totalRequests > 0 ? totalBytes / totalRequests : 0.0;
  
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
  counter,
  gauge,
  histogram,
}

/// Custom metric
class CustomMetric {
  final String name;
  final MetricType type;
  final String? unit;
  final Queue<MetricValue> _values = Queue();
  double _currentValue = 0.0;
  
  CustomMetric({
    required this.name,
    this.type = MetricType.histogram,
    this.unit,
  });
  
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
  
  void setValue(double value) {
    _currentValue = value;
    addValue(value);
  }
  
  double get currentValue => _currentValue;
  
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
  final double value;
  final DateTime timestamp;
  
  const MetricValue({
    required this.value,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Network summary
class NetworkSummary {
  final int totalRequests;
  final int failedRequests;
  final int totalBytesTransferred;
  final List<String> hosts;
  
  const NetworkSummary({
    required this.totalRequests,
    required this.failedRequests,
    required this.totalBytesTransferred,
    required this.hosts,
  });
  
  double get successRate => totalRequests > 0 
      ? (totalRequests - failedRequests) / totalRequests 
      : 0.0;
  
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
  final bool isMonitoring;
  final Duration uptime;
  final int totalEvents;
  final double memoryUsageMB;
  final double cpuUsagePercent;
  final NetworkSummary networkRequests;
  final Map<String, double> averageEventDurations;
  final Map<String, dynamic> customMetrics;
  final List<PerformanceAlert> alerts;
  
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
  final int totalEvents;
  final double averageDurationMs;
  final double minDurationMs;
  final double maxDurationMs;
  final double p50DurationMs;
  final double p95DurationMs;
  final int errorCount;
  
  const EventAnalysis({
    required this.totalEvents,
    required this.averageDurationMs,
    required this.minDurationMs,
    required this.maxDurationMs,
    required this.p50DurationMs,
    required this.p95DurationMs,
    required this.errorCount,
  });
  
  double get errorRate => totalEvents > 0 ? errorCount / totalEvents : 0.0;
  
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
  final int totalRequests;
  final int failedRequests;
  final double successRate;
  final int totalBytesTransferred;
  final Map<String, NetworkRequestMetrics> hostMetrics;
  
  const NetworkAnalytics({
    required this.totalRequests,
    required this.failedRequests,
    required this.successRate,
    required this.totalBytesTransferred,
    required this.hostMetrics,
  });
  
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
  final double averageMemoryUsageMB;
  final double peakMemoryUsageMB;
  final double averageCpuUsagePercent;
  final double peakCpuUsagePercent;
  final int systemSnapshots;
  
  const SystemAnalytics({
    required this.averageMemoryUsageMB,
    required this.peakMemoryUsageMB,
    required this.averageCpuUsagePercent,
    required this.peakCpuUsagePercent,
    required this.systemSnapshots,
  });
  
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
  final Duration? timeWindow;
  final List<String> categories;
  final Map<String, EventAnalysis> eventBreakdown;
  final NetworkAnalytics networkAnalytics;
  final SystemAnalytics systemAnalytics;
  final Map<String, dynamic> customMetricsAnalytics;
  final List<String> recommendations;
  
  const PerformanceAnalytics({
    this.timeWindow,
    required this.categories,
    required this.eventBreakdown,
    required this.networkAnalytics,
    required this.systemAnalytics,
    required this.customMetricsAnalytics,
    required this.recommendations,
  });
  
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
  final double memoryUsageMB;
  final double cpuUsagePercent;
  final DateTime timestamp;
  final Map<String, dynamic> platformInfo;
  
  const SystemStats({
    required this.memoryUsageMB,
    required this.cpuUsagePercent,
    required this.timestamp,
    required this.platformInfo,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'memory_usage_mb': memoryUsageMB,
      'cpu_usage_percent': cpuUsagePercent,
      'timestamp': timestamp.toIso8601String(),
      'platform_info': platformInfo,
    };
  }
}