import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';

/// Enhanced WebSocket service with improved message handling, queuing, and resilience.
/// 
/// Provides robust WebSocket connectivity with automatic reconnection, message queuing,
/// priority handling, health monitoring, and comprehensive error recovery.
/// Supports both text and binary message types with intelligent routing.
class EnhancedWebSocketService {
  final Dio _dio;
  WebSocketChannel? _queueChannel;
  WebSocketChannel? _audioChannel;
  
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
  
  // Stream subscriptions
  StreamSubscription? _queueSubscription;
  StreamSubscription? _audioSubscription;
  
  // Connection state
  WebSocketConnectionState _queueConnectionState = WebSocketConnectionState.disconnected;
  WebSocketConnectionState _audioConnectionState = WebSocketConnectionState.disconnected;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  DateTime? _lastConnectedTime;
  DateTime? _lastMessageTime;
  
  // Reconnection configuration
  int _maxReconnectAttempts = 10;
  Duration _baseReconnectDelay = const Duration(seconds: 1);
  bool _isReconnecting = false;
  
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
  bool get isConnected => _queueConnectionState == WebSocketConnectionState.connected;
  bool get isAudioConnected => _audioConnectionState == WebSocketConnectionState.connected;
  bool get isConnecting => _queueConnectionState == WebSocketConnectionState.connecting || _audioConnectionState == WebSocketConnectionState.connecting;
  bool get isBothConnected => isConnected && isAudioConnected;
  WebSocketConnectionState get queueConnectionState => _queueConnectionState;
  WebSocketConnectionState get audioConnectionState => _audioConnectionState;
  String? get sessionId => _sessionId;
  String? get userId => _userId;
  Stream<WebSocketMessage> get messageStream => _messageController.stream;
  Stream<WebSocketEvent> get eventStream => _eventController.stream;
  WebSocketMetrics get metrics => _metrics;
  int get queueSize => _messageQueue.length;
  int get priorityQueueSize => _priorityQueue.length;
  
  // Base URL for WebSocket connections
  String _baseUrl = 'ws://localhost:7999';
  
  EnhancedWebSocketService(this._dio) {
    _startHealthCheck();
    _startQueueProcessor();
  }
  
  /// Set the base URL for WebSocket connections
  void setBaseUrl(String baseUrl) {
    _baseUrl = baseUrl;
  }
  
  /// Establishes WebSocket connection with enhanced error handling and resilience.
  /// 
  /// Requires:
  ///   - Network connectivity must be available
  ///   - Backend WebSocket endpoint must be accessible
  ///   - userId (if provided) must be valid for authentication
  /// 
  /// Ensures:
  ///   - Connection is established with session ID retrieval
  ///   - Authentication is performed if userId is provided
  ///   - Message queues are optionally cleared based on clearQueue parameter
  ///   - Reconnection logic is initialized for future failures
  /// 
  /// Raises:
  ///   - TimeoutException if connection establishment times out
  ///   - WebSocketException if WebSocket connection fails
  ///   - AuthenticationException if user authentication fails
  Future<void> connect({
    String? userId,
    Map<String, String>? headers,
    bool clearQueue = false,
    bool connectQueue = true,
    bool connectAudio = true,
  }) async {
    _userId = userId;
    _shouldReconnect = true;
    
    if (clearQueue) {
      _clearQueues();
    }
    
    // Connect queue WebSocket if requested and not already connected
    if (connectQueue && _queueConnectionState != WebSocketConnectionState.connected) {
      await _establishQueueConnection(headers: headers);
    }
    
    // Connect audio WebSocket if requested and not already connected  
    if (connectAudio && _audioConnectionState != WebSocketConnectionState.connected) {
      await _establishAudioConnection(headers: headers);
    }
  }
  
  /// Establishes queue WebSocket connection for main UI events
  Future<void> _establishQueueConnection({Map<String, String>? headers}) async {
    _setQueueConnectionState(WebSocketConnectionState.connecting);
    
    try {
      _metrics.connectionAttempts++;
      
      // Step 1: Get session ID with retry logic (only once for both connections)
      if (_sessionId == null) {
        _sessionId = await _getSessionIdWithRetry();
      }
      
      // Step 2: Connect to queue WebSocket
      final uri = Uri.parse('${AppConstants.wsBaseUrl}${AppConstants.wsQueueEndpoint}/$_sessionId');
      
      _eventController.add(WebSocketEvent.connecting('Queue: ${uri.toString()}'));
      
      _queueChannel = WebSocketChannel.connect(
        uri,
        protocols: ['lupin-mobile-v1'],
      );
      
      // Wait for connection with timeout
      await _queueChannel!.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Queue connection timeout'),
      );
      
      _setQueueConnectionState(WebSocketConnectionState.connected);
      _lastConnectedTime = DateTime.now();
      _reconnectAttempts = 0;
      _metrics.successfulConnections++;
      
      _eventController.add(WebSocketEvent.connected('Queue: $_sessionId'));
      
      // Start listening to queue messages
      _queueChannel!.stream.listen(
        (message) => _handleIncomingMessage(message, isAudioChannel: false),
        onError: (error) => _handleConnectionError(error, isAudioChannel: false),
        onDone: () => _handleConnectionClosed(isAudioChannel: false),
      );
      
      // Step 3: Authenticate queue connection
      if (_userId != null) {
        await _authenticateWithRetry(_userId!, isAudioChannel: false);
      }
      
      // Step 4: Start periodic tasks (only for queue connection)
      _startPingTimer();
      _processMessageQueue();
      
    } catch (e) {
      _metrics.failedConnections++;
      _setQueueConnectionState(WebSocketConnectionState.disconnected);
      _eventController.add(WebSocketEvent.connectionFailed('Queue: $e'));
      
      await _scheduleReconnect();
    }
  }
  
  /// Establishes audio WebSocket connection for TTS streaming
  Future<void> _establishAudioConnection({Map<String, String>? headers}) async {
    _setAudioConnectionState(WebSocketConnectionState.connecting);
    
    try {
      _metrics.connectionAttempts++;
      
      // Step 1: Ensure session ID is available
      if (_sessionId == null) {
        _sessionId = await _getSessionIdWithRetry();
      }
      
      // Step 2: Connect to audio WebSocket
      final uri = Uri.parse('${AppConstants.wsBaseUrl}${AppConstants.wsAudioEndpoint}/$_sessionId');
      
      _eventController.add(WebSocketEvent.connecting('Audio: ${uri.toString()}'));
      
      _audioChannel = WebSocketChannel.connect(
        uri,
        protocols: ['lupin-mobile-v1'],
      );
      
      // Wait for connection with timeout
      await _audioChannel!.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Audio connection timeout'),
      );
      
      _setAudioConnectionState(WebSocketConnectionState.connected);
      _metrics.successfulConnections++;
      
      _eventController.add(WebSocketEvent.connected('Audio: $_sessionId'));
      
      // Start listening to audio messages
      _audioChannel!.stream.listen(
        (message) => _handleIncomingMessage(message, isAudioChannel: true),
        onError: (error) => _handleConnectionError(error, isAudioChannel: true),
        onDone: () => _handleConnectionClosed(isAudioChannel: true),
      );
      
      // Step 3: Authentication is optional for audio channel
      // Audio channel can be pre-registered via TTS API request
      
    } catch (e) {
      _metrics.failedConnections++;
      _setAudioConnectionState(WebSocketConnectionState.disconnected);
      _eventController.add(WebSocketEvent.connectionFailed('Audio: $e'));
      
      // Audio connection failure is not critical, don't trigger reconnect
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
  Future<void> _authenticateWithRetry(String userId, {int maxRetries = 3, bool isAudioChannel = false}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _authToken = 'Bearer mock_token_email_$userId';
        
        final authMessage = WebSocketMessage.authentication(
          token: _authToken!,
          sessionId: _sessionId!,
          userId: userId,
          clientInfo: {
            'platform': 'flutter',
            'version': '1.0.0',
            'capabilities': ['audio', 'binary', 'compression'],
            'channel': isAudioChannel ? 'audio' : 'queue',
          },
        );
        
        final response = await sendMessageWithResponse(authMessage, timeout: const Duration(seconds: 10));
        
        if (response.type == AppConstants.eventAuthSuccess) {
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
  void _handleIncomingMessage(dynamic rawMessage, {bool isAudioChannel = false}) {
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
  
  /// Sends message with enhanced queuing and retry logic.
  /// 
  /// Requires:
  ///   - message must be a valid WebSocketMessage instance
  ///   - priority must be a valid MessagePriority value
  /// 
  /// Ensures:
  ///   - Message is sent immediately if connected and skipQueue is true
  ///   - Message is queued with appropriate priority if not connected
  ///   - High/critical priority messages use separate priority queue
  ///   - Queue overflow protection prevents memory issues
  /// 
  /// Raises:
  ///   - WebSocketException if direct send fails and skipQueue is true
  ///   - No exceptions for queued messages (handled asynchronously)
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
  
  /// Sends message and waits for a correlated response.
  /// 
  /// Requires:
  ///   - message must be a valid WebSocketMessage instance
  ///   - timeout (if provided) must be a positive duration
  ///   - WebSocket connection must be active
  /// 
  /// Ensures:
  ///   - Message is sent with a unique request ID
  ///   - Response is awaited and matched by request ID
  ///   - Timeout protection prevents indefinite waiting
  ///   - Pending request is cleaned up on completion or timeout
  /// 
  /// Raises:
  ///   - TimeoutException if response is not received within timeout
  ///   - WebSocketException if message sending fails
  ///   - ConnectionException if WebSocket is not connected
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
    // Determine which channel to use based on message type
    final useAudioChannel = _isAudioMessage(message);
    final channel = useAudioChannel ? _audioChannel : _queueChannel;
    final isChannelConnected = useAudioChannel ? isAudioConnected : isConnected;
    
    if (!isChannelConnected || channel == null) {
      throw Exception('WebSocket ${useAudioChannel ? "audio" : "queue"} channel not connected');
    }
    
    try {
      _metrics.messagesSent++;
      
      if (message.binaryData != null) {
        channel.sink.add(message.binaryData!);
        _metrics.binaryMessagesSent++;
      } else {
        final encoded = jsonEncode(message.toJson());
        channel.sink.add(encoded);
        _metrics.textMessagesSent++;
      }
      
    } catch (e) {
      _metrics.messageSendErrors++;
      _eventController.add(WebSocketEvent.messageSendFailed(e.toString()));
      throw Exception('Failed to send message: $e');
    }
  }
  
  /// Determines if a message should be sent through the audio channel
  bool _isAudioMessage(WebSocketMessage message) {
    const audioMessageTypes = {
      AppConstants.eventAudioStreamingChunk,
      AppConstants.eventAudioStreamingStatus,
      AppConstants.eventAudioStreamingComplete,
      'tts_request',
      'voice_input',
      'binary', // Binary data typically goes to audio channel
    };
    
    return audioMessageTypes.contains(message.type) || message.binaryData != null;
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
  void _handleConnectionError(dynamic error, {bool isAudioChannel = false}) {
    _metrics.connectionErrors++;
    
    if (isAudioChannel) {
      _setAudioConnectionState(WebSocketConnectionState.error);
      _eventController.add(WebSocketEvent.connectionError('Audio: $error'));
    } else {
      _setQueueConnectionState(WebSocketConnectionState.error);
      _eventController.add(WebSocketEvent.connectionError('Queue: $error'));
      
      // Only cancel ping timer for queue connection
      _pingTimer?.cancel();
      
      if (_shouldReconnect) {
        _scheduleReconnect();
      }
    }
  }
  
  /// Enhanced connection closed handling
  void _handleConnectionClosed({bool isAudioChannel = false}) {
    if (isAudioChannel) {
      _setAudioConnectionState(WebSocketConnectionState.disconnected);
      _eventController.add(WebSocketEvent.disconnected());
    } else {
      _setQueueConnectionState(WebSocketConnectionState.disconnected);
      _eventController.add(WebSocketEvent.disconnected());
      
      // Only clean up ping timer for queue connection
      _pingTimer?.cancel();
      
      // Complete pending requests with error (only for queue connection)
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
  
  /// Establish WebSocket connections with robust error handling
  Future<void> _establishConnection() async {
    if (_isReconnecting) {
      print('[WebSocket] Already reconnecting, skipping duplicate attempt');
      return;
    }
    
    _isReconnecting = true;
    
    try {
      final queueUrl = '${_baseUrl}/ws/queue/${_sessionId ?? 'default'}';
      final audioUrl = '${_baseUrl}/ws/audio/${_sessionId ?? 'default'}';
      
      print('[WebSocket] Establishing connections to $queueUrl and $audioUrl (attempt ${_reconnectAttempts + 1})');
      
      // Update connection states
      _queueConnectionState = WebSocketConnectionState.connecting;
      _audioConnectionState = WebSocketConnectionState.connecting;
      
      // Emit connecting events
      _eventController.add(WebSocketEvent.connecting(queueUrl));
      
      // Establish queue connection
      await _connectToQueue(queueUrl);
      
      // Establish audio connection
      await _connectToAudio(audioUrl);
      
      // If we get here, both connections succeeded
      _onConnectionSuccess();
      
    } catch (e) {
      print('[WebSocket] Connection establishment failed: $e');
      _onConnectionFailure(e.toString());
    } finally {
      _isReconnecting = false;
    }
  }
  
  /// Connect to queue WebSocket
  Future<void> _connectToQueue(String url) async {
    try {
      print('[WebSocket] Connecting to queue: $url');
      
      // Cancel existing subscription first
      await _queueSubscription?.cancel();
      _queueSubscription = null;
      
      // Close existing connection if any
      await _queueChannel?.sink.close();
      _queueChannel = null;
      
      // Create new connection with timeout
      _queueChannel = WebSocketChannel.connect(
        Uri.parse(url),
        // Add headers if needed for authentication
      );
      
      // Wait for initial connection success using a separate completer
      final connectionCompleter = Completer<void>();
      bool isFirstMessage = true;
      
      // Set up message listener that handles both connection confirmation and ongoing messages
      _queueSubscription = _queueChannel!.stream.listen(
        (message) {
          if (isFirstMessage) {
            isFirstMessage = false;
            print('[WebSocket] Received initial message on queue channel, connection confirmed');
            if (!connectionCompleter.isCompleted) {
              connectionCompleter.complete();
            }
          }
          _handleQueueMessage(message);
        },
        onError: (error) {
          if (!connectionCompleter.isCompleted) {
            connectionCompleter.completeError(error);
          }
          _handleQueueError(error);
        },
        onDone: () {
          if (!connectionCompleter.isCompleted) {
            connectionCompleter.completeError(Exception('Connection closed during setup'));
          }
          _handleQueueDisconnection();
        },
      );
      
      // Send authentication message
      _sendAuthenticationMessage(_queueChannel!, 'queue');
      
      // Wait for connection confirmation with timeout
      await connectionCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Queue connection timeout', const Duration(seconds: 10)),
      );
      
      _queueConnectionState = WebSocketConnectionState.connected;
      _eventController.add(WebSocketEvent.queueConnected());
      
      print('[WebSocket] Queue connection established successfully');
      
    } catch (e) {
      _queueConnectionState = WebSocketConnectionState.error;
      _eventController.add(WebSocketEvent.queueConnectionFailed(e.toString()));
      throw Exception('Queue connection failed: $e');
    }
  }
  
  /// Connect to audio WebSocket
  Future<void> _connectToAudio(String url) async {
    try {
      print('[WebSocket] Connecting to audio: $url');
      
      // Cancel existing subscription first
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      
      // Close existing connection if any
      await _audioChannel?.sink.close();
      _audioChannel = null;
      
      // Create new connection
      _audioChannel = WebSocketChannel.connect(Uri.parse(url));
      
      // Wait for initial connection success using a separate completer
      final connectionCompleter = Completer<void>();
      bool isFirstMessage = true;
      
      // Set up message listener that handles both connection confirmation and ongoing messages
      _audioSubscription = _audioChannel!.stream.listen(
        (message) {
          if (isFirstMessage) {
            isFirstMessage = false;
            print('[WebSocket] Received initial message on audio channel, connection confirmed');
            if (!connectionCompleter.isCompleted) {
              connectionCompleter.complete();
            }
          }
          _handleAudioMessage(message);
        },
        onError: (error) {
          if (!connectionCompleter.isCompleted) {
            connectionCompleter.completeError(error);
          }
          _handleAudioError(error);
        },
        onDone: () {
          if (!connectionCompleter.isCompleted) {
            connectionCompleter.completeError(Exception('Connection closed during setup'));
          }
          _handleAudioDisconnection();
        },
      );
      
      // Send authentication message
      _sendAuthenticationMessage(_audioChannel!, 'audio');
      
      // Wait for connection confirmation with timeout
      await connectionCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Audio connection timeout', const Duration(seconds: 10)),
      );
      
      _audioConnectionState = WebSocketConnectionState.connected;
      _eventController.add(WebSocketEvent.audioConnected());
      
      print('[WebSocket] Audio connection established successfully');
      
    } catch (e) {
      _audioConnectionState = WebSocketConnectionState.error;
      _eventController.add(WebSocketEvent.audioConnectionFailed(e.toString()));
      throw Exception('Audio connection failed: $e');
    }
  }
  
  /// Removed _waitForConnectionAck method as connection handling is now integrated directly into _connectToQueue and _connectToAudio
  
  /// Send authentication message
  void _sendAuthenticationMessage(WebSocketChannel channel, String type) {
    final authMessage = {
      'type': 'auth_request',
      'data': {
        'user_id': _userId ?? 'anonymous',
        'session_id': _sessionId ?? 'default',
        'channel_type': type,
        'timestamp': DateTime.now().toIso8601String(),
      }
    };
    
    try {
      channel.sink.add(jsonEncode(authMessage));
      print('[WebSocket] Sent authentication for $type channel');
    } catch (e) {
      print('[WebSocket] Failed to send authentication for $type: $e');
    }
  }
  
  /// Handle successful connection
  void _onConnectionSuccess() {
    print('[WebSocket] All connections established successfully');
    _reconnectAttempts = 0;
    _lastConnectedTime = DateTime.now();
    _startHealthMonitoring();
    _eventController.add(WebSocketEvent.fullyConnected());
  }
  
  /// Handle connection failure and initiate reconnection
  void _onConnectionFailure(String error) {
    print('[WebSocket] Connection failed: $error');
    _eventController.add(WebSocketEvent.connectionFailed(error));
    
    if (_shouldReconnect && _reconnectAttempts < _maxReconnectAttempts) {
      _scheduleReconnection();
    } else {
      print('[WebSocket] Max reconnection attempts reached or reconnection disabled');
      _eventController.add(WebSocketEvent.reconnectionGiveUp(_reconnectAttempts));
    }
  }
  
  /// Schedule reconnection with exponential backoff
  void _scheduleReconnection() {
    _reconnectAttempts++;
    
    // Calculate exponential backoff delay
    final delay = Duration(
      milliseconds: (_baseReconnectDelay.inMilliseconds * 
                    (1 << (_reconnectAttempts - 1))).clamp(
        _baseReconnectDelay.inMilliseconds,
        30000, // Max 30 seconds
      ),
    );
    
    print('[WebSocket] Scheduling reconnection attempt $_reconnectAttempts in ${delay.inSeconds}s');
    _eventController.add(WebSocketEvent.reconnectionScheduled(_reconnectAttempts, delay));
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      print('[WebSocket] Attempting reconnection $_reconnectAttempts');
      _eventController.add(WebSocketEvent.reconnectionAttempt(_reconnectAttempts));
      _establishConnection();
    });
  }
  
  /// Start health monitoring
  void _startHealthMonitoring() {
    _startPingTimer();
    _startConnectionMonitoring();
  }
  
  /// Start connection monitoring
  void _startConnectionMonitoring() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _performHealthCheck();
    });
  }
  
  /// Perform connection health check
  void _performHealthCheck() {
    final now = DateTime.now();
    
    // Check if we've received messages recently
    if (_lastMessageTime != null) {
      final timeSinceLastMessage = now.difference(_lastMessageTime!);
      if (timeSinceLastMessage > const Duration(minutes: 5)) {
        print('[WebSocket] No messages received for ${timeSinceLastMessage.inMinutes} minutes, connection may be stale');
        _eventController.add(WebSocketEvent.connectionStale(timeSinceLastMessage));
        
        // Trigger reconnection if connection seems dead
        if (timeSinceLastMessage > const Duration(minutes: 10)) {
          print('[WebSocket] Connection appears dead, triggering reconnection');
          disconnect();
          connect();
        }
      }
    }
    
    // Check connection states
    if (_queueConnectionState != WebSocketConnectionState.connected ||
        _audioConnectionState != WebSocketConnectionState.connected) {
      print('[WebSocket] Health check detected disconnected state, attempting reconnection');
      connect();
    }
  }
  
  /// Handle queue message
  void _handleQueueMessage(dynamic message) {
    _lastMessageTime = DateTime.now();
    _eventController.add(WebSocketEvent.messageReceived('queue', message.toString()));
    
    try {
      if (message is String) {
        final data = jsonDecode(message);
        final webSocketMessage = WebSocketMessage.fromJson(data);
        _messageController.add(webSocketMessage);
      }
    } catch (e) {
      print('[WebSocket] Failed to parse queue message: $e');
      _eventController.add(WebSocketEvent.messageParsingError(e.toString()));
    }
  }
  
  /// Handle audio message
  void _handleAudioMessage(dynamic message) {
    _lastMessageTime = DateTime.now();
    _eventController.add(WebSocketEvent.messageReceived('audio', 'binary'));
    
    try {
      if (message is List<int>) {
        final audioData = Uint8List.fromList(message);
        final audioMessage = WebSocketMessage.audioBinary(audioData);
        _messageController.add(audioMessage);
      } else if (message is String) {
        final data = jsonDecode(message);
        final webSocketMessage = WebSocketMessage.fromJson(data);
        _messageController.add(webSocketMessage);
      }
    } catch (e) {
      print('[WebSocket] Failed to process audio message: $e');
      _eventController.add(WebSocketEvent.messageParsingError(e.toString()));
    }
  }
  
  /// Handle queue connection error
  void _handleQueueError(dynamic error) {
    print('[WebSocket] Queue connection error: $error');
    _queueConnectionState = WebSocketConnectionState.error;
    _eventController.add(WebSocketEvent.queueConnectionFailed(error.toString()));
    
    if (_shouldReconnect) {
      _scheduleReconnection();
    }
  }
  
  /// Handle audio connection error
  void _handleAudioError(dynamic error) {
    print('[WebSocket] Audio connection error: $error');
    _audioConnectionState = WebSocketConnectionState.error;
    _eventController.add(WebSocketEvent.audioConnectionFailed(error.toString()));
    
    if (_shouldReconnect) {
      _scheduleReconnection();
    }
  }
  
  /// Handle queue disconnection
  void _handleQueueDisconnection() {
    print('[WebSocket] Queue connection closed');
    _queueConnectionState = WebSocketConnectionState.disconnected;
    _eventController.add(WebSocketEvent.queueDisconnected());
    
    if (_shouldReconnect) {
      _scheduleReconnection();
    }
  }
  
  /// Handle audio disconnection
  void _handleAudioDisconnection() {
    print('[WebSocket] Audio connection closed');
    _audioConnectionState = WebSocketConnectionState.disconnected;
    _eventController.add(WebSocketEvent.audioDisconnected());
    
    if (_shouldReconnect) {
      _scheduleReconnection();
    }
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
  
  /// Set queue connection state and emit event
  void _setQueueConnectionState(WebSocketConnectionState state) {
    final previousState = _queueConnectionState;
    _queueConnectionState = state;
    
    if (previousState != state) {
      _eventController.add(WebSocketEvent.stateChanged(previousState, state));
    }
  }
  
  /// Set audio connection state and emit event
  void _setAudioConnectionState(WebSocketConnectionState state) {
    final previousState = _audioConnectionState;
    _audioConnectionState = state;
    
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
  
  /// Retrieves comprehensive connection and performance statistics.
  /// 
  /// Requires:
  ///   - Service must be instantiated (no connection required)
  /// 
  /// Ensures:
  ///   - Returns current connection state and metadata
  ///   - Includes queue sizes and pending request counts
  ///   - Provides detailed performance metrics
  ///   - Statistics reflect real-time service state
  /// 
  /// Raises:
  ///   - No exceptions are raised (always returns valid stats)
  Map<String, dynamic> getConnectionStats() {
    return {
      'state': _queueConnectionState.toString(),
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
  
  /// Disconnects WebSocket connection with comprehensive cleanup.
  /// 
  /// Requires:
  ///   - Service must be instantiated (connection state irrelevant)
  /// 
  /// Ensures:
  ///   - WebSocket connection is properly closed
  ///   - All timers and periodic tasks are cancelled
  ///   - Message queues are optionally cleared
  ///   - Pending requests are completed with errors
  ///   - Reconnection attempts are disabled
  /// 
  /// Raises:
  ///   - No exceptions propagate (cleanup errors are suppressed)
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
    
    // Close queue channel
    if (_queueChannel != null) {
      try {
        await _queueChannel!.sink.close(status.goingAway);
      } catch (e) {
        // Ignore close errors
      }
      _queueChannel = null;
    }
    
    // Close audio channel
    if (_audioChannel != null) {
      try {
        await _audioChannel!.sink.close(status.goingAway);
      } catch (e) {
        // Ignore close errors
      }
      _audioChannel = null;
    }
    
    _setQueueConnectionState(WebSocketConnectionState.disconnected);
    _setAudioConnectionState(WebSocketConnectionState.disconnected);
    _sessionId = null;
    _authToken = null;
    
    _eventController.add(WebSocketEvent.disconnected());
  }
  
  /// Dispose resources
  /// Configure service parameters
  void configure({
    String? baseUrl,
    String? sessionId,
    String? userId,
  }) {
    if (baseUrl != null) {
      _baseUrl = baseUrl;
    }
    if (sessionId != null) {
      _sessionId = sessionId;
    }
    if (userId != null) {
      _userId = userId;
    }
  }
  
  /// Configure reconnection parameters
  void configureReconnection({
    int? maxAttempts,
    Duration? baseDelay,
  }) {
    if (maxAttempts != null) {
      _maxReconnectAttempts = maxAttempts;
    }
    if (baseDelay != null) {
      _baseReconnectDelay = baseDelay;
    }
  }
  
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
  
  factory WebSocketMessage.custom({
    required String type,
    Map<String, dynamic>? data,
    Uint8List? binaryData,
    Map<String, dynamic>? metadata,
    String? requestId,
    DateTime? timestamp,
  }) {
    return WebSocketMessage(
      type: type,
      data: data,
      binaryData: binaryData,
      metadata: metadata,
      requestId: requestId,
      timestamp: timestamp ?? DateTime.now(),
    );
  }
  
  factory WebSocketMessage.audioBinary(Uint8List audioData) {
    return WebSocketMessage(
      type: 'audio_chunk',
      binaryData: audioData,
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
  final DateTime timestamp;
  
  WebSocketEvent() : timestamp = DateTime.now();
  
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
  factory WebSocketEvent.queueConnected() = WebSocketQueueConnectedEvent;
  factory WebSocketEvent.audioConnected() = WebSocketAudioConnectedEvent;
  factory WebSocketEvent.queueConnectionFailed(String error) = WebSocketQueueConnectionFailedEvent;
  factory WebSocketEvent.audioConnectionFailed(String error) = WebSocketAudioConnectionFailedEvent;
  factory WebSocketEvent.queueDisconnected() = WebSocketQueueDisconnectedEvent;
  factory WebSocketEvent.audioDisconnected() = WebSocketAudioDisconnectedEvent;
  factory WebSocketEvent.fullyConnected() = WebSocketFullyConnectedEvent;
  factory WebSocketEvent.reconnectionScheduled(int attempt, Duration delay) = WebSocketReconnectionScheduledEvent;
  factory WebSocketEvent.reconnectionAttempt(int attempt) = WebSocketReconnectionAttemptEvent;
  factory WebSocketEvent.reconnectionGiveUp(int totalAttempts) = WebSocketReconnectionGiveUpEvent;
  factory WebSocketEvent.connectionStale(Duration timeSinceLastMessage) = WebSocketConnectionStaleEvent;
  factory WebSocketEvent.messageReceived(String channel, String content) = WebSocketMessageReceivedEvent;
}

// Event implementations
class WebSocketConnectingEvent extends WebSocketEvent {
  final String url;
  WebSocketConnectingEvent(this.url) : super();
}

class WebSocketConnectedEvent extends WebSocketEvent {
  final String sessionId;
  WebSocketConnectedEvent(this.sessionId) : super();
}

class WebSocketAuthenticatedEvent extends WebSocketEvent {
  final String userId;
  WebSocketAuthenticatedEvent(this.userId) : super();
}

class WebSocketConnectionFailedEvent extends WebSocketEvent {
  final String error;
  WebSocketConnectionFailedEvent(this.error) : super();
}

class WebSocketConnectionErrorEvent extends WebSocketEvent {
  final String error;
  WebSocketConnectionErrorEvent(this.error) : super();
}

class WebSocketAuthenticationFailedEvent extends WebSocketEvent {
  final String error;
  WebSocketAuthenticationFailedEvent(this.error) : super();
}

class WebSocketDisconnectedEvent extends WebSocketEvent {
  WebSocketDisconnectedEvent() : super();
}

class WebSocketReconnectScheduledEvent extends WebSocketEvent {
  final int attempt;
  final Duration delay;
  WebSocketReconnectScheduledEvent(this.attempt, this.delay) : super();
}

class WebSocketReconnectGiveUpEvent extends WebSocketEvent {
  final int totalAttempts;
  WebSocketReconnectGiveUpEvent(this.totalAttempts) : super();
}

class WebSocketStateChangedEvent extends WebSocketEvent {
  final WebSocketConnectionState from;
  final WebSocketConnectionState to;
  WebSocketStateChangedEvent(this.from, this.to) : super();
}

class WebSocketMessageParsingErrorEvent extends WebSocketEvent {
  final String error;
  WebSocketMessageParsingErrorEvent(this.error) : super();
}

class WebSocketMessageSendFailedEvent extends WebSocketEvent {
  final String error;
  WebSocketMessageSendFailedEvent(this.error) : super();
}

class WebSocketQueuedMessageFailedEvent extends WebSocketEvent {
  final String messageType;
  final String error;
  WebSocketQueuedMessageFailedEvent(this.messageType, this.error) : super();
}

class WebSocketAudioChunkReceivedEvent extends WebSocketEvent {
  final Uint8List? data;
  final Map<String, dynamic>? metadata;
  WebSocketAudioChunkReceivedEvent({this.data, this.metadata}) : super();
}

class WebSocketAudioCompleteEvent extends WebSocketEvent {
  final String sessionId;
  WebSocketAudioCompleteEvent(this.sessionId) : super();
}

class WebSocketTTSStatusEvent extends WebSocketEvent {
  final String status;
  final Map<String, dynamic>? details;
  WebSocketTTSStatusEvent({required this.status, this.details}) : super();
}

class WebSocketServerErrorEvent extends WebSocketEvent {
  final String error;
  final String? code;
  WebSocketServerErrorEvent({required this.error, this.code}) : super();
}

class WebSocketServerStatusEvent extends WebSocketEvent {
  final String status;
  final Map<String, dynamic>? details;
  WebSocketServerStatusEvent({required this.status, this.details}) : super();
}

class WebSocketRateLimitedEvent extends WebSocketEvent {
  final int? retryAfter;
  final Map<String, dynamic>? details;
  WebSocketRateLimitedEvent({this.retryAfter, this.details}) : super();
}

class WebSocketHealthCheckWarningEvent extends WebSocketEvent {
  final String warning;
  WebSocketHealthCheckWarningEvent(this.warning) : super();
}

class WebSocketPingFailedEvent extends WebSocketEvent {
  final String error;
  WebSocketPingFailedEvent(this.error) : super();
}

class WebSocketQueueConnectedEvent extends WebSocketEvent {
  WebSocketQueueConnectedEvent() : super();
}

class WebSocketAudioConnectedEvent extends WebSocketEvent {
  WebSocketAudioConnectedEvent() : super();
}

class WebSocketQueueConnectionFailedEvent extends WebSocketEvent {
  final String error;
  WebSocketQueueConnectionFailedEvent(this.error) : super();
}

class WebSocketAudioConnectionFailedEvent extends WebSocketEvent {
  final String error;
  WebSocketAudioConnectionFailedEvent(this.error) : super();
}

class WebSocketQueueDisconnectedEvent extends WebSocketEvent {
  WebSocketQueueDisconnectedEvent() : super();
}

class WebSocketAudioDisconnectedEvent extends WebSocketEvent {
  WebSocketAudioDisconnectedEvent() : super();
}

class WebSocketFullyConnectedEvent extends WebSocketEvent {
  WebSocketFullyConnectedEvent() : super();
}

class WebSocketReconnectionScheduledEvent extends WebSocketEvent {
  final int attempt;
  final Duration delay;
  WebSocketReconnectionScheduledEvent(this.attempt, this.delay) : super();
}

class WebSocketReconnectionAttemptEvent extends WebSocketEvent {
  final int attempt;
  WebSocketReconnectionAttemptEvent(this.attempt) : super();
}

class WebSocketReconnectionGiveUpEvent extends WebSocketEvent {
  final int totalAttempts;
  WebSocketReconnectionGiveUpEvent(this.totalAttempts) : super();
}

class WebSocketConnectionStaleEvent extends WebSocketEvent {
  final Duration timeSinceLastMessage;
  WebSocketConnectionStaleEvent(this.timeSinceLastMessage) : super();
}

class WebSocketMessageReceivedEvent extends WebSocketEvent {
  final String channel;
  final String content;
  WebSocketMessageReceivedEvent(this.channel, this.content) : super();
}