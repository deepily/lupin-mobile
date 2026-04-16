import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../lib/services/websocket/enhanced_websocket_service.dart';
import '../../lib/services/websocket/websocket_connection_manager.dart';
import '../../lib/services/websocket/websocket_message_router.dart';
import '../../lib/services/websocket/websocket_subscription_manager.dart';
import '../../lib/services/websocket/websocket_dynamic_subscription_controller.dart';
import '../../lib/services/websocket/websocket_event_handlers.dart';
import '../../lib/services/websocket/websocket_debug_monitor.dart';
import '../../lib/core/constants/app_constants.dart';
import '../mocks/mock_websocket_server.dart';
import '../helpers/mock_event_generators.dart';

/// Utility functions and helpers for WebSocket testing.
/// 
/// Provides builders, assertion helpers, timing utilities, and mock data
/// factories to simplify WebSocket test creation and maintenance.
class WebSocketTestUtils {
  static const String _defaultUserId = 'test_user';
  static final Random _random = Random();
  
  /// Create a test connection manager with specified configuration
  static WebSocketConnectionManager createTestConnectionManager({
    String? baseUrl,
    ConnectionManagerConfig? config,
    bool enableDebugMonitor = false,
  }) {
    final webSocketService = EnhancedWebSocketService(Dio());
    final messageRouter = WebSocketMessageRouter();
    
    if (baseUrl != null) {
      webSocketService.setBaseUrl(baseUrl);
    }
    
    return WebSocketConnectionManager(
      webSocketService: webSocketService,
      messageRouter: messageRouter,
      config: config ?? ConnectionManagerConfig.defaultConfig(),
    );
  }
  
  /// Create a test connection manager with full event system
  static TestConnectionSetup createFullTestSetup({
    String? baseUrl,
    ConnectionManagerConfig? connectionConfig,
    DebugConfig? debugConfig,
  }) {
    final connectionManager = createTestConnectionManager(
      baseUrl: baseUrl,
      config: connectionConfig,
    );
    
    final eventHandlerSystem = WebSocketEventHandlerSystem(
      connectionManager: connectionManager,
    );
    
    final debugMonitor = WebSocketDebugMonitor(
      connectionManager: connectionManager,
      eventHandlerSystem: eventHandlerSystem,
      config: debugConfig ?? DebugConfig.defaultConfig(),
    );
    
    return TestConnectionSetup(
      connectionManager: connectionManager,
      eventHandlerSystem: eventHandlerSystem,
      debugMonitor: debugMonitor,
    );
  }
  
  /// Connect to test server with common setup
  static Future<void> connectToTestServer(
    WebSocketConnectionManager connectionManager, {
    String? userId,
    int serverPort = 8080,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final completer = Completer<void>();
    Timer? timeoutTimer;
    
    // Set up timeout
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Connection timeout', timeout));
      }
    });
    
    try {
      await connectionManager.connect(userId: userId ?? _defaultUserId);
      
      // Wait for both connections to be established
      await connectionManager.waitForBothConnections(timeout: timeout);
      
      timeoutTimer.cancel();
      if (!completer.isCompleted) {
        completer.complete();
      }
    } catch (e) {
      timeoutTimer.cancel();
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }
    
    return completer.future;
  }
  
  /// Wait for specific event type to be received
  static Future<T> waitForEvent<T>(
    Stream<T> eventStream, {
    Duration timeout = const Duration(seconds: 5),
    bool Function(T)? predicate,
  }) async {
    final completer = Completer<T>();
    late StreamSubscription<T> subscription;
    Timer? timeoutTimer;
    
    // Set up timeout
    timeoutTimer = Timer(timeout, () {
      subscription.cancel();
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Event timeout', timeout));
      }
    });
    
    // Listen for events
    subscription = eventStream.listen((event) {
      if (predicate == null || predicate(event)) {
        timeoutTimer?.cancel();
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.complete(event);
        }
      }
    });
    
    return completer.future;
  }
  
  /// Wait for multiple events of the same type
  static Future<List<T>> waitForEvents<T>(
    Stream<T> eventStream, {
    required int count,
    Duration timeout = const Duration(seconds: 10),
    bool Function(T)? predicate,
  }) async {
    final completer = Completer<List<T>>();
    final events = <T>[];
    late StreamSubscription<T> subscription;
    Timer? timeoutTimer;
    
    // Set up timeout
    timeoutTimer = Timer(timeout, () {
      subscription.cancel();
      if (!completer.isCompleted) {
        completer.complete(events); // Return what we have
      }
    });
    
    // Listen for events
    subscription = eventStream.listen((event) {
      if (predicate == null || predicate(event)) {
        events.add(event);
        
        if (events.length >= count) {
          timeoutTimer?.cancel();
          subscription.cancel();
          if (!completer.isCompleted) {
            completer.complete(events);
          }
        }
      }
    });
    
    return completer.future;
  }
  
  /// Wait for connection state to match condition
  static Future<void> waitForConnectionState(
    WebSocketConnectionManager connectionManager, {
    bool? isConnected,
    bool? isAudioConnected,
    bool? isBothConnected,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final completer = Completer<void>();
    Timer? timeoutTimer;
    Timer? checkTimer;
    
    // Set up timeout
    timeoutTimer = Timer(timeout, () {
      checkTimer?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Connection state timeout', timeout));
      }
    });
    
    // Check condition periodically
    checkTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
      bool conditionMet = true;
      
      if (isConnected != null && connectionManager.isConnected != isConnected) {
        conditionMet = false;
      }
      if (isAudioConnected != null && connectionManager.isAudioConnected != isAudioConnected) {
        conditionMet = false;
      }
      if (isBothConnected != null && connectionManager.isBothConnected != isBothConnected) {
        conditionMet = false;
      }
      
      if (conditionMet) {
        timeoutTimer?.cancel();
        timer.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });
    
    return completer.future;
  }
  
  /// Send a sequence of test events to mock server
  static Future<void> sendTestEventSequence(
    MockWebSocketServer server,
    String sessionId, {
    List<Map<String, dynamic>>? events,
    Duration? delayBetweenEvents,
  }) async {
    final testEvents = events ?? _generateDefaultEventSequence(sessionId);
    final delay = delayBetweenEvents ?? Duration(milliseconds: 100);
    
    for (final event in testEvents) {
      final eventType = event['type'] as String;
      
      // Route to appropriate channel based on event type
      if (_isAudioEvent(eventType)) {
        await server.sendToAudio(sessionId, event);
      } else {
        await server.sendToQueue(sessionId, event);
      }
      
      await Future.delayed(delay);
    }
  }
  
  /// Generate a complete TTS workflow sequence
  static Future<void> sendTTSWorkflow(
    MockWebSocketServer server,
    String sessionId, {
    String? text,
    String? provider,
    int? chunkCount,
  }) async {
    final events = MockEventGenerators.generateTTSFlow(
      sessionId: sessionId,
      text: text,
      provider: provider,
    );
    
    for (final event in events) {
      final eventType = event['type'] as String;
      
      if (_isAudioEvent(eventType)) {
        await server.sendToAudio(sessionId, event);
      } else {
        await server.sendToQueue(sessionId, event);
      }
      
      await Future.delayed(Duration(milliseconds: 50));
    }
  }
  
  /// Generate performance test load
  static Future<PerformanceTestResult> generatePerformanceLoad(
    MockWebSocketServer server,
    String sessionId, {
    int eventsPerSecond = 50,
    int durationSeconds = 5,
    List<String>? eventTypes,
  }) async {
    final result = PerformanceTestResult();
    final startTime = DateTime.now();
    
    final types = eventTypes ?? [
      'queue_todo_update',
      'notification_queue_update',
      'sys_time_update',
    ];
    
    final totalEvents = eventsPerSecond * durationSeconds;
    final intervalMs = 1000 ~/ eventsPerSecond;
    
    result.targetEventsPerSecond = eventsPerSecond;
    result.targetDurationSeconds = durationSeconds;
    result.totalEventsToSend = totalEvents;
    
    Timer.periodic(Duration(milliseconds: intervalMs), (timer) async {
      if (timer.tick > totalEvents) {
        timer.cancel();
        return;
      }
      
      final eventType = types[timer.tick % types.length];
      final event = _generateEventByType(eventType, sessionId);
      
      await server.sendToQueue(sessionId, event);
      result.eventsSent++;
    });
    
    // Wait for completion
    await Future.delayed(Duration(seconds: durationSeconds + 1));
    
    final endTime = DateTime.now();
    result.actualDuration = endTime.difference(startTime);
    result.actualEventsPerSecond = result.eventsSent / result.actualDuration.inSeconds;
    
    return result;
  }
  
  /// Measure event processing latency
  static Future<LatencyMeasurement> measureEventLatency(
    MockWebSocketServer server,
    WebSocketConnectionManager connectionManager,
    String sessionId, {
    int sampleCount = 10,
    String eventType = 'queue_todo_update',
  }) async {
    final latencies = <Duration>[];
    final subscription = connectionManager.queueUpdates.listen((_) {});
    
    for (int i = 0; i < sampleCount; i++) {
      final startTime = DateTime.now();
      
      final event = _generateEventByType(eventType, sessionId);
      await server.sendToQueue(sessionId, event);
      
      // Wait for event to be processed
      await waitForEvent(connectionManager.queueUpdates, timeout: Duration(seconds: 2));
      
      final endTime = DateTime.now();
      latencies.add(endTime.difference(startTime));
      
      // Small delay between samples
      await Future.delayed(Duration(milliseconds: 100));
    }
    
    await subscription.cancel();
    
    final totalMicroseconds = latencies.fold(0, (sum, duration) => sum + duration.inMicroseconds);
    final averageMicroseconds = totalMicroseconds ~/ latencies.length;
    
    return LatencyMeasurement(
      samples: latencies,
      average: Duration(microseconds: averageMicroseconds),
      minimum: latencies.reduce((a, b) => a < b ? a : b),
      maximum: latencies.reduce((a, b) => a > b ? a : b),
    );
  }
  
  /// Assert event sequence was received in order
  static void assertEventSequence<T>(
    List<T> actualEvents,
    List<T> expectedEvents, {
    bool allowExtra = false,
    String? message,
  }) {
    if (!allowExtra) {
      expect(actualEvents.length, equals(expectedEvents.length), 
          reason: message ?? 'Event count mismatch');
    } else {
      expect(actualEvents.length, greaterThanOrEqualTo(expectedEvents.length),
          reason: message ?? 'Insufficient events received');
    }
    
    for (int i = 0; i < expectedEvents.length; i++) {
      expect(actualEvents[i], equals(expectedEvents[i]),
          reason: message ?? 'Event mismatch at index $i');
    }
  }
  
  /// Assert events contain required fields
  static void assertEventFields(
    Map<String, dynamic> event,
    List<String> requiredFields, {
    String? message,
  }) {
    for (final field in requiredFields) {
      expect(event.containsKey(field), isTrue,
          reason: message ?? 'Missing required field: $field');
      expect(event[field], isNotNull,
          reason: message ?? 'Required field is null: $field');
    }
  }
  
  /// Assert performance metrics meet requirements
  static void assertPerformanceMetrics(
    PerformanceTestResult result, {
    double? minimumEventsPerSecond,
    Duration? maximumDuration,
    double? minimumDeliveryRate,
  }) {
    if (minimumEventsPerSecond != null) {
      expect(result.actualEventsPerSecond, greaterThanOrEqualTo(minimumEventsPerSecond),
          reason: 'Events per second below requirement');
    }
    
    if (maximumDuration != null) {
      expect(result.actualDuration, lessThanOrEqualTo(maximumDuration),
          reason: 'Duration exceeded maximum');
    }
    
    if (minimumDeliveryRate != null) {
      final deliveryRate = result.eventsReceived / result.eventsSent;
      expect(deliveryRate, greaterThanOrEqualTo(minimumDeliveryRate),
          reason: 'Event delivery rate below requirement');
    }
  }
  
  /// Create mock server with test configuration
  static Future<MockWebSocketServer> createTestServer({
    int? port,
    bool enableAutoEvents = false,
    Duration? eventInterval,
  }) async {
    final server = MockWebSocketServer(
      config: MockServerConfig(
        port: port ?? (8080 + _random.nextInt(1000)),
        enableAutoEventGeneration: enableAutoEvents,
        eventGenerationInterval: eventInterval?.inSeconds ?? 5,
        ttsGenerationDelay: 100,
        audioChunkDelay: 50,
        enableAudioEcho: true,
      ),
    );
    
    await server.start();
    return server;
  }
  
  /// Clean up test resources
  static Future<void> cleanupTestResources(
    List<dynamic> resources,
  ) async {
    for (final resource in resources) {
      try {
        if (resource is WebSocketConnectionManager) {
          await resource.disconnect();
        } else if (resource is WebSocketDebugMonitor) {
          resource.dispose();
        } else if (resource is WebSocketEventHandlerSystem) {
          resource.dispose();
        } else if (resource is MockWebSocketServer) {
          await resource.stop();
        } else if (resource is StreamSubscription) {
          await resource.cancel();
        }
      } catch (e) {
        // Ignore cleanup errors
        print('[TestUtils] Cleanup error (ignored): $e');
      }
    }
  }
  
  /// Generate default test event sequence
  static List<Map<String, dynamic>> _generateDefaultEventSequence(String sessionId) {
    return [
      MockEventGenerators.generateAuthSuccess(sessionId: sessionId),
      MockEventGenerators.generateConnect(sessionId: sessionId),
      MockEventGenerators.generateQueueUpdate(sessionId: sessionId, queueType: 'todo'),
      MockEventGenerators.generateSystemTimeUpdate(sessionId: sessionId),
      MockEventGenerators.generateNotificationQueueUpdate(sessionId: sessionId),
    ];
  }
  
  /// Check if event type is audio-related
  static bool _isAudioEvent(String eventType) {
    return eventType.contains('audio') || 
           eventType.contains('tts') ||
           eventType == AppConstants.eventAudioStreamingChunk ||
           eventType == AppConstants.eventAudioStreamingStatus ||
           eventType == AppConstants.eventAudioStreamingComplete;
  }
  
  /// Generate event by type name
  static Map<String, dynamic> _generateEventByType(String eventType, String sessionId) {
    switch (eventType) {
      case 'queue_todo_update':
        return MockEventGenerators.generateQueueUpdate(
          sessionId: sessionId, queueType: 'todo');
      case 'queue_running_update':
        return MockEventGenerators.generateQueueUpdate(
          sessionId: sessionId, queueType: 'running');
      case 'queue_done_update':
        return MockEventGenerators.generateQueueUpdate(
          sessionId: sessionId, queueType: 'done');
      case 'notification_queue_update':
        return MockEventGenerators.generateNotificationQueueUpdate(sessionId: sessionId);
      case 'sys_time_update':
        return MockEventGenerators.generateSystemTimeUpdate(sessionId: sessionId);
      case 'sys_ping':
        return MockEventGenerators.generateSystemPing(sessionId: sessionId);
      case 'audio_streaming_chunk':
        return MockEventGenerators.generateAudioStreamingChunk(sessionId: sessionId);
      default:
        return MockEventGenerators.generateQueueUpdate(sessionId: sessionId);
    }
  }
  
  /// Create timeline assertion helper
  static TimelineAssertion createTimelineAssertion() {
    return TimelineAssertion();
  }
  
  /// Generate realistic session scenario
  static Future<void> simulateRealisticSession(
    MockWebSocketServer server,
    WebSocketConnectionManager connectionManager,
    String sessionId, {
    Duration duration = const Duration(minutes: 2),
  }) async {
    final events = MockEventGenerators.generateSessionScenario(
      sessionId: sessionId,
      duration: duration,
    );
    
    final endTime = DateTime.now().add(duration);
    var eventIndex = 0;
    
    while (DateTime.now().isBefore(endTime) && eventIndex < events.length) {
      final event = events[eventIndex % events.length];
      
      if (_isAudioEvent(event['type'])) {
        await server.sendToAudio(sessionId, event);
      } else {
        await server.sendToQueue(sessionId, event);
      }
      
      eventIndex++;
      
      // Variable delay to simulate realistic timing
      final delayMs = 500 + _random.nextInt(2000); // 0.5-2.5 seconds
      await Future.delayed(Duration(milliseconds: delayMs));
    }
  }
}

/// Test connection setup container
class TestConnectionSetup {
  final WebSocketConnectionManager connectionManager;
  final WebSocketEventHandlerSystem eventHandlerSystem;
  final WebSocketDebugMonitor debugMonitor;
  
  TestConnectionSetup({
    required this.connectionManager,
    required this.eventHandlerSystem,
    required this.debugMonitor,
  });
  
  Future<void> dispose() async {
    await connectionManager.disconnect();
    debugMonitor.dispose();
    eventHandlerSystem.dispose();
  }
}

/// Performance test result container
class PerformanceTestResult {
  int targetEventsPerSecond = 0;
  int targetDurationSeconds = 0;
  int totalEventsToSend = 0;
  int eventsSent = 0;
  int eventsReceived = 0;
  Duration actualDuration = Duration.zero;
  double actualEventsPerSecond = 0.0;
  
  Map<String, dynamic> toJson() {
    return {
      'target_events_per_second': targetEventsPerSecond,
      'target_duration_seconds': targetDurationSeconds,
      'total_events_to_send': totalEventsToSend,
      'events_sent': eventsSent,
      'events_received': eventsReceived,
      'actual_duration_ms': actualDuration.inMilliseconds,
      'actual_events_per_second': actualEventsPerSecond,
      'delivery_rate': eventsSent > 0 ? eventsReceived / eventsSent : 0.0,
    };
  }
}

/// Latency measurement container
class LatencyMeasurement {
  final List<Duration> samples;
  final Duration average;
  final Duration minimum;
  final Duration maximum;
  
  LatencyMeasurement({
    required this.samples,
    required this.average,
    required this.minimum,
    required this.maximum,
  });
  
  Duration get median {
    final sorted = List<Duration>.from(samples)..sort((a, b) => a.compareTo(b));
    final middle = sorted.length ~/ 2;
    return sorted[middle];
  }
  
  double get standardDeviation {
    if (samples.isEmpty) return 0.0;
    
    final avgMs = average.inMicroseconds.toDouble();
    final variance = samples.fold(0.0, (sum, sample) {
      final diff = sample.inMicroseconds - avgMs;
      return sum + (diff * diff);
    }) / samples.length;
    
    return sqrt(variance);
  }
  
  Map<String, dynamic> toJson() {
    return {
      'sample_count': samples.length,
      'average_ms': average.inMilliseconds,
      'minimum_ms': minimum.inMilliseconds,
      'maximum_ms': maximum.inMilliseconds,
      'median_ms': median.inMilliseconds,
      'std_deviation_ms': standardDeviation / 1000, // Convert μs to ms
    };
  }
}

/// Timeline assertion helper for event ordering
class TimelineAssertion {
  final List<_TimelineEvent> _events = [];
  
  void addEvent(String name, DateTime timestamp, {Map<String, dynamic>? data}) {
    _events.add(_TimelineEvent(name, timestamp, data));
  }
  
  void assertEventOrder(List<String> expectedOrder, {Duration? tolerance}) {
    final actualOrder = _events.map((e) => e.name).toList();
    expect(actualOrder, equals(expectedOrder));
    
    if (tolerance != null) {
      for (int i = 1; i < _events.length; i++) {
        final timeDiff = _events[i].timestamp.difference(_events[i-1].timestamp);
        expect(timeDiff.abs(), lessThanOrEqualTo(tolerance),
            reason: 'Event timing outside tolerance: ${_events[i-1].name} -> ${_events[i].name}');
      }
    }
  }
  
  void assertEventWithinTimeRange(String eventName, DateTime start, DateTime end) {
    final event = _events.firstWhere((e) => e.name == eventName,
        orElse: () => throw Exception('Event not found: $eventName'));
    
    expect(event.timestamp.isAfter(start) && event.timestamp.isBefore(end), isTrue,
        reason: 'Event $eventName outside time range');
  }
  
  Duration getTimeBetween(String firstEvent, String secondEvent) {
    final first = _events.firstWhere((e) => e.name == firstEvent);
    final second = _events.firstWhere((e) => e.name == secondEvent);
    return second.timestamp.difference(first.timestamp);
  }
}

class _TimelineEvent {
  final String name;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  
  _TimelineEvent(this.name, this.timestamp, this.data);
}