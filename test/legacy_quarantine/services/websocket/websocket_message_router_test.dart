import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'dart:typed_data';
import '../../../lib/services/websocket/websocket_message_router.dart';
import '../../../lib/services/websocket/enhanced_websocket_service.dart';

void main() {
  group('WebSocketMessageRouter Tests', () {
    late WebSocketMessageRouter router;

    setUp(() {
      router = WebSocketMessageRouter();
    });

    tearDown(() {
      router.dispose();
    });

    group('Message Handler Registration', () {
      test('should register and call message handlers', () async {
        // Arrange
        bool handlerCalled = false;
        WebSocketMessage? receivedMessage;

        router.registerHandler('test', (message) async {
          handlerCalled = true;
          receivedMessage = message;
        });

        final testMessage = WebSocketMessage(
          type: 'test',
          data: {'key': 'value'},
          timestamp: DateTime.now(),
        );

        // Act
        await router.routeMessage(testMessage);

        // Assert
        expect(handlerCalled, isTrue);
        expect(receivedMessage?.type, equals('test'));
        expect(receivedMessage?.data!['key'], equals('value'));
      });

      test('should register and call binary message handlers', () async {
        // Arrange
        bool handlerCalled = false;
        Uint8List? receivedData;
        Map<String, dynamic>? receivedMetadata;

        router.registerBinaryHandler('binary', (data, metadata) async {
          handlerCalled = true;
          receivedData = data;
          receivedMetadata = metadata;
        });

        final binaryData = Uint8List.fromList([1, 2, 3, 4, 5]);
        final testMessage = WebSocketMessage.binaryData(
          data: binaryData,
          metadata: {'source': 'test'},
        );

        // Act
        await router.routeMessage(testMessage);

        // Assert
        expect(handlerCalled, isTrue);
        expect(receivedData, equals(binaryData));
        expect(receivedMetadata!['source'], equals('test'));
      });

      test('should call wildcard handlers for all messages', () async {
        // Arrange
        int wildcardCallCount = 0;
        final receivedTypes = <String>[];

        router.registerHandler('*', (message) async {
          wildcardCallCount++;
          receivedTypes.add(message.type);
        });

        // Act
        await router.routeMessage(WebSocketMessage(
          type: 'test1',
          timestamp: DateTime.now(),
        ));
        await router.routeMessage(WebSocketMessage(
          type: 'test2',
          timestamp: DateTime.now(),
        ));

        // Assert
        expect(wildcardCallCount, equals(2));
        expect(receivedTypes, containsAll(['test1', 'test2']));
      });

      test('should unregister handlers correctly', () async {
        // Arrange
        bool handlerCalled = false;

        Future<void> handler(WebSocketMessage message) async {
          handlerCalled = true;
        }

        router.registerHandler('test', handler);
        router.unregisterHandler('test', handler);

        final testMessage = WebSocketMessage(
          type: 'test',
          timestamp: DateTime.now(),
        );

        // Act
        await router.routeMessage(testMessage);

        // Assert
        expect(handlerCalled, isFalse);
      });
    });

    group('Stream Routing', () {
      test('should route audio chunk messages to audio stream', () async {
        // Arrange
        final receivedChunks = <AudioChunkMessage>[];
        router.audioChunks.listen(receivedChunks.add);

        final binaryData = Uint8List.fromList([1, 2, 3, 4, 5]);
        final testMessage = WebSocketMessage(
          type: 'audio_chunk',
          data: {
            'provider': 'elevenlabs',
            'sequence_number': 1,
            'total_chunks': 5,
          },
          binaryData: binaryData,
          timestamp: DateTime.now(),
        );

        // Act
        await router.routeMessage(testMessage);

        // Assert
        await Future.delayed(Duration.zero); // Allow stream to process
        expect(receivedChunks.length, equals(1));
        expect(receivedChunks[0].provider, equals('elevenlabs'));
        expect(receivedChunks[0].sequenceNumber, equals(1));
        expect(receivedChunks[0].totalChunks, equals(5));
        expect(receivedChunks[0].audioData, equals(binaryData));
      });

      test('should route TTS status messages to TTS stream', () async {
        // Arrange
        final receivedStatuses = <TTSStatusMessage>[];
        router.ttsStatus.listen(receivedStatuses.add);

        final testMessage = WebSocketMessage(
          type: 'tts_status',
          data: {
            'status': 'generating',
            'provider': 'openai',
            'session_id': 'test-session',
            'text': 'Hello world',
          },
          timestamp: DateTime.now(),
        );

        // Act
        await router.routeMessage(testMessage);

        // Assert
        await Future.delayed(Duration.zero);
        expect(receivedStatuses.length, equals(1));
        expect(receivedStatuses[0].status, equals('tts_status'));
        expect(receivedStatuses[0].provider, equals('openai'));
        expect(receivedStatuses[0].sessionId, equals('test-session'));
        expect(receivedStatuses[0].text, equals('Hello world'));
      });

      test('should route voice input messages to voice stream', () async {
        // Arrange
        final receivedInputs = <VoiceInputMessage>[];
        router.voiceInput.listen(receivedInputs.add);

        final testMessage = WebSocketMessage(
          type: 'voice_input',
          data: {
            'action': 'start',
            'transcription': 'Hello world',
            'confidence': 0.95,
          },
          timestamp: DateTime.now(),
        );

        // Act
        await router.routeMessage(testMessage);

        // Assert
        await Future.delayed(Duration.zero);
        expect(receivedInputs.length, equals(1));
        expect(receivedInputs[0].action, equals('start'));
        expect(receivedInputs[0].transcription, equals('Hello world'));
        expect(receivedInputs[0].confidence, equals(0.95));
      });

      test('should route error messages to error stream', () async {
        // Arrange
        final receivedErrors = <ErrorMessage>[];
        router.errors.listen(receivedErrors.add);

        final testMessage = WebSocketMessage(
          type: 'error',
          data: {
            'error': 'Something went wrong',
            'code': 'E001',
          },
          timestamp: DateTime.now(),
        );

        // Act
        await router.routeMessage(testMessage);

        // Assert
        await Future.delayed(Duration.zero);
        expect(receivedErrors.length, equals(1));
        expect(receivedErrors[0].error, equals('Something went wrong'));
        expect(receivedErrors[0].code, equals('E001'));
      });
    });

    group('Middleware Processing', () {
      test('should apply middleware in order', () async {
        // Arrange
        final processingOrder = <String>[];

        final middleware1 = TestMiddleware('middleware1', processingOrder);
        final middleware2 = TestMiddleware('middleware2', processingOrder);

        router.registerMiddleware(middleware1);
        router.registerMiddleware(middleware2);

        bool handlerCalled = false;
        router.registerHandler('test', (message) async {
          handlerCalled = true;
        });

        final testMessage = WebSocketMessage(
          type: 'test',
          timestamp: DateTime.now(),
        );

        // Act
        await router.routeMessage(testMessage);

        // Assert
        expect(processingOrder, equals(['middleware1', 'middleware2']));
        expect(handlerCalled, isTrue);
      });

      test('should handle middleware errors gracefully', () async {
        // Arrange
        final receivedErrors = <ErrorMessage>[];
        router.errors.listen(receivedErrors.add);

        final failingMiddleware = FailingMiddleware();
        router.registerMiddleware(failingMiddleware);

        final testMessage = WebSocketMessage(
          type: 'test',
          timestamp: DateTime.now(),
        );

        // Act
        await router.routeMessage(testMessage);

        // Assert
        await Future.delayed(Duration.zero);
        expect(receivedErrors.length, equals(1));
        expect(receivedErrors[0].error, contains('Message routing failed'));
      });
    });

    group('Message Creation', () {
      test('should create TTS request message correctly', () {
        // Act
        final message = router.createTTSRequest(
          text: 'Hello world',
          provider: 'elevenlabs',
          voiceId: 'voice-123',
          settings: {'speed': 1.0},
        );

        // Assert
        expect(message.type, equals('tts_request'));
        expect(message.data!['text'], equals('Hello world'));
        expect(message.data!['provider'], equals('elevenlabs'));
        expect(message.data!['voice_id'], equals('voice-123'));
        expect(message.data!['settings']['speed'], equals(1.0));
      });

      test('should create voice input message correctly', () {
        // Arrange
        final audioData = Uint8List.fromList([1, 2, 3, 4, 5]);

        // Act
        final message = router.createVoiceInput(
          action: 'data',
          audioData: audioData,
          settings: {'format': 'wav'},
        );

        // Assert
        expect(message.type, equals('voice_input'));
        expect(message.data!['action'], equals('data'));
        expect(message.data!['settings']['format'], equals('wav'));
        expect(message.binaryData, equals(audioData));
      });

      test('should create agent interaction message correctly', () {
        // Act
        final message = router.createAgentInteraction(
          agentType: 'math',
          action: 'calculate',
          data: {'expression': '2 + 2'},
        );

        // Assert
        expect(message.type, equals('agent_interaction'));
        expect(message.data!['agent_type'], equals('math'));
        expect(message.data!['action'], equals('calculate'));
        expect(message.data!['data']['expression'], equals('2 + 2'));
      });
    });

    group('Error Handling', () {
      test('should handle handler errors gracefully', () async {
        // Arrange
        final receivedErrors = <ErrorMessage>[];
        router.errors.listen(receivedErrors.add);

        router.registerHandler('test', (message) async {
          throw Exception('Handler error');
        });

        final testMessage = WebSocketMessage(
          type: 'test',
          timestamp: DateTime.now(),
        );

        // Act
        await router.routeMessage(testMessage);

        // Assert
        await Future.delayed(Duration.zero);
        expect(receivedErrors.length, equals(1));
        expect(receivedErrors[0].error, contains('Message handler error'));
      });

      test('should handle binary handler errors gracefully', () async {
        // Arrange
        final receivedErrors = <ErrorMessage>[];
        router.errors.listen(receivedErrors.add);

        router.registerBinaryHandler('binary', (data, metadata) async {
          throw Exception('Binary handler error');
        });

        final testMessage = WebSocketMessage.binaryData(
          data: Uint8List.fromList([1, 2, 3]),
        );

        // Act
        await router.routeMessage(testMessage);

        // Assert
        await Future.delayed(Duration.zero);
        expect(receivedErrors.length, equals(1));
        expect(receivedErrors[0].error, contains('Binary handler error'));
      });
    });

    group('Statistics', () {
      test('should provide routing statistics', () {
        // Arrange
        router.registerHandler('test1', (message) async {});
        router.registerHandler('test1', (message) async {}); // Second handler for same type
        router.registerHandler('test2', (message) async {});
        router.registerBinaryHandler('binary1', (data, metadata) async {});

        // Act
        final stats = router.getRoutingStats();

        // Assert
        expect(stats['registered_handlers']['test1'], equals(2));
        expect(stats['registered_handlers']['test2'], equals(1));
        expect(stats['registered_binary_handlers']['binary1'], equals(1));
        expect(stats['middleware_count'], equals(0));
      });
    });
  });

  group('Middleware Tests', () {
    group('LoggingMiddleware', () {
      test('should log text messages', () async {
        // Arrange
        final middleware = LoggingMiddleware();
        final message = WebSocketMessage(
          type: 'test',
          data: {'key': 'value'},
          timestamp: DateTime.now(),
        );

        // Act
        final result = await middleware.process(message);

        // Assert
        expect(result, equals(message));
        // Note: In a real test, we'd capture the console output
      });

      test('should log binary messages when enabled', () async {
        // Arrange
        final middleware = LoggingMiddleware(
          logBinary: true,
          maxBinaryLogSize: 5,
        );
        final message = WebSocketMessage.binaryData(
          data: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        );

        // Act
        final result = await middleware.process(message);

        // Assert
        expect(result, equals(message));
      });
    });

    group('AnalyticsMiddleware', () {
      test('should track message counts', () async {
        // Arrange
        final middleware = AnalyticsMiddleware();

        // Act
        await middleware.process(WebSocketMessage(type: 'test1', timestamp: DateTime.now()));
        await middleware.process(WebSocketMessage(type: 'test1', timestamp: DateTime.now()));
        await middleware.process(WebSocketMessage(type: 'test2', timestamp: DateTime.now()));

        final analytics = middleware.getAnalytics();

        // Assert
        expect(analytics['message_counts']['test1'], equals(2));
        expect(analytics['message_counts']['test2'], equals(1));
        expect(analytics['total_messages'], equals(3));
      });

      test('should track binary message sizes', () async {
        // Arrange
        final middleware = AnalyticsMiddleware();

        // Act
        await middleware.process(WebSocketMessage.binaryData(
          data: Uint8List.fromList([1, 2, 3]),
        ));
        await middleware.process(WebSocketMessage.binaryData(
          data: Uint8List.fromList([1, 2, 3, 4, 5]),
        ));

        final analytics = middleware.getAnalytics();

        // Assert
        expect(analytics['binary_message_sizes']['binary'], equals(8)); // 3 + 5
        expect(analytics['total_binary_size'], equals(8));
      });

      test('should reset analytics correctly', () async {
        // Arrange
        final middleware = AnalyticsMiddleware();
        await middleware.process(WebSocketMessage(type: 'test', timestamp: DateTime.now()));

        // Act
        middleware.resetAnalytics();
        final analytics = middleware.getAnalytics();

        // Assert
        expect(analytics['total_messages'], equals(0));
      });
    });

    group('RateLimitingMiddleware', () {
      test('should allow messages within rate limit', () async {
        // Arrange
        final middleware = RateLimitingMiddleware(
          maxMessagesPerMinute: 2,
          timeWindow: const Duration(seconds: 1),
        );

        final message = WebSocketMessage(type: 'test', timestamp: DateTime.now());

        // Act & Assert
        await middleware.process(message); // Should succeed
        await middleware.process(message); // Should succeed
      });

      test('should reject messages exceeding rate limit', () async {
        // Arrange
        final middleware = RateLimitingMiddleware(
          maxMessagesPerMinute: 1,
          timeWindow: const Duration(seconds: 10),
        );

        final message = WebSocketMessage(type: 'test', timestamp: DateTime.now());

        // Act & Assert
        await middleware.process(message); // Should succeed
        
        expect(
          () => middleware.process(message), // Should fail
          throwsException,
        );
      });
    });

    group('ValidationMiddleware', () {
      test('should validate messages correctly', () async {
        // Arrange
        final middleware = ValidationMiddleware();
        middleware.registerValidator('test', TestValidator(isValid: true));

        final message = WebSocketMessage(type: 'test', timestamp: DateTime.now());

        // Act
        final result = await middleware.process(message);

        // Assert
        expect(result, equals(message));
      });

      test('should reject invalid messages', () async {
        // Arrange
        final middleware = ValidationMiddleware();
        middleware.registerValidator('test', TestValidator(isValid: false));

        final message = WebSocketMessage(type: 'test', timestamp: DateTime.now());

        // Act & Assert
        expect(
          () => middleware.process(message),
          throwsException,
        );
      });
    });

    group('TTSRequestValidator', () {
      test('should validate valid TTS requests', () async {
        // Arrange
        final validator = TTSRequestValidator();
        final message = WebSocketMessage(
          type: 'tts_request',
          data: {
            'text': 'Hello world',
            'provider': 'elevenlabs',
          },
          timestamp: DateTime.now(),
        );

        // Act
        final result = await validator.validate(message);

        // Assert
        expect(result.isValid, isTrue);
      });

      test('should reject TTS requests without text', () async {
        // Arrange
        final validator = TTSRequestValidator();
        final message = WebSocketMessage(
          type: 'tts_request',
          data: {
            'provider': 'elevenlabs',
          },
          timestamp: DateTime.now(),
        );

        // Act
        final result = await validator.validate(message);

        // Assert
        expect(result.isValid, isFalse);
        expect(result.error, contains('text is required'));
      });

      test('should reject TTS requests with invalid provider', () async {
        // Arrange
        final validator = TTSRequestValidator();
        final message = WebSocketMessage(
          type: 'tts_request',
          data: {
            'text': 'Hello world',
            'provider': 'invalid',
          },
          timestamp: DateTime.now(),
        );

        // Act
        final result = await validator.validate(message);

        // Assert
        expect(result.isValid, isFalse);
        expect(result.error, contains('Invalid TTS provider'));
      });

      test('should reject TTS requests with text too long', () async {
        // Arrange
        final validator = TTSRequestValidator();
        final longText = 'a' * 5001; // Exceeds 5000 character limit
        final message = WebSocketMessage(
          type: 'tts_request',
          data: {
            'text': longText,
            'provider': 'elevenlabs',
          },
          timestamp: DateTime.now(),
        );

        // Act
        final result = await validator.validate(message);

        // Assert
        expect(result.isValid, isFalse);
        expect(result.error, contains('text too long'));
      });
    });
  });

  group('Specialized Message Types', () {
    test('AudioChunkMessage should detect last chunk correctly', () {
      // Arrange
      final lastChunk = AudioChunkMessage(
        sequenceNumber: 4,
        totalChunks: 5,
        timestamp: DateTime.now(),
      );

      final notLastChunk = AudioChunkMessage(
        sequenceNumber: 2,
        totalChunks: 5,
        timestamp: DateTime.now(),
      );

      // Assert
      expect(lastChunk.isLastChunk, isTrue);
      expect(notLastChunk.isLastChunk, isFalse);
    });

    test('should create AudioChunkMessage from WebSocketMessage correctly', () {
      // Arrange
      final binaryData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final webSocketMessage = WebSocketMessage(
        type: 'audio_chunk',
        data: {
          'provider': 'elevenlabs',
          'sequence_number': 2,
          'total_chunks': 5,
        },
        binaryData: binaryData,
        metadata: {'quality': 'high'},
        timestamp: DateTime.now(),
      );

      // Act
      final audioChunk = AudioChunkMessage.fromWebSocketMessage(webSocketMessage);

      // Assert
      expect(audioChunk.provider, equals('elevenlabs'));
      expect(audioChunk.sequenceNumber, equals(2));
      expect(audioChunk.totalChunks, equals(5));
      expect(audioChunk.audioData, equals(binaryData));
      expect(audioChunk.metadata!['quality'], equals('high'));
    });
  });
}

// Test helper classes

class TestMiddleware extends MessageMiddleware {
  final String name;
  final List<String> processingOrder;

  TestMiddleware(this.name, this.processingOrder);

  @override
  Future<WebSocketMessage> process(WebSocketMessage message) async {
    processingOrder.add(name);
    return message;
  }
}

class FailingMiddleware extends MessageMiddleware {
  @override
  Future<WebSocketMessage> process(WebSocketMessage message) async {
    throw Exception('Middleware failed');
  }
}

class TestValidator extends MessageValidator {
  final bool isValid;

  TestValidator({required this.isValid});

  @override
  Future<ValidationResult> validate(WebSocketMessage message) async {
    return isValid 
        ? const ValidationResult.valid()
        : const ValidationResult.invalid('Test validation failed');
  }
}