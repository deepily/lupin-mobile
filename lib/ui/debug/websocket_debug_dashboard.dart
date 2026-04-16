import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import '../../services/websocket/websocket_debug_monitor.dart';
import '../../services/websocket/websocket_connection_manager.dart';
import '../../core/constants/app_constants.dart';

/// Debug dashboard widget for monitoring WebSocket events and performance.
/// 
/// Provides real-time visualization of WebSocket traffic, connection status,
/// event statistics, and performance metrics for debugging purposes.
class WebSocketDebugDashboard extends StatefulWidget {
  final WebSocketDebugMonitor debugMonitor;
  final WebSocketConnectionManager connectionManager;
  
  const WebSocketDebugDashboard({
    super.key,
    required this.debugMonitor,
    required this.connectionManager,
  });
  
  @override
  State<WebSocketDebugDashboard> createState() => _WebSocketDebugDashboardState();
}

class _WebSocketDebugDashboardState extends State<WebSocketDebugDashboard>
    with TickerProviderStateMixin {
  late TabController _tabController;
  
  // Stream subscriptions
  StreamSubscription? _debugUpdateSubscription;
  StreamSubscription? _performanceAlertSubscription;
  
  // Dashboard state
  Map<String, dynamic> _currentStats = {};
  List<EventLogEntry> _recentEvents = [];
  List<PerformanceAlert> _recentAlerts = [];
  Map<String, dynamic> _connectionHealth = {};
  bool _isAutoRefresh = true;
  Timer? _refreshTimer;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _setupSubscriptions();
    _refreshData();
    _startAutoRefresh();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _debugUpdateSubscription?.cancel();
    _performanceAlertSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
  
  void _setupSubscriptions() {
    _debugUpdateSubscription = widget.debugMonitor.debugUpdates.listen((update) {
      if (mounted) {
        setState(() {
          if (update.type == DebugUpdateType.statsUpdate) {
            _currentStats = update.data;
          }
        });
      }
    });
    
    _performanceAlertSubscription = widget.debugMonitor.performanceAlerts.listen((alert) {
      if (mounted) {
        setState(() {
          _recentAlerts.insert(0, alert);
          if (_recentAlerts.length > 50) {
            _recentAlerts = _recentAlerts.take(50).toList();
          }
        });
      }
    });
  }
  
  void _startAutoRefresh() {
    if (_isAutoRefresh) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshData());
    }
  }
  
  void _refreshData() {
    setState(() {
      _currentStats = widget.debugMonitor.getDebugStatistics();
      _recentEvents = widget.debugMonitor.getRecentEvents(maxCount: 100);
      _connectionHealth = widget.debugMonitor.getConnectionHealthReport();
    });
  }
  
  void _toggleAutoRefresh() {
    setState(() {
      _isAutoRefresh = !_isAutoRefresh;
      _refreshTimer?.cancel();
      if (_isAutoRefresh) {
        _startAutoRefresh();
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebSocket Debug Dashboard'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.event), text: 'Events'),
            Tab(icon: Icon(Icons.link), text: 'Connection'),
            Tab(icon: Icon(Icons.speed), text: 'Performance'),
            Tab(icon: Icon(Icons.settings), text: 'Tools'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_isAutoRefresh ? Icons.pause : Icons.play_arrow),
            onPressed: _toggleAutoRefresh,
            tooltip: _isAutoRefresh ? 'Pause auto-refresh' : 'Start auto-refresh',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh data',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildEventsTab(),
          _buildConnectionTab(),
          _buildPerformanceTab(),
          _buildToolsTab(),
        ],
      ),
    );
  }
  
  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildConnectionStatusCard(),
          const SizedBox(height: 16),
          _buildQuickStatsCards(),
          const SizedBox(height: 16),
          _buildRecentAlertsCard(),
        ],
      ),
    );
  }
  
  Widget _buildConnectionStatusCard() {
    final isConnected = widget.connectionManager.isConnected;
    final isAudioConnected = widget.connectionManager.isAudioConnected;
    final connectionStatus = widget.connectionManager.getConnectionStatus();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isConnected && isAudioConnected 
                      ? Icons.check_circle 
                      : Icons.error,
                  color: isConnected && isAudioConnected 
                      ? Colors.green 
                      : Colors.red,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Connection Status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatusRow('Queue Connection', 
                isConnected ? 'Connected' : 'Disconnected',
                isConnected),
            _buildStatusRow('Audio Connection', 
                isAudioConnected ? 'Connected' : 'Disconnected',
                isAudioConnected),
            if (connectionStatus['session_id'] != null)
              _buildStatusRow('Session ID', connectionStatus['session_id'], true),
            if (connectionStatus['user_id'] != null)
              _buildStatusRow('User ID', connectionStatus['user_id'], true),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusRow(String label, String value, bool isGood) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              color: isGood ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildQuickStatsCards() {
    final eventStats = _currentStats['event_statistics'] as Map<String, dynamic>? ?? {};
    final totalEvents = eventStats.values
        .map((stats) => (stats as Map<String, dynamic>)['total_count'] as int? ?? 0)
        .fold(0, (a, b) => a + b);
    
    final totalErrors = eventStats.values
        .map((stats) => (stats as Map<String, dynamic>)['error_count'] as int? ?? 0)
        .fold(0, (a, b) => a + b);
    
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total Events',
            totalEvents.toString(),
            Icons.event,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            'Error Events',
            totalErrors.toString(),
            Icons.error,
            Colors.red,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            'Event Types',
            eventStats.length.toString(),
            Icons.category,
            Colors.green,
          ),
        ),
      ],
    );
  }
  
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRecentAlertsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent Alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_recentAlerts.isEmpty)
              const Text('No recent alerts', style: TextStyle(color: Colors.grey))
            else
              ..._recentAlerts.take(5).map((alert) => _buildAlertItem(alert)),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAlertItem(PerformanceAlert alert) {
    Color severityColor;
    IconData severityIcon;
    
    switch (alert.severity) {
      case AlertSeverity.critical:
        severityColor = Colors.red.shade700;
        severityIcon = Icons.error;
        break;
      case AlertSeverity.error:
        severityColor = Colors.red;
        severityIcon = Icons.error_outline;
        break;
      case AlertSeverity.warning:
        severityColor = Colors.orange;
        severityIcon = Icons.warning;
        break;
      case AlertSeverity.info:
        severityColor = Colors.blue;
        severityIcon = Icons.info;
        break;
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(severityIcon, color: severityColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              alert.message,
              style: TextStyle(fontSize: 12),
            ),
          ),
          Text(
            _formatTime(alert.timestamp),
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEventsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Filter events',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    // Implement event filtering
                  },
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _recentEvents = widget.debugMonitor.getRecentEvents(maxCount: 100);
                  });
                },
                child: const Text('Refresh'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _recentEvents.length,
            itemBuilder: (context, index) {
              final event = _recentEvents[index];
              return _buildEventListItem(event);
            },
          ),
        ),
      ],
    );
  }
  
  Widget _buildEventListItem(EventLogEntry event) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ExpansionTile(
        leading: Icon(
          event.isError ? Icons.error : Icons.event,
          color: event.isError ? Colors.red : Colors.blue,
        ),
        title: Text(event.eventType),
        subtitle: Text(_formatTime(event.timestamp)),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Event Details:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    const JsonEncoder.withIndent('  ').convert(event.details),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildConnectionTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildConnectionHealthCard(),
          const SizedBox(height: 16),
          _buildConnectionMetricsCard(),
          const SizedBox(height: 16),
          _buildSubscriptionStatusCard(),
        ],
      ),
    );
  }
  
  Widget _buildConnectionHealthCard() {
    final health = _connectionHealth;
    final stabilityScore = health['stability_score'] as double? ?? 0.0;
    final successRate = health['success_rate'] as double? ?? 0.0;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Connection Health',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildHealthMetric('Stability Score', '${(stabilityScore * 100).toStringAsFixed(1)}%', stabilityScore),
            _buildHealthMetric('Success Rate', '${(successRate * 100).toStringAsFixed(1)}%', successRate),
            _buildHealthRow('Recent Disconnections', health['recent_disconnections']?.toString() ?? '0'),
            _buildHealthRow('Connection Attempts', health['connection_attempts']?.toString() ?? '0'),
            if (health['last_connection_time'] != null)
              _buildHealthRow('Last Connection', _formatTime(DateTime.parse(health['last_connection_time']))),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHealthMetric(String label, String value, double score) {
    Color color;
    if (score >= 0.8) color = Colors.green;
    else if (score >= 0.6) color = Colors.orange;
    else color = Colors.red;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: score,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ],
      ),
    );
  }
  
  Widget _buildHealthRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
  
  Widget _buildConnectionMetricsCard() {
    final connectionStats = _currentStats['connection_statistics'] as Map<String, dynamic>? ?? {};
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Connection Metrics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildMetricRow('Total Connection Events', connectionStats['total_connection_events']?.toString() ?? '0'),
            _buildMetricRow('Recent Connections (1h)', connectionStats['recent_connections']?.toString() ?? '0'),
            _buildMetricRow('Avg Duration (ms)', connectionStats['average_connection_duration']?.toString() ?? '0'),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSubscriptionStatusCard() {
    final subscriptionStats = _currentStats['subscription_statistics'] as Map<String, dynamic>? ?? {};
    final currentSubs = widget.connectionManager.getSubscriptionStats();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Subscription Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildMetricRow('Subscribe to All', currentSubs['subscribe_to_all']?.toString() ?? 'false'),
            _buildMetricRow('Subscribed Events', currentSubs['total_subscribed_events']?.toString() ?? '0'),
            _buildMetricRow('Subscription Rate', '${((currentSubs['subscription_rate'] as double? ?? 0.0) * 100).toStringAsFixed(1)}%'),
            _buildMetricRow('Active Filters', (currentSubs['active_filters'] as List?)?.length.toString() ?? '0'),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
  
  Widget _buildPerformanceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildPerformanceAlertsCard(),
          const SizedBox(height: 16),
          _buildEventFrequencyCard(),
          const SizedBox(height: 16),
          _buildLogSizesCard(),
        ],
      ),
    );
  }
  
  Widget _buildPerformanceAlertsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Performance Alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_recentAlerts.isEmpty)
              const Text('No performance alerts', style: TextStyle(color: Colors.grey))
            else
              ..._recentAlerts.map((alert) => _buildDetailedAlertItem(alert)),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDetailedAlertItem(PerformanceAlert alert) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        title: Text(alert.message),
        subtitle: Text('${alert.eventType} - ${alert.severity.toString().split('.').last}'),
        children: [
          if (alert.details != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  const JsonEncoder.withIndent('  ').convert(alert.details),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildEventFrequencyCard() {
    final eventStats = _currentStats['event_statistics'] as Map<String, dynamic>? ?? {};
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Event Frequency Analysis',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...eventStats.entries.take(10).map((entry) {
              final stats = entry.value as Map<String, dynamic>;
              final frequency = stats['frequency_per_minute'] as double? ?? 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(entry.key)),
                    Text('${frequency.toStringAsFixed(1)}/min'),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLogSizesCard() {
    final logSizes = _currentStats['log_sizes'] as Map<String, dynamic>? ?? {};
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Log Sizes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...logSizes.entries.map((entry) => 
              _buildMetricRow(entry.key, entry.value.toString())),
          ],
        ),
      ),
    );
  }
  
  Widget _buildToolsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildConnectionToolsCard(),
          const SizedBox(height: 16),
          _buildExportToolsCard(),
          const SizedBox(height: 16),
          _buildMonitoringConfigCard(),
        ],
      ),
    );
  }
  
  Widget _buildConnectionToolsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Connection Tools',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => widget.connectionManager.reconnectBoth(),
                    child: const Text('Reconnect'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => widget.connectionManager.performHealthCheck(),
                    child: const Text('Health Check'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildExportToolsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Export Tools',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _exportDebugData,
              child: const Text('Export Debug Data'),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMonitoringConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Monitoring Configuration',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Monitoring features can be configured here'),
            // Add configuration options here
          ],
        ),
      ),
    );
  }
  
  void _exportDebugData() {
    final debugData = widget.debugMonitor.exportDebugData(
      timeWindow: const Duration(hours: 24),
      includeDetails: true,
    );
    
    // In a real implementation, this would save to file or share
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Debug Data Exported'),
        content: Text('Exported ${debugData['events'].length} events'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  
  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }
}