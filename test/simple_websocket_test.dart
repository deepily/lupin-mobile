import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import '../lib/services/websocket/enhanced_websocket_service.dart';
import '../lib/services/websocket/websocket_message_router.dart';
import '../lib/services/websocket/websocket_debug_monitor.dart';
import 'mocks/mock_websocket_server.dart';
import 'helpers/mock_event_generators.dart';

void main() {
  group('Simple WebSocket Tests', () {
    late MockWebSocketServer mockServer;
    
    setUpAll(() async {
      // Start mock server
      mockServer = MockWebSocketServer(
        config: MockServerConfig(
          port: 8090,
          enableAutoEventGeneration: false,
        ),
      );
      await mockServer.start();
      print('[Test] Mock server started on port ${mockServer.config.port}');
    });
    
    tearDownAll(() async {
      await mockServer.stop();
    });
    
    test('should create WebSocket service components', () {
      // Test basic component creation
      final dio = Dio();
      final webSocketService = EnhancedWebSocketService(dio);
      final messageRouter = WebSocketMessageRouter();
      
      // Test setBaseUrl method
      webSocketService.setBaseUrl('ws://localhost:8090');
      
      expect(webSocketService, isNotNull);
      expect(messageRouter, isNotNull);
    });
    
    test('should create debug monitor with default config', () {
      final dio = Dio();
      final webSocketService = EnhancedWebSocketService(dio);
      final messageRouter = WebSocketMessageRouter();
      
      // Test debug config factory methods
      final defaultConfig = DebugConfig.defaultConfig();
      final minimalConfig = DebugConfig.minimal();
      final verboseConfig = DebugConfig.verbose();
      
      expect(defaultConfig, isNotNull);
      expect(minimalConfig, isNotNull);
      expect(verboseConfig, isNotNull);
      
      expect(minimalConfig.enableEventLogging, isTrue);
      expect(minimalConfig.enablePerformanceMonitoring, isFalse);
      expect(verboseConfig.enableEventLogging, isTrue);
      expect(verboseConfig.enablePerformanceMonitoring, isTrue);
    });
    
    test('should generate mock events', () {
      // Test mock event generators
      final sessionId = MockEventGenerators.generateSessionId();
      expect(sessionId, isNotNull);
      expect(sessionId.contains(' '), isTrue); // Should be "adjective noun" format
      
      final queueEvent = MockEventGenerators.generateQueueUpdate(
        sessionId: sessionId,
        queueType: 'todo',
      );
      expect(queueEvent['type'], isNotNull);
      expect(queueEvent['session_id'], equals(sessionId));
      
      final authEvent = MockEventGenerators.generateAuthRequest(
        sessionId: sessionId,
        userId: 'test_user',
      );
      expect(authEvent['type'], equals('auth_request'));
      expect(authEvent['token'], startsWith('Bearer mock_token_email_'));
    });
    
    test('should handle mock server basic operations', () async {
      // Test mock server stats
      final stats = mockServer.getStats();
      expect(stats['total_connections'], equals(0));
      expect(stats['config'], isNotNull);
      
      // Test session management
      final sessionId = MockEventGenerators.generateSessionId();
      
      // Test public send methods
      final testEvent = {
        'type': 'test_event',
        'session_id': sessionId,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // These should not throw exceptions even if session doesn't exist
      await mockServer.sendToQueue(sessionId, testEvent);
      await mockServer.sendToAudio(sessionId, testEvent);
    });
    
    test('should validate message processor middleware', () {
      final messageRouter = WebSocketMessageRouter();
      
      // Test middleware registration
      final loggingMiddleware = LoggingMiddleware();
      final analyticsMiddleware = AnalyticsMiddleware();
      
      messageRouter.registerMiddleware(loggingMiddleware);
      messageRouter.registerMiddleware(analyticsMiddleware);
      
      // Should not throw exceptions
      expect(loggingMiddleware, isA<MessageProcessor>());
      expect(analyticsMiddleware, isA<MessageProcessor>());
    });
  });
}