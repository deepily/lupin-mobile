import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'websocket_connection_manager.dart';
import 'websocket_debug_monitor.dart';
import 'enhanced_websocket_service.dart';
import '../../core/constants/app_constants.dart';

/// Utility functions for WebSocket debugging and testing.
/// 
/// Provides helper methods for testing connections, generating mock data,
/// analyzing performance, and troubleshooting common issues.
class WebSocketDebugUtils {
  static const String _tag = '[WebSocketDebugUtils]';
  
  /// Test WebSocket connection with comprehensive diagnostics
  static Future<ConnectionTestResult> testConnection(
    WebSocketConnectionManager connectionManager, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    print('$_tag Starting connection test...');
    
    final startTime = DateTime.now();
    final result = ConnectionTestResult();
    
    try {
      // Test basic connection
      result.steps.add(TestStep('Initiating connection', TestStepStatus.running));
      await connectionManager.connect();
      
      final connectionTime = DateTime.now().difference(startTime);
      result.steps.last.status = TestStepStatus.completed;
      result.steps.last.duration = connectionTime;
      
      // Test queue connection
      result.steps.add(TestStep('Testing queue connection', TestStepStatus.running));
      if (connectionManager.isConnected) {
        result.steps.last.status = TestStepStatus.completed;
        result.queueConnectionWorking = true;
      } else {
        result.steps.last.status = TestStepStatus.failed;
        result.steps.last.error = 'Queue connection failed';
      }
      
      // Test audio connection
      result.steps.add(TestStep('Testing audio connection', TestStepStatus.running));
      if (connectionManager.isAudioConnected) {
        result.steps.last.status = TestStepStatus.completed;
        result.audioConnectionWorking = true;
      } else {
        result.steps.last.status = TestStepStatus.failed;
        result.steps.last.error = 'Audio connection failed';
      }
      
      // Test authentication
      result.steps.add(TestStep('Testing authentication', TestStepStatus.running));
      // Wait for auth messages
      final authCompleter = Completer<bool>();
      late StreamSubscription authSub;
      
      authSub = connectionManager.authMessages.listen((authMessage) {
        if (authMessage.authType == 'auth_success') {
          authCompleter.complete(true);
        } else if (authMessage.authType == 'auth_error') {
          authCompleter.complete(false);
        }
      });
      
      Timer(const Duration(seconds: 5), () {
        if (!authCompleter.isCompleted) {
          authCompleter.complete(false);
        }
      });
      
      final authSuccess = await authCompleter.future;
      authSub.cancel();
      
      if (authSuccess) {
        result.steps.last.status = TestStepStatus.completed;
        result.authenticationWorking = true;
      } else {
        result.steps.last.status = TestStepStatus.failed;
        result.steps.last.error = 'Authentication failed or timed out';
      }
      
      // Test message flow
      result.steps.add(TestStep('Testing message flow', TestStepStatus.running));
      final messageReceived = await _testMessageFlow(connectionManager);
      
      if (messageReceived) {
        result.steps.last.status = TestStepStatus.completed;
        result.messageFlowWorking = true;
      } else {
        result.steps.last.status = TestStepStatus.failed;
        result.steps.last.error = 'No messages received during test period';
      }
      
      result.totalDuration = DateTime.now().difference(startTime);
      result.overallSuccess = result.queueConnectionWorking && 
                             result.audioConnectionWorking && 
                             result.authenticationWorking && 
                             result.messageFlowWorking;
      
    } catch (e) {
      result.steps.last.status = TestStepStatus.failed;
      result.steps.last.error = e.toString();
      result.totalDuration = DateTime.now().difference(startTime);
      result.overallSuccess = false;
    }
    
    print('$_tag Connection test completed: ${result.overallSuccess ? 'PASS' : 'FAIL'}');
    return result;
  }
  
  /// Test message flow by listening for any messages
  static Future<bool> _testMessageFlow(WebSocketConnectionManager connectionManager) async {
    final completer = Completer<bool>();
    final subscriptions = <StreamSubscription>[];
    
    // Listen to all message streams
    subscriptions.add(connectionManager.queueUpdates.listen((_) => completer.complete(true)));
    subscriptions.add(connectionManager.notifications.listen((_) => completer.complete(true)));
    subscriptions.add(connectionManager.systemMessages.listen((_) => completer.complete(true)));
    subscriptions.add(connectionManager.authMessages.listen((_) => completer.complete(true)));
    subscriptions.add(connectionManager.audioChunks.listen((_) => completer.complete(true)));
    subscriptions.add(connectionManager.ttsStatus.listen((_) => completer.complete(true)));
    
    // Set timeout
    Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });
    
    final result = await completer.future;
    
    // Clean up subscriptions
    for (final sub in subscriptions) {
      sub.cancel();
    }
    
    return result;
  }
  
  /// Generate mock WebSocket events for testing
  static Future<void> generateMockEvents(
    WebSocketConnectionManager connectionManager, {
    int eventCount = 10,
    Duration interval = const Duration(seconds: 1),
  }) async {
    print('$_tag Generating $eventCount mock events...');
    
    for (int i = 0; i < eventCount; i++) {
      final eventType = _getRandomEventType();
      final mockMessage = _createMockMessage(eventType, i);
      
      try {
        await connectionManager.sendCustomMessage(mockMessage);
        print('$_tag Sent mock $eventType event ($i/${eventCount})');
      } catch (e) {
        print('$_tag Failed to send mock event: $e');
      }
      
      if (i < eventCount - 1) {
        await Future.delayed(interval);
      }
    }
    
    print('$_tag Completed generating mock events');
  }
  
  /// Get a random event type for mock generation
  static String _getRandomEventType() {
    final eventTypes = [
      'tts_request',
      'voice_input',
      'agent_interaction',
      'test_event',
    ];
    return eventTypes[DateTime.now().millisecond % eventTypes.length];
  }
  
  /// Create a mock WebSocket message
  static WebSocketMessage _createMockMessage(String eventType, int sequence) {
    Map<String, dynamic> data;
    
    switch (eventType) {
      case 'tts_request':
        data = {
          'text': 'Test TTS message $sequence',
          'provider': 'elevenlabs',
          'voice_id': 'test_voice',
          'sequence': sequence,
        };
        break;
      case 'voice_input':
        data = {
          'action': 'test',
          'sequence': sequence,
        };
        break;
      case 'agent_interaction':
        data = {
          'agent_type': 'test_agent',
          'action': 'test_action',
          'sequence': sequence,
        };
        break;
      default:
        data = {
          'message': 'Test event $sequence',
          'sequence': sequence,
        };
    }
    
    return WebSocketMessage(
      type: eventType,
      data: data,
      timestamp: DateTime.now(),
    );
  }
  
  /// Analyze WebSocket performance metrics
  static PerformanceAnalysis analyzePerformance(
    WebSocketDebugMonitor debugMonitor, {
    Duration timeWindow = const Duration(hours: 1),
  }) {
    print('$_tag Analyzing performance metrics...');
    
    final stats = debugMonitor.getDebugStatistics();
    final recentEvents = debugMonitor.getRecentEvents(timeWindow: timeWindow);
    
    final analysis = PerformanceAnalysis();
    
    // Analyze event frequency
    final eventCounts = <String, int>{};
    for (final event in recentEvents) {
      eventCounts[event.eventType] = (eventCounts[event.eventType] ?? 0) + 1;
    }
    
    analysis.eventFrequency = eventCounts;
    analysis.totalEvents = recentEvents.length;
    analysis.eventsPerMinute = recentEvents.length / (timeWindow.inMinutes);
    
    // Analyze error rates
    final errorEvents = recentEvents.where((e) => e.isError).length;
    analysis.errorRate = recentEvents.isNotEmpty ? errorEvents / recentEvents.length : 0.0;
    
    // Analyze event timing
    if (recentEvents.isNotEmpty) {
      final intervals = <Duration>[];
      for (int i = 1; i < recentEvents.length; i++) {
        intervals.add(recentEvents[i-1].timestamp.difference(recentEvents[i].timestamp).abs());
      }
      
      if (intervals.isNotEmpty) {
        intervals.sort((a, b) => a.compareTo(b));
        analysis.medianEventInterval = intervals[intervals.length ~/ 2];
        analysis.averageEventInterval = Duration(
          milliseconds: intervals.fold(0, (sum, d) => sum + d.inMilliseconds) ~/ intervals.length
        );
      }
    }
    
    // Generate recommendations
    analysis.recommendations = _generatePerformanceRecommendations(analysis);
    
    print('$_tag Performance analysis completed');
    return analysis;
  }
  
  /// Generate performance recommendations
  static List<String> _generatePerformanceRecommendations(PerformanceAnalysis analysis) {
    final recommendations = <String>[];
    
    if (analysis.errorRate > 0.1) {
      recommendations.add('High error rate detected (${(analysis.errorRate * 100).toStringAsFixed(1)}%). Investigate error causes.');
    }
    
    if (analysis.eventsPerMinute > 100) {
      recommendations.add('High event frequency detected (${analysis.eventsPerMinute.toStringAsFixed(1)}/min). Consider filtering events.');
    }
    
    if (analysis.eventsPerMinute < 1) {
      recommendations.add('Low event frequency detected. Check connection and subscriptions.');
    }
    
    final highFrequencyEvents = analysis.eventFrequency.entries
        .where((e) => e.value > analysis.totalEvents * 0.3)
        .map((e) => e.key)
        .toList();
    
    if (highFrequencyEvents.isNotEmpty) {
      recommendations.add('High-frequency events detected: ${highFrequencyEvents.join(", ")}. Consider optimization.');
    }
    
    if (recommendations.isEmpty) {
      recommendations.add('Performance looks good! No issues detected.');
    }
    
    return recommendations;
  }
  
  /// Diagnose common WebSocket issues
  static Future<DiagnosisResult> diagnoseIssues(
    WebSocketConnectionManager connectionManager,
    WebSocketDebugMonitor debugMonitor,
  ) async {
    print('$_tag Running diagnostic checks...');
    
    final result = DiagnosisResult();
    final checks = <DiagnosticCheck>[];
    
    // Check connection status
    checks.add(DiagnosticCheck(
      name: 'Connection Status',
      description: 'Verify WebSocket connections are established',
      severity: DiagnosticSeverity.critical,
    ));
    
    if (connectionManager.isConnected && connectionManager.isAudioConnected) {
      checks.last.status = DiagnosticStatus.pass;
      checks.last.message = 'All connections active';
    } else {
      checks.last.status = DiagnosticStatus.fail;
      checks.last.message = 'Queue: ${connectionManager.isConnected}, Audio: ${connectionManager.isAudioConnected}';
    }
    
    // Check message flow
    checks.add(DiagnosticCheck(
      name: 'Message Flow',
      description: 'Verify messages are being received',
      severity: DiagnosticSeverity.high,
    ));
    
    final recentEvents = debugMonitor.getRecentEvents(timeWindow: const Duration(minutes: 5));
    if (recentEvents.isNotEmpty) {
      checks.last.status = DiagnosticStatus.pass;
      checks.last.message = '${recentEvents.length} events in last 5 minutes';
    } else {
      checks.last.status = DiagnosticStatus.warning;
      checks.last.message = 'No events received in last 5 minutes';
    }
    
    // Check error rate
    checks.add(DiagnosticCheck(
      name: 'Error Rate',
      description: 'Check for excessive errors',
      severity: DiagnosticSeverity.medium,
    ));
    
    final errorEvents = recentEvents.where((e) => e.isError).length;
    final errorRate = recentEvents.isNotEmpty ? errorEvents / recentEvents.length : 0.0;
    
    if (errorRate < 0.05) {
      checks.last.status = DiagnosticStatus.pass;
      checks.last.message = 'Low error rate (${(errorRate * 100).toStringAsFixed(1)}%)';
    } else if (errorRate < 0.2) {
      checks.last.status = DiagnosticStatus.warning;
      checks.last.message = 'Moderate error rate (${(errorRate * 100).toStringAsFixed(1)}%)';
    } else {
      checks.last.status = DiagnosticStatus.fail;
      checks.last.message = 'High error rate (${(errorRate * 100).toStringAsFixed(1)}%)';
    }
    
    // Check subscription health
    checks.add(DiagnosticCheck(
      name: 'Subscription Health',
      description: 'Verify event subscriptions are configured',
      severity: DiagnosticSeverity.medium,
    ));
    
    final subscriptionStats = connectionManager.getSubscriptionStats();
    final subscribedCount = subscriptionStats['total_subscribed_events'] as int? ?? 0;
    
    if (subscribedCount > 0) {
      checks.last.status = DiagnosticStatus.pass;
      checks.last.message = '$subscribedCount events subscribed';
    } else {
      checks.last.status = DiagnosticStatus.warning;
      checks.last.message = 'No event subscriptions configured';
    }
    
    result.checks = checks;
    result.overallStatus = _calculateOverallStatus(checks);
    result.timestamp = DateTime.now();
    
    print('$_tag Diagnostic completed: ${result.overallStatus}');
    return result;
  }
  
  /// Calculate overall diagnostic status
  static DiagnosticStatus _calculateOverallStatus(List<DiagnosticCheck> checks) {
    final criticalFails = checks
        .where((c) => c.severity == DiagnosticSeverity.critical && c.status == DiagnosticStatus.fail)
        .length;
    
    if (criticalFails > 0) return DiagnosticStatus.fail;
    
    final highFails = checks
        .where((c) => c.severity == DiagnosticSeverity.high && c.status == DiagnosticStatus.fail)
        .length;
    
    if (highFails > 0) return DiagnosticStatus.fail;
    
    final warnings = checks.where((c) => c.status == DiagnosticStatus.warning).length;
    
    if (warnings > 0) return DiagnosticStatus.warning;
    
    return DiagnosticStatus.pass;
  }
  
  /// Format debug data for easy reading
  static String formatDebugData(Map<String, dynamic> debugData) {
    final buffer = StringBuffer();
    
    buffer.writeln('=== WebSocket Debug Report ===');
    buffer.writeln('Generated: ${debugData['export_info']['generated_at']}');
    buffer.writeln('Time Window: ${debugData['export_info']['time_window']}');
    buffer.writeln();
    
    // Connection health
    final health = debugData['health_report'] as Map<String, dynamic>? ?? {};
    buffer.writeln('Connection Health:');
    buffer.writeln('  Status: ${health['status']?['queue_connected']} / ${health['status']?['audio_connected']}');
    buffer.writeln('  Stability: ${((health['stability_score'] as double? ?? 0.0) * 100).toStringAsFixed(1)}%');
    buffer.writeln('  Success Rate: ${((health['success_rate'] as double? ?? 0.0) * 100).toStringAsFixed(1)}%');
    buffer.writeln();
    
    // Event statistics
    final events = debugData['events'] as List? ?? [];
    buffer.writeln('Events:');
    buffer.writeln('  Total Events: ${events.length}');
    
    final eventCounts = <String, int>{};
    for (final event in events) {
      final eventType = event['event_type'] as String;
      eventCounts[eventType] = (eventCounts[eventType] ?? 0) + 1;
    }
    
    eventCounts.entries.forEach((entry) {
      buffer.writeln('  ${entry.key}: ${entry.value}');
    });
    
    return buffer.toString();
  }
  
  /// Create a simple WebSocket message for testing
  static WebSocketMessage createTestMessage({
    String type = 'test_message',
    Map<String, dynamic>? data,
    Uint8List? binaryData,
  }) {
    return WebSocketMessage(
      type: type,
      data: data ?? {'test': true, 'timestamp': DateTime.now().toIso8601String()},
      binaryData: binaryData,
      timestamp: DateTime.now(),
    );
  }
}

// ============================================================================
// Data Classes
// ============================================================================

class ConnectionTestResult {
  List<TestStep> steps = [];
  bool queueConnectionWorking = false;
  bool audioConnectionWorking = false;
  bool authenticationWorking = false;
  bool messageFlowWorking = false;
  bool overallSuccess = false;
  Duration? totalDuration;
  
  Map<String, dynamic> toJson() {
    return {
      'steps': steps.map((s) => s.toJson()).toList(),
      'queue_connection_working': queueConnectionWorking,
      'audio_connection_working': audioConnectionWorking,
      'authentication_working': authenticationWorking,
      'message_flow_working': messageFlowWorking,
      'overall_success': overallSuccess,
      'total_duration_ms': totalDuration?.inMilliseconds,
    };
  }
}

class TestStep {
  String name;
  TestStepStatus status;
  Duration? duration;
  String? error;
  
  TestStep(this.name, this.status);
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'status': status.toString(),
      'duration_ms': duration?.inMilliseconds,
      'error': error,
    };
  }
}

enum TestStepStatus {
  pending,
  running,
  completed,
  failed,
}

class PerformanceAnalysis {
  Map<String, int> eventFrequency = {};
  int totalEvents = 0;
  double eventsPerMinute = 0.0;
  double errorRate = 0.0;
  Duration? medianEventInterval;
  Duration? averageEventInterval;
  List<String> recommendations = [];
  
  Map<String, dynamic> toJson() {
    return {
      'event_frequency': eventFrequency,
      'total_events': totalEvents,
      'events_per_minute': eventsPerMinute,
      'error_rate': errorRate,
      'median_event_interval_ms': medianEventInterval?.inMilliseconds,
      'average_event_interval_ms': averageEventInterval?.inMilliseconds,
      'recommendations': recommendations,
    };
  }
}

class DiagnosisResult {
  List<DiagnosticCheck> checks = [];
  DiagnosticStatus overallStatus = DiagnosticStatus.unknown;
  DateTime? timestamp;
  
  Map<String, dynamic> toJson() {
    return {
      'checks': checks.map((c) => c.toJson()).toList(),
      'overall_status': overallStatus.toString(),
      'timestamp': timestamp?.toIso8601String(),
    };
  }
}

class DiagnosticCheck {
  String name;
  String description;
  DiagnosticSeverity severity;
  DiagnosticStatus status = DiagnosticStatus.unknown;
  String? message;
  
  DiagnosticCheck({
    required this.name,
    required this.description,
    required this.severity,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'severity': severity.toString(),
      'status': status.toString(),
      'message': message,
    };
  }
}

enum DiagnosticSeverity {
  low,
  medium,
  high,
  critical,
}

enum DiagnosticStatus {
  unknown,
  pass,
  warning,
  fail,
}

// WebSocketMessage class imported from enhanced_websocket_service.dart