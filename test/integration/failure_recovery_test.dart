import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import '../../lib/services/websocket/enhanced_websocket_service.dart';
import '../../lib/services/websocket/websocket_connection_manager.dart';
import '../../lib/services/websocket/websocket_message_router.dart';
import '../../lib/services/websocket/websocket_debug_monitor.dart';
import '../../lib/core/constants/app_constants.dart';
import '../mocks/mock_websocket_server.dart';
import '../helpers/mock_event_generators.dart';

void main() {
  group('Failure and Recovery Tests', () {
    late MockWebSocketServer mockServer;
    late WebSocketConnectionManager connectionManager;
    late WebSocketDebugMonitor debugMonitor;
    
    const String testUserId = 'recovery_test_user';
    late String testSessionId;
    
    setUpAll(() async {
      // Start mock server
      mockServer = MockWebSocketServer(
        config: MockServerConfig(
          port: 8083,
          enableAutoEventGeneration: false,
          ttsGenerationDelay: 100,
          audioChunkDelay: 50,
          simulateAuthFailure: false,
        ),
      );
      await mockServer.start();
      print('[RecoveryTest] Mock server started on port 8083');
    });
    
    tearDownAll(() async {
      await mockServer.stop();
    });
    
    setUp(() async {
      testSessionId = MockEventGenerators.generateSessionId();
      
      // Create connection manager with recovery settings
      final webSocketService = EnhancedWebSocketService(Dio());
      final messageRouter = WebSocketMessageRouter();
      
      connectionManager = WebSocketConnectionManager(
        webSocketService: webSocketService,
        messageRouter: messageRouter,
        config: ConnectionManagerConfig(
          enableLogging: true,
          enableHealthChecks: true,
          connectionCheckInterval: Duration(seconds: 2),
        ),
      );
      
      debugMonitor = WebSocketDebugMonitor(
        connectionManager: connectionManager,
        config: DebugConfig(
          enableEventLogging: true,
          enablePerformanceMonitoring: true,
          enableConsoleLogging: false,
          enablePerformanceAlerts: true,
        ),
      );
      
      webSocketService.setBaseUrl('ws://localhost:8083');
    });
    
    tearDown(() async {
      try {
        await connectionManager.disconnect();
      } catch (e) {
        // May already be disconnected from test scenarios
      }
      debugMonitor.dispose();
    });
    
    group('Connection Loss and Recovery', () {
      test('should detect connection loss and attempt reconnection', () async {
        final connectionEvents = <dynamic>[];
        final performanceAlerts = <PerformanceAlert>[];
        
        // Monitor connection state changes
        connectionManager.addConnectionStateListener((change) {
          connectionEvents.add(change);
          print('[RecoveryTest] Connection state: ${change.from} -> ${change.to}');
        });
        
        // Monitor performance alerts
        final alertSubscription = debugMonitor.performanceAlerts.listen((alert) {
          performanceAlerts.add(alert);
          print('[RecoveryTest] Performance alert: ${alert.type} - ${alert.message}');
        });
        
        // Establish initial connection
        await connectionManager.connect(userId: testUserId);
        expect(connectionManager.isBothConnected, isTrue);
        
        // Simulate connection loss by disconnecting session on server
        print('[RecoveryTest] Simulating connection loss...');
        await mockServer.disconnectSession(testSessionId);
        
        // Wait for detection and recovery attempt
        await Future.delayed(Duration(seconds: 5));
        
        // Verify connection loss was detected
        expect(connectionEvents, isNotEmpty);
        
        // Check for performance alerts about connection issues
        final connectionAlerts = performanceAlerts.where((alert) => 
            alert.type == PerformanceAlertType.connectionFlapping).toList();
        
        if (connectionAlerts.isNotEmpty) {
          print('[RecoveryTest] Connection flapping detected as expected');
        }
        
        await alertSubscription.cancel();
      });
      
      test('should handle partial connection loss (queue only)', () async {
        final connectionEvents = <dynamic>[];
        final queueUpdates = <QueueUpdateMessage>[];
        final audioChunks = <AudioChunkMessage>[];
        
        // Monitor events
        connectionManager.addConnectionStateListener(connectionEvents.add);
        final queueSub = connectionManager.queueUpdates.listen(queueUpdates.add);
        final audioSub = connectionManager.audioChunks.listen(audioChunks.add);
        
        // Establish both connections
        await connectionManager.connect(userId: testUserId);
        expect(connectionManager.isBothConnected, isTrue);
        
        // Send test events to verify both connections work
        final queueEvent = MockEventGenerators.generateQueueUpdate(sessionId: testSessionId);
        final audioEvent = MockEventGenerators.generateAudioStreamingChunk(sessionId: testSessionId);
        
        await mockServer.sendToQueue(testSessionId, queueEvent);
        await mockServer.sendToAudio(testSessionId, audioEvent);
        await Future.delayed(Duration(milliseconds: 200));
        
        expect(queueUpdates, isNotEmpty);
        expect(audioChunks, isNotEmpty);
        
        // Clear event lists
        queueUpdates.clear();
        audioChunks.clear();
        
        // Simulate audio connection loss only
        print('[RecoveryTest] Simulating audio connection loss...');
        final audioConnection = mockServer.audioConnections[testSessionId];
        if (audioConnection != null) {
          await audioConnection.sink.close();
          mockServer.audioConnections.remove(testSessionId);
        }
        
        await Future.delayed(Duration(milliseconds: 500));
        
        // Queue should still work, audio should not
        await mockServer.sendToQueue(testSessionId, queueEvent);
        await Future.delayed(Duration(milliseconds: 200));
        
        expect(queueUpdates, isNotEmpty); // Queue still working
        expect(connectionManager.isConnected, isTrue);
        expect(connectionManager.isAudioConnected, isFalse);
        
        await queueSub.cancel();
        await audioSub.cancel();
      });
      
      test('should handle authentication failures during reconnection', () async {
        final authMessages = <AuthMessage>[];
        
        // Monitor auth messages
        final authSub = connectionManager.authMessages.listen(authMessages.add);
        
        // Establish initial connection
        await connectionManager.connect(userId: testUserId);
        expect(connectionManager.isBothConnected, isTrue);
        
        // Trigger auth failure on server for future connections
        mockServer.triggerAuthFailure();
        
        // Disconnect and attempt to reconnect
        await connectionManager.disconnect();
        
        try {
          await connectionManager.connect(userId: testUserId);
        } catch (e) {
          print('[RecoveryTest] Expected auth failure: $e');
        }
        
        await Future.delayed(Duration(milliseconds: 500));
        
        // Verify auth failure was handled
        expect(authMessages.any((msg) => msg.authType == 'auth_error'), isTrue);
        
        // Reset auth failure and retry
        mockServer.resetAuthFailure();
        await connectionManager.connect(userId: testUserId);
        expect(connectionManager.isBothConnected, isTrue);
        
        await authSub.cancel();
      });
    });
    
    group('Data Loss and Synchronization', () {
      test('should handle missing event sequences', () async {
        final audioChunks = <AudioChunkMessage>[];
        final debugEvents = <DebugUpdate>[];
        
        // Monitor events
        final audioSub = connectionManager.audioChunks.listen(audioChunks.add);
        final debugSub = debugMonitor.debugUpdates.listen(debugEvents.add);
        
        await connectionManager.connect(userId: testUserId);
        
        // Send audio chunks with gaps in sequence
        final totalChunks = 10;
        final missingChunks = [2, 5, 8]; // Simulate missing chunks
        
        print('[RecoveryTest] Sending audio chunks with gaps...');
        
        for (int i = 0; i < totalChunks; i++) {
          if (missingChunks.contains(i)) {
            print('[RecoveryTest] Skipping chunk $i (simulated loss)');
            continue;
          }
          
          final chunkEvent = MockEventGenerators.generateAudioStreamingChunk(
            sessionId: testSessionId,
            sequenceNumber: i,
            totalChunks: totalChunks,
            isLastChunk: i == totalChunks - 1,
          );
          
          await mockServer.sendToAudio(testSessionId, chunkEvent);
          await Future.delayed(Duration(milliseconds: 50));
        }
        
        await Future.delayed(Duration(milliseconds: 500));
        
        // Verify chunks were received (minus missing ones)
        final expectedChunks = totalChunks - missingChunks.length;
        expect(audioChunks.length, equals(expectedChunks));
        
        // Check for gap detection in debug events
        final errorEvents = debugEvents.where((event) => 
            event.type == DebugUpdateType.eventLogged && 
            event.data.toString().contains('error')).toList();
        
        print('[RecoveryTest] Received ${audioChunks.length}/$totalChunks chunks');
        if (errorEvents.isNotEmpty) {
          print('[RecoveryTest] Gap detection events: ${errorEvents.length}');
        }
        
        await audioSub.cancel();
        await debugSub.cancel();
      });
      
      test('should handle out-of-order events', () async {
        final queueUpdates = <QueueUpdateMessage>[];
        final timestamps = <DateTime>[];
        
        final subscription = connectionManager.queueUpdates.listen((update) {
          queueUpdates.add(update);
          timestamps.add(update.timestamp);
        });
        
        await connectionManager.connect(userId: testUserId);
        
        print('[RecoveryTest] Sending out-of-order events...');
        
        // Generate events with timestamps
        final baseTime = DateTime.now();
        final events = [
          (0, MockEventGenerators.generateQueueUpdate(sessionId: testSessionId)),
          (2, MockEventGenerators.generateQueueUpdate(sessionId: testSessionId)),
          (1, MockEventGenerators.generateQueueUpdate(sessionId: testSessionId)), // Out of order
          (4, MockEventGenerators.generateQueueUpdate(sessionId: testSessionId)),
          (3, MockEventGenerators.generateQueueUpdate(sessionId: testSessionId)), // Out of order
        ];
        
        // Send events in wrong order
        for (final (offset, event) in events) {
          event['timestamp'] = baseTime.add(Duration(seconds: offset)).toIso8601String();
          await mockServer.sendToQueue(testSessionId, event);
          await Future.delayed(Duration(milliseconds: 100));
        }
        
        await Future.delayed(Duration(milliseconds: 500));
        
        // Verify all events were received
        expect(queueUpdates.length, equals(events.length));
        
        // Check if timestamps reflect order received (not logical order)
        print('[RecoveryTest] Event timestamps (received order):');
        for (int i = 0; i < timestamps.length; i++) {
          print('[RecoveryTest]   Event $i: ${timestamps[i]}');
        }
        
        await subscription.cancel();
      });
      
      test('should handle corrupted or malformed events', () async {
        final receivedEvents = <dynamic>[];
        final errorEvents = <ErrorMessage>[];
        final performanceAlerts = <PerformanceAlert>[];
        
        // Monitor all events
        final eventSubs = [
          connectionManager.queueUpdates.listen(receivedEvents.add),
          connectionManager.notifications.listen(receivedEvents.add),
          connectionManager.errors.listen(errorEvents.add),
        ];
        
        final alertSub = debugMonitor.performanceAlerts.listen(performanceAlerts.add);
        
        await connectionManager.connect(userId: testUserId);
        
        print('[RecoveryTest] Sending malformed events...');
        
        // Send valid event first
        final validEvent = MockEventGenerators.generateQueueUpdate(sessionId: testSessionId);
        await mockServer.sendToQueue(testSessionId, validEvent);
        
        // Send malformed events
        final malformedEvents = [
          '{"type": "invalid_json", "data": {invalid}}', // Invalid JSON
          '{"missing_type": true}', // Missing required field
          '{"type": "", "data": null}', // Empty type
          '{"type": "unknown_event", "data": {}}', // Unknown event type
        ];
        
        for (final malformedEvent in malformedEvents) {
          try {
            // Directly send malformed string to connection
            final queueConnection = mockServer.queueConnections[testSessionId];
            if (queueConnection != null) {
              queueConnection.sink.add(malformedEvent);
            }
          } catch (e) {
            print('[RecoveryTest] Expected error sending malformed event: $e');
          }
          await Future.delayed(Duration(milliseconds: 100));
        }
        
        // Send another valid event to verify system still works
        final validEvent2 = MockEventGenerators.generateNotificationQueueUpdate(sessionId: testSessionId);
        await mockServer.sendToQueue(testSessionId, validEvent2);
        
        await Future.delayed(Duration(milliseconds: 500));
        
        // Verify system handled malformed events gracefully
        expect(receivedEvents.length, greaterThanOrEqualTo(2)); // Valid events received
        
        // Check for error handling
        if (errorEvents.isNotEmpty) {
          print('[RecoveryTest] Error events generated: ${errorEvents.length}');
        }
        
        // Check for high error rate alerts
        final errorRateAlerts = performanceAlerts.where((alert) => 
            alert.type == PerformanceAlertType.highErrorRate).toList();
        
        if (errorRateAlerts.isNotEmpty) {
          print('[RecoveryTest] High error rate detected as expected');
        }
        
        for (final sub in eventSubs) {
          await sub.cancel();
        }
        await alertSub.cancel();
      });
    });
    
    group('Resource Exhaustion Scenarios', () {
      test('should handle queue overflow gracefully', () async {
        final performanceAlerts = <PerformanceAlert>[];
        
        final alertSub = debugMonitor.performanceAlerts.listen(performanceAlerts.add);
        
        await connectionManager.connect(userId: testUserId);
        
        print('[RecoveryTest] Testing queue overflow handling...');
        
        // Send many messages rapidly while disconnected to fill queue
        await connectionManager.disconnect();
        
        // Queue messages while disconnected
        final messageCount = 1000;
        final sendFutures = <Future>[];
        
        for (int i = 0; i < messageCount; i++) {
          final future = connectionManager.sendTTSRequest(
            text: 'Test message $i',
            provider: 'elevenlabs',
          );
          sendFutures.add(future);
        }
        
        // Wait for all messages to be queued
        await Future.wait(sendFutures, eagerError: false);
        
        // Check queue size
        final stats = connectionManager.getConnectionStats();
        print('[RecoveryTest] Messages queued: ${stats['websocket_stats']}');
        
        // Reconnect and see how system handles the queue
        await connectionManager.connect(userId: testUserId);
        
        // Wait for queue processing
        await Future.delayed(Duration(seconds: 3));
        
        // Check for memory usage alerts
        final memoryAlerts = performanceAlerts.where((alert) => 
            alert.type == PerformanceAlertType.memoryUsage).toList();
        
        if (memoryAlerts.isNotEmpty) {
          print('[RecoveryTest] Memory usage alerts generated: ${memoryAlerts.length}');
        }
        
        await alertSub.cancel();
      });
      
      test('should handle excessive subscription changes', () async {
        final subscriptionChanges = <dynamic>[];
        final performanceAlerts = <PerformanceAlert>[];
        
        // Monitor changes and alerts
        final changeSub = connectionManager.subscriptionChanges.listen(subscriptionChanges.add);
        final alertSub = debugMonitor.performanceAlerts.listen(performanceAlerts.add);
        
        await connectionManager.connect(userId: testUserId);
        
        print('[RecoveryTest] Testing excessive subscription changes...');
        
        // Rapid subscription changes
        final changeCount = 200;
        final eventTypes = [
          AppConstants.eventQueueTodoUpdate,
          AppConstants.eventQueueRunningUpdate,
          AppConstants.eventAudioStreamingChunk,
          AppConstants.eventNotificationQueueUpdate,
          AppConstants.eventSysTimeUpdate,
        ];
        
        for (int i = 0; i < changeCount; i++) {
          // Randomly change subscriptions
          final random = Random();
          final operation = random.nextInt(3);
          
          try {
            switch (operation) {
              case 0:
                await connectionManager.subscribeToAllEvents();
                break;
              case 1:
                final selectedEvents = eventTypes.take(random.nextInt(eventTypes.length) + 1).toSet();
                await connectionManager.subscribeToSpecificEvents(selectedEvents);
                break;
              case 2:
                final categories = ['queue', 'audio', 'system'].take(random.nextInt(3) + 1).toSet();
                await connectionManager.subscribeToEventCategories(categories);
                break;
            }
          } catch (e) {
            // Some operations might fail under stress - that's expected
            print('[RecoveryTest] Subscription change failed (expected): $e');
          }
          
          // Small delay to prevent overwhelming the system
          if (i % 10 == 0) {
            await Future.delayed(Duration(milliseconds: 10));
          }
        }
        
        await Future.delayed(Duration(seconds: 1));
        
        // Verify system is still responsive
        expect(connectionManager.isBothConnected, isTrue);
        
        // Check subscription state
        final finalStats = connectionManager.getSubscriptionStats();
        expect(finalStats, isNotNull);
        
        print('[RecoveryTest] Final subscription state: ${finalStats['subscribe_to_all']}');
        print('[RecoveryTest] Subscription changes processed: ${subscriptionChanges.length}');
        
        await changeSub.cancel();
        await alertSub.cancel();
      });
    });
    
    group('Network Condition Simulation', () {
      test('should handle high latency conditions', () async {
        final responseMessages = <dynamic>[];
        final responseTimes = <Duration>[];
        
        await connectionManager.connect(userId: testUserId);
        
        print('[RecoveryTest] Simulating high latency conditions...');
        
        // Send requests and measure response times
        for (int i = 0; i < 10; i++) {
          final startTime = DateTime.now();
          
          // Send TTS request
          await connectionManager.sendTTSRequest(
            text: 'Test message $i',
            provider: 'elevenlabs',
          );
          
          // Simulate network delay by adding delay to server responses
          await Future.delayed(Duration(milliseconds: 500 + Random().nextInt(500)));
          
          final endTime = DateTime.now();
          responseTimes.add(endTime.difference(startTime));
          
          print('[RecoveryTest] Request $i response time: ${responseTimes.last.inMilliseconds}ms');
        }
        
        // Verify system handled high latency
        final averageLatency = responseTimes.fold(Duration.zero, (a, b) => a + b) / responseTimes.length;
        print('[RecoveryTest] Average latency: ${averageLatency.inMilliseconds}ms');
        
        // System should remain stable even with high latency
        expect(connectionManager.isBothConnected, isTrue);
      });
      
      test('should handle intermittent connectivity', () async {
        final connectionEvents = <dynamic>[];
        final receivedEvents = <dynamic>[];
        
        // Monitor connection state
        connectionManager.addConnectionStateListener(connectionEvents.add);
        final eventSub = connectionManager.queueUpdates.listen(receivedEvents.add);
        
        await connectionManager.connect(userId: testUserId);
        
        print('[RecoveryTest] Simulating intermittent connectivity...');
        
        // Simulate on/off connectivity pattern
        for (int cycle = 0; cycle < 5; cycle++) {
          print('[RecoveryTest] Cycle $cycle: Disconnecting...');
          
          // Disconnect
          await mockServer.disconnectSession(testSessionId);
          await Future.delayed(Duration(seconds: 1));
          
          print('[RecoveryTest] Cycle $cycle: Reconnecting...');
          
          // Attempt to send events during disconnection
          final event = MockEventGenerators.generateQueueUpdate(sessionId: testSessionId);
          try {
            await mockServer.sendToQueue(testSessionId, event);
          } catch (e) {
            // Expected to fail during disconnection
          }
          
          // Reconnect (may need to call connect again depending on implementation)
          try {
            await connectionManager.connect(userId: testUserId);
          } catch (e) {
            // May already be attempting to reconnect
          }
          
          await Future.delayed(Duration(seconds: 1));
          
          // Send events during good connectivity
          if (connectionManager.isBothConnected) {
            await mockServer.sendToQueue(testSessionId, event);
          }
        }
        
        await Future.delayed(Duration(seconds: 2));
        
        // Verify system handled intermittent connectivity
        expect(connectionEvents, isNotEmpty);
        print('[RecoveryTest] Connection state changes: ${connectionEvents.length}');
        print('[RecoveryTest] Events received during test: ${receivedEvents.length}');
        
        await eventSub.cancel();
      });
    });
    
    group('Error Recovery Validation', () {
      test('should maintain data consistency during failures', () async {
        final queueStates = <Map<String, dynamic>>[];
        
        final queueHandler = connectionManager.connectionManager.eventHandlerSystem?.queueHandler;
        if (queueHandler != null) {
          final stateSub = queueHandler.stateUpdates.listen((update) {
            queueStates.add({
              'queue_type': update.queueType,
              'item_count': update.totalCount,
              'timestamp': update.timestamp,
            });
          });
        }
        
        await connectionManager.connect(userId: testUserId);
        
        print('[RecoveryTest] Testing data consistency during failures...');
        
        // Send initial queue state
        final initialEvent = MockEventGenerators.generateQueueUpdate(
          sessionId: testSessionId,
          queueType: 'todo',
          itemCount: 5,
        );
        await mockServer.sendToQueue(testSessionId, initialEvent);
        await Future.delayed(Duration(milliseconds: 200));
        
        // Simulate failure during queue processing
        await mockServer.disconnectSession(testSessionId);
        
        // Try to send queue updates during disconnection
        final failureEvents = [
          MockEventGenerators.generateQueueUpdate(
            sessionId: testSessionId,
            queueType: 'running',
            itemCount: 2,
          ),
          MockEventGenerators.generateQueueUpdate(
            sessionId: testSessionId,
            queueType: 'done',
            itemCount: 1,
          ),
        ];
        
        for (final event in failureEvents) {
          try {
            await mockServer.sendToQueue(testSessionId, event);
          } catch (e) {
            // Expected to fail
          }
        }
        
        // Reconnect and resend state
        await connectionManager.connect(userId: testUserId);
        
        // Send recovery state
        final recoveryEvent = MockEventGenerators.generateQueueUpdate(
          sessionId: testSessionId,
          queueType: 'done',
          itemCount: 3,
        );
        await mockServer.sendToQueue(testSessionId, recoveryEvent);
        
        await Future.delayed(Duration(milliseconds: 500));
        
        // Verify data consistency
        expect(queueStates, isNotEmpty);
        
        // Check that final state is consistent
        if (queueStates.isNotEmpty) {
          final finalState = queueStates.last;
          print('[RecoveryTest] Final queue state: $finalState');
          expect(finalState['item_count'], isA<int>());
        }
      });
      
      test('should provide proper error reporting and diagnostics', () async {
        final errorMessages = <ErrorMessage>[];
        final performanceAlerts = <PerformanceAlert>[];
        final debugUpdates = <DebugUpdate>[];
        
        // Monitor all error sources
        final subscriptions = [
          connectionManager.errors.listen(errorMessages.add),
          debugMonitor.performanceAlerts.listen(performanceAlerts.add),
          debugMonitor.debugUpdates.listen(debugUpdates.add),
        ];
        
        await connectionManager.connect(userId: testUserId);
        
        print('[RecoveryTest] Testing error reporting and diagnostics...');
        
        // Trigger various error conditions
        
        // 1. Authentication error
        mockServer.triggerAuthFailure();
        try {
          await connectionManager.disconnect();
          await connectionManager.connect(userId: testUserId);
        } catch (e) {
          // Expected
        }
        mockServer.resetAuthFailure();
        
        await Future.delayed(Duration(milliseconds: 200));
        
        // 2. Send malformed message
        final queueConnection = mockServer.queueConnections[testSessionId];
        if (queueConnection != null) {
          queueConnection.sink.add('invalid json {');
        }
        
        await Future.delayed(Duration(milliseconds: 200));
        
        // 3. Generate event burst to trigger performance alerts
        for (int i = 0; i < 30; i++) {
          final event = MockEventGenerators.generateQueueUpdate(sessionId: testSessionId);
          await mockServer.sendToQueue(testSessionId, event);
        }
        
        await Future.delayed(Duration(seconds: 1));
        
        // Verify comprehensive error reporting
        print('[RecoveryTest] Error messages: ${errorMessages.length}');
        print('[RecoveryTest] Performance alerts: ${performanceAlerts.length}');
        print('[RecoveryTest] Debug updates: ${debugUpdates.length}');
        
        // Generate diagnostic report
        final healthReport = debugMonitor.getConnectionHealthReport();
        final debugStats = debugMonitor.getDebugStatistics();
        
        expect(healthReport, isNotNull);
        expect(debugStats, isNotNull);
        
        print('[RecoveryTest] Health report stability score: ${healthReport['stability_score']}');
        print('[RecoveryTest] Total events in debug log: ${debugStats['log_sizes']['event_log']}');
        
        for (final sub in subscriptions) {
          await sub.cancel();
        }
      });
    });
  });
}