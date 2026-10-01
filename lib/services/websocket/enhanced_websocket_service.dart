import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';
import '../auth/auth_token_provider.dart';

/// WebSocket client for the queue and audio channels, with queuing and reconnection.
///
/// Reconnects automatically, queues messages while disconnected (a separate queue for high and critical
/// priority), pings and health-checks the connection, and routes text and binary messages.
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
  /// Reconnect attempts before giving up.
  static const int maxReconnectAttempts = 10;
  /// Wait before the first reconnect attempt.
  static const Duration initialReconnectDelay = Duration(seconds: 2);
  /// Longest wait between reconnect attempts.
  static const Duration maxReconnectDelay = Duration(seconds: 60);
  /// Interval between keepalive pings.
  static const Duration pingInterval = Duration(seconds: 30);
  /// Interval between connection health checks.
  static const Duration healthCheckInterval = Duration(seconds: 10);
  /// Default time to wait for a response to a request.
  static const Duration requestTimeout = Duration(seconds: 30);
  /// Largest size of the normal message queue.
  static const int maxQueueSize = 1000;
  /// Largest size of the high and critical priority queue.
  static const int maxPriorityQueueSize = 100;
  
  // Session management
  String? _sessionId;
  String? _userId;
  String? _authToken;
  
  // Performance metrics
  final WebSocketMetrics _metrics = WebSocketMetrics();
  
  // Public getters
  /// True when the queue channel is connected.
  bool get isConnected => _queueConnectionState == WebSocketConnectionState.connected;
  /// True when the audio channel is connected.
  bool get isAudioConnected => _audioConnectionState == WebSocketConnectionState.connected;
  /// True when either channel is connecting.
  bool get isConnecting => _queueConnectionState == WebSocketConnectionState.connecting || _audioConnectionState == WebSocketConnectionState.connecting;
  /// True when both channels are connected.
  bool get isBothConnected => isConnected && isAudioConnected;
  /// State of the queue channel.
  WebSocketConnectionState get queueConnectionState => _queueConnectionState;
  /// State of the audio channel.
  WebSocketConnectionState get audioConnectionState => _audioConnectionState;
  /// Current session id, or null when not set.
  String? get sessionId => _sessionId;
  /// Current user id, or null when not set.
  String? get userId => _userId;
  /// Emits each message received.
  Stream<WebSocketMessage> get messageStream => _messageController.stream;
  /// Emits connection and error events for monitoring.
  Stream<WebSocketEvent> get eventStream => _eventController.stream;
  /// Counters of connections, messages and errors.
  WebSocketMetrics get metrics => _metrics;
  /// Number of messages waiting in the normal queue.
  int get queueSize => _messageQueue.length;
  /// Number of messages waiting in the priority queue.
  int get priorityQueueSize => _priorityQueue.length;
  
  // Base URL for WebSocket connections
  String _baseUrl = 'ws://localhost:7999';
  
  /// Creates the service and starts the health check and queue processor.
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
        final accessToken = readAccessToken();
        if (accessToken == null) {
          throw Exception('No access token — login required before WS auth');
        }
        _authToken = 'Bearer $accessToken';
        
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
  ///   - nothing is raised for queued messages; they are handled asynchronously
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
  ///   - nothing is raised; always returns valid stats
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
  ///   - nothing propagates; cleanup errors are suppressed
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
  
  /// Sets the base URL, session id and user id; null arguments leave the current value.
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
  
  /// Disconnects, clears the queues and closes both streams.
  void dispose() {
    disconnect(clearQueue: true);
    _messageController.close();
    _eventController.close();
  }
}

/// WebSocket connection states
enum WebSocketConnectionState {
  /// Not connected.
  disconnected,
  /// A connection attempt is in progress.
  connecting,
  /// Connected.
  connected,
  /// The last connection attempt failed.
  error,
}

/// Message priorities for queuing
enum MessagePriority {
  /// Sent after everything else.
  low,
  /// Default priority; uses the normal queue.
  normal,
  /// Uses the priority queue.
  high,
  /// Uses the priority queue.
  critical,
}

/// Queued message wrapper
class QueuedMessage {
  /// The message waiting to be sent.
  final WebSocketMessage message;
  /// Priority that decides which queue holds it.
  final MessagePriority priority;
  /// When the message was queued.
  final DateTime timestamp;
  /// Number of failed send attempts so far.
  int retryCount;
  
  /// Creates a queued message; every field is required.
  QueuedMessage({
    required this.message,
    required this.priority,
    required this.timestamp,
    required this.retryCount,
  });
}

/// Pending request tracking
class PendingRequest {
  /// Completes with the response, or with an error on timeout.
  final Completer<WebSocketMessage> completer;
  /// When the request was sent.
  final DateTime timestamp;
  /// How long to wait for the response.
  final Duration timeout;
  
  /// Creates a pending request; every field is required.
  PendingRequest({
    required this.completer,
    required this.timestamp,
    required this.timeout,
  });
}

/// WebSocket performance metrics
class WebSocketMetrics {
  /// Connection attempts made.
  int connectionAttempts = 0;
  /// Connection attempts that succeeded.
  int successfulConnections = 0;
  /// Connection attempts that failed.
  int failedConnections = 0;
  /// Errors raised on an open connection.
  int connectionErrors = 0;
  /// Messages received, text and binary.
  int messagesReceived = 0;
  /// Messages sent, text and binary.
  int messagesSent = 0;
  /// Text messages received.
  int textMessagesReceived = 0;
  /// Text messages sent.
  int textMessagesSent = 0;
  /// Binary messages received.
  int binaryMessagesReceived = 0;
  /// Binary messages sent.
  int binaryMessagesSent = 0;
  /// Received messages that could not be parsed.
  int messageParsingErrors = 0;
  /// Messages that failed to send.
  int messageSendErrors = 0;
  /// Queued messages sent successfully.
  int queuedMessagesProcessed = 0;
  /// Queued messages that failed to send.
  int queuedMessagesFailed = 0;
  /// Messages dropped because a queue was full.
  int queueOverflows = 0;
  /// When the last pong arrived, or null if none has.
  DateTime? lastPongReceived;
  
  /// Serializes the counters with snake_case keys.
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
  /// Message type, for example `auth`, `ping` or `audio_chunk`.
  final String type;
  /// JSON payload, or null.
  final Map<String, dynamic>? data;
  /// Binary payload, or null.
  final Uint8List? binaryData;
  /// Extra JSON describing the message, or null.
  final Map<String, dynamic>? metadata;
  /// Id that pairs a response with its request, or null.
  final String? requestId;
  /// When the message was created.
  final DateTime timestamp;
  
  /// Creates a message; only [type] and [timestamp] are required.
  const WebSocketMessage({
    required this.type,
    this.data,
    this.binaryData,
    this.metadata,
    this.requestId,
    required this.timestamp,
  });
  
  /// Reads a message from JSON; a missing timestamp becomes now.
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
  
  /// Builds an `auth` message carrying the token, session id and user id.
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
  
  /// Builds a `binary` message around [data].
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
  
  /// Builds a `ping` message stamped with [timestamp], or now.
  factory WebSocketMessage.ping({DateTime? timestamp}) {
    return WebSocketMessage(
      type: 'ping',
      data: {'timestamp': (timestamp ?? DateTime.now()).toIso8601String()},
      timestamp: timestamp ?? DateTime.now(),
    );
  }
  
  /// Builds a `pong` message stamped with [timestamp], or now.
  factory WebSocketMessage.pong({DateTime? timestamp}) {
    return WebSocketMessage(
      type: 'pong',
      data: {'timestamp': (timestamp ?? DateTime.now()).toIso8601String()},
      timestamp: timestamp ?? DateTime.now(),
    );
  }
  
  /// Wraps [rawData] in a `raw` message.
  factory WebSocketMessage.raw(dynamic rawData) {
    return WebSocketMessage(
      type: 'raw',
      data: {'raw_data': rawData},
      timestamp: DateTime.now(),
    );
  }
  
  /// Builds a message of any [type].
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
  
  /// Builds an `audio_chunk` message around [audioData].
  factory WebSocketMessage.audioBinary(Uint8List audioData) {
    return WebSocketMessage(
      type: 'audio_chunk',
      binaryData: audioData,
      timestamp: DateTime.now(),
    );
  }
  
  /// Copy with the given fields replaced.
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
  
  /// Serializes the message; null fields are omitted and binary data is not included.
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
  /// When the event was created.
  final DateTime timestamp;
  
  /// Base constructor; stamps the event with the current time.
  WebSocketEvent() : timestamp = DateTime.now();
  
  /// The socket is connecting to [url].
  factory WebSocketEvent.connecting(String url) = WebSocketConnectingEvent;
  /// The socket connected with [sessionId].
  factory WebSocketEvent.connected(String sessionId) = WebSocketConnectedEvent;
  /// The server authenticated [userId].
  factory WebSocketEvent.authenticated(String userId) = WebSocketAuthenticatedEvent;
  /// The connection attempt failed with [error].
  factory WebSocketEvent.connectionFailed(String error) = WebSocketConnectionFailedEvent;
  /// An open connection raised [error].
  factory WebSocketEvent.connectionError(String error) = WebSocketConnectionErrorEvent;
  /// Authentication failed with [error].
  factory WebSocketEvent.authenticationFailed(String error) = WebSocketAuthenticationFailedEvent;
  /// The socket disconnected.
  factory WebSocketEvent.disconnected() = WebSocketDisconnectedEvent;
  /// A reconnect is scheduled as attempt [attempt] after [delay].
  factory WebSocketEvent.reconnectScheduled(int attempt, Duration delay) = WebSocketReconnectScheduledEvent;
  /// Reconnecting stopped after [totalAttempts] attempts.
  factory WebSocketEvent.reconnectGiveUp(int totalAttempts) = WebSocketReconnectGiveUpEvent;
  /// The connection state changed from [from] to [to].
  factory WebSocketEvent.stateChanged(WebSocketConnectionState from, WebSocketConnectionState to) = WebSocketStateChangedEvent;
  /// A received message could not be parsed: [error].
  factory WebSocketEvent.messageParsingError(String error) = WebSocketMessageParsingErrorEvent;
  /// Sending a message failed: [error].
  factory WebSocketEvent.messageSendFailed(String error) = WebSocketMessageSendFailedEvent;
  /// A queued message of [messageType] failed to send: [error].
  factory WebSocketEvent.queuedMessageFailed(String messageType, String error) = WebSocketQueuedMessageFailedEvent;
  /// An audio chunk arrived.
  factory WebSocketEvent.audioChunkReceived({Uint8List? data, Map<String, dynamic>? metadata}) = WebSocketAudioChunkReceivedEvent;
  /// The audio stream for [sessionId] finished.
  factory WebSocketEvent.audioComplete(String sessionId) = WebSocketAudioCompleteEvent;
  /// The server reported a TTS [status].
  factory WebSocketEvent.ttsStatus({required String status, Map<String, dynamic>? details}) = WebSocketTTSStatusEvent;
  /// The server reported an error.
  factory WebSocketEvent.serverError({required String error, String? code}) = WebSocketServerErrorEvent;
  /// The server reported a [status].
  factory WebSocketEvent.serverStatus({required String status, Map<String, dynamic>? details}) = WebSocketServerStatusEvent;
  /// The server rate-limited the client; [retryAfter] is the wait.
  factory WebSocketEvent.rateLimited({int? retryAfter, Map<String, dynamic>? details}) = WebSocketRateLimitedEvent;
  /// The health check raised [warning].
  factory WebSocketEvent.healthCheckWarning(String warning) = WebSocketHealthCheckWarningEvent;
  /// A keepalive ping failed: [error].
  factory WebSocketEvent.pingFailed(String error) = WebSocketPingFailedEvent;
  /// The queue channel connected.
  factory WebSocketEvent.queueConnected() = WebSocketQueueConnectedEvent;
  /// The audio channel connected.
  factory WebSocketEvent.audioConnected() = WebSocketAudioConnectedEvent;
  /// The queue channel failed to connect: [error].
  factory WebSocketEvent.queueConnectionFailed(String error) = WebSocketQueueConnectionFailedEvent;
  /// The audio channel failed to connect: [error].
  factory WebSocketEvent.audioConnectionFailed(String error) = WebSocketAudioConnectionFailedEvent;
  /// The queue channel disconnected.
  factory WebSocketEvent.queueDisconnected() = WebSocketQueueDisconnectedEvent;
  /// The audio channel disconnected.
  factory WebSocketEvent.audioDisconnected() = WebSocketAudioDisconnectedEvent;
  /// Both channels are connected.
  factory WebSocketEvent.fullyConnected() = WebSocketFullyConnectedEvent;
  /// A reconnection is scheduled as attempt [attempt] after [delay].
  factory WebSocketEvent.reconnectionScheduled(int attempt, Duration delay) = WebSocketReconnectionScheduledEvent;
  /// Reconnection attempt [attempt] started.
  factory WebSocketEvent.reconnectionAttempt(int attempt) = WebSocketReconnectionAttemptEvent;
  /// Reconnection stopped after [totalAttempts] attempts.
  factory WebSocketEvent.reconnectionGiveUp(int totalAttempts) = WebSocketReconnectionGiveUpEvent;
  /// No message arrived for [timeSinceLastMessage].
  factory WebSocketEvent.connectionStale(Duration timeSinceLastMessage) = WebSocketConnectionStaleEvent;
  /// A message arrived on [channel] with [content].
  factory WebSocketEvent.messageReceived(String channel, String content) = WebSocketMessageReceivedEvent;
}

// Event implementations
/// The socket is connecting.
class WebSocketConnectingEvent extends WebSocketEvent {
  /// URL being connected to.
  final String url;
  /// Creates the event.
  WebSocketConnectingEvent(this.url) : super();
}

/// The socket connected.
class WebSocketConnectedEvent extends WebSocketEvent {
  /// Session id of the connection.
  final String sessionId;
  /// Creates the event.
  WebSocketConnectedEvent(this.sessionId) : super();
}

/// The server authenticated the user.
class WebSocketAuthenticatedEvent extends WebSocketEvent {
  /// The authenticated user's id.
  final String userId;
  /// Creates the event.
  WebSocketAuthenticatedEvent(this.userId) : super();
}

/// A connection attempt failed.
class WebSocketConnectionFailedEvent extends WebSocketEvent {
  /// Description of the failure.
  final String error;
  /// Creates the event.
  WebSocketConnectionFailedEvent(this.error) : super();
}

/// An open connection raised an error.
class WebSocketConnectionErrorEvent extends WebSocketEvent {
  /// Description of the error.
  final String error;
  /// Creates the event.
  WebSocketConnectionErrorEvent(this.error) : super();
}

/// Authentication failed.
class WebSocketAuthenticationFailedEvent extends WebSocketEvent {
  /// Description of the failure.
  final String error;
  /// Creates the event.
  WebSocketAuthenticationFailedEvent(this.error) : super();
}

/// The socket disconnected.
class WebSocketDisconnectedEvent extends WebSocketEvent {
  /// Creates the event.
  WebSocketDisconnectedEvent() : super();
}

/// A reconnect was scheduled.
class WebSocketReconnectScheduledEvent extends WebSocketEvent {
  /// Attempt number.
  final int attempt;
  /// Wait before the attempt.
  final Duration delay;
  /// Creates the event.
  WebSocketReconnectScheduledEvent(this.attempt, this.delay) : super();
}

/// Reconnecting stopped.
class WebSocketReconnectGiveUpEvent extends WebSocketEvent {
  /// Attempts made.
  final int totalAttempts;
  /// Creates the event.
  WebSocketReconnectGiveUpEvent(this.totalAttempts) : super();
}

/// The connection state changed.
class WebSocketStateChangedEvent extends WebSocketEvent {
  /// State before the change.
  final WebSocketConnectionState from;
  /// State after the change.
  final WebSocketConnectionState to;
  /// Creates the event.
  WebSocketStateChangedEvent(this.from, this.to) : super();
}

/// A received message could not be parsed.
class WebSocketMessageParsingErrorEvent extends WebSocketEvent {
  /// Description of the failure.
  final String error;
  /// Creates the event.
  WebSocketMessageParsingErrorEvent(this.error) : super();
}

/// Sending a message failed.
class WebSocketMessageSendFailedEvent extends WebSocketEvent {
  /// Description of the failure.
  final String error;
  /// Creates the event.
  WebSocketMessageSendFailedEvent(this.error) : super();
}

/// A queued message failed to send.
class WebSocketQueuedMessageFailedEvent extends WebSocketEvent {
  /// Type of the message.
  final String messageType;
  /// Description of the failure.
  final String error;
  /// Creates the event.
  WebSocketQueuedMessageFailedEvent(this.messageType, this.error) : super();
}

/// An audio chunk arrived.
class WebSocketAudioChunkReceivedEvent extends WebSocketEvent {
  /// Audio bytes, or null.
  final Uint8List? data;
  /// Chunk metadata, or null.
  final Map<String, dynamic>? metadata;
  /// Creates the event.
  WebSocketAudioChunkReceivedEvent({this.data, this.metadata}) : super();
}

/// An audio stream finished.
class WebSocketAudioCompleteEvent extends WebSocketEvent {
  /// Session id of the stream.
  final String sessionId;
  /// Creates the event.
  WebSocketAudioCompleteEvent(this.sessionId) : super();
}

/// The server reported a TTS status.
class WebSocketTTSStatusEvent extends WebSocketEvent {
  /// Status text.
  final String status;
  /// Extra detail, or null.
  final Map<String, dynamic>? details;
  /// Creates the event.
  WebSocketTTSStatusEvent({required this.status, this.details}) : super();
}

/// The server reported an error.
class WebSocketServerErrorEvent extends WebSocketEvent {
  /// Error text.
  final String error;
  /// Server error code, or null.
  final String? code;
  /// Creates the event.
  WebSocketServerErrorEvent({required this.error, this.code}) : super();
}

/// The server reported a status.
class WebSocketServerStatusEvent extends WebSocketEvent {
  /// Status text.
  final String status;
  /// Extra detail, or null.
  final Map<String, dynamic>? details;
  /// Creates the event.
  WebSocketServerStatusEvent({required this.status, this.details}) : super();
}

/// The server rate-limited the client.
class WebSocketRateLimitedEvent extends WebSocketEvent {
  /// Seconds to wait, or null.
  final int? retryAfter;
  /// Extra detail, or null.
  final Map<String, dynamic>? details;
  /// Creates the event.
  WebSocketRateLimitedEvent({this.retryAfter, this.details}) : super();
}

/// The health check raised a warning.
class WebSocketHealthCheckWarningEvent extends WebSocketEvent {
  /// Warning text.
  final String warning;
  /// Creates the event.
  WebSocketHealthCheckWarningEvent(this.warning) : super();
}

/// A keepalive ping failed.
class WebSocketPingFailedEvent extends WebSocketEvent {
  /// Description of the failure.
  final String error;
  /// Creates the event.
  WebSocketPingFailedEvent(this.error) : super();
}

/// The queue channel connected.
class WebSocketQueueConnectedEvent extends WebSocketEvent {
  /// Creates the event.
  WebSocketQueueConnectedEvent() : super();
}

/// The audio channel connected.
class WebSocketAudioConnectedEvent extends WebSocketEvent {
  /// Creates the event.
  WebSocketAudioConnectedEvent() : super();
}

/// The queue channel failed to connect.
class WebSocketQueueConnectionFailedEvent extends WebSocketEvent {
  /// Description of the failure.
  final String error;
  /// Creates the event.
  WebSocketQueueConnectionFailedEvent(this.error) : super();
}

/// The audio channel failed to connect.
class WebSocketAudioConnectionFailedEvent extends WebSocketEvent {
  /// Description of the failure.
  final String error;
  /// Creates the event.
  WebSocketAudioConnectionFailedEvent(this.error) : super();
}

/// The queue channel disconnected.
class WebSocketQueueDisconnectedEvent extends WebSocketEvent {
  /// Creates the event.
  WebSocketQueueDisconnectedEvent() : super();
}

/// The audio channel disconnected.
class WebSocketAudioDisconnectedEvent extends WebSocketEvent {
  /// Creates the event.
  WebSocketAudioDisconnectedEvent() : super();
}

/// Both channels are connected.
class WebSocketFullyConnectedEvent extends WebSocketEvent {
  /// Creates the event.
  WebSocketFullyConnectedEvent() : super();
}

/// A reconnection was scheduled.
class WebSocketReconnectionScheduledEvent extends WebSocketEvent {
  /// Attempt number.
  final int attempt;
  /// Wait before the attempt.
  final Duration delay;
  /// Creates the event.
  WebSocketReconnectionScheduledEvent(this.attempt, this.delay) : super();
}

/// A reconnection attempt started.
class WebSocketReconnectionAttemptEvent extends WebSocketEvent {
  /// Attempt number.
  final int attempt;
  /// Creates the event.
  WebSocketReconnectionAttemptEvent(this.attempt) : super();
}

/// Reconnection stopped.
class WebSocketReconnectionGiveUpEvent extends WebSocketEvent {
  /// Attempts made.
  final int totalAttempts;
  /// Creates the event.
  WebSocketReconnectionGiveUpEvent(this.totalAttempts) : super();
}

/// No message arrived for a long time.
class WebSocketConnectionStaleEvent extends WebSocketEvent {
  /// Time since the last message.
  final Duration timeSinceLastMessage;
  /// Creates the event.
  WebSocketConnectionStaleEvent(this.timeSinceLastMessage) : super();
}

/// A message arrived on a channel.
class WebSocketMessageReceivedEvent extends WebSocketEvent {
  /// Channel name.
  final String channel;
  /// Message content.
  final String content;
  /// Creates the event.
  WebSocketMessageReceivedEvent(this.channel, this.content) : super();
}