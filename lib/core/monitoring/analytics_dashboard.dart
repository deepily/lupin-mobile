import 'dart:async';
import 'dart:math' as math;
import 'performance_monitor.dart';
import 'monitoring_models.dart';
import '../storage/storage_manager.dart';

/// Analytics dashboard for performance insights and reporting
class AnalyticsDashboard {
  static AnalyticsDashboard? _instance;
  late final PerformanceMonitor _performanceMonitor;
  late final StorageManager _storage;
  
  // Dashboard state
  final Map<String, DashboardWidget> _widgets = {};
  final List<AnalyticsReport> _reports = [];
  Timer? _refreshTimer;
  
  // Stream controllers
  final StreamController<DashboardUpdate> _updateController = 
      StreamController<DashboardUpdate>.broadcast();
  final StreamController<AnalyticsInsight> _insightController = 
      StreamController<AnalyticsInsight>.broadcast();
  
  // Configuration
  final AnalyticsDashboardConfig _config;
  
  AnalyticsDashboard._(this._config);
  
  /// Get singleton instance
  static Future<AnalyticsDashboard> getInstance({
    AnalyticsDashboardConfig? config,
  }) async {
    if (_instance == null) {
      _instance = AnalyticsDashboard._(
        config ?? AnalyticsDashboardConfig.defaultConfig(),
      );
      await _instance!._initialize();
    }
    return _instance!;
  }
  
  /// Initialize the analytics dashboard
  Future<void> _initialize() async {
    _performanceMonitor = await PerformanceMonitor.getInstance();
    _storage = await StorageManager.getInstance();
    
    _setupDefaultWidgets();
    _setupInsightGeneration();
    
    if (_config.enableAutoRefresh) {
      _startAutoRefresh();
    }
  }
  
  /// Start the dashboard
  Future<void> start() async {
    await _performanceMonitor.startMonitoring();
    
    // Generate initial insights
    await _generateInsights();
    
    _updateController.add(DashboardUpdate.started());
  }
  
  /// Stop the dashboard
  Future<void> stop() async {
    _refreshTimer?.cancel();
    await _performanceMonitor.stopMonitoring();
    
    _updateController.add(DashboardUpdate.stopped());
  }
  
  /// Get dashboard summary
  Future<DashboardSummary> getDashboardSummary() async {
    final performanceSummary = _performanceMonitor.getPerformanceSummary();
    final systemStats = await _performanceMonitor.getCurrentSystemStats();
    
    return DashboardSummary(
      isActive: performanceSummary.isMonitoring,
      uptime: performanceSummary.uptime,
      totalEvents: performanceSummary.totalEvents,
      alertCount: performanceSummary.alerts.length,
      memoryUsageMB: systemStats.memoryUsageMB,
      cpuUsagePercent: systemStats.cpuUsagePercent,
      networkSuccessRate: performanceSummary.networkRequests.successRate,
      widgetCount: _widgets.length,
      recentInsights: await _getRecentInsights(),
    );
  }
  
  /// Add custom widget to dashboard
  void addWidget(String id, DashboardWidget widget) {
    _widgets[id] = widget;
    _updateController.add(DashboardUpdate.widgetAdded(id));
  }
  
  /// Remove widget from dashboard
  void removeWidget(String id) {
    _widgets.remove(id);
    _updateController.add(DashboardUpdate.widgetRemoved(id));
  }
  
  /// Get widget by ID
  DashboardWidget? getWidget(String id) {
    return _widgets[id];
  }
  
  /// Get all widgets
  Map<String, DashboardWidget> getAllWidgets() {
    return Map.from(_widgets);
  }
  
  /// Update widget data
  Future<void> updateWidget(String id) async {
    final widget = _widgets[id];
    if (widget == null) return;
    
    try {
      await widget.updateData(_performanceMonitor);
      _updateController.add(DashboardUpdate.widgetUpdated(id));
    } catch (e) {
      _updateController.add(DashboardUpdate.widgetError(id, e.toString()));
    }
  }
  
  /// Update all widgets
  Future<void> updateAllWidgets() async {
    for (final widgetId in _widgets.keys) {
      await updateWidget(widgetId);
    }
    
    _updateController.add(DashboardUpdate.allWidgetsUpdated());
  }
  
  /// Generate performance report
  Future<AnalyticsReport> generateReport({
    Duration? timeWindow,
    List<String>? categories,
    String format = 'detailed',
  }) async {
    final analytics = _performanceMonitor.getAnalytics(
      timeWindow: timeWindow,
      categories: categories,
    );
    
    final summary = _performanceMonitor.getPerformanceSummary();
    final insights = await _generateInsightsFromAnalytics(analytics);
    
    final report = AnalyticsReport(
      id: _generateReportId(),
      title: _generateReportTitle(timeWindow),
      generatedAt: DateTime.now(),
      timeWindow: timeWindow,
      categories: categories,
      format: format,
      summary: summary,
      analytics: analytics,
      insights: insights,
      recommendations: _generateRecommendations(analytics, summary),
    );
    
    _reports.add(report);
    
    // Limit report history
    if (_reports.length > _config.maxReports) {
      _reports.removeAt(0);
    }
    
    return report;
  }
  
  /// Get stored reports
  List<AnalyticsReport> getReports() {
    return List.from(_reports);
  }
  
  /// Get real-time metrics
  Future<RealTimeMetrics> getRealTimeMetrics() async {
    final performanceSummary = _performanceMonitor.getPerformanceSummary();
    final systemStats = await _performanceMonitor.getCurrentSystemStats();
    
    // Calculate trends
    final trends = await _calculateTrends();
    
    return RealTimeMetrics(
      timestamp: DateTime.now(),
      memoryUsageMB: systemStats.memoryUsageMB,
      cpuUsagePercent: systemStats.cpuUsagePercent,
      networkRequests: performanceSummary.networkRequests,
      activeEvents: performanceSummary.totalEvents,
      alertLevel: _calculateCurrentAlertLevel(performanceSummary.alerts),
      trends: trends,
    );
  }
  
  /// Get performance trends
  Future<PerformanceTrends> getPerformanceTrends({
    Duration lookback = const Duration(hours: 1),
  }) async {
    return await _calculateTrends(lookback: lookback);
  }
  
  /// Export dashboard data
  Future<String> exportDashboard({
    String format = 'json',
    bool includeWidgets = true,
    bool includeReports = true,
    bool includeInsights = true,
  }) async {
    final dashboardData = {
      'exported_at': DateTime.now().toIso8601String(),
      'config': _config.toJson(),
      'summary': (await getDashboardSummary()).toJson(),
    };
    
    if (includeWidgets) {
      dashboardData['widgets'] = _widgets.map((key, widget) => 
          MapEntry(key, widget.toJson()));
    }
    
    if (includeReports) {
      dashboardData['reports'] = _reports.map((r) => r.toJson()).toList();
    }
    
    if (includeInsights) {
      dashboardData['insights'] = (await _getRecentInsights())
          .map((i) => i.toJson()).toList();
    }
    
    if (format == 'csv') {
      return _convertToCSV(dashboardData);
    } else {
      return _convertToJSON(dashboardData);
    }
  }
  
  /// Get health score
  Future<HealthScore> getHealthScore() async {
    final summary = _performanceMonitor.getPerformanceSummary();
    final analytics = _performanceMonitor.getAnalytics();
    
    double score = 100.0;
    final factors = <String, double>{};
    
    // Memory usage factor
    final memoryScore = math.max(0, 100 - (summary.memoryUsageMB / 10));
    factors['memory'] = memoryScore;
    score *= memoryScore / 100;
    
    // CPU usage factor
    final cpuScore = math.max(0, 100 - summary.cpuUsagePercent);
    factors['cpu'] = cpuScore;
    score *= cpuScore / 100;
    
    // Network success rate factor
    final networkScore = summary.networkRequests.successRate * 100;
    factors['network'] = networkScore;
    score *= networkScore / 100;
    
    // Error rate factor
    double overallErrorRate = 0.0;
    int totalEvents = 0;
    int totalErrors = 0;
    
    for (final analysis in analytics.eventBreakdown.values) {
      totalEvents += analysis.totalEvents;
      totalErrors += analysis.errorCount;
    }
    
    if (totalEvents > 0) {
      overallErrorRate = totalErrors / totalEvents;
    }
    
    final errorScore = math.max(0, 100 - (overallErrorRate * 200));
    factors['errors'] = errorScore;
    score *= errorScore / 100;
    
    // Alert level factor
    final alertLevel = _calculateCurrentAlertLevel(summary.alerts);
    final alertScore = _getAlertLevelScore(alertLevel);
    factors['alerts'] = alertScore;
    score *= alertScore / 100;
    
    return HealthScore(
      score: score.clamp(0, 100),
      level: _getHealthLevel(score),
      factors: factors,
      calculatedAt: DateTime.now(),
    );
  }
  
  /// Stream of dashboard updates
  Stream<DashboardUpdate> get updates => _updateController.stream;
  
  /// Stream of analytics insights
  Stream<AnalyticsInsight> get insights => _insightController.stream;
  
  /// Dispose resources
  void dispose() {
    _refreshTimer?.cancel();
    _updateController.close();
    _insightController.close();
  }
  
  // Private methods
  
  void _setupDefaultWidgets() {
    // System overview widget
    addWidget('system_overview', SystemOverviewWidget());
    
    // Network performance widget
    addWidget('network_performance', NetworkPerformanceWidget());
    
    // Event timeline widget
    addWidget('event_timeline', EventTimelineWidget());
    
    // Alert summary widget
    addWidget('alert_summary', AlertSummaryWidget());
    
    // Custom metrics widget
    addWidget('custom_metrics', CustomMetricsWidget());
  }
  
  void _setupInsightGeneration() {
    // Listen for performance alerts and generate insights
    _performanceMonitor.alerts.listen((alert) {
      _generateInsightFromAlert(alert);
    });
  }
  
  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(
      Duration(seconds: _config.refreshIntervalSeconds),
      (_) => updateAllWidgets(),
    );
  }
  
  Future<void> _generateInsights() async {
    final analytics = _performanceMonitor.getAnalytics();
    final insights = await _generateInsightsFromAnalytics(analytics);
    
    for (final insight in insights) {
      _insightController.add(insight);
    }
  }
  
  Future<List<AnalyticsInsight>> _generateInsightsFromAnalytics(
    PerformanceAnalytics analytics,
  ) async {
    final insights = <AnalyticsInsight>[];
    
    // Memory usage insights
    if (analytics.systemAnalytics.peakMemoryUsageMB > 400) {
      insights.add(AnalyticsInsight(
        type: InsightType.performance,
        severity: InsightSeverity.warning,
        title: 'High Memory Usage Detected',
        description: 'Peak memory usage reached ${analytics.systemAnalytics.peakMemoryUsageMB.toStringAsFixed(1)}MB',
        recommendation: 'Consider optimizing memory usage or increasing available memory',
        metadata: {
          'peak_memory_mb': analytics.systemAnalytics.peakMemoryUsageMB,
          'average_memory_mb': analytics.systemAnalytics.averageMemoryUsageMB,
        },
      ));
    }
    
    // Network performance insights
    if (analytics.networkAnalytics.successRate < 0.95) {
      insights.add(AnalyticsInsight(
        type: InsightType.reliability,
        severity: InsightSeverity.error,
        title: 'Low Network Success Rate',
        description: 'Network success rate is ${(analytics.networkAnalytics.successRate * 100).toStringAsFixed(1)}%',
        recommendation: 'Check network connectivity and server reliability',
        metadata: {
          'success_rate': analytics.networkAnalytics.successRate,
          'failed_requests': analytics.networkAnalytics.failedRequests,
          'total_requests': analytics.networkAnalytics.totalRequests,
        },
      ));
    }
    
    // Event performance insights
    for (final entry in analytics.eventBreakdown.entries) {
      final category = entry.key;
      final analysis = entry.value;
      
      if (analysis.p95DurationMs > 2000) {
        insights.add(AnalyticsInsight(
          type: InsightType.performance,
          severity: InsightSeverity.warning,
          title: 'Slow ${category.toUpperCase()} Operations',
          description: '95th percentile duration is ${analysis.p95DurationMs.toStringAsFixed(0)}ms',
          recommendation: 'Optimize $category operations for better performance',
          metadata: {
            'category': category,
            'p95_duration_ms': analysis.p95DurationMs,
            'average_duration_ms': analysis.averageDurationMs,
          },
        ));
      }
    }
    
    return insights;
  }
  
  void _generateInsightFromAlert(PerformanceAlert alert) {
    InsightSeverity severity;
    switch (alert.level) {
      case AlertLevel.info:
        severity = InsightSeverity.info;
        break;
      case AlertLevel.warning:
        severity = InsightSeverity.warning;
        break;
      case AlertLevel.error:
        severity = InsightSeverity.error;
        break;
      case AlertLevel.critical:
        severity = InsightSeverity.critical;
        break;
    }
    
    final insight = AnalyticsInsight(
      type: InsightType.alert,
      severity: severity,
      title: 'Performance Alert: ${alert.message}',
      description: alert.message,
      recommendation: _getRecommendationForAlert(alert),
      metadata: alert.details,
    );
    
    _insightController.add(insight);
  }
  
  String _getRecommendationForAlert(PerformanceAlert alert) {
    if (alert.message.contains('memory')) {
      return 'Review memory usage patterns and optimize allocations';
    } else if (alert.message.contains('network')) {
      return 'Check network configuration and retry logic';
    } else if (alert.message.contains('CPU')) {
      return 'Optimize CPU-intensive operations';
    }
    return 'Review system performance and optimize as needed';
  }
  
  Future<List<AnalyticsInsight>> _getRecentInsights({int limit = 10}) async {
    // Implementation would fetch recent insights from storage
    // For now, return empty list
    return [];
  }
  
  Future<PerformanceTrends> _calculateTrends({
    Duration lookback = const Duration(minutes: 30),
  }) async {
    // Implementation would calculate actual trends from historical data
    // For now, return placeholder data
    return PerformanceTrends(
      memoryTrend: TrendDirection.stable,
      cpuTrend: TrendDirection.stable,
      networkTrend: TrendDirection.stable,
      errorTrend: TrendDirection.stable,
      calculatedAt: DateTime.now(),
      lookbackDuration: lookback,
    );
  }
  
  AlertLevel _calculateCurrentAlertLevel(List<PerformanceAlert> alerts) {
    if (alerts.isEmpty) return AlertLevel.info;
    
    final recentAlerts = alerts.where((a) => 
        DateTime.now().difference(a.timestamp).inMinutes < 5).toList();
    
    if (recentAlerts.any((a) => a.level == AlertLevel.critical)) {
      return AlertLevel.critical;
    } else if (recentAlerts.any((a) => a.level == AlertLevel.error)) {
      return AlertLevel.error;
    } else if (recentAlerts.any((a) => a.level == AlertLevel.warning)) {
      return AlertLevel.warning;
    }
    
    return AlertLevel.info;
  }
  
  double _getAlertLevelScore(AlertLevel level) {
    switch (level) {
      case AlertLevel.info:
        return 100.0;
      case AlertLevel.warning:
        return 80.0;
      case AlertLevel.error:
        return 60.0;
      case AlertLevel.critical:
        return 20.0;
    }
  }
  
  HealthLevel _getHealthLevel(double score) {
    if (score >= 90) return HealthLevel.excellent;
    if (score >= 75) return HealthLevel.good;
    if (score >= 60) return HealthLevel.fair;
    if (score >= 40) return HealthLevel.poor;
    return HealthLevel.critical;
  }
  
  List<String> _generateRecommendations(
    PerformanceAnalytics analytics,
    PerformanceSummary summary,
  ) {
    final recommendations = <String>[];
    
    // Add analytics-based recommendations
    recommendations.addAll(analytics.recommendations);
    
    // Add summary-based recommendations
    if (summary.memoryUsageMB > 300) {
      recommendations.add('Consider implementing memory optimization strategies');
    }
    
    if (summary.networkRequests.successRate < 0.9) {
      recommendations.add('Improve error handling and retry logic for network requests');
    }
    
    return recommendations;
  }
  
  String _generateReportId() {
    return 'report_${DateTime.now().millisecondsSinceEpoch}';
  }
  
  String _generateReportTitle(Duration? timeWindow) {
    if (timeWindow == null) {
      return 'Performance Report - All Time';
    } else {
      return 'Performance Report - Last ${timeWindow.inHours}h';
    }
  }
  
  String _convertToJSON(Map<String, dynamic> data) {
    // Implementation would properly format JSON
    return data.toString();
  }
  
  String _convertToCSV(Map<String, dynamic> data) {
    // Implementation would format as CSV
    return 'CSV format not implemented';
  }
}

/// Analytics dashboard configuration
class AnalyticsDashboardConfig {
  final bool enableAutoRefresh;
  final int refreshIntervalSeconds;
  final int maxReports;
  final int maxInsights;
  final bool enableInsightGeneration;
  final bool enableHealthScoring;
  
  const AnalyticsDashboardConfig({
    this.enableAutoRefresh = true,
    this.refreshIntervalSeconds = 30,
    this.maxReports = 50,
    this.maxInsights = 100,
    this.enableInsightGeneration = true,
    this.enableHealthScoring = true,
  });
  
  factory AnalyticsDashboardConfig.defaultConfig() {
    return const AnalyticsDashboardConfig();
  }
  
  factory AnalyticsDashboardConfig.production() {
    return const AnalyticsDashboardConfig(
      refreshIntervalSeconds = 60,
      maxReports = 20,
      maxInsights = 50,
    );
  }
  
  factory AnalyticsDashboardConfig.development() {
    return const AnalyticsDashboardConfig(
      refreshIntervalSeconds = 10,
      maxReports = 100,
      maxInsights = 200,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'enable_auto_refresh': enableAutoRefresh,
      'refresh_interval_seconds': refreshIntervalSeconds,
      'max_reports': maxReports,
      'max_insights': maxInsights,
      'enable_insight_generation': enableInsightGeneration,
      'enable_health_scoring': enableHealthScoring,
    };
  }
}