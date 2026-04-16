import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'enhanced_websocket_service.dart';
import '../../core/constants/app_constants.dart';

/// Message router for organizing WebSocket message handling
class WebSocketMessageRouter {
  final Map<String, List<MessageHandler>> _handlers = {};
  final Map<String, List<BinaryMessageHandler>> _binaryHandlers = {};
  final List<MessageProcessor> _middlewares = [];
  
  // Stream controllers for specific message types
  final StreamController<AudioChunkMessage> _audioChunkController = 
      StreamController<AudioChunkMessage>.broadcast();
  final StreamController<TTSStatusMessage> _ttsStatusController = 
      StreamController<TTSStatusMessage>.broadcast();
  final StreamController<VoiceInputMessage> _voiceInputController = 
      StreamController<VoiceInputMessage>.broadcast();
  final StreamController<ErrorMessage> _errorController = 
      StreamController<ErrorMessage>.broadcast();
  
  // New stream controllers for server events
  final StreamController<QueueUpdateMessage> _queueUpdateController = 
      StreamController<QueueUpdateMessage>.broadcast();
  final StreamController<NotificationMessage> _notificationController = 
      StreamController<NotificationMessage>.broadcast();
  final StreamController<SystemMessage> _systemController = 
      StreamController<SystemMessage>.broadcast();
  final StreamController<AuthMessage> _authController = 
      StreamController<AuthMessage>.broadcast();
  
  // Public streams
  Stream<AudioChunkMessage> get audioChunks => _audioChunkController.stream;
  Stream<TTSStatusMessage> get ttsStatus => _ttsStatusController.stream;
  Stream<VoiceInputMessage> get voiceInput => _voiceInputController.stream;
  Stream<ErrorMessage> get errors => _errorController.stream;
  
  // New public streams for server events
  Stream<QueueUpdateMessage> get queueUpdates => _queueUpdateController.stream;
  Stream<NotificationMessage> get notifications => _notificationController.stream;
  Stream<SystemMessage> get systemMessages => _systemController.stream;
  Stream<AuthMessage> get authMessages => _authController.stream;
  
  /// Register a message handler for a specific message type
  void registerHandler(String messageType, MessageHandler handler) {
    _handlers.putIfAbsent(messageType, () => []).add(handler);
  }
  
  /// Register a binary message handler
  void registerBinaryHandler(String messageType, BinaryMessageHandler handler) {
    _binaryHandlers.putIfAbsent(messageType, () => []).add(handler);
  }
  
  /// Register middleware for message processing
  void registerMiddleware(MessageProcessor middleware) {
    _middlewares.add(middleware);
  }
  
  /// Remove a message handler
  void unregisterHandler(String messageType, MessageHandler handler) {
    _handlers[messageType]?.remove(handler);
    if (_handlers[messageType]?.isEmpty ?? false) {
      _handlers.remove(messageType);
    }
  }
  
  /// Remove a binary message handler
  void unregisterBinaryHandler(String messageType, BinaryMessageHandler handler) {
    _binaryHandlers[messageType]?.remove(handler);
    if (_binaryHandlers[messageType]?.isEmpty ?? false) {
      _binaryHandlers.remove(messageType);
    }
  }
  
  /// Route incoming WebSocket message
  Future<void> routeMessage(WebSocketMessage message) async {
    try {
      // Apply middlewares
      WebSocketMessage processedMessage = message;
      for (final middleware in _middlewares) {
        processedMessage = await middleware.process(processedMessage);
      }
      
      // Route to specific streams
      await _routeToStreams(processedMessage);
      
      // Route to registered handlers
      await _routeToHandlers(processedMessage);
      
    } catch (e) {
      _errorController.add(ErrorMessage(
        error: 'Message routing failed: $e',
        originalMessage: message,
        timestamp: DateTime.now(),
      ));
    }
  }
  
  /// Route message to appropriate streams
  Future<void> _routeToStreams(WebSocketMessage message) async {
    switch (message.type) {
      // Audio events
      case 'audio_chunk':
      case AppConstants.eventAudioStreamingChunk:
        _audioChunkController.add(AudioChunkMessage.fromWebSocketMessage(message));
        break;
        
      // TTS events
      case 'tts_status':
      case 'tts_start':
      case 'tts_complete':
      case 'tts_error':
      case AppConstants.eventTtsJobRequest:
      case AppConstants.eventAudioStreamingStatus:
      case AppConstants.eventAudioStreamingComplete:
        _ttsStatusController.add(TTSStatusMessage.fromWebSocketMessage(message));
        break;
        
      // Voice input events
      case 'voice_input':
      case 'voice_start':
      case 'voice_stop':
      case 'transcription':
        _voiceInputController.add(VoiceInputMessage.fromWebSocketMessage(message));
        break;
        
      // Queue events
      case AppConstants.eventQueueTodoUpdate:
      case AppConstants.eventQueueRunningUpdate:
      case AppConstants.eventQueueDoneUpdate:
      case AppConstants.eventQueueDeadUpdate:
        _queueUpdateController.add(QueueUpdateMessage.fromWebSocketMessage(message));
        break;
        
      // Notification events
      case AppConstants.eventNotificationQueueUpdate:
      case AppConstants.eventNotificationPlaySound:
        _notificationController.add(NotificationMessage.fromWebSocketMessage(message));
        break;
        
      // System events
      case AppConstants.eventSysTimeUpdate:
      case AppConstants.eventSysPing:
      case AppConstants.eventSysPong:
        _systemController.add(SystemMessage.fromWebSocketMessage(message));
        break;
        
      // Authentication events
      case AppConstants.eventAuthRequest:
      case AppConstants.eventAuthSuccess:
      case AppConstants.eventAuthError:
      case AppConstants.eventConnect:
        _authController.add(AuthMessage.fromWebSocketMessage(message));
        break;
        
      // Error events
      case 'error':
      case 'server_error':
        _errorController.add(ErrorMessage.fromWebSocketMessage(message));
        break;
    }
  }
  
  /// Route message to registered handlers
  Future<void> _routeToHandlers(WebSocketMessage message) async {
    // Handle binary messages
    if (message.binaryData != null) {
      final binaryHandlers = _binaryHandlers[message.type] ?? [];
      for (final handler in binaryHandlers) {
        try {
          await handler(message.binaryData!, message.metadata);
        } catch (e) {
          _errorController.add(ErrorMessage(
            error: 'Binary handler error: $e',
            originalMessage: message,
            timestamp: DateTime.now(),
          ));
        }
      }
      return;
    }
    
    // Handle text messages
    final handlers = _handlers[message.type] ?? [];
    for (final handler in handlers) {
      try {
        await handler(message);
      } catch (e) {
        _errorController.add(ErrorMessage(
          error: 'Message handler error: $e',
          originalMessage: message,
          timestamp: DateTime.now(),
        ));
      }
    }
    
    // Handle wildcard handlers
    final wildcardHandlers = _handlers['*'] ?? [];
    for (final handler in wildcardHandlers) {
      try {
        await handler(message);
      } catch (e) {
        _errorController.add(ErrorMessage(
          error: 'Wildcard handler error: $e',
          originalMessage: message,
          timestamp: DateTime.now(),
        ));
      }
    }
  }
  
  /// Create TTS request message
  WebSocketMessage createTTSRequest({
    required String text,
    required String provider,
    String? voiceId,
    Map<String, dynamic>? settings,
  }) {
    return WebSocketMessage(
      type: 'tts_request',
      data: {
        'text': text,
        'provider': provider,
        'voice_id': voiceId,
        'settings': settings ?? {},
      },
      timestamp: DateTime.now(),
    );
  }
  
  /// Create voice input message
  WebSocketMessage createVoiceInput({
    required String action, // 'start', 'stop', 'data'
    Uint8List? audioData,
    Map<String, dynamic>? settings,
  }) {
    return WebSocketMessage(
      type: 'voice_input',
      data: {
        'action': action,
        'settings': settings ?? {},
      },
      binaryData: audioData,
      timestamp: DateTime.now(),
    );
  }
  
  /// Create agent interaction message
  WebSocketMessage createAgentInteraction({
    required String agentType,
    required String action,
    Map<String, dynamic>? data,
  }) {
    return WebSocketMessage(
      type: 'agent_interaction',
      data: {
        'agent_type': agentType,
        'action': action,
        'data': data ?? {},
      },
      timestamp: DateTime.now(),
    );
  }
  
  /// Get routing statistics
  Map<String, dynamic> getRoutingStats() {
    return {
      'registered_handlers': _handlers.map((type, handlers) => 
          MapEntry(type, handlers.length)),
      'registered_binary_handlers': _binaryHandlers.map((type, handlers) => 
          MapEntry(type, handlers.length)),
      'middleware_count': _middlewares.length,
      'active_streams': {
        'audio_chunks': _audioChunkController.hasListener,
        'tts_status': _ttsStatusController.hasListener,
        'voice_input': _voiceInputController.hasListener,
        'errors': _errorController.hasListener,
      },
    };
  }
  
  /// Add an error message to the error stream
  void addError(String error, {WebSocketMessage? originalMessage}) {
    _errorController.add(ErrorMessage(
      error: error,
      originalMessage: originalMessage,
      timestamp: DateTime.now(),
    ));
  }
  
  /// Dispose resources
  void dispose() {
    _audioChunkController.close();
    _ttsStatusController.close();
    _voiceInputController.close();
    _errorController.close();
    
    // Close new stream controllers
    _queueUpdateController.close();
    _notificationController.close();
    _systemController.close();
    _authController.close();
    
    _handlers.clear();
    _binaryHandlers.clear();
    _middlewares.clear();
  }
}

/// Message handler function type
typedef MessageHandler = Future<void> Function(WebSocketMessage message);

/// Binary message handler function type
typedef BinaryMessageHandler = Future<void> Function(
  Uint8List data, 
  Map<String, dynamic>? metadata,
);

/// Message middleware function type (deprecated - use MessageProcessor)
typedef MessageMiddleware = Future<WebSocketMessage> Function(WebSocketMessage message);

// Message classes for different event types

/// Queue update message
class QueueUpdateMessage {
  final String queueType; // 'todo', 'running', 'done', 'dead'
  final Map<String, dynamic> queueData;
  final DateTime timestamp;
  final String? sessionId;
  
  QueueUpdateMessage({
    required this.queueType,
    required this.queueData,
    required this.timestamp,
    this.sessionId,
  });
  
  factory QueueUpdateMessage.fromWebSocketMessage(WebSocketMessage message) {
    final type = message.type;
    String queueType = 'unknown';
    
    if (type == AppConstants.eventQueueTodoUpdate) queueType = 'todo';
    else if (type == AppConstants.eventQueueRunningUpdate) queueType = 'running';
    else if (type == AppConstants.eventQueueDoneUpdate) queueType = 'done';
    else if (type == AppConstants.eventQueueDeadUpdate) queueType = 'dead';
    
    return QueueUpdateMessage(
      queueType: queueType,
      queueData: message.data ?? {},
      timestamp: message.timestamp,
      sessionId: message.data?['session_id'],
    );
  }
}

/// Notification message
class NotificationMessage {
  final String notificationType; // 'queue_update', 'play_sound'
  final String? message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  NotificationMessage({
    required this.notificationType,
    this.message,
    this.data,
    required this.timestamp,
  });
  
  factory NotificationMessage.fromWebSocketMessage(WebSocketMessage message) {
    final type = message.type;
    String notificationType = 'unknown';
    
    if (type == AppConstants.eventNotificationQueueUpdate) notificationType = 'queue_update';
    else if (type == AppConstants.eventNotificationPlaySound) notificationType = 'play_sound';
    
    return NotificationMessage(
      notificationType: notificationType,
      message: message.data?['message'],
      data: message.data,
      timestamp: message.timestamp,
    );
  }
}

/// System message
class SystemMessage {
  final String systemType; // 'time_update', 'ping', 'pong'
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  SystemMessage({
    required this.systemType,
    this.data,
    required this.timestamp,
  });
  
  factory SystemMessage.fromWebSocketMessage(WebSocketMessage message) {
    final type = message.type;
    String systemType = 'unknown';
    
    if (type == AppConstants.eventSysTimeUpdate) systemType = 'time_update';
    else if (type == AppConstants.eventSysPing) systemType = 'ping';
    else if (type == AppConstants.eventSysPong) systemType = 'pong';
    
    return SystemMessage(
      systemType: systemType,
      data: message.data,
      timestamp: message.timestamp,
    );
  }
}

/// Authentication message
class AuthMessage {
  final String authType; // 'auth_request', 'auth_success', 'auth_error', 'connect'
  final String? userId;
  final String? sessionId;
  final String? message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  AuthMessage({
    required this.authType,
    this.userId,
    this.sessionId,
    this.message,
    this.data,
    required this.timestamp,
  });
  
  factory AuthMessage.fromWebSocketMessage(WebSocketMessage message) {
    final type = message.type;
    String authType = 'unknown';
    
    if (type == AppConstants.eventAuthRequest) authType = 'auth_request';
    else if (type == AppConstants.eventAuthSuccess) authType = 'auth_success';
    else if (type == AppConstants.eventAuthError) authType = 'auth_error';
    else if (type == AppConstants.eventConnect) authType = 'connect';
    
    return AuthMessage(
      authType: authType,
      userId: message.data?['user_id'],
      sessionId: message.data?['session_id'],
      message: message.data?['message'],
      data: message.data,
      timestamp: message.timestamp,
    );
  }
}


/// Message processor for processing messages before routing
abstract class MessageProcessor {
  Future<WebSocketMessage> process(WebSocketMessage message);
}

/// Logging middleware
class LoggingMiddleware extends MessageProcessor {
  final bool logBinary;
  final int maxBinaryLogSize;
  
  LoggingMiddleware({
    this.logBinary = false,
    this.maxBinaryLogSize = 100,
  });
  
  @override
  Future<WebSocketMessage> process(WebSocketMessage message) async {
    if (message.binaryData != null && logBinary) {
      final dataSize = message.binaryData!.length;
      final preview = dataSize > maxBinaryLogSize 
          ? message.binaryData!.take(maxBinaryLogSize).toList()
          : message.binaryData!;
      
      print('[WebSocket] Binary ${message.type}: ${dataSize} bytes, preview: $preview');
    } else if (message.binaryData == null) {
      print('[WebSocket] ${message.type}: ${message.data}');
    }
    
    return message;
  }
}

/// Analytics middleware
class AnalyticsMiddleware extends MessageProcessor {
  final Map<String, int> _messageCounts = {};
  final Map<String, int> _binaryMessageSizes = {};
  
  @override
  Future<WebSocketMessage> process(WebSocketMessage message) async {
    _messageCounts[message.type] = (_messageCounts[message.type] ?? 0) + 1;
    
    if (message.binaryData != null) {
      _binaryMessageSizes[message.type] = 
          (_binaryMessageSizes[message.type] ?? 0) + message.binaryData!.length;
    }
    
    return message;
  }
  
  Map<String, dynamic> getAnalytics() {
    return {
      'message_counts': Map.from(_messageCounts),
      'binary_message_sizes': Map.from(_binaryMessageSizes),
      'total_messages': _messageCounts.values.fold(0, (a, b) => a + b),
      'total_binary_size': _binaryMessageSizes.values.fold(0, (a, b) => a + b),
    };
  }
  
  void resetAnalytics() {
    _messageCounts.clear();
    _binaryMessageSizes.clear();
  }
}

/// Rate limiting middleware
class RateLimitingMiddleware extends MessageProcessor {
  final Map<String, Queue<DateTime>> _messageTimestamps = {};
  final int maxMessagesPerMinute;
  final Duration timeWindow;
  
  RateLimitingMiddleware({
    this.maxMessagesPerMinute = 60,
    this.timeWindow = const Duration(minutes: 1),
  });
  
  @override
  Future<WebSocketMessage> process(WebSocketMessage message) async {
    final now = DateTime.now();
    final messageType = message.type;
    
    _messageTimestamps.putIfAbsent(messageType, () => Queue<DateTime>());
    final timestamps = _messageTimestamps[messageType]!;
    
    // Remove old timestamps
    while (timestamps.isNotEmpty && 
           now.difference(timestamps.first) > timeWindow) {
      timestamps.removeFirst();
    }
    
    // Check rate limit
    if (timestamps.length >= maxMessagesPerMinute) {
      throw Exception('Rate limit exceeded for message type: $messageType');
    }
    
    timestamps.add(now);
    return message;
  }
}

/// Validation middleware
class ValidationMiddleware extends MessageProcessor {
  final Map<String, MessageValidator> _validators = {};
  
  void registerValidator(String messageType, MessageValidator validator) {
    _validators[messageType] = validator;
  }
  
  @override
  Future<WebSocketMessage> process(WebSocketMessage message) async {
    final validator = _validators[message.type];
    if (validator != null) {
      final validationResult = await validator.validate(message);
      if (!validationResult.isValid) {
        throw Exception('Message validation failed: ${validationResult.error}');
      }
    }
    
    return message;
  }
}

/// Message validator
abstract class MessageValidator {
  Future<ValidationResult> validate(WebSocketMessage message);
}

/// Validation result
class ValidationResult {
  final bool isValid;
  final String? error;
  
  const ValidationResult.valid() : isValid = true, error = null;
  const ValidationResult.invalid(this.error) : isValid = false;
}

/// TTS request validator
class TTSRequestValidator extends MessageValidator {
  @override
  Future<ValidationResult> validate(WebSocketMessage message) async {
    final data = message.data;
    
    if (data == null) {
      return const ValidationResult.invalid('TTS request data is required');
    }
    
    final text = data['text'] as String?;
    if (text == null || text.isEmpty) {
      return const ValidationResult.invalid('TTS text is required');
    }
    
    if (text.length > 5000) {
      return const ValidationResult.invalid('TTS text too long (max 5000 characters)');
    }
    
    final provider = data['provider'] as String?;
    if (provider == null || !['openai', 'elevenlabs'].contains(provider)) {
      return const ValidationResult.invalid('Invalid TTS provider');
    }
    
    return const ValidationResult.valid();
  }
}

/// Specialized message types
class AudioChunkMessage {
  final Uint8List? audioData;
  final String? provider;
  final int? sequenceNumber;
  final int? totalChunks;
  final Map<String, dynamic>? metadata;
  final DateTime timestamp;
  
  AudioChunkMessage({
    this.audioData,
    this.provider,
    this.sequenceNumber,
    this.totalChunks,
    this.metadata,
    required this.timestamp,
  });
  
  factory AudioChunkMessage.fromWebSocketMessage(WebSocketMessage message) {
    return AudioChunkMessage(
      audioData: message.binaryData,
      provider: message.data?['provider'],
      sequenceNumber: message.data?['sequence_number'],
      totalChunks: message.data?['total_chunks'],
      metadata: message.metadata,
      timestamp: message.timestamp,
    );
  }
  
  bool get isLastChunk => 
      sequenceNumber != null && 
      totalChunks != null && 
      sequenceNumber! >= totalChunks! - 1;
}

class TTSStatusMessage {
  final String status;
  final String? provider;
  final String? sessionId;
  final String? text;
  final Map<String, dynamic>? details;
  final DateTime timestamp;
  
  TTSStatusMessage({
    required this.status,
    this.provider,
    this.sessionId,
    this.text,
    this.details,
    required this.timestamp,
  });
  
  factory TTSStatusMessage.fromWebSocketMessage(WebSocketMessage message) {
    return TTSStatusMessage(
      status: message.type,
      provider: message.data?['provider'],
      sessionId: message.data?['session_id'],
      text: message.data?['text'],
      details: message.data,
      timestamp: message.timestamp,
    );
  }
}

class VoiceInputMessage {
  final String action;
  final Uint8List? audioData;
  final String? transcription;
  final double? confidence;
  final Map<String, dynamic>? settings;
  final DateTime timestamp;
  
  VoiceInputMessage({
    required this.action,
    this.audioData,
    this.transcription,
    this.confidence,
    this.settings,
    required this.timestamp,
  });
  
  factory VoiceInputMessage.fromWebSocketMessage(WebSocketMessage message) {
    return VoiceInputMessage(
      action: message.data?['action'] ?? message.type,
      audioData: message.binaryData,
      transcription: message.data?['transcription'],
      confidence: message.data?['confidence'],
      settings: message.data?['settings'],
      timestamp: message.timestamp,
    );
  }
}

class ErrorMessage {
  final String error;
  final String? code;
  final WebSocketMessage? originalMessage;
  final Map<String, dynamic>? details;
  final DateTime timestamp;
  
  ErrorMessage({
    required this.error,
    this.code,
    this.originalMessage,
    this.details,
    required this.timestamp,
  });
  
  factory ErrorMessage.fromWebSocketMessage(WebSocketMessage message) {
    return ErrorMessage(
      error: message.data?['error'] ?? 'Unknown error',
      code: message.data?['code'],
      details: message.data,
      timestamp: message.timestamp,
    );
  }
}