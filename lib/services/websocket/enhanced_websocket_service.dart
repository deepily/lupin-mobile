import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';

/// Enhanced WebSocket service with improved message handling, queuing, and resilience
class EnhancedWebSocketService {
  final Dio _dio;
  WebSocketChannel? _channel;
  
  // Message handling
  final StreamController<WebSocketMessage> _messageController = 
      StreamController<WebSocketMessage>.broadcast();
  final StreamController<WebSocketEvent> _eventController = 
      StreamController<WebSocketEvent>.broadcast();
  
  // Message queuing
  final Queue<QueuedMessage> _messageQueue = Queue<QueuedMessage>();
  final Queue<QueuedMessage> _priorityQueue = Queue<QueuedMessage>();
  final Map<String, PendingRequest> _pendingRequests = {};
  
  // Connection management
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _queueProcessTimer;
  Timer? _healthCheckTimer;
  
  // Connection state
  WebSocketConnectionState _connectionState = WebSocketConnectionState.disconnected;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  DateTime? _lastConnectedTime;
  DateTime? _lastMessageTime;
  
  // Configuration
  static const int maxReconnectAttempts = 10;
  static const Duration initialReconnectDelay = Duration(seconds: 2);
  static const Duration maxReconnectDelay = Duration(seconds: 60);
  static const Duration pingInterval = Duration(seconds: 30);
  static const Duration healthCheckInterval = Duration(seconds: 10);
  static const Duration requestTimeout = Duration(seconds: 30);
  static const int maxQueueSize = 1000;
  static const int maxPriorityQueueSize = 100;
  
  // Session management
  String? _sessionId;
  String? _userId;
  String? _authToken;
  
  // Performance metrics
  final WebSocketMetrics _metrics = WebSocketMetrics();
  
  // Public getters
  bool get isConnected => _connectionState == WebSocketConnectionState.connected;
  bool get isConnecting => _connectionState == WebSocketConnectionState.connecting;
  WebSocketConnectionState get connectionState => _connectionState;
  String? get sessionId => _sessionId;
  String? get userId => _userId;
  Stream<WebSocketMessage> get messageStream => _messageController.stream;
  Stream<WebSocketEvent> get eventStream => _eventController.stream;
  WebSocketMetrics get metrics => _metrics;
  int get queueSize => _messageQueue.length;
  int get priorityQueueSize => _priorityQueue.length;
  
  EnhancedWebSocketService(this._dio) {
    _startHealthCheck();
    _startQueueProcessor();
  }
  
  /// Connect to WebSocket with enhanced error handling
  Future<void> connect({
    String? userId,
    Map<String, String>? headers,
    bool clearQueue = false,
  }) async {
    if (_connectionState == WebSocketConnectionState.connected) {
      return;
    }
    
    if (_connectionState == WebSocketConnectionState.connecting) {
      // Wait for current connection attempt
      await _waitForConnection();
      return;
    }
    
    _userId = userId;
    _shouldReconnect = true;
    
    if (clearQueue) {
      _clearQueues();
    }
    
    await _establishConnection(headers: headers);
  }
  
  /// Enhanced connection establishment with better error handling
  Future<void> _establishConnection({Map<String, String>? headers}) async {
    _setConnectionState(WebSocketConnectionState.connecting);
    
    try {
      _metrics.connectionAttempts++;
      
      // Step 1: Get session ID with retry logic
      _sessionId = await _getSessionIdWithRetry();
      
      // Step 2: Connect to WebSocket
      final uri = Uri.parse('${AppConstants.wsBaseUrl}/ws/$_sessionId');
      
      _eventController.add(WebSocketEvent.connecting(uri.toString()));
      
      _channel = WebSocketChannel.connect(
        uri,
        protocols: ['lupin-mobile-v1'],
      );
      
      // Wait for connection with timeout
      await _channel!.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Connection timeout'),
      );
      
      _setConnectionState(WebSocketConnectionState.connected);
      _lastConnectedTime = DateTime.now();
      _reconnectAttempts = 0;
      _metrics.successfulConnections++;
      
      _eventController.add(WebSocketEvent.connected(_sessionId!));
      
      // Start listening to messages
      _channel!.stream.listen(
        _handleIncomingMessage,
        onError: _handleConnectionError,
        onDone: _handleConnectionClosed,
      );
      
      // Step 3: Authenticate if user provided
      if (_userId != null) {
        await _authenticateWithRetry(_userId!);
      }
      
      // Step 4: Start periodic tasks
      _startPingTimer();
      _processMessageQueue();
      
    } catch (e) {
      _metrics.failedConnections++;
      _setConnectionState(WebSocketConnectionState.disconnected);
      _eventController.add(WebSocketEvent.connectionFailed(e.toString()));
      
      await _scheduleReconnect();
    }
  }
  
  /// Get session ID with retry logic
  Future<String> _getSessionIdWithRetry({int maxRetries = 3}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await _dio.get('${AppConstants.apiBaseUrl}/api/get-session-id')
            .timeout(const Duration(seconds: 10));
        
        final sessionData = response.data;
        final sessionId = sessionData['session_id'] as String?;
        
        if (sessionId == null || sessionId.isEmpty) {
          throw Exception('Invalid session ID received');
        }
        
        return sessionId;
        
      } catch (e) {
        if (attempt == maxRetries) {
          throw Exception('Failed to get session ID after $maxRetries attempts: $e');
        }
        
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    
    throw Exception('Failed to get session ID');
  }
  
  /// Enhanced authentication with retry logic
  Future<void> _authenticateWithRetry(String userId, {int maxRetries = 3}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _authToken = 'enhanced_token_${userId}_${DateTime.now().millisecondsSinceEpoch}';
        
        final authMessage = WebSocketMessage.authentication(
          token: _authToken!,
          sessionId: _sessionId!,
          userId: userId,
          clientInfo: {
            'platform': 'flutter',
            'version': '1.0.0',
            'capabilities': ['audio', 'binary', 'compression'],
          },
        );
        
        final response = await sendMessageWithResponse(authMessage, timeout: const Duration(seconds: 10));
        
        if (response.type == 'auth_success') {
          _eventController.add(WebSocketEvent.authenticated(userId));
          return;
        } else {
          throw Exception('Authentication failed: ${response.data}');
        }
        
      } catch (e) {
        if (attempt == maxRetries) {
          _eventController.add(WebSocketEvent.authenticationFailed(e.toString()));
          throw Exception('Authentication failed after $maxRetries attempts: $e');
        }
        
        await Future.delayed(Duration(milliseconds: 1000 * attempt));
      }
    }
  }
  
  /// Enhanced message handling with type safety and routing
  void _handleIncomingMessage(dynamic rawMessage) {
    try {
      _lastMessageTime = DateTime.now();
      _metrics.messagesReceived++;
      
      WebSocketMessage message;
      
      // Handle binary messages (audio data)
      if (rawMessage is List<int> || rawMessage is Uint8List) {
        final binaryData = rawMessage is Uint8List 
            ? rawMessage 
            : Uint8List.fromList(rawMessage);
        
        message = WebSocketMessage.binaryData(
          data: binaryData,
          metadata: {'received_at': DateTime.now().toIso8601String()},
        );
        
        _metrics.binaryMessagesReceived++;
        
      } else {
        // Handle text/JSON messages
        final Map<String, dynamic> data;
        
        if (rawMessage is String) {
          data = jsonDecode(rawMessage);
        } else if (rawMessage is Map<String, dynamic>) {
          data = rawMessage;
        } else {
          throw Exception('Unknown message format: ${rawMessage.runtimeType}');
        }
        
        message = WebSocketMessage.fromJson(data);
        _metrics.textMessagesReceived++;
      }
      
      // Handle system messages
      if (_handleSystemMessage(message)) {
        return;
      }
      
      // Handle pending request responses
      if (message.requestId != null && _pendingRequests.containsKey(message.requestId)) {
        final pendingRequest = _pendingRequests.remove(message.requestId)!;
        pendingRequest.completer.complete(message);
        return;
      }
      
      // Forward to message stream
      _messageController.add(message);
      
      // Emit specific events based on message type
      _emitMessageEvent(message);
      
    } catch (e) {
      _metrics.messageParsingErrors++;
      _eventController.add(WebSocketEvent.messageParsingError(e.toString()));
      
      // Try to forward raw message
      try {
        final fallbackMessage = WebSocketMessage.raw(rawMessage);
        _messageController.add(fallbackMessage);
      } catch (e2) {
        // Log error but don't crash
        print('[WebSocket] Failed to handle raw message: $e2');
      }
    }
  }
  
  /// Handle system messages (ping/pong, auth, etc.)
  bool _handleSystemMessage(WebSocketMessage message) {
    switch (message.type) {
      case 'ping':
        _sendPong();
        return true;
        
      case 'pong':
        _metrics.lastPongReceived = DateTime.now();
        return true;
        
      case 'auth_success':
        _eventController.add(WebSocketEvent.authenticated(_userId ?? 'unknown'));
        return true;
        
      case 'auth_failed':
        _eventController.add(WebSocketEvent.authenticationFailed(
          message.data?['error'] ?? 'Unknown auth error',
        ));
        return true;
        
      case 'server_status':
        _handleServerStatus(message);
        return true;
        
      case 'rate_limit':
        _handleRateLimit(message);
        return true;
        
      default:
        return false;
    }
  }
  
  /// Emit specific events based on message type
  void _emitMessageEvent(WebSocketMessage message) {
    switch (message.type) {
      case 'audio_chunk':
        _eventController.add(WebSocketEvent.audioChunkReceived(
          data: message.binaryData,
          metadata: message.metadata,
        ));
        break;
        
      case 'audio_complete':
        _eventController.add(WebSocketEvent.audioComplete(
          message.data?['session_id'] ?? '',
        ));
        break;
        
      case 'tts_status':
        _eventController.add(WebSocketEvent.ttsStatus(
          status: message.data?['status'] ?? 'unknown',
          details: message.data,
        ));
        break;
        
      case 'error':
        _eventController.add(WebSocketEvent.serverError(
          error: message.data?['error'] ?? 'Unknown error',
          code: message.data?['code'],
        ));
        break;
    }
  }
  
  /// Send message with enhanced queuing and retry logic
  Future<void> sendMessage(
    WebSocketMessage message, {
    MessagePriority priority = MessagePriority.normal,
    bool skipQueue = false,
  }) async {
    if (skipQueue && isConnected) {
      await _sendMessageDirectly(message);
      return;
    }
    
    final queuedMessage = QueuedMessage(
      message: message,
      priority: priority,
      timestamp: DateTime.now(),
      retryCount: 0,
    );
    
    if (priority == MessagePriority.high || priority == MessagePriority.critical) {
      if (_priorityQueue.length >= maxPriorityQueueSize) {
        _priorityQueue.removeFirst();
        _metrics.queueOverflows++;
      }
      _priorityQueue.add(queuedMessage);
    } else {
      if (_messageQueue.length >= maxQueueSize) {
        _messageQueue.removeFirst();
        _metrics.queueOverflows++;
      }
      _messageQueue.add(queuedMessage);
    }
    
    // Process queue immediately if connected
    if (isConnected) {
      _processMessageQueue();
    }
  }
  
  /// Send message and wait for response
  Future<WebSocketMessage> sendMessageWithResponse(
    WebSocketMessage message, {
    Duration? timeout,
    MessagePriority priority = MessagePriority.normal,
  }) async {
    final requestId = _generateRequestId();
    final messageWithId = message.copyWith(requestId: requestId);
    
    final completer = Completer<WebSocketMessage>();
    final pendingRequest = PendingRequest(
      completer: completer,
      timestamp: DateTime.now(),
      timeout: timeout ?? requestTimeout,
    );
    
    _pendingRequests[requestId] = pendingRequest;
    
    // Set up timeout
    Timer(pendingRequest.timeout, () {
      if (_pendingRequests.containsKey(requestId)) {
        _pendingRequests.remove(requestId);
        completer.completeError(TimeoutException(
          'Request timeout',
          pendingRequest.timeout,
        ));
      }
    });
    
    await sendMessage(messageWithId, priority: priority);
    
    return await completer.future;
  }
  
  /// Send message directly without queuing
  Future<void> _sendMessageDirectly(WebSocketMessage message) async {
    if (!isConnected || _channel == null) {
      throw Exception('WebSocket not connected');
    }
    
    try {
      _metrics.messagesSent++;
      
      if (message.binaryData != null) {
        _channel!.sink.add(message.binaryData!);
        _metrics.binaryMessagesSent++;
      } else {
        final encoded = jsonEncode(message.toJson());
        _channel!.sink.add(encoded);
        _metrics.textMessagesSent++;
      }
      
    } catch (e) {
      _metrics.messageSendErrors++;
      _eventController.add(WebSocketEvent.messageSendFailed(e.toString()));
      throw Exception('Failed to send message: $e');
    }
  }
  
  /// Process message queue
  void _processMessageQueue() {
    if (!isConnected) return;
    
    // Process priority queue first
    while (_priorityQueue.isNotEmpty && isConnected) {
      final queuedMessage = _priorityQueue.removeFirst();
      _sendQueuedMessage(queuedMessage);
    }
    
    // Process normal queue
    while (_messageQueue.isNotEmpty && isConnected) {
      final queuedMessage = _messageQueue.removeFirst();
      _sendQueuedMessage(queuedMessage);
    }
  }
  
  /// Send queued message with retry logic
  Future<void> _sendQueuedMessage(QueuedMessage queuedMessage) async {
    try {
      await _sendMessageDirectly(queuedMessage.message);
      _metrics.queuedMessagesProcessed++;
      
    } catch (e) {
      queuedMessage.retryCount++;
      
      if (queuedMessage.retryCount < 3) {
        // Re-queue for retry
        if (queuedMessage.priority == MessagePriority.high || 
            queuedMessage.priority == MessagePriority.critical) {
          _priorityQueue.addFirst(queuedMessage);
        } else {
          _messageQueue.addFirst(queuedMessage);
        }
      } else {
        _metrics.queuedMessagesFailed++;
        _eventController.add(WebSocketEvent.queuedMessageFailed(
          queuedMessage.message.type,
          e.toString(),
        ));
      }
    }
  }
  
  /// Enhanced connection error handling
  void _handleConnectionError(dynamic error) {
    _metrics.connectionErrors++;
    _setConnectionState(WebSocketConnectionState.error);
    
    _eventController.add(WebSocketEvent.connectionError(error.toString()));
    
    // Clean up
    _pingTimer?.cancel();
    
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }
  
  /// Enhanced connection closed handling
  void _handleConnectionClosed() {
    _setConnectionState(WebSocketConnectionState.disconnected);
    _eventController.add(WebSocketEvent.disconnected());
    
    // Clean up
    _pingTimer?.cancel();
    
    // Complete pending requests with error
    for (final pendingRequest in _pendingRequests.values) {
      pendingRequest.completer.completeError(
        Exception('Connection closed'),
      );
    }
    _pendingRequests.clear();
    
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }
  
  /// Enhanced reconnection with exponential backoff
  Future<void> _scheduleReconnect() async {
    if (!_shouldReconnect || _reconnectAttempts >= maxReconnectAttempts) {
      _eventController.add(WebSocketEvent.reconnectGiveUp(_reconnectAttempts));
      return;
    }
    
    _reconnectAttempts++;
    
    // Exponential backoff with jitter
    final baseDelay = initialReconnectDelay.inMilliseconds * 
        (1 << (_reconnectAttempts - 1).clamp(0, 6));
    final jitter = (baseDelay * 0.1 * (DateTime.now().millisecond / 1000));
    final totalDelay = (baseDelay + jitter).clamp(
      initialReconnectDelay.inMilliseconds.toDouble(),
      maxReconnectDelay.inMilliseconds.toDouble(),
    );
    
    final delay = Duration(milliseconds: totalDelay.round());
    
    _eventController.add(WebSocketEvent.reconnectScheduled(
      _reconnectAttempts,
      delay,
    ));
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_shouldReconnect && !isConnected) {
        _establishConnection();
      }
    });
  }
  
  /// Wait for connection to complete
  Future<void> _waitForConnection({Duration? timeout}) async {
    timeout ??= const Duration(seconds: 30);
    
    final completer = Completer<void>();
    late StreamSubscription subscription;
    
    subscription = _eventController.stream.listen((event) {
      if (event is WebSocketConnectedEvent) {
        subscription.cancel();
        completer.complete();
      } else if (event is WebSocketConnectionFailedEvent) {
        subscription.cancel();
        completer.completeError(Exception(event.error));
      }
    });
    
    Timer(timeout, () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.completeError(TimeoutException('Connection timeout', timeout));
      }
    });
    
    return completer.future;
  }
  
  /// Start health check timer
  void _startHealthCheck() {
    _healthCheckTimer = Timer.periodic(healthCheckInterval, (_) {
      _performHealthCheck();
    });
  }
  
  /// Start queue processor timer
  void _startQueueProcessor() {
    _queueProcessTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (isConnected && (_messageQueue.isNotEmpty || _priorityQueue.isNotEmpty)) {
        _processMessageQueue();
      }
    });
  }
  
  /// Perform connection health check
  void _performHealthCheck() {
    if (!isConnected) return;
    
    final now = DateTime.now();
    
    // Check if we've received any messages recently
    if (_lastMessageTime != null) {
      final timeSinceLastMessage = now.difference(_lastMessageTime!);
      if (timeSinceLastMessage > const Duration(minutes: 2)) {
        _eventController.add(WebSocketEvent.healthCheckWarning(
          'No messages received for ${timeSinceLastMessage.inMinutes} minutes',
        ));
      }
    }
    
    // Check ping response time
    if (_metrics.lastPongReceived != null) {
      final pingAge = now.difference(_metrics.lastPongReceived!);
      if (pingAge > const Duration(minutes: 1)) {
        _eventController.add(WebSocketEvent.healthCheckWarning(
          'No pong received for ${pingAge.inSeconds} seconds',
        ));
      }
    }
  }
  
  /// Enhanced ping with better tracking
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (_) {
      if (isConnected) {
        _sendPing();
      }
    });
  }
  
  /// Send ping message
  void _sendPing() {
    final pingMessage = WebSocketMessage.ping(timestamp: DateTime.now());
    _sendMessageDirectly(pingMessage).catchError((e) {
      _eventController.add(WebSocketEvent.pingFailed(e.toString()));
    });
  }
  
  /// Send pong message
  void _sendPong() {
    final pongMessage = WebSocketMessage.pong(timestamp: DateTime.now());
    _sendMessageDirectly(pongMessage).catchError((e) {
      // Pong failures are not critical
      print('[WebSocket] Pong send failed: $e');
    });
  }
  
  /// Handle server status messages
  void _handleServerStatus(WebSocketMessage message) {
    _eventController.add(WebSocketEvent.serverStatus(
      status: message.data?['status'] ?? 'unknown',
      details: message.data,
    ));
  }
  
  /// Handle rate limiting
  void _handleRateLimit(WebSocketMessage message) {
    _eventController.add(WebSocketEvent.rateLimited(
      retryAfter: message.data?['retry_after'],
      details: message.data,
    ));
  }
  
  /// Set connection state and emit event
  void _setConnectionState(WebSocketConnectionState state) {
    final previousState = _connectionState;
    _connectionState = state;
    
    if (previousState != state) {
      _eventController.add(WebSocketEvent.stateChanged(previousState, state));
    }
  }
  
  /// Clear message queues
  void _clearQueues() {
    _messageQueue.clear();
    _priorityQueue.clear();
    
    // Cancel pending requests
    for (final pendingRequest in _pendingRequests.values) {
      pendingRequest.completer.completeError(
        Exception('Queue cleared'),
      );
    }
    _pendingRequests.clear();
  }
  
  /// Generate unique request ID
  String _generateRequestId() {
    return 'req_${DateTime.now().millisecondsSinceEpoch}_${_pendingRequests.length}';
  }
  
  /// Get connection statistics
  Map<String, dynamic> getConnectionStats() {
    return {
      'state': _connectionState.toString(),
      'session_id': _sessionId,
      'user_id': _userId,
      'connected_at': _lastConnectedTime?.toIso8601String(),
      'last_message_at': _lastMessageTime?.toIso8601String(),
      'reconnect_attempts': _reconnectAttempts,
      'queue_size': _messageQueue.length,
      'priority_queue_size': _priorityQueue.length,
      'pending_requests': _pendingRequests.length,
      'metrics': _metrics.toJson(),
    };
  }
  
  /// Disconnect with cleanup
  Future<void> disconnect({bool clearQueue = true}) async {
    _shouldReconnect = false;
    
    // Cancel timers
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _queueProcessTimer?.cancel();
    _healthCheckTimer?.cancel();
    
    if (clearQueue) {
      _clearQueues();
    }
    
    if (_channel != null) {
      try {
        await _channel!.sink.close(status.goingAway);
      } catch (e) {
        // Ignore close errors
      }
      _channel = null;
    }
    
    _setConnectionState(WebSocketConnectionState.disconnected);
    _sessionId = null;
    _authToken = null;
    
    _eventController.add(WebSocketEvent.disconnected());
  }
  
  /// Dispose resources
  void dispose() {
    disconnect(clearQueue: true);
    _messageController.close();
    _eventController.close();
  }
}

/// WebSocket connection states
enum WebSocketConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// Message priorities for queuing
enum MessagePriority {
  low,
  normal,
  high,
  critical,
}

/// Queued message wrapper
class QueuedMessage {
  final WebSocketMessage message;
  final MessagePriority priority;
  final DateTime timestamp;
  int retryCount;
  
  QueuedMessage({
    required this.message,
    required this.priority,
    required this.timestamp,
    required this.retryCount,
  });
}

/// Pending request tracking
class PendingRequest {
  final Completer<WebSocketMessage> completer;
  final DateTime timestamp;
  final Duration timeout;
  
  PendingRequest({
    required this.completer,
    required this.timestamp,
    required this.timeout,
  });
}

/// WebSocket performance metrics
class WebSocketMetrics {
  int connectionAttempts = 0;
  int successfulConnections = 0;
  int failedConnections = 0;
  int connectionErrors = 0;
  int messagesReceived = 0;
  int messagesSent = 0;
  int textMessagesReceived = 0;
  int textMessagesSent = 0;
  int binaryMessagesReceived = 0;
  int binaryMessagesSent = 0;
  int messageParsingErrors = 0;
  int messageSendErrors = 0;
  int queuedMessagesProcessed = 0;
  int queuedMessagesFailed = 0;
  int queueOverflows = 0;
  DateTime? lastPongReceived;
  
  Map<String, dynamic> toJson() {
    return {
      'connection_attempts': connectionAttempts,
      'successful_connections': successfulConnections,
      'failed_connections': failedConnections,
      'connection_errors': connectionErrors,
      'messages_received': messagesReceived,
      'messages_sent': messagesSent,
      'text_messages_received': textMessagesReceived,
      'text_messages_sent': textMessagesSent,
      'binary_messages_received': binaryMessagesReceived,
      'binary_messages_sent': binaryMessagesSent,
      'message_parsing_errors': messageParsingErrors,
      'message_send_errors': messageSendErrors,
      'queued_messages_processed': queuedMessagesProcessed,
      'queued_messages_failed': queuedMessagesFailed,
      'queue_overflows': queueOverflows,
      'last_pong_received': lastPongReceived?.toIso8601String(),
    };
  }
}

/// Enhanced WebSocket message with better type safety
class WebSocketMessage {
  final String type;
  final Map<String, dynamic>? data;
  final Uint8List? binaryData;
  final Map<String, dynamic>? metadata;
  final String? requestId;
  final DateTime timestamp;
  
  const WebSocketMessage({
    required this.type,
    this.data,
    this.binaryData,
    this.metadata,
    this.requestId,
    required this.timestamp,
  });
  
  factory WebSocketMessage.fromJson(Map<String, dynamic> json) {
    return WebSocketMessage(
      type: json['type'] as String,
      data: json['data'] as Map<String, dynamic>?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      requestId: json['request_id'] as String?,
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
    );
  }
  
  factory WebSocketMessage.authentication({
    required String token,
    required String sessionId,
    required String userId,
    Map<String, dynamic>? clientInfo,
  }) {
    return WebSocketMessage(
      type: 'auth',
      data: {
        'token': token,
        'session_id': sessionId,
        'user_id': userId,
        'client_info': clientInfo ?? {},
      },
      timestamp: DateTime.now(),
    );
  }
  
  factory WebSocketMessage.binaryData({
    required Uint8List data,
    Map<String, dynamic>? metadata,
  }) {
    return WebSocketMessage(
      type: 'binary',
      binaryData: data,
      metadata: metadata,
      timestamp: DateTime.now(),
    );
  }
  
  factory WebSocketMessage.ping({DateTime? timestamp}) {
    return WebSocketMessage(
      type: 'ping',
      data: {'timestamp': (timestamp ?? DateTime.now()).toIso8601String()},
      timestamp: timestamp ?? DateTime.now(),
    );
  }
  
  factory WebSocketMessage.pong({DateTime? timestamp}) {
    return WebSocketMessage(
      type: 'pong',
      data: {'timestamp': (timestamp ?? DateTime.now()).toIso8601String()},
      timestamp: timestamp ?? DateTime.now(),
    );
  }
  
  factory WebSocketMessage.raw(dynamic rawData) {
    return WebSocketMessage(
      type: 'raw',
      data: {'raw_data': rawData},
      timestamp: DateTime.now(),
    );
  }
  
  WebSocketMessage copyWith({
    String? type,
    Map<String, dynamic>? data,
    Uint8List? binaryData,
    Map<String, dynamic>? metadata,
    String? requestId,
    DateTime? timestamp,
  }) {
    return WebSocketMessage(
      type: type ?? this.type,
      data: data ?? this.data,
      binaryData: binaryData ?? this.binaryData,
      metadata: metadata ?? this.metadata,
      requestId: requestId ?? this.requestId,
      timestamp: timestamp ?? this.timestamp,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (data != null) 'data': data,
      if (metadata != null) 'metadata': metadata,
      if (requestId != null) 'request_id': requestId,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// WebSocket events for external monitoring
abstract class WebSocketEvent {
  final DateTime timestamp = DateTime.now();
  
  factory WebSocketEvent.connecting(String url) = WebSocketConnectingEvent;
  factory WebSocketEvent.connected(String sessionId) = WebSocketConnectedEvent;
  factory WebSocketEvent.authenticated(String userId) = WebSocketAuthenticatedEvent;
  factory WebSocketEvent.connectionFailed(String error) = WebSocketConnectionFailedEvent;
  factory WebSocketEvent.connectionError(String error) = WebSocketConnectionErrorEvent;
  factory WebSocketEvent.authenticationFailed(String error) = WebSocketAuthenticationFailedEvent;
  factory WebSocketEvent.disconnected() = WebSocketDisconnectedEvent;
  factory WebSocketEvent.reconnectScheduled(int attempt, Duration delay) = WebSocketReconnectScheduledEvent;
  factory WebSocketEvent.reconnectGiveUp(int totalAttempts) = WebSocketReconnectGiveUpEvent;
  factory WebSocketEvent.stateChanged(WebSocketConnectionState from, WebSocketConnectionState to) = WebSocketStateChangedEvent;
  factory WebSocketEvent.messageParsingError(String error) = WebSocketMessageParsingErrorEvent;
  factory WebSocketEvent.messageSendFailed(String error) = WebSocketMessageSendFailedEvent;
  factory WebSocketEvent.queuedMessageFailed(String messageType, String error) = WebSocketQueuedMessageFailedEvent;
  factory WebSocketEvent.audioChunkReceived({Uint8List? data, Map<String, dynamic>? metadata}) = WebSocketAudioChunkReceivedEvent;
  factory WebSocketEvent.audioComplete(String sessionId) = WebSocketAudioCompleteEvent;
  factory WebSocketEvent.ttsStatus({required String status, Map<String, dynamic>? details}) = WebSocketTTSStatusEvent;
  factory WebSocketEvent.serverError({required String error, String? code}) = WebSocketServerErrorEvent;
  factory WebSocketEvent.serverStatus({required String status, Map<String, dynamic>? details}) = WebSocketServerStatusEvent;
  factory WebSocketEvent.rateLimited({int? retryAfter, Map<String, dynamic>? details}) = WebSocketRateLimitedEvent;
  factory WebSocketEvent.healthCheckWarning(String warning) = WebSocketHealthCheckWarningEvent;
  factory WebSocketEvent.pingFailed(String error) = WebSocketPingFailedEvent;
}

// Event implementations
class WebSocketConnectingEvent extends WebSocketEvent {
  final String url;
  WebSocketConnectingEvent(this.url);
}

class WebSocketConnectedEvent extends WebSocketEvent {
  final String sessionId;
  WebSocketConnectedEvent(this.sessionId);
}

class WebSocketAuthenticatedEvent extends WebSocketEvent {
  final String userId;
  WebSocketAuthenticatedEvent(this.userId);
}

class WebSocketConnectionFailedEvent extends WebSocketEvent {
  final String error;
  WebSocketConnectionFailedEvent(this.error);
}

class WebSocketConnectionErrorEvent extends WebSocketEvent {
  final String error;
  WebSocketConnectionErrorEvent(this.error);
}

class WebSocketAuthenticationFailedEvent extends WebSocketEvent {
  final String error;
  WebSocketAuthenticationFailedEvent(this.error);
}

class WebSocketDisconnectedEvent extends WebSocketEvent {}

class WebSocketReconnectScheduledEvent extends WebSocketEvent {
  final int attempt;
  final Duration delay;
  WebSocketReconnectScheduledEvent(this.attempt, this.delay);
}

class WebSocketReconnectGiveUpEvent extends WebSocketEvent {
  final int totalAttempts;
  WebSocketReconnectGiveUpEvent(this.totalAttempts);
}

class WebSocketStateChangedEvent extends WebSocketEvent {
  final WebSocketConnectionState from;
  final WebSocketConnectionState to;
  WebSocketStateChangedEvent(this.from, this.to);
}

class WebSocketMessageParsingErrorEvent extends WebSocketEvent {
  final String error;
  WebSocketMessageParsingErrorEvent(this.error);
}

class WebSocketMessageSendFailedEvent extends WebSocketEvent {
  final String error;
  WebSocketMessageSendFailedEvent(this.error);
}

class WebSocketQueuedMessageFailedEvent extends WebSocketEvent {
  final String messageType;
  final String error;
  WebSocketQueuedMessageFailedEvent(this.messageType, this.error);
}

class WebSocketAudioChunkReceivedEvent extends WebSocketEvent {
  final Uint8List? data;
  final Map<String, dynamic>? metadata;
  WebSocketAudioChunkReceivedEvent({this.data, this.metadata});
}

class WebSocketAudioCompleteEvent extends WebSocketEvent {
  final String sessionId;
  WebSocketAudioCompleteEvent(this.sessionId);
}

class WebSocketTTSStatusEvent extends WebSocketEvent {
  final String status;
  final Map<String, dynamic>? details;
  WebSocketTTSStatusEvent({required this.status, this.details});
}

class WebSocketServerErrorEvent extends WebSocketEvent {
  final String error;
  final String? code;
  WebSocketServerErrorEvent({required this.error, this.code});
}

class WebSocketServerStatusEvent extends WebSocketEvent {
  final String status;
  final Map<String, dynamic>? details;
  WebSocketServerStatusEvent({required this.status, this.details});
}

class WebSocketRateLimitedEvent extends WebSocketEvent {
  final int? retryAfter;
  final Map<String, dynamic>? details;
  WebSocketRateLimitedEvent({this.retryAfter, this.details});
}

class WebSocketHealthCheckWarningEvent extends WebSocketEvent {
  final String warning;
  WebSocketHealthCheckWarningEvent(this.warning);
}

class WebSocketPingFailedEvent extends WebSocketEvent {
  final String error;
  WebSocketPingFailedEvent(this.error);
}