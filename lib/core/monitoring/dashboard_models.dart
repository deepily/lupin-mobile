import 'dart:async';
import 'monitoring_models.dart';
import 'performance_monitor.dart';

/// Dashboard update types
abstract class DashboardUpdate {
  final DateTime timestamp = DateTime.now();
  
  factory DashboardUpdate.started() = DashboardStartedUpdate;
  factory DashboardUpdate.stopped() = DashboardStoppedUpdate;
  factory DashboardUpdate.widgetAdded(String widgetId) = WidgetAddedUpdate;
  factory DashboardUpdate.widgetRemoved(String widgetId) = WidgetRemovedUpdate;
  factory DashboardUpdate.widgetUpdated(String widgetId) = WidgetUpdatedUpdate;
  factory DashboardUpdate.widgetError(String widgetId, String error) = WidgetErrorUpdate;
  factory DashboardUpdate.allWidgetsUpdated() = AllWidgetsUpdatedUpdate;
}

class DashboardStartedUpdate extends DashboardUpdate {}
class DashboardStoppedUpdate extends DashboardUpdate {}

class WidgetAddedUpdate extends DashboardUpdate {
  final String widgetId;
  WidgetAddedUpdate(this.widgetId);
}

class WidgetRemovedUpdate extends DashboardUpdate {
  final String widgetId;
  WidgetRemovedUpdate(this.widgetId);
}

class WidgetUpdatedUpdate extends DashboardUpdate {
  final String widgetId;
  WidgetUpdatedUpdate(this.widgetId);
}

class WidgetErrorUpdate extends DashboardUpdate {
  final String widgetId;
  final String error;
  WidgetErrorUpdate(this.widgetId, this.error);
}

class AllWidgetsUpdatedUpdate extends DashboardUpdate {}

/// Dashboard summary
class DashboardSummary {
  final bool isActive;
  final Duration uptime;
  final int totalEvents;
  final int alertCount;
  final double memoryUsageMB;
  final double cpuUsagePercent;
  final double networkSuccessRate;
  final int widgetCount;
  final List<AnalyticsInsight> recentInsights;
  
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
  performance,
  reliability,
  security,
  usage,
  alert,
  trend,
}

/// Analytics insight severity
enum InsightSeverity {
  info,
  warning,
  error,
  critical,
}

/// Analytics insight
class AnalyticsInsight {
  final InsightType type;
  final InsightSeverity severity;
  final String title;
  final String description;
  final String recommendation;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
  
  AnalyticsInsight({
    required this.type,
    required this.severity,
    required this.title,
    required this.description,
    required this.recommendation,
    DateTime? timestamp,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();
  
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
  final String id;
  final String title;
  final DateTime generatedAt;
  final Duration? timeWindow;
  final List<String>? categories;
  final String format;
  final PerformanceSummary summary;
  final PerformanceAnalytics analytics;
  final List<AnalyticsInsight> insights;
  final List<String> recommendations;
  
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
  increasing,
  decreasing,
  stable,
  volatile,
}

/// Performance trends
class PerformanceTrends {
  final TrendDirection memoryTrend;
  final TrendDirection cpuTrend;
  final TrendDirection networkTrend;
  final TrendDirection errorTrend;
  final DateTime calculatedAt;
  final Duration lookbackDuration;
  
  const PerformanceTrends({
    required this.memoryTrend,
    required this.cpuTrend,
    required this.networkTrend,
    required this.errorTrend,
    required this.calculatedAt,
    required this.lookbackDuration,
  });
  
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
  final DateTime timestamp;
  final double memoryUsageMB;
  final double cpuUsagePercent;
  final NetworkSummary networkRequests;
  final int activeEvents;
  final AlertLevel alertLevel;
  final PerformanceTrends trends;
  
  const RealTimeMetrics({
    required this.timestamp,
    required this.memoryUsageMB,
    required this.cpuUsagePercent,
    required this.networkRequests,
    required this.activeEvents,
    required this.alertLevel,
    required this.trends,
  });
  
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
  excellent,
  good,
  fair,
  poor,
  critical,
}

/// Health score
class HealthScore {
  final double score;
  final HealthLevel level;
  final Map<String, double> factors;
  final DateTime calculatedAt;
  
  const HealthScore({
    required this.score,
    required this.level,
    required this.factors,
    required this.calculatedAt,
  });
  
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
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  DateTime lastUpdatedAt;
  Map<String, dynamic> data = {};
  bool isLoading = false;
  String? error;
  
  DashboardWidget({
    required this.id,
    required this.title,
    required this.description,
  })  : createdAt = DateTime.now(),
        lastUpdatedAt = DateTime.now();
  
  /// Update widget data from performance monitor
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