import 'dart:async';
import 'monitoring_models.dart';
import 'performance_monitor.dart';

/// Dashboard update types
abstract class DashboardUpdate {
  /// When the update was created.
  final DateTime timestamp = DateTime.now();
  
  /// Builds the update emitted when the dashboard starts.
  factory DashboardUpdate.started() = DashboardStartedUpdate;
  /// Builds the update emitted when the dashboard stops.
  factory DashboardUpdate.stopped() = DashboardStoppedUpdate;
  /// Builds the update emitted when a widget is added.
  factory DashboardUpdate.widgetAdded(String widgetId) = WidgetAddedUpdate;
  /// Builds the update emitted when a widget is removed.
  factory DashboardUpdate.widgetRemoved(String widgetId) = WidgetRemovedUpdate;
  /// Builds the update emitted when a widget's data is updated.
  factory DashboardUpdate.widgetUpdated(String widgetId) = WidgetUpdatedUpdate;
  /// Builds the update emitted when a widget fails.
  factory DashboardUpdate.widgetError(String widgetId, String error) = WidgetErrorUpdate;
  /// Builds the update emitted after every widget is updated.
  factory DashboardUpdate.allWidgetsUpdated() = AllWidgetsUpdatedUpdate;
}

/// Emitted when the dashboard starts.
class DashboardStartedUpdate extends DashboardUpdate {}
/// Emitted when the dashboard stops.
class DashboardStoppedUpdate extends DashboardUpdate {}

/// Emitted when a widget is added.
class WidgetAddedUpdate extends DashboardUpdate {
  /// Id of the widget concerned.
  final String widgetId;
  /// Creates the update for [widgetId].
  WidgetAddedUpdate(this.widgetId);
}

/// Emitted when a widget is removed.
class WidgetRemovedUpdate extends DashboardUpdate {
  /// Id of the widget concerned.
  final String widgetId;
  /// Creates the update for [widgetId].
  WidgetRemovedUpdate(this.widgetId);
}

/// Emitted when a widget's data is updated.
class WidgetUpdatedUpdate extends DashboardUpdate {
  /// Id of the widget concerned.
  final String widgetId;
  /// Creates the update for [widgetId].
  WidgetUpdatedUpdate(this.widgetId);
}

/// Emitted when a widget fails.
class WidgetErrorUpdate extends DashboardUpdate {
  /// Id of the widget concerned.
  final String widgetId;
  /// Description of the failure.
  final String error;
  /// Creates the update for [widgetId] with [error].
  WidgetErrorUpdate(this.widgetId, this.error);
}

/// Emitted after every widget is updated.
class AllWidgetsUpdatedUpdate extends DashboardUpdate {}

/// Dashboard summary
class DashboardSummary {
  /// Whether the dashboard is running.
  final bool isActive;
  /// Time since the dashboard started.
  final Duration uptime;
  /// Number of performance events recorded.
  final int totalEvents;
  /// Number of alerts raised.
  final int alertCount;
  /// Memory usage, in megabytes.
  final double memoryUsageMB;
  /// CPU usage, in percent.
  final double cpuUsagePercent;
  /// Share of network requests that succeeded, from 0 to 1.
  final double networkSuccessRate;
  /// Number of widgets on the dashboard.
  final int widgetCount;
  /// The most recent insights.
  final List<AnalyticsInsight> recentInsights;
  
  /// Creates a summary; every field is required.
  const DashboardSummary({
    required this.isActive,
    required this.uptime,
    required this.totalEvents,
    required this.alertCount,
    required this.memoryUsageMB,
    required this.cpuUsagePercent,
    required this.networkSuccessRate,
    required this.widgetCount,
    required this.recentInsights,
  });
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'is_active': isActive,
      'uptime_seconds': uptime.inSeconds,
      'total_events': totalEvents,
      'alert_count': alertCount,
      'memory_usage_mb': memoryUsageMB,
      'cpu_usage_percent': cpuUsagePercent,
      'network_success_rate': networkSuccessRate,
      'widget_count': widgetCount,
      'recent_insights': recentInsights.map((i) => i.toJson()).toList(),
    };
  }
}

/// Analytics insight types
enum InsightType {
  /// Performance insight.
  performance,
  /// Reliability insight.
  reliability,
  /// Security insight.
  security,
  /// Usage insight.
  usage,
  /// Insight raised from an alert.
  alert,
  /// Insight about a trend.
  trend,
}

/// Analytics insight severity
enum InsightSeverity {
  /// Informational.
  info,
  /// Needs attention.
  warning,
  /// Something is failing.
  error,
  /// Needs immediate attention.
  critical,
}

/// Analytics insight
class AnalyticsInsight {
  /// Kind of insight.
  final InsightType type;
  /// How serious the insight is.
  final InsightSeverity severity;
  /// Short headline of the insight.
  final String title;
  /// Explanation of the insight.
  final String description;
  /// Suggested action.
  final String recommendation;
  /// When the insight was produced.
  final DateTime timestamp;
  /// Extra structured detail, or null.
  final Map<String, dynamic>? metadata;
  
  /// Creates an insight.
  AnalyticsInsight({
    required this.type,
    required this.severity,
    required this.title,
    required this.description,
    required this.recommendation,
    DateTime? timestamp,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'severity': severity.name,
      'title': title,
      'description': description,
      'recommendation': recommendation,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }
}

/// Analytics report
class AnalyticsReport {
  /// Unique id of the report.
  final String id;
  /// Title of the report.
  final String title;
  /// When the report was generated.
  final DateTime generatedAt;
  /// Window the report covers, or null for all recorded data.
  final Duration? timeWindow;
  /// Event categories included, or null for all.
  final List<String>? categories;
  /// Output format of the report.
  final String format;
  /// Overall performance summary.
  final PerformanceSummary summary;
  /// Detailed performance analytics.
  final PerformanceAnalytics analytics;
  /// Insights included in the report.
  final List<AnalyticsInsight> insights;
  /// Suggested actions across the report.
  final List<String> recommendations;
  
  /// Creates a report; every field is required.
  const AnalyticsReport({
    required this.id,
    required this.title,
    required this.generatedAt,
    this.timeWindow,
    this.categories,
    required this.format,
    required this.summary,
    required this.analytics,
    required this.insights,
    required this.recommendations,
  });
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'generated_at': generatedAt.toIso8601String(),
      'time_window_seconds': timeWindow?.inSeconds,
      'categories': categories,
      'format': format,
      'summary': summary.toJson(),
      'analytics': analytics.toJson(),
      'insights': insights.map((i) => i.toJson()).toList(),
      'recommendations': recommendations,
    };
  }
}

/// Trend direction
enum TrendDirection {
  /// The value is rising.
  increasing,
  /// The value is falling.
  decreasing,
  /// The value is steady.
  stable,
  /// The value swings widely.
  volatile,
}

/// Performance trends
class PerformanceTrends {
  /// Direction of memory usage.
  final TrendDirection memoryTrend;
  /// Direction of CPU usage.
  final TrendDirection cpuTrend;
  /// Direction of network activity.
  final TrendDirection networkTrend;
  /// Direction of the error rate.
  final TrendDirection errorTrend;
  /// When the value was calculated.
  final DateTime calculatedAt;
  /// How far back the trends look.
  final Duration lookbackDuration;
  
  /// Creates trends; every field is required.
  const PerformanceTrends({
    required this.memoryTrend,
    required this.cpuTrend,
    required this.networkTrend,
    required this.errorTrend,
    required this.calculatedAt,
    required this.lookbackDuration,
  });
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'memory_trend': memoryTrend.name,
      'cpu_trend': cpuTrend.name,
      'network_trend': networkTrend.name,
      'error_trend': errorTrend.name,
      'calculated_at': calculatedAt.toIso8601String(),
      'lookback_duration_seconds': lookbackDuration.inSeconds,
    };
  }
}

/// Real-time metrics
class RealTimeMetrics {
  /// When the metrics were sampled.
  final DateTime timestamp;
  /// Memory usage, in megabytes.
  final double memoryUsageMB;
  /// CPU usage, in percent.
  final double cpuUsagePercent;
  /// Network request summary.
  final NetworkSummary networkRequests;
  /// Number of events in progress.
  final int activeEvents;
  /// Highest current alert level.
  final AlertLevel alertLevel;
  /// Current trends.
  final PerformanceTrends trends;
  
  /// Creates real-time metrics; every field is required.
  const RealTimeMetrics({
    required this.timestamp,
    required this.memoryUsageMB,
    required this.cpuUsagePercent,
    required this.networkRequests,
    required this.activeEvents,
    required this.alertLevel,
    required this.trends,
  });
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'memory_usage_mb': memoryUsageMB,
      'cpu_usage_percent': cpuUsagePercent,
      'network_requests': networkRequests.toJson(),
      'active_events': activeEvents,
      'alert_level': alertLevel.name,
      'trends': trends.toJson(),
    };
  }
}

/// Health score levels
enum HealthLevel {
  /// Excellent health.
  excellent,
  /// Good health.
  good,
  /// Fair health.
  fair,
  /// Poor health.
  poor,
  /// Critical health.
  critical,
}

/// Health score
class HealthScore {
  /// Overall health score.
  final double score;
  /// Health level the score maps to.
  final HealthLevel level;
  /// Per-factor scores that make up the overall score.
  final Map<String, double> factors;
  /// When the value was calculated.
  final DateTime calculatedAt;
  
  /// Creates a score; every field is required.
  const HealthScore({
    required this.score,
    required this.level,
    required this.factors,
    required this.calculatedAt,
  });
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'score': score,
      'level': level.name,
      'factors': factors,
      'calculated_at': calculatedAt.toIso8601String(),
    };
  }
}

/// Base dashboard widget
abstract class DashboardWidget {
  /// Unique id of the widget.
  final String id;
  /// Title of the widget.
  final String title;
  /// Description of the widget.
  final String description;
  /// When the widget was created.
  final DateTime createdAt;
  /// When the widget's data was last refreshed.
  DateTime lastUpdatedAt;
  /// Data the widget currently displays.
  Map<String, dynamic> data = {};
  /// Whether the widget is refreshing its data.
  bool isLoading = false;
  /// Description of the last failure, or null.
  String? error;
  
  /// Creates a widget; `lastUpdatedAt` starts at the creation time.
  DashboardWidget({
    required this.id,
    required this.title,
    required this.description,
  })  : createdAt = DateTime.now(),
        lastUpdatedAt = DateTime.now();
  
  /// Refreshes the widget data from the performance monitor.
  Future<void> updateData(PerformanceMonitor monitor);
  
  /// Get widget configuration
  Map<String, dynamic> getConfig() => {};
  
  /// Set widget configuration
  void setConfig(Map<String, dynamic> config) {}
  
  /// Convert widget to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'last_updated_at': lastUpdatedAt.toIso8601String(),
      'data': data,
      'is_loading': isLoading,
      'error': error,
      'config': getConfig(),
    };
  }
}

/// System overview widget
class SystemOverviewWidget extends DashboardWidget {
  /// Creates the system overview widget.
  SystemOverviewWidget()
      : super(
          id: 'system_overview',
          title: 'System Overview',
          description: 'Real-time system performance metrics',
        );
  
  @override
  Future<void> updateData(PerformanceMonitor monitor) async {
    isLoading = true;
    error = null;
    
    try {
      final summary = monitor.getPerformanceSummary();
      final systemStats = await monitor.getCurrentSystemStats();
      
      data = {
        'memory_usage_mb': systemStats.memoryUsageMB,
        'cpu_usage_percent': systemStats.cpuUsagePercent,
        'uptime_seconds': summary.uptime.inSeconds,
        'total_events': summary.totalEvents,
        'alert_count': summary.alerts.length,
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      lastUpdatedAt = DateTime.now();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
    }
  }
}

/// Network performance widget
class NetworkPerformanceWidget extends DashboardWidget {
  /// Creates the network performance widget.
  NetworkPerformanceWidget()
      : super(
          id: 'network_performance',
          title: 'Network Performance',
          description: 'Network request metrics and success rates',
        );
  
  @override
  Future<void> updateData(PerformanceMonitor monitor) async {
    isLoading = true;
    error = null;
    
    try {
      final summary = monitor.getPerformanceSummary();
      final networkSummary = summary.networkRequests;
      
      data = {
        'total_requests': networkSummary.totalRequests,
        'failed_requests': networkSummary.failedRequests,
        'success_rate': networkSummary.successRate,
        'total_bytes_transferred': networkSummary.totalBytesTransferred,
        'active_hosts': networkSummary.hosts.length,
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      lastUpdatedAt = DateTime.now();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
    }
  }
}

/// Event timeline widget
class EventTimelineWidget extends DashboardWidget {
  /// Creates the event timeline widget.
  EventTimelineWidget()
      : super(
          id: 'event_timeline',
          title: 'Event Timeline',
          description: 'Recent performance events and their durations',
        );
  
  @override
  Future<void> updateData(PerformanceMonitor monitor) async {
    isLoading = true;
    error = null;
    
    try {
      final analytics = monitor.getAnalytics(
        timeWindow: const Duration(minutes: 30),
      );
      
      final eventSummary = <String, Map<String, dynamic>>{};
      
      for (final entry in analytics.eventBreakdown.entries) {
        eventSummary[entry.key] = {
          'total_events': entry.value.totalEvents,
          'average_duration_ms': entry.value.averageDurationMs,
          'error_count': entry.value.errorCount,
          'error_rate': entry.value.errorRate,
        };
      }
      
      data = {
        'event_summary': eventSummary,
        'time_window_minutes': 30,
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      lastUpdatedAt = DateTime.now();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
    }
  }
}

/// Alert summary widget
class AlertSummaryWidget extends DashboardWidget {
  /// Creates the alert summary widget.
  AlertSummaryWidget()
      : super(
          id: 'alert_summary',
          title: 'Alert Summary',
          description: 'Current alerts and warning status',
        );
  
  @override
  Future<void> updateData(PerformanceMonitor monitor) async {
    isLoading = true;
    error = null;
    
    try {
      final summary = monitor.getPerformanceSummary();
      final alerts = summary.alerts;
      
      final alertCounts = <String, int>{
        'info': 0,
        'warning': 0,
        'error': 0,
        'critical': 0,
      };
      
      for (final alert in alerts) {
        alertCounts[alert.level.name] = 
            (alertCounts[alert.level.name] ?? 0) + 1;
      }
      
      data = {
        'total_alerts': alerts.length,
        'alert_counts': alertCounts,
        'recent_alerts': alerts
            .take(5)
            .map((a) => {
              'level': a.level.name,
              'message': a.message,
              'timestamp': a.timestamp.toIso8601String(),
            })
            .toList(),
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      lastUpdatedAt = DateTime.now();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
    }
  }
}

/// Custom metrics widget
class CustomMetricsWidget extends DashboardWidget {
  /// Creates the custom metrics widget.
  CustomMetricsWidget()
      : super(
          id: 'custom_metrics',
          title: 'Custom Metrics',
          description: 'Application-specific performance metrics',
        );
  
  @override
  Future<void> updateData(PerformanceMonitor monitor) async {
    isLoading = true;
    error = null;
    
    try {
      final summary = monitor.getPerformanceSummary();
      final customMetrics = summary.customMetrics;
      
      data = {
        'metrics': customMetrics,
        'metric_count': customMetrics.length,
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      lastUpdatedAt = DateTime.now();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
    }
  }
}