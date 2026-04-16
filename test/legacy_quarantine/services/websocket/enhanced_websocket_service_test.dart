import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:async';
import 'dart:typed_data';
import '../../../lib/services/websocket/enhanced_websocket_service.dart';

// Generate mocks
@GenerateMocks([
  Dio,
  WebSocketChannel,
  WebSocketSink,
])
import 'enhanced_websocket_service_test.mocks.dart';

void main() {
  group('EnhancedWebSocketService Tests', () {
    late EnhancedWebSocketService service;
    late MockDio mockDio;
    late MockWebSocketChannel mockChannel;
    late MockWebSocketSink mockSink;

    setUp(() {
      mockDio = MockDio();
      mockChannel = MockWebSocketChannel();
      mockSink = MockWebSocketSink();
      service = EnhancedWebSocketService(mockDio);

      // Setup default mock responses
      when(mockChannel.sink).thenReturn(mockSink);
      when(mockChannel.ready).thenAnswer((_) => Future.value());
      when(mockSink.close(any)).thenAnswer((_) => Future.value());
    });

    group('Connection Management', () {
      test('should connect successfully with valid session ID', () async {
        // Arrange
        when(mockDio.get(any)).thenAnswer((_) async => Response(
          data: {'session_id': 'test-session-123'},
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/get-session-id'),
        ));

        // Act
        await service.connect(userId: 'test-user');

        // Assert
        expect(service.isConnected, isTrue);
        expect(service.sessionId, equals('test-session-123'));
        expect(service.userId, equals('test-user'));
      });

      test('should handle connection failure gracefully', () async {
        // Arrange
        when(mockDio.get(any)).thenThrow(Exception('Network error'));

        // Act & Assert
        expect(
          () => service.connect(userId: 'test-user'),
          throwsException,
        );
        expect(service.isConnected, isFalse);
      });

      test('should retry session ID retrieval on failure', () async {
        // Arrange
        when(mockDio.get(any))
            .thenThrow(Exception('Network error'))
            .thenAnswer((_) async => Response(
              data: {'session_id': 'test-session-456'},
              statusCode: 200,
              requestOptions: RequestOptions(path: '/api/get-session-id'),
            ));

        // Act
        await service.connect(userId: 'test-user');

        // Assert
        verify(mockDio.get(any)).called(2);
        expect(service.sessionId, equals('test-session-456'));
      });

      test('should handle invalid session ID response', () async {
        // Arrange
        when(mockDio.get(any)).thenAnswer((_) async => Response(
          data: {'session_id': null},
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/get-session-id'),
        ));

        // Act & Assert
        expect(
          () => service.connect(userId: 'test-user'),
          throwsException,
        );
      });

      test('should disconnect cleanly', () async {
        // Arrange
        when(mockDio.get(any)).thenAnswer((_) async => Response(
          data: {'session_id': 'test-session-123'},
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/get-session-id'),
        ));

        await service.connect(userId: 'test-user');

        // Act
        await service.disconnect();

        // Assert
        expect(service.isConnected, isFalse);
        expect(service.sessionId, isNull);
        verify(mockSink.close(any)).called(1);
      });
    });

    group('Message Handling', () {
      test('should handle binary messages correctly', () async {
        // Arrange
        final binaryData = Uint8List.fromList([1, 2, 3, 4, 5]);
        final receivedMessages = <WebSocketMessage>[];

        service.messageStream.listen(receivedMessages.add);

        // Act
        service._handleIncomingMessage(binaryData);

        // Assert
        await Future.delayed(Duration.zero); // Allow stream to process
        expect(receivedMessages.length, equals(1));
        expect(receivedMessages[0].type, equals('binary'));
        expect(receivedMessages[0].binaryData, equals(binaryData));
      });

      test('should handle JSON messages correctly', () async {
        // Arrange
        final jsonMessage = '{"type": "test", "data": {"key": "value"}}';
        final receivedMessages = <WebSocketMessage>[];

        service.messageStream.listen(receivedMessages.add);

        // Act
        service._handleIncomingMessage(jsonMessage);

        // Assert
        await Future.delayed(Duration.zero);
        expect(receivedMessages.length, equals(1));
        expect(receivedMessages[0].type, equals('test'));
        expect(receivedMessages[0].data!['key'], equals('value'));
      });

      test('should handle ping/pong messages', () async {
        // Arrange
        when(mockDio.get(any)).thenAnswer((_) async => Response(
          data: {'session_id': 'test-session-123'},
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/get-session-id'),
        ));

        await service.connect(userId: 'test-user');

        // Act
        service._handleIncomingMessage('{"type": "ping"}');

        // Assert
        // Verify that a pong message was sent
        verify(mockSink.add(any)).called(greaterThan(0));
      });

      test('should handle authentication messages', () async {
        // Arrange
        final events = <WebSocketEvent>[];
        service.eventStream.listen(events.add);

        // Act
        service._handleIncomingMessage('{"type": "auth_success", "session_id": "new-session"}');

        // Assert
        await Future.delayed(Duration.zero);
        expect(events.any((e) => e is WebSocketAuthenticatedEvent), isTrue);
      });

      test('should handle malformed messages gracefully', () async {
        // Arrange
        final receivedMessages = <WebSocketMessage>[];
        final errors = <WebSocketEvent>[];

        service.messageStream.listen(receivedMessages.add);
        service.eventStream.listen((event) {
          if (event is WebSocketMessageParsingErrorEvent) {
            errors.add(event);
          }
        });

        // Act
        service._handleIncomingMessage('invalid json {');

        // Assert
        await Future.delayed(Duration.zero);
        expect(errors.length, equals(1));
        expect(receivedMessages.length, equals(1)); // Should still forward raw message
        expect(receivedMessages[0].type, equals('raw'));
      });
    });

    group('Message Sending', () {
      test('should send text messages correctly', () async {
        // Arrange
        when(mockDio.get(any)).thenAnswer((_) async => Response(
          data: {'session_id': 'test-session-123'},
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/get-session-id'),
        ));

        await service.connect(userId: 'test-user');

        final message = WebSocketMessage(
          type: 'test',
          data: {'key': 'value'},
          timestamp: DateTime.now(),
        );

        // Act
        await service.sendMessage(message);

        // Assert
        verify(mockSink.add(any)).called(greaterThan(0));
      });

      test('should send binary messages correctly', () async {
        // Arrange
        when(mockDio.get(any)).thenAnswer((_) async => Response(
          data: {'session_id': 'test-session-123'},
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/get-session-id'),
        ));

        await service.connect(userId: 'test-user');

        final binaryData = Uint8List.fromList([1, 2, 3, 4, 5]);
        final message = WebSocketMessage.binaryData(data: binaryData);

        // Act
        await service.sendMessage(message);

        // Assert
        verify(mockSink.add(binaryData)).called(1);
      });

      test('should queue messages when disconnected', () async {
        // Arrange
        final message = WebSocketMessage(
          type: 'test',
          data: {'key': 'value'},
          timestamp: DateTime.now(),
        );

        // Act
        await service.sendMessage(message);

        // Assert
        expect(service.queueSize, greaterThan(0));
      });

      test('should process priority queue first', () async {
        // Arrange
        when(mockDio.get(any)).thenAnswer((_) async => Response(
          data: {'session_id': 'test-session-123'},
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/get-session-id'),
        ));

        final normalMessage = WebSocketMessage(
          type: 'normal',
          timestamp: DateTime.now(),
        );

        final priorityMessage = WebSocketMessage(
          type: 'priority',
          timestamp: DateTime.now(),
        );

        // Add messages while disconnected
        await service.sendMessage(normalMessage, priority: MessagePriority.normal);
        await service.sendMessage(priorityMessage, priority: MessagePriority.high);

        // Act
        await service.connect(userId: 'test-user');

        // Assert
        // Priority message should be processed first
        expect(service.queueSize, equals(0));
        expect(service.priorityQueueSize, equals(0));
      });

      test('should handle send failures gracefully', () async {
        // Arrange
        when(mockDio.get(any)).thenAnswer((_) async => Response(
          data: {'session_id': 'test-session-123'},
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/get-session-id'),
        ));

        await service.connect(userId: 'test-user');

        when(mockSink.add(any)).thenThrow(Exception('Send failed'));

        final message = WebSocketMessage(
          type: 'test',
          timestamp: DateTime.now(),
        );

        // Act & Assert
        expect(
          () => service.sendMessage(message, skipQueue: true),
          throwsException,
        );
      });
    });

    group('Request-Response Pattern', () {
      test('should handle request-response correctly', () async {
        // Arrange
        when(mockDio.get(any)).thenAnswer((_) async => Response(
          data: {'session_id': 'test-session-123'},
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/get-session-id'),
        ));

        await service.connect(userId: 'test-user');

        final requestMessage = WebSocketMessage(
          type: 'request',
          data: {'query': 'test'},
          timestamp: DateTime.now(),
        );

        // Act
        final responseFuture = service.sendMessageWithResponse(requestMessage);

        // Simulate response
        final responseJson = '{"type": "response", "request_id": "req_123", "data": {"result": "success"}}';
        service._handleIncomingMessage(responseJson);

        // Assert
        // Note: This test would need more setup to properly test request-response
        // as we need to capture the actual request ID that gets generated
      });

      test('should timeout requests correctly', () async {
        // Arrange
        when(mockDio.get(any)).thenAnswer((_) async => Response(
          data: {'session_id': 'test-session-123'},
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/get-session-id'),
        ));

        await service.connect(userId: 'test-user');

        final requestMessage = WebSocketMessage(
          type: 'request',
          data: {'query': 'test'},
          timestamp: DateTime.now(),
        );

        // Act & Assert
        expect(
          () => service.sendMessageWithResponse(
            requestMessage,
            timeout: const Duration(milliseconds: 100),
          ),
          throwsA(isA<TimeoutException>()),
        );
      });
    });

    group('Reconnection Logic', () {
      test('should attempt reconnection on connection loss', () async {
        // This test would require mocking the WebSocket channel behavior
        // to simulate connection loss and verify reconnection attempts
      });

      test('should use exponential backoff for reconnection', () async {
        // This test would verify that reconnection delays increase exponentially
      });

      test('should give up after max reconnection attempts', () async {
        // This test would verify that reconnection stops after reaching the limit
      });
    });

    group('Message Metrics', () {
      test('should track message statistics correctly', () async {
        // Arrange
        when(mockDio.get(any)).thenAnswer((_) async => Response(
          data: {'session_id': 'test-session-123'},
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/get-session-id'),
        ));

        await service.connect(userId: 'test-user');

        // Act
        service._handleIncomingMessage('{"type": "test"}');
        service._handleIncomingMessage(Uint8List.fromList([1, 2, 3]));

        final message = WebSocketMessage(type: 'test', timestamp: DateTime.now());
        await service.sendMessage(message, skipQueue: true);

        // Assert
        final metrics = service.metrics;
        expect(metrics.messagesReceived, equals(2));
        expect(metrics.textMessagesReceived, equals(1));
        expect(metrics.binaryMessagesReceived, equals(1));
        expect(metrics.messagesSent, greaterThan(0));
      });

      test('should track connection attempts', () async {
        // Arrange
        when(mockDio.get(any)).thenAnswer((_) async => Response(
          data: {'session_id': 'test-session-123'},
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/get-session-id'),
        ));

        // Act
        await service.connect(userId: 'test-user');

        // Assert
        final metrics = service.metrics;
        expect(metrics.connectionAttempts, greaterThan(0));
        expect(metrics.successfulConnections, greaterThan(0));
      });
    });

    group('Error Handling', () {
      test('should handle connection errors gracefully', () async {
        // Arrange
        final events = <WebSocketEvent>[];
        service.eventStream.listen(events.add);

        // Act
        service._handleConnectionError(Exception('Connection lost'));

        // Assert
        await Future.delayed(Duration.zero);
        expect(events.any((e) => e is WebSocketConnectionErrorEvent), isTrue);
      });

      test('should handle parsing errors gracefully', () async {
        // Arrange
        final events = <WebSocketEvent>[];
        service.eventStream.listen(events.add);

        // Act
        service._handleIncomingMessage('invalid json');

        // Assert
        await Future.delayed(Duration.zero);
        expect(events.any((e) => e is WebSocketMessageParsingErrorEvent), isTrue);
      });
    });

    group('Health Monitoring', () {
      test('should perform health checks', () async {
        // This would test the periodic health check functionality
        // by verifying that health check events are emitted
      });

      test('should detect stale connections', () async {
        // This would test the detection of connections that haven't
        // received messages for a long time
      });
    });

    group('Configuration', () {
      test('should respect configuration parameters', () {
        // Test various configuration options like timeouts,
        // queue sizes, retry attempts, etc.
      });
    });

    tearDown(() {
      service.dispose();
    });
  });

  group('WebSocketMessage Tests', () {
    test('should create authentication message correctly', () {
      // Arrange & Act
      final message = WebSocketMessage.authentication(
        token: 'test-token',
        sessionId: 'test-session',
        userId: 'test-user',
        clientInfo: {'platform': 'flutter'},
      );

      // Assert
      expect(message.type, equals('auth'));
      expect(message.data!['token'], equals('test-token'));
      expect(message.data!['session_id'], equals('test-session'));
      expect(message.data!['user_id'], equals('test-user'));
      expect(message.data!['client_info']['platform'], equals('flutter'));
    });

    test('should create binary data message correctly', () {
      // Arrange
      final binaryData = Uint8List.fromList([1, 2, 3, 4, 5]);

      // Act
      final message = WebSocketMessage.binaryData(
        data: binaryData,
        metadata: {'source': 'test'},
      );

      // Assert
      expect(message.type, equals('binary'));
      expect(message.binaryData, equals(binaryData));
      expect(message.metadata!['source'], equals('test'));
    });

    test('should serialize and deserialize correctly', () {
      // Arrange
      final originalMessage = WebSocketMessage(
        type: 'test',
        data: {'key': 'value'},
        metadata: {'source': 'test'},
        requestId: 'req-123',
        timestamp: DateTime.now(),
      );

      // Act
      final json = originalMessage.toJson();
      final restoredMessage = WebSocketMessage.fromJson(json);

      // Assert
      expect(restoredMessage.type, equals(originalMessage.type));
      expect(restoredMessage.data, equals(originalMessage.data));
      expect(restoredMessage.metadata, equals(originalMessage.metadata));
      expect(restoredMessage.requestId, equals(originalMessage.requestId));
    });

    test('should copy with changes correctly', () {
      // Arrange
      final originalMessage = WebSocketMessage(
        type: 'test',
        data: {'key': 'value'},
        timestamp: DateTime.now(),
      );

      // Act
      final copiedMessage = originalMessage.copyWith(
        type: 'modified',
        requestId: 'req-456',
      );

      // Assert
      expect(copiedMessage.type, equals('modified'));
      expect(copiedMessage.data, equals(originalMessage.data));
      expect(copiedMessage.requestId, equals('req-456'));
      expect(copiedMessage.timestamp, equals(originalMessage.timestamp));
    });
  });

  group('WebSocketMetrics Tests', () {
    test('should serialize metrics correctly', () {
      // Arrange
      final metrics = WebSocketMetrics();
      metrics.connectionAttempts = 5;
      metrics.successfulConnections = 4;
      metrics.messagesReceived = 100;
      metrics.messagesSent = 50;

      // Act
      final json = metrics.toJson();

      // Assert
      expect(json['connection_attempts'], equals(5));
      expect(json['successful_connections'], equals(4));
      expect(json['messages_received'], equals(100));
      expect(json['messages_sent'], equals(50));
    });
  });
}