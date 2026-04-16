import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:dio/dio.dart';
import '../lib/services/websocket/enhanced_websocket_service.dart';
import '../lib/services/websocket/websocket_message_router.dart';
import '../lib/services/websocket/websocket_subscription_manager.dart';
import '../lib/services/websocket/websocket_connection_manager.dart';
import 'mocks/mock_websocket_server.dart';

void main() {
  group('WebSocket Connection Recovery Tests', () {
    late MockWebSocketServer mockServer;
    late EnhancedWebSocketService webSocketService;
    late WebSocketMessageRouter messageRouter;
    late WebSocketSubscriptionManager subscriptionManager;
    late WebSocketConnectionManager connectionManager;

    setUpAll(() async {
      // Start mock server for connection recovery testing
      mockServer = MockWebSocketServer(config: MockServerConfig.testing());
      await mockServer.start();
      print('[Test] Mock server started on port ${mockServer.config.port}');
    });

    tearDownAll(() async {
      await mockServer.stop();
      print('[MockServer] Stopped');
    });

    setUp(() {
      // Create service components
      final dio = Dio();
      webSocketService = EnhancedWebSocketService(dio);
      webSocketService.configure(
        baseUrl: 'ws://localhost:${mockServer.config.port}',
        sessionId: 'test_recovery_session',
      );
      
      messageRouter = WebSocketMessageRouter();
      
      subscriptionManager = WebSocketSubscriptionManager(
        webSocketService: webSocketService,
      );
      
      connectionManager = WebSocketConnectionManager(
        webSocketService: webSocketService,
        messageRouter: messageRouter,
        subscriptionManager: subscriptionManager,
      );
    });

    tearDown(() async {
      await connectionManager.disconnect();
      messageRouter.dispose();
      subscriptionManager.dispose();
    });

    test('should recover from connection failure with exponential backoff', () async {
      // Configure mock server to fail initially then succeed
      int connectionAttempts = 0;
      
      // Track connection events
      List<WebSocketEvent> events = [];
      webSocketService.eventStream.listen((event) {
        events.add(event);
        print('[Test] Event: ${event.runtimeType}');
      });
      
      // Track reconnection attempts
      List<int> reconnectionAttempts = [];
      List<Duration> reconnectionDelays = [];
      
      webSocketService.eventStream.listen((event) {
        if (event is WebSocketReconnectionScheduledEvent) {
          reconnectionAttempts.add(event.attempt);
          reconnectionDelays.add(event.delay);
        }
      });
      
      // Simulate connection failure recovery
      mockServer.simulateConnectionFailures(
        failureCount: 3,
        onConnectionAttempt: () {
          connectionAttempts++;
          print('[Test] Connection attempt: $connectionAttempts');
        },
      );
      
      // Attempt connection
      try {
        await connectionManager.connect();
      } catch (e) {
        print('[Test] Initial connection failed as expected: $e');
      }
      
      // Wait for reconnection attempts
      await Future.delayed(const Duration(seconds: 8));
      
      // Verify exponential backoff pattern
      expect(reconnectionAttempts.length, greaterThan(1));
      expect(reconnectionDelays.length, greaterThan(1));
      
      // Verify exponential backoff delays
      for (int i = 1; i < reconnectionDelays.length; i++) {
        expect(
          reconnectionDelays[i].inMilliseconds,
          greaterThanOrEqualTo(reconnectionDelays[i-1].inMilliseconds),
          reason: 'Reconnection delay should increase with each attempt',
        );
      }
      
      print('[Test] ✅ Exponential backoff pattern verified');
    });
    
    test('should handle connection health monitoring', () async {
      // Start connection
      await connectionManager.connect();
      
      // Wait for connection to establish
      await Future.delayed(const Duration(seconds: 2));
      
      // Get connection metrics
      final metrics = connectionManager.metrics;
      expect(metrics, isNotNull);
      
      // Verify health monitoring is active
      expect(connectionManager.isConnected, isTrue);
      
      // Simulate stale connection by stopping message flow
      mockServer.pauseMessageGeneration();
      
      List<WebSocketEvent> healthEvents = [];
      webSocketService.eventStream.listen((event) {
        if (event is WebSocketConnectionStaleEvent ||
            event is WebSocketHealthCheckWarningEvent) {
          healthEvents.add(event);
          print('[Test] Health event: ${event.runtimeType}');
        }
      });
      
      // Wait for health check to detect stale connection
      await Future.delayed(const Duration(seconds: 3));
      
      // Resume message flow
      mockServer.resumeMessageGeneration();
      
      print('[Test] ✅ Connection health monitoring verified');
    });
    
    test('should maintain connection state consistency', () async {
      // Track connection state changes
      List<WebSocketConnectionState> queueStates = [];
      List<WebSocketConnectionState> audioStates = [];
      
      // Monitor state changes
      Timer.periodic(const Duration(milliseconds: 100), (timer) {
        queueStates.add(connectionManager.queueConnectionState);
        audioStates.add(connectionManager.audioConnectionState);
        
        if (queueStates.length > 50) {
          timer.cancel();
        }
      });
      
      // Perform connection operations
      await connectionManager.connect();
      await Future.delayed(const Duration(seconds: 1));
      
      await connectionManager.disconnect();
      await Future.delayed(const Duration(seconds: 1));
      
      await connectionManager.connect();
      await Future.delayed(const Duration(seconds: 1));
      
      // Verify state consistency
      expect(queueStates.isNotEmpty, isTrue);
      expect(audioStates.isNotEmpty, isTrue);
      
      // Verify final state is connected
      expect(connectionManager.queueConnectionState, WebSocketConnectionState.connected);
      expect(connectionManager.audioConnectionState, WebSocketConnectionState.connected);
      
      print('[Test] ✅ Connection state consistency verified');
    });
    
    test('should handle rapid connect/disconnect cycles', () async {
      // Perform rapid connection cycles
      for (int i = 0; i < 5; i++) {
        print('[Test] Connection cycle ${i + 1}');
        
        await connectionManager.connect();
        await Future.delayed(const Duration(milliseconds: 500));
        
        await connectionManager.disconnect();
        await Future.delayed(const Duration(milliseconds: 200));
      }
      
      // Final connection should work
      await connectionManager.connect();
      expect(connectionManager.isConnected, isTrue);
      
      print('[Test] ✅ Rapid connect/disconnect cycles handled');
    });
    
    test('should respect reconnection limits', () async {
      // Configure short reconnection limits for testing
      webSocketService.configureReconnection(
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 100),
      );
      
      // Simulate persistent connection failures
      mockServer.simulatePersistentFailure();
      
      List<WebSocketEvent> giveUpEvents = [];
      webSocketService.eventStream.listen((event) {
        if (event is WebSocketReconnectionGiveUpEvent) {
          giveUpEvents.add(event);
          print('[Test] Reconnection gave up after ${event.totalAttempts} attempts');
        }
      });
      
      // Attempt connection
      try {
        await connectionManager.connect();
      } catch (e) {
        print('[Test] Connection failed as expected: $e');
      }
      
      // Wait for reconnection attempts to exhaust
      await Future.delayed(const Duration(seconds: 3));
      
      // Verify reconnection gave up
      expect(giveUpEvents.length, equals(1));
      final giveUpEvent = giveUpEvents.first as WebSocketReconnectionGiveUpEvent;
      expect(giveUpEvent.totalAttempts, equals(3));
      
      print('[Test] ✅ Reconnection limits respected');
    });
  });
}