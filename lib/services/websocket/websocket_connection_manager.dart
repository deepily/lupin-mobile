import 'dart:async';
import 'dart:typed_data';
import 'enhanced_websocket_service.dart';
import 'websocket_message_router.dart';

/// Comprehensive WebSocket connection manager that coordinates all WebSocket functionality
class WebSocketConnectionManager {
  final EnhancedWebSocketService _webSocketService;
  final WebSocketMessageRouter _messageRouter;
  
  // Stream subscriptions
  StreamSubscription? _messageSubscription;
  StreamSubscription? _eventSubscription;
  
  // Connection monitoring
  Timer? _connectionMonitorTimer;
  final List<ConnectionStateListener> _stateListeners = [];
  
  // Message handlers for common use cases
  final Map<String, StreamSubscription> _messageSubscriptions = {};
  
  // Configuration
  final ConnectionManagerConfig _config;
  
  WebSocketConnectionManager({
    required EnhancedWebSocketService webSocketService,
    required WebSocketMessageRouter messageRouter,
    ConnectionManagerConfig? config,
  })  : _webSocketService = webSocketService,
        _messageRouter = messageRouter,
        _config = config ?? ConnectionManagerConfig.defaultConfig() {
    _initialize();
  }
  
  // Public getters
  bool get isConnected => _webSocketService.isConnected;
  bool get isConnecting => _webSocketService.isConnecting;
  WebSocketConnectionState get connectionState => _webSocketService.connectionState;
  String? get sessionId => _webSocketService.sessionId;
  String? get userId => _webSocketService.userId;
  WebSocketMetrics get metrics => _webSocketService.metrics;
  
  // Message routing streams
  Stream<AudioChunkMessage> get audioChunks => _messageRouter.audioChunks;
  Stream<TTSStatusMessage> get ttsStatus => _messageRouter.ttsStatus;
  Stream<VoiceInputMessage> get voiceInput => _messageRouter.voiceInput;
  Stream<ErrorMessage> get errors => _messageRouter.errors;
  
  /// Initialize the connection manager
  void _initialize() {
    _setupMessageRouting();
    _setupEventHandling();
    _setupDefaultHandlers();
    _startConnectionMonitoring();
  }
  
  /// Set up message routing from WebSocket service to message router
  void _setupMessageRouting() {
    _messageSubscription = _webSocketService.messageStream.listen(
      (message) => _messageRouter.routeMessage(message),
      onError: (error) => _handleRoutingError(error),
    );
  }
  
  /// Set up event handling from WebSocket service
  void _setupEventHandling() {
    _eventSubscription = _webSocketService.eventStream.listen(
      _handleWebSocketEvent,
      onError: (error) => _handleEventError(error),
    );
  }
  
  /// Set up default message handlers
  void _setupDefaultHandlers() {
    // Register default middlewares
    if (_config.enableLogging) {
      _messageRouter.registerMiddleware(LoggingMiddleware(
        logBinary: _config.logBinaryMessages,
        maxBinaryLogSize: _config.maxBinaryLogSize,
      ));
    }
    
    if (_config.enableAnalytics) {
      _messageRouter.registerMiddleware(AnalyticsMiddleware());
    }
    
    if (_config.enableRateLimit) {
      _messageRouter.registerMiddleware(RateLimitingMiddleware(
        maxMessagesPerMinute: _config.maxMessagesPerMinute,
      ));
    }
    
    if (_config.enableValidation) {
      final validationMiddleware = ValidationMiddleware();
      validationMiddleware.registerValidator('tts_request', TTSRequestValidator());
      _messageRouter.registerMiddleware(validationMiddleware);
    }
    
    // Register default message handlers
    _registerDefaultHandlers();
  }
  
  /// Register default message handlers for common scenarios
  void _registerDefaultHandlers() {
    // Handle connection status messages
    _messageRouter.registerHandler('connection_status', (message) async {
      _notifyStateListeners(ConnectionStateChange(
        from: connectionState,
        to: connectionState,
        details: message.data,
      ));
    });
    
    // Handle server notifications
    _messageRouter.registerHandler('server_notification', (message) async {
      final notification = ServerNotification.fromMessage(message);
      _handleServerNotification(notification);
    });
    
    // Handle session updates
    _messageRouter.registerHandler('session_update', (message) async {
      final sessionData = message.data;
      if (sessionData != null) {
        _handleSessionUpdate(sessionData);
      }
    });
  }
  
  /// Start connection monitoring
  void _startConnectionMonitoring() {
    _connectionMonitorTimer = Timer.periodic(
      _config.connectionCheckInterval,
      (_) => _performConnectionCheck(),
    );
  }
  
  /// Connect to WebSocket server
  Future<void> connect({
    String? userId,
    Map<String, String>? headers,
    bool clearQueue = false,
  }) async {
    try {
      await _webSocketService.connect(
        userId: userId,
        headers: headers,
        clearQueue: clearQueue,
      );
    } catch (e) {
      _handleConnectionError(e);
      rethrow;
    }
  }
  
  /// Disconnect from WebSocket server
  Future<void> disconnect({bool clearQueue = true}) async {
    await _webSocketService.disconnect(clearQueue: clearQueue);
  }
  
  /// Send TTS request
  Future<void> sendTTSRequest({
    required String text,
    required String provider,
    String? voiceId,
    Map<String, dynamic>? settings,
    MessagePriority priority = MessagePriority.normal,
  }) async {
    final message = _messageRouter.createTTSRequest(
      text: text,
      provider: provider,
      voiceId: voiceId,
      settings: settings,
    );
    
    await _webSocketService.sendMessage(message, priority: priority);
  }
  
  /// Send TTS request and wait for audio completion
  Future<List<AudioChunkMessage>> sendTTSRequestAndWaitForAudio({
    required String text,
    required String provider,
    String? voiceId,
    Map<String, dynamic>? settings,
    Duration? timeout,
  }) async {
    final chunks = <AudioChunkMessage>[];
    final completer = Completer<List<AudioChunkMessage>>();
    
    // Listen for audio chunks
    late StreamSubscription audioSubscription;
    late StreamSubscription statusSubscription;
    
    audioSubscription = audioChunks.listen((chunk) {
      if (chunk.provider == provider) {
        chunks.add(chunk);
        
        if (chunk.isLastChunk) {
          audioSubscription.cancel();
          statusSubscription.cancel();
          completer.complete(chunks);
        }
      }
    });
    
    // Listen for completion or error
    statusSubscription = ttsStatus.listen((status) {
      if (status.provider == provider) {
        if (status.status == 'tts_complete') {
          audioSubscription.cancel();
          statusSubscription.cancel();
          completer.complete(chunks);
        } else if (status.status == 'tts_error') {
          audioSubscription.cancel();
          statusSubscription.cancel();
          completer.completeError(Exception(status.details?['error'] ?? 'TTS error'));
        }
      }
    });
    
    // Set up timeout
    final timeoutDuration = timeout ?? const Duration(seconds: 30);
    Timer(timeoutDuration, () {
      if (!completer.isCompleted) {
        audioSubscription.cancel();
        statusSubscription.cancel();
        completer.completeError(TimeoutException(
          'TTS request timeout',
          timeoutDuration,
        ));
      }
    });
    
    // Send the request
    await sendTTSRequest(
      text: text,
      provider: provider,
      voiceId: voiceId,
      settings: settings,
      priority: MessagePriority.high,
    );
    
    return await completer.future;
  }
  
  /// Send voice input
  Future<void> sendVoiceInput({
    required String action,
    Uint8List? audioData,
    Map<String, dynamic>? settings,
    MessagePriority priority = MessagePriority.high,
  }) async {
    final message = _messageRouter.createVoiceInput(
      action: action,
      audioData: audioData,
      settings: settings,
    );
    
    await _webSocketService.sendMessage(message, priority: priority);
  }
  
  /// Send agent interaction
  Future<void> sendAgentInteraction({
    required String agentType,
    required String action,
    Map<String, dynamic>? data,
    MessagePriority priority = MessagePriority.normal,
  }) async {
    final message = _messageRouter.createAgentInteraction(
      agentType: agentType,
      action: action,
      data: data,
    );
    
    await _webSocketService.sendMessage(message, priority: priority);
  }
  
  /// Send custom message
  Future<void> sendCustomMessage(
    WebSocketMessage message, {
    MessagePriority priority = MessagePriority.normal,
  }) async {
    await _webSocketService.sendMessage(message, priority: priority);
  }
  
  /// Send message and wait for response
  Future<WebSocketMessage> sendMessageWithResponse(
    WebSocketMessage message, {
    Duration? timeout,
    MessagePriority priority = MessagePriority.normal,
  }) async {
    return await _webSocketService.sendMessageWithResponse(
      message,
      timeout: timeout,
      priority: priority,
    );
  }
  
  /// Register a message handler
  void registerMessageHandler(String messageType, MessageHandler handler) {
    _messageRouter.registerHandler(messageType, handler);
  }
  
  /// Register a binary message handler
  void registerBinaryMessageHandler(String messageType, BinaryMessageHandler handler) {
    _messageRouter.registerBinaryHandler(messageType, handler);
  }
  
  /// Register a connection state listener
  void addConnectionStateListener(ConnectionStateListener listener) {
    _stateListeners.add(listener);
  }
  
  /// Remove a connection state listener
  void removeConnectionStateListener(ConnectionStateListener listener) {
    _stateListeners.remove(listener);
  }
  
  /// Subscribe to specific message type with automatic cleanup
  StreamSubscription<T> subscribeToMessages<T>(
    String messageType,
    Stream<T> messageStream,
    void Function(T) onMessage, {
    void Function(Object)? onError,
  }) {
    final subscription = messageStream.listen(
      onMessage,
      onError: onError ?? _handleSubscriptionError,
    );
    
    _messageSubscriptions[messageType] = subscription;
    return subscription;
  }
  
  /// Unsubscribe from specific message type
  void unsubscribeFromMessages(String messageType) {
    _messageSubscriptions[messageType]?.cancel();
    _messageSubscriptions.remove(messageType);
  }
  
  /// Get connection statistics
  Map<String, dynamic> getConnectionStats() {
    return {
      'websocket_stats': _webSocketService.getConnectionStats(),
      'routing_stats': _messageRouter.getRoutingStats(),
      'active_subscriptions': _messageSubscriptions.length,
      'state_listeners': _stateListeners.length,
      'config': _config.toJson(),
    };
  }
  
  /// Perform health check
  Future<HealthCheckResult> performHealthCheck() async {
    final stats = _webSocketService.getConnectionStats();
    final metrics = _webSocketService.metrics;
    
    final issues = <String>[];
    
    // Check connection state
    if (!isConnected) {
      issues.add('WebSocket not connected');
    }
    
    // Check message flow
    if (metrics.messagesReceived == 0 && metrics.messagesSent > 0) {
      issues.add('No messages received despite sending messages');
    }
    
    // Check error rates
    final errorRate = metrics.connectionErrors / 
        (metrics.connectionAttempts > 0 ? metrics.connectionAttempts : 1);
    if (errorRate > 0.5) {
      issues.add('High connection error rate: ${(errorRate * 100).toStringAsFixed(1)}%');
    }
    
    // Check queue sizes
    final queueSize = _webSocketService.queueSize;
    if (queueSize > 50) {
      issues.add('Large message queue: $queueSize messages');
    }
    
    return HealthCheckResult(
      isHealthy: issues.isEmpty,
      issues: issues,
      stats: stats,
      timestamp: DateTime.now(),
    );
  }
  
  /// Handle WebSocket events
  void _handleWebSocketEvent(WebSocketEvent event) {
    if (event is WebSocketStateChangedEvent) {
      _notifyStateListeners(ConnectionStateChange(
        from: event.from,
        to: event.to,
      ));
    }
    
    // Forward critical events to error stream if needed
    if (event is WebSocketConnectionErrorEvent ||
        event is WebSocketAuthenticationFailedEvent ||
        event is WebSocketConnectionFailedEvent) {
      _messageRouter._errorController.add(ErrorMessage(
        error: _getEventErrorMessage(event),
        timestamp: event.timestamp,
      ));
    }
  }
  
  /// Handle routing errors
  void _handleRoutingError(dynamic error) {
    _messageRouter._errorController.add(ErrorMessage(
      error: 'Message routing error: $error',
      timestamp: DateTime.now(),
    ));
  }
  
  /// Handle event errors
  void _handleEventError(dynamic error) {
    _messageRouter._errorController.add(ErrorMessage(
      error: 'Event handling error: $error',
      timestamp: DateTime.now(),
    ));
  }
  
  /// Handle connection errors
  void _handleConnectionError(dynamic error) {
    _messageRouter._errorController.add(ErrorMessage(
      error: 'Connection error: $error',
      timestamp: DateTime.now(),
    ));
  }
  
  /// Handle subscription errors
  void _handleSubscriptionError(dynamic error) {
    _messageRouter._errorController.add(ErrorMessage(
      error: 'Subscription error: $error',
      timestamp: DateTime.now(),
    ));
  }
  
  /// Handle server notifications
  void _handleServerNotification(ServerNotification notification) {
    // Implement server notification handling
    print('[WebSocket] Server notification: ${notification.type} - ${notification.message}');
  }
  
  /// Handle session updates
  void _handleSessionUpdate(Map<String, dynamic> sessionData) {
    // Implement session update handling
    print('[WebSocket] Session update: $sessionData');
  }
  
  /// Perform periodic connection check
  void _performConnectionCheck() {
    if (_config.enableHealthChecks) {
      performHealthCheck().then((result) {
        if (!result.isHealthy) {
          print('[WebSocket] Health check failed: ${result.issues.join(', ')}');
        }
      }).catchError((error) {
        print('[WebSocket] Health check error: $error');
      });
    }
  }
  
  /// Notify connection state listeners
  void _notifyStateListeners(ConnectionStateChange change) {
    for (final listener in _stateListeners) {
      try {
        listener(change);
      } catch (e) {
        print('[WebSocket] State listener error: $e');
      }
    }
  }
  
  /// Get error message from WebSocket event
  String _getEventErrorMessage(WebSocketEvent event) {
    if (event is WebSocketConnectionErrorEvent) {
      return 'Connection error: ${event.error}';
    } else if (event is WebSocketAuthenticationFailedEvent) {
      return 'Authentication failed: ${event.error}';
    } else if (event is WebSocketConnectionFailedEvent) {
      return 'Connection failed: ${event.error}';
    }
    return 'Unknown error event';
  }
  
  /// Dispose all resources
  void dispose() {
    _connectionMonitorTimer?.cancel();
    _messageSubscription?.cancel();
    _eventSubscription?.cancel();
    
    // Cancel all message subscriptions
    for (final subscription in _messageSubscriptions.values) {
      subscription.cancel();
    }
    _messageSubscriptions.clear();
    
    _stateListeners.clear();
    _messageRouter.dispose();
    _webSocketService.dispose();
  }
}

/// Connection manager configuration
class ConnectionManagerConfig {
  final bool enableLogging;
  final bool enableAnalytics;
  final bool enableRateLimit;
  final bool enableValidation;
  final bool enableHealthChecks;
  final bool logBinaryMessages;
  final int maxBinaryLogSize;
  final int maxMessagesPerMinute;
  final Duration connectionCheckInterval;
  
  const ConnectionManagerConfig({
    this.enableLogging = true,
    this.enableAnalytics = true,
    this.enableRateLimit = true,
    this.enableValidation = true,
    this.enableHealthChecks = true,
    this.logBinaryMessages = false,
    this.maxBinaryLogSize = 100,
    this.maxMessagesPerMinute = 60,
    this.connectionCheckInterval = const Duration(minutes: 1),
  });
  
  factory ConnectionManagerConfig.defaultConfig() {
    return const ConnectionManagerConfig();
  }
  
  factory ConnectionManagerConfig.production() {
    return const ConnectionManagerConfig(
      enableLogging = false,
      logBinaryMessages = false,
      enableHealthChecks = true,
    );
  }
  
  factory ConnectionManagerConfig.development() {
    return const ConnectionManagerConfig(
      enableLogging = true,
      logBinaryMessages = true,
      maxBinaryLogSize = 200,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'enable_logging': enableLogging,
      'enable_analytics': enableAnalytics,
      'enable_rate_limit': enableRateLimit,
      'enable_validation': enableValidation,
      'enable_health_checks': enableHealthChecks,
      'log_binary_messages': logBinaryMessages,
      'max_binary_log_size': maxBinaryLogSize,
      'max_messages_per_minute': maxMessagesPerMinute,
      'connection_check_interval_ms': connectionCheckInterval.inMilliseconds,
    };
  }
}

/// Connection state change notification
class ConnectionStateChange {
  final WebSocketConnectionState from;
  final WebSocketConnectionState to;
  final Map<String, dynamic>? details;
  final DateTime timestamp;
  
  ConnectionStateChange({
    required this.from,
    required this.to,
    this.details,
  }) : timestamp = DateTime.now();
}

/// Connection state listener function type
typedef ConnectionStateListener = void Function(ConnectionStateChange change);

/// Health check result
class HealthCheckResult {
  final bool isHealthy;
  final List<String> issues;
  final Map<String, dynamic> stats;
  final DateTime timestamp;
  
  const HealthCheckResult({
    required this.isHealthy,
    required this.issues,
    required this.stats,
    required this.timestamp,
  });
}

/// Server notification
class ServerNotification {
  final String type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  const ServerNotification({
    required this.type,
    required this.message,
    this.data,
    required this.timestamp,
  });
  
  factory ServerNotification.fromMessage(WebSocketMessage message) {
    return ServerNotification(
      type: message.data?['type'] ?? 'unknown',
      message: message.data?['message'] ?? '',
      data: message.data,
      timestamp: message.timestamp,
    );
  }
}