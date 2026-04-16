import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
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

void main() {
  group('Event System Integration Tests', () {
    late MockWebSocketServer mockServer;
    late WebSocketConnectionManager connectionManager;
    late WebSocketEventHandlerSystem eventHandlerSystem;
    late WebSocketDebugMonitor debugMonitor;
    
    // Test configuration
    const String testUserId = 'test_user_123';
    late String testSessionId;
    
    setUpAll(() async {
      // Start mock server
      mockServer = MockWebSocketServer(
        config: MockServerConfig.testing(),
      );
      await mockServer.start();
      print('[Test] Mock server started on port ${mockServer.config.port}');
    });
    
    tearDownAll(() async {
      await mockServer.stop();
    });
    
    setUp(() async {
      // Generate test session ID
      testSessionId = MockEventGenerators.generateSessionId();
      
      // Create WebSocket service components
      final webSocketService = EnhancedWebSocketService(Dio());
      final messageRouter = WebSocketMessageRouter();
      
      connectionManager = WebSocketConnectionManager(
        webSocketService: webSocketService,
        messageRouter: messageRouter,
        config: ConnectionManagerConfig.development(),
      );
      
      eventHandlerSystem = WebSocketEventHandlerSystem(
        connectionManager: connectionManager,
      );
      
      debugMonitor = WebSocketDebugMonitor(
        connectionManager: connectionManager,
        eventHandlerSystem: eventHandlerSystem,
        config: DebugConfig.verbose(),
      );
      
      // Override base URL to point to mock server
      webSocketService.setBaseUrl('ws://localhost:${mockServer.config.port}');
    });
    
    tearDown(() async {
      await connectionManager.disconnect();
      debugMonitor.dispose();
      eventHandlerSystem.dispose();
    });
    
    group('Connection and Authentication', () {
      test('should establish dual WebSocket connections successfully', () async {
        // Test dual connection establishment
        await connectionManager.connect(userId: testUserId);
        
        // Verify both connections are established
        expect(connectionManager.isConnected, isTrue);
        expect(connectionManager.isAudioConnected, isTrue);
        expect(connectionManager.isBothConnected, isTrue);
        expect(connectionManager.sessionId, equals(testSessionId));
        expect(connectionManager.userId, equals(testUserId));
      });
      
      test('should handle authentication flow correctly', () async {
        final authMessages = <AuthMessage>[];
        
        // Listen for auth messages
        final subscription = connectionManager.authMessages.listen(authMessages.add);
        
        // Connect and authenticate
        await connectionManager.connect(userId: testUserId);
        
        // Wait for auth messages
        await Future.delayed(Duration(milliseconds: 500));
        
        // Verify authentication success
        expect(authMessages, isNotEmpty);
        expect(authMessages.any((msg) => msg.authType == 'auth_success'), isTrue);
        expect(authMessages.any((msg) => msg.authType == 'connect'), isTrue);
        
        await subscription.cancel();
      });
      
      test('should handle authentication failure gracefully', () async {
        final authMessages = <AuthMessage>[];
        
        // Trigger auth failure on server
        mockServer.triggerAuthFailure();
        
        // Listen for auth messages
        final subscription = connectionManager.authMessages.listen(authMessages.add);
        
        // Attempt to connect
        try {
          await connectionManager.connect(userId: testUserId);
        } catch (e) {
          // Expected to fail
        }
        
        await Future.delayed(Duration(milliseconds: 500));
        
        // Verify authentication failure
        expect(authMessages.any((msg) => msg.authType == 'auth_error'), isTrue);
        
        // Reset auth failure
        mockServer.resetAuthFailure();
        await subscription.cancel();
      });
      
      test('should handle partial connections (queue only)', () async {
        // Connect queue only
        await connectionManager.connectQueue(userId: testUserId);
        
        expect(connectionManager.isConnected, isTrue);
        expect(connectionManager.isAudioConnected, isFalse);
        expect(connectionManager.isBothConnected, isFalse);
      });
      
      test('should handle partial connections (audio only)', () async {
        // Connect audio only
        await connectionManager.connectAudio(userId: testUserId);
        
        expect(connectionManager.isConnected, isFalse);
        expect(connectionManager.isAudioConnected, isTrue);
        expect(connectionManager.isBothConnected, isFalse);
      });
    });
    
    group('Event Subscription Management', () {
      test('should handle subscribe-to-all mode correctly', () async {
        await connectionManager.connect(userId: testUserId);
        
        // Subscribe to all events (default)
        await connectionManager.subscribeToAllEvents();
        
        final stats = connectionManager.getSubscriptionStats();
        expect(stats['subscribe_to_all'], isTrue);
      });
      
      test('should handle specific event subscriptions', () async {
        await connectionManager.connect(userId: testUserId);
        
        // Subscribe to specific events
        final specificEvents = {
          AppConstants.eventAudioStreamingChunk,
          AppConstants.eventQueueTodoUpdate,
          AppConstants.eventSysTimeUpdate,
        };
        
        await connectionManager.subscribeToSpecificEvents(specificEvents);
        
        final stats = connectionManager.getSubscriptionStats();
        expect(stats['subscribe_to_all'], isFalse);
        expect(stats['total_subscribed_events'], equals(specificEvents.length));
      });
      
      test('should handle category-based subscriptions', () async {
        await connectionManager.connect(userId: testUserId);
        
        // Subscribe to audio and system categories
        await connectionManager.subscribeToEventCategories({'audio', 'system'});
        
        final stats = connectionManager.getSubscriptionStats();
        expect(stats['subscribe_to_all'], isFalse);
        
        final categoryBreakdown = stats['category_breakdown'] as Map<String, dynamic>;
        expect(categoryBreakdown['audio']['subscription_rate'], equals(1.0));
        expect(categoryBreakdown['system']['subscription_rate'], equals(1.0));
      });
      
      test('should handle dynamic subscription changes', () async {
        await connectionManager.connect(userId: testUserId);
        
        // Start with specific events
        await connectionManager.subscribeToSpecificEvents({
          AppConstants.eventQueueTodoUpdate,
        });
        
        // Add more events
        await connectionManager.addEventSubscriptions({
          AppConstants.eventAudioStreamingChunk,
          AppConstants.eventSysTimeUpdate,
        });
        
        final stats = connectionManager.getSubscriptionStats();
        expect(stats['total_subscribed_events'], equals(3));
        
        // Remove some events
        await connectionManager.removeEventSubscriptions({
          AppConstants.eventSysTimeUpdate,
        });
        
        final updatedStats = connectionManager.getSubscriptionStats();
        expect(updatedStats['total_subscribed_events'], equals(2));
      });
    });
    
    group('Event Handling and Routing', () {
      test('should route queue events correctly', () async {
        final queueUpdates = <QueueUpdateMessage>[];
        
        await connectionManager.connect(userId: testUserId);
        
        // Listen for queue updates
        final subscription = connectionManager.queueUpdates.listen(queueUpdates.add);
        
        // Generate mock queue event on server
        final mockEvent = MockEventGenerators.generateQueueUpdate(
          sessionId: testSessionId,
          queueType: 'todo',
          itemCount: 3,
        );
        
        // Send event through mock server
        await mockServer.sendToQueue(testSessionId, mockEvent);
        
        // Wait for event processing
        await Future.delayed(Duration(milliseconds: 200));
        
        // Verify event was received and routed
        expect(queueUpdates, isNotEmpty);
        expect(queueUpdates.first.queueType, equals('todo'));
        expect(queueUpdates.first.sessionId, equals(testSessionId));
        
        await subscription.cancel();
      });
      
      test('should route audio events correctly', () async {
        final audioChunks = <AudioChunkMessage>[];
        final ttsStatus = <TTSStatusMessage>[];
        
        await connectionManager.connect(userId: testUserId);
        
        // Listen for audio events
        final audioSub = connectionManager.audioChunks.listen(audioChunks.add);
        final statusSub = connectionManager.ttsStatus.listen(ttsStatus.add);
        
        // Generate mock audio events
        final chunkEvent = MockEventGenerators.generateAudioStreamingChunk(
          sessionId: testSessionId,
          sequenceNumber: 0,
          totalChunks: 5,
        );
        
        final statusEvent = MockEventGenerators.generateAudioStreamingStatus(
          sessionId: testSessionId,
          status: 'streaming',
        );
        
        // Send events through mock server
        await mockServer.sendToAudio(testSessionId, chunkEvent);
        await mockServer.sendToAudio(testSessionId, statusEvent);
        
        await Future.delayed(Duration(milliseconds: 200));
        
        // Verify events were received
        expect(audioChunks, isNotEmpty);
        expect(ttsStatus, isNotEmpty);
        expect(audioChunks.first.sequenceNumber, equals(0));
        expect(ttsStatus.first.status, equals('streaming'));
        
        await audioSub.cancel();
        await statusSub.cancel();
      });
      
      test('should route notification events correctly', () async {
        final notifications = <NotificationMessage>[];
        
        await connectionManager.connect(userId: testUserId);
        
        // Listen for notifications
        final subscription = connectionManager.notifications.listen(notifications.add);
        
        // Generate mock notification event
        final notificationEvent = MockEventGenerators.generateNotificationQueueUpdate(
          sessionId: testSessionId,
          message: 'Test notification message',
        );
        
        await mockServer.sendToQueue(testSessionId, notificationEvent);
        await Future.delayed(Duration(milliseconds: 200));
        
        // Verify notification was received
        expect(notifications, isNotEmpty);
        expect(notifications.first.message, equals('Test notification message'));
        
        await subscription.cancel();
      });
      
      test('should route system events correctly', () async {
        final systemMessages = <SystemMessage>[];
        
        await connectionManager.connect(userId: testUserId);
        
        // Listen for system messages
        final subscription = connectionManager.systemMessages.listen(systemMessages.add);
        
        // Generate mock system events
        final pingEvent = MockEventGenerators.generateSystemPing(sessionId: testSessionId);
        final timeEvent = MockEventGenerators.generateSystemTimeUpdate(sessionId: testSessionId);
        
        await mockServer.sendToQueue(testSessionId, pingEvent);
        await mockServer.sendToQueue(testSessionId, timeEvent);
        await Future.delayed(Duration(milliseconds: 200));
        
        // Verify system messages were received
        expect(systemMessages.length, greaterThanOrEqualTo(2));
        expect(systemMessages.any((msg) => msg.systemType == 'ping'), isTrue);
        expect(systemMessages.any((msg) => msg.systemType == 'time_update'), isTrue);
        
        await subscription.cancel();
      });
    });
    
    group('Event Handler System', () {
      test('should process queue events through handlers', () async {
        final queueHandler = eventHandlerSystem.queueHandler;
        final stateUpdates = <QueueStateUpdate>[];
        final notifications = <QueueNotification>[];
        
        await connectionManager.connect(userId: testUserId);
        
        // Listen for handler output
        final stateSub = queueHandler.stateUpdates.listen(stateUpdates.add);
        final notifSub = queueHandler.notifications.listen(notifications.add);
        
        // Generate queue events
        final todoEvent = MockEventGenerators.generateQueueUpdate(
          sessionId: testSessionId,
          queueType: 'todo',
          itemCount: 2,
        );
        
        final doneEvent = MockEventGenerators.generateQueueUpdate(
          sessionId: testSessionId,
          queueType: 'done',
          itemCount: 1,
        );
        
        await mockServer.sendToQueue(testSessionId, todoEvent);
        await mockServer.sendToQueue(testSessionId, doneEvent);
        await Future.delayed(Duration(milliseconds: 300));
        
        // Verify handler processed events
        expect(stateUpdates.length, greaterThanOrEqualTo(2));
        expect(notifications, isNotEmpty); // Should generate completion notification
        
        final summary = queueHandler.getQueueSummary();
        expect(summary['todo'], equals(2));
        expect(summary['done'], equals(1));
        
        await stateSub.cancel();
        await notifSub.cancel();
      });
      
      test('should process audio events through handlers', () async {
        final audioHandler = eventHandlerSystem.audioHandler;
        final progressUpdates = <AudioStreamProgress>[];
        final playbackEvents = <AudioPlaybackEvent>[];
        
        await connectionManager.connect(userId: testUserId);
        
        // Listen for handler output
        final progressSub = audioHandler.streamProgress.listen(progressUpdates.add);
        final playbackSub = audioHandler.playbackEvents.listen(playbackEvents.add);
        
        // Generate TTS flow events
        final ttsEvents = MockEventGenerators.generateTTSFlow(
          sessionId: testSessionId,
          text: 'Test TTS message',
        );
        
        // Send events through server
        for (final event in ttsEvents) {
          if (event['type'].toString().contains('audio')) {
            await mockServer.sendToAudio(testSessionId, event);
          } else {
            await mockServer.sendToQueue(testSessionId, event);
          }
          await Future.delayed(Duration(milliseconds: 50));
        }
        
        await Future.delayed(Duration(milliseconds: 500));
        
        // Verify handler processed events
        expect(progressUpdates, isNotEmpty);
        expect(playbackEvents, isNotEmpty);
        
        final stats = audioHandler.getAudioStats();
        expect(stats['total_bytes_received'], greaterThan(0));
        
        await progressSub.cancel();
        await playbackSub.cancel();
      });
      
      test('should handle notifications through handlers', () async {
        final notificationHandler = eventHandlerSystem.notificationHandler;
        final userNotifications = <UserNotification>[];
        
        await connectionManager.connect(userId: testUserId);
        
        // Listen for handler output
        final subscription = notificationHandler.notifications.listen(userNotifications.add);
        
        // Generate notification events
        final queueNotif = MockEventGenerators.generateNotificationQueueUpdate(
          sessionId: testSessionId,
          message: 'Queue processing completed',
        );
        
        final soundNotif = MockEventGenerators.generateNotificationPlaySound(
          sessionId: testSessionId,
          soundType: 'chime',
        );
        
        await mockServer.sendToQueue(testSessionId, queueNotif);
        await mockServer.sendToQueue(testSessionId, soundNotif);
        await Future.delayed(Duration(milliseconds: 200));
        
        // Verify notifications were processed
        expect(userNotifications.length, greaterThanOrEqualTo(2));
        expect(userNotifications.any((n) => n.type == UserNotificationType.info), isTrue);
        expect(userNotifications.any((n) => n.type == UserNotificationType.audio), isTrue);
        
        await subscription.cancel();
      });
      
      test('should handle system events through handlers', () async {
        final systemHandler = eventHandlerSystem.systemHandler;
        final statusUpdates = <SystemStatus>[];
        
        await connectionManager.connect(userId: testUserId);
        
        // Listen for handler output
        final subscription = systemHandler.statusUpdates.listen(statusUpdates.add);
        
        // Generate ping/pong sequence
        final pingEvent = MockEventGenerators.generateSystemPing(sessionId: testSessionId);
        final pongEvent = MockEventGenerators.generateSystemPong(
          sessionId: testSessionId,
          pingId: pingEvent['ping_id'],
        );
        
        await mockServer.sendToQueue(testSessionId, pingEvent);
        await Future.delayed(Duration(milliseconds: 50));
        await mockServer.sendToQueue(testSessionId, pongEvent);
        await Future.delayed(Duration(milliseconds: 200));
        
        // Verify system stats were updated
        expect(statusUpdates, isNotEmpty);
        
        final stats = systemHandler.getSystemStats();
        expect(stats['ping_pong_active'], isTrue);
        expect(stats['current_latency_ms'], isNotNull);
        
        await subscription.cancel();
      });
    });
    
    group('Dynamic Subscription Management', () {
      test('should learn from event usage patterns', () async {
        await connectionManager.connect(userId: testUserId);
        
        final dynamicController = connectionManager.dynamicController;
        final recommendations = <SubscriptionRecommendation>[];
        
        // Listen for recommendations
        final subscription = dynamicController.recommendations.listen(recommendations.add);
        
        // Generate high-frequency events of specific type
        for (int i = 0; i < 15; i++) {
          final event = MockEventGenerators.generateQueueUpdate(
            sessionId: testSessionId,
            queueType: 'todo',
          );
          await mockServer.sendToQueue(testSessionId, event);
          await Future.delayed(Duration(milliseconds: 100));
        }
        
        // Wait for analysis
        await Future.delayed(Duration(seconds: 2));
        
        // Verify recommendations were generated
        expect(recommendations, isNotEmpty);
        
        final analytics = dynamicController.getSubscriptionAnalytics();
        expect(analytics['total_events_received'], greaterThanOrEqualTo(15));
        
        await subscription.cancel();
      });
      
      test('should adjust subscriptions based on app state', () async {
        await connectionManager.connect(userId: testUserId);
        
        // Test different app states
        await connectionManager.adjustSubscriptionsForAppState(AppState.ttsActive);
        await Future.delayed(Duration(milliseconds: 100));
        
        await connectionManager.adjustSubscriptionsForAppState(AppState.background);
        await Future.delayed(Duration(milliseconds: 100));
        
        // Verify subscriptions were adjusted
        final analytics = connectionManager.dynamicController.getSubscriptionAnalytics();
        expect(analytics['active_contexts'], isNotEmpty);
      });
      
      test('should handle contextual subscriptions', () async {
        await connectionManager.connect(userId: testUserId);
        
        // Add contextual subscription
        final context = SubscriptionContext(
          name: 'test_context',
          eventTypes: {
            AppConstants.eventAudioStreamingChunk,
            AppConstants.eventQueueTodoUpdate,
          },
          priority: SubscriptionPriority.high,
          isActive: true,
        );
        
        await connectionManager.addContextualSubscription(context);
        
        // Verify context was added
        final analytics = connectionManager.dynamicController.getSubscriptionAnalytics();
        final activeContexts = analytics['active_contexts'] as List;
        expect(activeContexts.any((c) => c['name'] == 'test_context'), isTrue);
        
        // Remove context
        await connectionManager.removeContextualSubscription('test_context');
      });
    });
    
    group('Performance and Load Testing', () {
      test('should handle event bursts without degradation', () async {
        await connectionManager.connect(userId: testUserId);
        
        final receivedEvents = <dynamic>[];
        
        // Listen to all event streams
        final subscriptions = [
          connectionManager.queueUpdates.listen(receivedEvents.add),
          connectionManager.notifications.listen(receivedEvents.add),
          connectionManager.systemMessages.listen(receivedEvents.add),
        ];
        
        // Generate event burst
        final burstEvents = MockEventGenerators.generateEventBurst(
          sessionId: testSessionId,
          count: 100,
          timeSpan: Duration(seconds: 5),
        );
        
        final startTime = DateTime.now();
        
        // Send all events rapidly
        for (final event in burstEvents) {
          await mockServer.sendToQueue(testSessionId, event);
        }
        
        // Wait for processing
        await Future.delayed(Duration(seconds: 2));
        
        final processingTime = DateTime.now().difference(startTime);
        
        // Verify performance
        expect(receivedEvents.length, greaterThanOrEqualTo(burstEvents.length * 0.9)); // 90% delivery
        expect(processingTime.inSeconds, lessThan(10)); // Reasonable processing time
        
        for (final sub in subscriptions) {
          await sub.cancel();
        }
      });
      
      test('should handle concurrent connections', () async {
        final connectionManagers = <WebSocketConnectionManager>[];
        final sessionIds = <String>[];
        
        // Create multiple connections
        for (int i = 0; i < 5; i++) {
          final sessionId = MockEventGenerators.generateSessionId();
          sessionIds.add(sessionId);
          
          final service = EnhancedWebSocketService(Dio());
          service.setBaseUrl('ws://localhost:${mockServer.config.port}');
          
          final manager = WebSocketConnectionManager(
            webSocketService: service,
            messageRouter: WebSocketMessageRouter(),
          );
          
          connectionManagers.add(manager);
          await manager.connect(userId: 'user_$i');
        }
        
        // Verify all connections are active
        for (final manager in connectionManagers) {
          expect(manager.isBothConnected, isTrue);
        }
        
        // Send events to all sessions
        for (int i = 0; i < sessionIds.length; i++) {
          final event = MockEventGenerators.generateQueueUpdate(sessionId: sessionIds[i]);
          await mockServer.sendToQueue(sessionIds[i], event);
        }
        
        await Future.delayed(Duration(milliseconds: 500));
        
        // Clean up connections
        for (final manager in connectionManagers) {
          await manager.disconnect();
        }
      });
    });
    
    group('Debug and Monitoring', () {
      test('should track all events in debug monitor', () async {
        await connectionManager.connect(userId: testUserId);
        
        // Generate various events
        final events = [
          MockEventGenerators.generateQueueUpdate(sessionId: testSessionId),
          MockEventGenerators.generateNotificationQueueUpdate(sessionId: testSessionId),
          MockEventGenerators.generateSystemTimeUpdate(sessionId: testSessionId),
        ];
        
        for (final event in events) {
          await mockServer.sendToQueue(testSessionId, event);
        }
        
        await Future.delayed(Duration(milliseconds: 500));
        
        // Verify debug monitor tracked events
        final recentEvents = debugMonitor.getRecentEvents(
          timeWindow: Duration(minutes: 1),
        );
        
        expect(recentEvents.length, greaterThanOrEqualTo(events.length));
        
        final stats = debugMonitor.getDebugStatistics();
        expect(stats['event_statistics'], isNotEmpty);
      });
      
      test('should detect performance issues', () async {
        final performanceAlerts = <PerformanceAlert>[];
        
        await connectionManager.connect(userId: testUserId);
        
        // Listen for performance alerts
        final subscription = debugMonitor.performanceAlerts.listen(performanceAlerts.add);
        
        // Generate event burst to trigger alerts
        for (int i = 0; i < 25; i++) {
          final event = MockEventGenerators.generateQueueUpdate(sessionId: testSessionId);
          await mockServer.sendToQueue(testSessionId, event);
        }
        
        await Future.delayed(Duration(seconds: 1));
        
        // Verify performance alerts were generated
        expect(performanceAlerts, isNotEmpty);
        expect(performanceAlerts.any((alert) => 
            alert.type == PerformanceAlertType.eventBurst), isTrue);
        
        await subscription.cancel();
      });
      
      test('should provide connection health reports', () async {
        await connectionManager.connect(userId: testUserId);
        
        // Generate some activity
        for (int i = 0; i < 5; i++) {
          final event = MockEventGenerators.generateSystemPing(sessionId: testSessionId);
          await mockServer.sendToQueue(testSessionId, event);
        }
        
        await Future.delayed(Duration(milliseconds: 200));
        
        // Get health report
        final healthReport = debugMonitor.getConnectionHealthReport();
        
        expect(healthReport['status'], isNotNull);
        expect(healthReport['stability_score'], isA<double>());
        expect(healthReport['success_rate'], isA<double>());
      });
    });
    
    group('End-to-End Scenarios', () {
      test('should handle complete TTS workflow', () async {
        final audioChunks = <AudioChunkMessage>[];
        final ttsStatus = <TTSStatusMessage>[];
        final queueUpdates = <QueueUpdateMessage>[];
        
        await connectionManager.connect(userId: testUserId);
        
        // Listen for all related events
        final subscriptions = [
          connectionManager.audioChunks.listen(audioChunks.add),
          connectionManager.ttsStatus.listen(ttsStatus.add),
          connectionManager.queueUpdates.listen(queueUpdates.add),
        ];
        
        // Send TTS request
        await connectionManager.sendTTSRequest(
          text: 'Hello, this is a test message',
          provider: 'elevenlabs',
          voiceId: 'test_voice',
        );
        
        // Wait for complete workflow
        await Future.delayed(Duration(seconds: 2));
        
        // Verify complete workflow
        expect(ttsStatus.any((s) => s.status == 'tts_start'), isTrue);
        expect(audioChunks, isNotEmpty);
        expect(ttsStatus.any((s) => s.status == 'tts_complete'), isTrue);
        
        for (final sub in subscriptions) {
          await sub.cancel();
        }
      });
      
      test('should handle voice input workflow', () async {
        final voiceInput = <VoiceInputMessage>[];
        
        await connectionManager.connect(userId: testUserId);
        
        // Listen for voice input events
        final subscription = connectionManager.voiceInput.listen(voiceInput.add);
        
        // Send voice input data
        final audioData = MockEventGenerators.generateMockAudioData(size: 2048);
        await connectionManager.sendVoiceInput(
          action: 'start',
          audioData: audioData,
        );
        
        await connectionManager.sendVoiceInput(action: 'stop');
        
        await Future.delayed(Duration(milliseconds: 500));
        
        // Verify voice input was processed
        expect(voiceInput.length, greaterThanOrEqualTo(2));
        
        await subscription.cancel();
      });
      
      test('should handle app state transitions', () async {
        await connectionManager.connect(userId: testUserId);
        
        // Test various app state transitions
        final states = [
          AppState.foreground,
          AppState.ttsActive,
          AppState.voiceInput,
          AppState.queueMonitoring,
          AppState.background,
        ];
        
        for (final state in states) {
          await connectionManager.adjustSubscriptionsForAppState(state);
          await Future.delayed(Duration(milliseconds: 100));
        }
        
        // Verify state transitions were handled
        final analytics = connectionManager.getSubscriptionAnalytics();
        expect(analytics, isNotEmpty);
      });
    });
  });
}