import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Mock WebSocket server that simulates the Lupin backend's dual WebSocket architecture.
/// 
/// Provides two endpoints: /ws/queue/{session_id} and /ws/audio/{session_id}
/// Supports authentication, event generation, and failure simulation for testing.
class MockWebSocketServer {
  late HttpServer _server;
  final Map<String, WebSocketChannel> _queueConnections = {};
  final Map<String, WebSocketChannel> _audioConnections = {};
  final Map<String, MockSessionData> _sessions = {};
  
  // Configuration
  final MockServerConfig _config;
  
  /// Get server configuration
  MockServerConfig get config => _config;
  
  /// Get queue connections (for testing)
  Map<String, WebSocketChannel> get queueConnections => _queueConnections;
  
  /// Get audio connections (for testing)
  Map<String, WebSocketChannel> get audioConnections => _audioConnections;
  
  // Event generation
  Timer? _eventGenerationTimer;
  final Random _random = Random();
  
  // Statistics
  int _totalConnections = 0;
  int _totalMessages = 0;
  DateTime? _startTime;
  
  MockWebSocketServer({MockServerConfig? config}) 
      : _config = config ?? MockServerConfig.defaultConfig();
  
  /// Start the mock server
  Future<void> start() async {
    _startTime = DateTime.now();
    _server = await HttpServer.bind('localhost', _config.port);
    
    print('[MockServer] Started on port ${_config.port}');
    
    _server.listen((HttpRequest request) async {
      if (request.uri.path.startsWith('/ws/')) {
        await _handleWebSocketRequest(request);
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    });
    
    if (_config.enableAutoEventGeneration) {
      _startEventGeneration();
    }
  }
  
  /// Stop the mock server
  Future<void> stop() async {
    _eventGenerationTimer?.cancel();
    
    // Close all connections
    for (final connection in _queueConnections.values) {
      await connection.sink.close();
    }
    for (final connection in _audioConnections.values) {
      await connection.sink.close();
    }
    
    await _server.close();
    print('[MockServer] Stopped');
  }
  
  /// Handle WebSocket connection requests
  Future<void> _handleWebSocketRequest(HttpRequest request) async {
    final path = request.uri.path;
    final sessionId = _extractSessionId(path);
    
    if (sessionId == null) {
      request.response.statusCode = 400;
      await request.response.close();
      return;
    }
    
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      final channel = IOWebSocketChannel(socket);
      
      _totalConnections++;
      
      if (path.startsWith('/ws/queue/')) {
        await _handleQueueConnection(channel, sessionId);
      } else if (path.startsWith('/ws/audio/')) {
        await _handleAudioConnection(channel, sessionId);
      } else {
        await channel.sink.close();
      }
    } catch (e) {
      print('[MockServer] WebSocket upgrade failed: $e');
      request.response.statusCode = 400;
      await request.response.close();
    }
  }
  
  /// Extract session ID from URL path
  String? _extractSessionId(String path) {
    final regex = RegExp(r'/ws/(queue|audio)/(.+)');
    final match = regex.firstMatch(path);
    return match?.group(2);
  }
  
  /// Handle queue WebSocket connection
  Future<void> _handleQueueConnection(WebSocketChannel channel, String sessionId) async {
    print('[MockServer] Queue connection for session: $sessionId');
    
    _queueConnections[sessionId] = channel;
    _sessions.putIfAbsent(sessionId, () => MockSessionData(sessionId: sessionId));
    
    // Set up message handling
    channel.stream.listen(
      (message) => _handleQueueMessage(sessionId, message),
      onDone: () {
        _queueConnections.remove(sessionId);
        print('[MockServer] Queue disconnected: $sessionId');
      },
      onError: (error) {
        print('[MockServer] Queue error for $sessionId: $error');
        _queueConnections.remove(sessionId);
      },
    );
    
    // Send connection confirmation
    await _sendToQueue(sessionId, {
      'type': 'connect',
      'session_id': sessionId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Handle audio WebSocket connection
  Future<void> _handleAudioConnection(WebSocketChannel channel, String sessionId) async {
    print('[MockServer] Audio connection for session: $sessionId');
    
    _audioConnections[sessionId] = channel;
    _sessions.putIfAbsent(sessionId, () => MockSessionData(sessionId: sessionId));
    
    // Set up message handling
    channel.stream.listen(
      (message) => _handleAudioMessage(sessionId, message),
      onDone: () {
        _audioConnections.remove(sessionId);
        print('[MockServer] Audio disconnected: $sessionId');
      },
      onError: (error) {
        print('[MockServer] Audio error for $sessionId: $error');
        _audioConnections.remove(sessionId);
      },
    );
    
    // Send connection confirmation
    await _sendToAudio(sessionId, {
      'type': 'connect',
      'session_id': sessionId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Handle incoming queue messages
  Future<void> _handleQueueMessage(String sessionId, dynamic message) async {
    _totalMessages++;
    
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final type = data['type'] as String?;
      
      print('[MockServer] Queue message from $sessionId: $type');
      
      switch (type) {
        case 'auth_request':
          await _handleAuthentication(sessionId, data, isQueue: true);
          break;
        case 'update_subscriptions':
          await _handleSubscriptionUpdate(sessionId, data);
          break;
        case 'tts_request':
          await _handleTTSRequest(sessionId, data);
          break;
        case 'ping':
          await _sendToQueue(sessionId, {
            'type': 'pong',
            'timestamp': DateTime.now().toIso8601String(),
          });
          break;
        default:
          print('[MockServer] Unknown queue message type: $type');
      }
    } catch (e) {
      print('[MockServer] Error parsing queue message: $e');
    }
  }
  
  /// Handle incoming audio messages
  Future<void> _handleAudioMessage(String sessionId, dynamic message) async {
    _totalMessages++;
    
    if (message is String) {
      try {
        final data = jsonDecode(message) as Map<String, dynamic>;
        final type = data['type'] as String?;
        
        print('[MockServer] Audio message from $sessionId: $type');
        
        switch (type) {
          case 'auth_request':
            await _handleAuthentication(sessionId, data, isQueue: false);
            break;
          case 'ping':
            await _sendToAudio(sessionId, {
              'type': 'pong',
              'timestamp': DateTime.now().toIso8601String(),
            });
            break;
          default:
            print('[MockServer] Unknown audio message type: $type');
        }
      } catch (e) {
        print('[MockServer] Error parsing audio message: $e');
      }
    } else if (message is List<int>) {
      // Handle binary audio data
      print('[MockServer] Received binary audio data: ${message.length} bytes');
      await _handleAudioData(sessionId, Uint8List.fromList(message));
    }
  }
  
  /// Handle authentication requests
  Future<void> _handleAuthentication(String sessionId, Map<String, dynamic> data, {required bool isQueue}) async {
    final token = data['token'] as String?;
    final sessionIdFromAuth = data['session_id'] as String?;
    
    // Validate authentication
    bool isValidAuth = _validateAuthentication(token, sessionIdFromAuth);
    
    if (_config.simulateAuthFailure) {
      isValidAuth = false;
    }
    
    final authResponse = isValidAuth
        ? {
            'type': 'auth_success',
            'session_id': sessionId,
            'user_id': _extractUserIdFromToken(token),
            'timestamp': DateTime.now().toIso8601String(),
          }
        : {
            'type': 'auth_error',
            'session_id': sessionId,
            'message': 'Authentication failed',
            'timestamp': DateTime.now().toIso8601String(),
          };
    
    if (isQueue) {
      await _sendToQueue(sessionId, authResponse);
    } else {
      await _sendToAudio(sessionId, authResponse);
    }
    
    // Update session data
    if (isValidAuth) {
      final session = _sessions[sessionId]!;
      session.isAuthenticated = true;
      session.userId = _extractUserIdFromToken(token);
      session.lastActivity = DateTime.now();
    }
  }
  
  /// Validate authentication token
  bool _validateAuthentication(String? token, String? sessionId) {
    if (token == null || !token.startsWith('Bearer ')) return false;
    
    final tokenPart = token.substring(7); // Remove "Bearer "
    if (!tokenPart.startsWith('mock_token_email_')) return false;
    
    // Validate session ID format (adjective noun)
    if (sessionId != null && !_isValidSessionIdFormat(sessionId)) return false;
    
    return true;
  }
  
  /// Check if session ID follows "adjective noun" format
  bool _isValidSessionIdFormat(String sessionId) {
    final parts = sessionId.split(' ');
    return parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty;
  }
  
  /// Extract user ID from authentication token
  String? _extractUserIdFromToken(String? token) {
    if (token == null || !token.startsWith('Bearer mock_token_email_')) return null;
    return token.substring(23); // Remove "Bearer mock_token_email_"
  }
  
  /// Handle subscription updates
  Future<void> _handleSubscriptionUpdate(String sessionId, Map<String, dynamic> data) async {
    final subscribeToAll = data['subscribe_to_all'] as bool? ?? true;
    final subscribedEvents = (data['subscribed_events'] as List?)?.cast<String>() ?? [];
    
    final session = _sessions[sessionId];
    if (session != null) {
      session.subscribeToAll = subscribeToAll;
      session.subscribedEvents = subscribedEvents.toSet();
    }
    
    await _sendToQueue(sessionId, {
      'type': 'subscription_update',
      'session_id': sessionId,
      'subscribe_to_all': subscribeToAll,
      'subscribed_events': subscribedEvents,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Handle TTS requests
  Future<void> _handleTTSRequest(String sessionId, Map<String, dynamic> data) async {
    final text = data['text'] as String?;
    final provider = data['provider'] as String? ?? 'elevenlabs';
    
    if (text == null || text.isEmpty) {
      await _sendToQueue(sessionId, {
        'type': 'tts_error',
        'session_id': sessionId,
        'error': 'Text is required',
        'timestamp': DateTime.now().toIso8601String(),
      });
      return;
    }
    
    // Simulate TTS processing
    await _simulateTTSGeneration(sessionId, text, provider);
  }
  
  /// Handle binary audio data
  Future<void> _handleAudioData(String sessionId, Uint8List audioData) async {
    // Simulate audio processing
    final session = _sessions[sessionId];
    if (session != null) {
      session.lastActivity = DateTime.now();
    }
    
    // Echo back processed audio (for testing)
    if (_config.enableAudioEcho) {
      await Future.delayed(Duration(milliseconds: 100));
      await _sendBinaryToAudio(sessionId, audioData);
    }
  }
  
  /// Simulate TTS generation and streaming
  Future<void> _simulateTTSGeneration(String sessionId, String text, String provider) async {
    // Send TTS start event
    await _sendToQueue(sessionId, {
      'type': 'tts_start',
      'session_id': sessionId,
      'provider': provider,
      'text': text,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    // Simulate audio generation delay
    await Future.delayed(Duration(milliseconds: _config.ttsGenerationDelay));
    
    // Send audio chunks
    await _sendMockAudioChunks(sessionId, text, provider);
    
    // Send TTS complete event
    await _sendToQueue(sessionId, {
      'type': 'tts_complete',
      'session_id': sessionId,
      'provider': provider,
      'text': text,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Send mock audio chunks to simulate streaming
  Future<void> _sendMockAudioChunks(String sessionId, String text, String provider) async {
    final chunkCount = (text.length / 10).ceil().clamp(1, 10); // 1-10 chunks
    
    for (int i = 0; i < chunkCount; i++) {
      // Create mock audio data
      final audioData = _generateMockAudioChunk(text, i, chunkCount);
      
      // Send audio chunk metadata
      await _sendToAudio(sessionId, {
        'type': 'audio_streaming_chunk',
        'session_id': sessionId,
        'provider': provider,
        'sequence_number': i,
        'total_chunks': chunkCount,
        'is_last_chunk': i == chunkCount - 1,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // Send binary audio data
      await _sendBinaryToAudio(sessionId, audioData);
      
      // Delay between chunks
      await Future.delayed(Duration(milliseconds: _config.audioChunkDelay));
    }
  }
  
  /// Generate mock audio chunk data
  Uint8List _generateMockAudioChunk(String text, int chunkIndex, int totalChunks) {
    // Create deterministic but varied audio data based on text and chunk index
    final hash = text.hashCode + chunkIndex;
    final size = 1024 + (hash % 2048); // 1-3KB chunks
    
    final data = Uint8List(size);
    for (int i = 0; i < size; i++) {
      data[i] = ((hash + i) % 256);
    }
    
    return data;
  }
  
  /// Start automatic event generation for testing
  void _startEventGeneration() {
    _eventGenerationTimer = Timer.periodic(
      Duration(seconds: _config.eventGenerationInterval),
      (_) => _generateRandomEvent(),
    );
  }
  
  /// Generate random events for all connected sessions
  void _generateRandomEvent() {
    if (_sessions.isEmpty) return;
    
    final sessionIds = _sessions.keys.toList();
    if (sessionIds.isEmpty) return;
    
    final sessionId = sessionIds[_random.nextInt(sessionIds.length)];
    final session = _sessions[sessionId]!;
    
    if (!session.isAuthenticated) return;
    
    final eventTypes = [
      'queue_todo_update',
      'queue_running_update',
      'queue_done_update',
      'sys_time_update',
      'notification_queue_update',
    ];
    
    final eventType = eventTypes[_random.nextInt(eventTypes.length)];
    
    switch (eventType) {
      case 'queue_todo_update':
      case 'queue_running_update':
      case 'queue_done_update':
        _generateQueueEvent(sessionId, eventType);
        break;
      case 'sys_time_update':
        _generateSystemEvent(sessionId);
        break;
      case 'notification_queue_update':
        _generateNotificationEvent(sessionId);
        break;
    }
  }
  
  /// Generate mock queue events
  Future<void> _generateQueueEvent(String sessionId, String eventType) async {
    final queueType = eventType.split('_')[1]; // Extract queue type
    final itemCount = _random.nextInt(5);
    
    final mockItems = List.generate(itemCount, (index) => {
      'id': 'job_${_random.nextInt(10000)}',
      'name': 'Mock Job $index',
      'created_at': DateTime.now().subtract(Duration(minutes: _random.nextInt(60))).toIso8601String(),
      'priority': ['low', 'medium', 'high'][_random.nextInt(3)],
    });
    
    await _sendToQueue(sessionId, {
      'type': eventType,
      'session_id': sessionId,
      'items': mockItems,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Generate mock system events
  Future<void> _generateSystemEvent(String sessionId) async {
    await _sendToQueue(sessionId, {
      'type': 'sys_time_update',
      'session_id': sessionId,
      'server_time': DateTime.now().toIso8601String(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Generate mock notification events
  Future<void> _generateNotificationEvent(String sessionId) async {
    final messages = [
      'New task completed',
      'Queue processing finished',
      'System update available',
      'Background job completed',
    ];
    
    await _sendToQueue(sessionId, {
      'type': 'notification_queue_update',
      'session_id': sessionId,
      'message': messages[_random.nextInt(messages.length)],
      'priority': ['low', 'medium', 'high'][_random.nextInt(3)],
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Send message to queue connection (public for testing)
  Future<void> sendToQueue(String sessionId, Map<String, dynamic> message) async {
    await _sendToQueue(sessionId, message);
  }
  
  /// Send message to audio connection (public for testing)
  Future<void> sendToAudio(String sessionId, Map<String, dynamic> message) async {
    await _sendToAudio(sessionId, message);
  }
  
  /// Send binary data to audio connection (public for testing)
  Future<void> sendBinaryToAudio(String sessionId, Uint8List data) async {
    await _sendBinaryToAudio(sessionId, data);
  }
  
  /// Send message to queue connection (internal)
  Future<void> _sendToQueue(String sessionId, Map<String, dynamic> message) async {
    final connection = _queueConnections[sessionId];
    if (connection != null) {
      final session = _sessions[sessionId]!;
      if (_shouldSendEvent(session, message['type'])) {
        connection.sink.add(jsonEncode(message));
      }
    }
  }
  
  /// Send message to audio connection
  Future<void> _sendToAudio(String sessionId, Map<String, dynamic> message) async {
    final connection = _audioConnections[sessionId];
    if (connection != null) {
      connection.sink.add(jsonEncode(message));
    }
  }
  
  /// Send binary data to audio connection
  Future<void> _sendBinaryToAudio(String sessionId, Uint8List data) async {
    final connection = _audioConnections[sessionId];
    if (connection != null) {
      connection.sink.add(data);
    }
  }
  
  /// Check if event should be sent based on subscription settings
  bool _shouldSendEvent(MockSessionData session, String eventType) {
    if (session.subscribeToAll) return true;
    return session.subscribedEvents.contains(eventType);
  }
  
  /// Get server statistics
  Map<String, dynamic> getStats() {
    return {
      'total_connections': _totalConnections,
      'active_queue_connections': _queueConnections.length,
      'active_audio_connections': _audioConnections.length,
      'total_messages': _totalMessages,
      'active_sessions': _sessions.length,
      'uptime_seconds': _startTime != null 
          ? DateTime.now().difference(_startTime!).inSeconds 
          : 0,
      'config': _config.toJson(),
    };
  }
  
  /// Trigger authentication failure for testing
  void triggerAuthFailure() {
    _config.simulateAuthFailure = true;
  }
  
  /// Reset authentication failure simulation
  void resetAuthFailure() {
    _config.simulateAuthFailure = false;
  }
  
  /// Disconnect a specific session
  Future<void> disconnectSession(String sessionId) async {
    final queueConnection = _queueConnections.remove(sessionId);
    final audioConnection = _audioConnections.remove(sessionId);
    
    await queueConnection?.sink.close();
    await audioConnection?.sink.close();
    
    _sessions.remove(sessionId);
  }
  
  /// Disconnect all sessions
  Future<void> disconnectAllSessions() async {
    final sessionIds = List.from(_sessions.keys);
    for (final sessionId in sessionIds) {
      await disconnectSession(sessionId);
    }
  }
  
  /// Simulate connection failures for testing reconnection logic
  void simulateConnectionFailures({
    required int failureCount,
    void Function()? onConnectionAttempt,
  }) {
    _config.simulateConnectionFailures = true;
    _config.connectionFailureCount = failureCount;
    _config.onConnectionAttempt = onConnectionAttempt;
  }
  
  /// Simulate persistent connection failure
  void simulatePersistentFailure() {
    _config.simulateConnectionFailures = true;
    _config.connectionFailureCount = 999; // Large number to simulate persistent failure
  }
  
  /// Pause message generation for health check testing
  void pauseMessageGeneration() {
    _config.enableAutoEventGeneration = false;
    // _stopEventGeneration(); // TODO: Implement if needed
  }
  
  /// Resume message generation
  void resumeMessageGeneration() {
    _config.enableAutoEventGeneration = true;
    // _startEventGeneration(); // TODO: Implement if needed
  }
}

/// Configuration for the mock WebSocket server
class MockServerConfig {
  final int port;
  bool enableAutoEventGeneration;
  final int eventGenerationInterval; // seconds
  final int ttsGenerationDelay; // milliseconds
  final int audioChunkDelay; // milliseconds
  final bool enableAudioEcho;
  bool simulateAuthFailure;
  
  // Connection failure simulation
  bool simulateConnectionFailures = false;
  int connectionFailureCount = 0;
  void Function()? onConnectionAttempt;
  
  MockServerConfig({
    this.port = 8080,
    this.enableAutoEventGeneration = false,
    this.eventGenerationInterval = 5,
    this.ttsGenerationDelay = 500,
    this.audioChunkDelay = 100,
    this.enableAudioEcho = false,
    this.simulateAuthFailure = false,
  });
  
  factory MockServerConfig.defaultConfig() {
    return MockServerConfig();
  }
  
  factory MockServerConfig.testing() {
    return MockServerConfig(
      port: 8081,
      enableAutoEventGeneration: true,
      eventGenerationInterval: 2,
      ttsGenerationDelay: 100,
      audioChunkDelay: 50,
      enableAudioEcho: true,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'port': port,
      'enable_auto_event_generation': enableAutoEventGeneration,
      'event_generation_interval': eventGenerationInterval,
      'tts_generation_delay': ttsGenerationDelay,
      'audio_chunk_delay': audioChunkDelay,
      'enable_audio_echo': enableAudioEcho,
      'simulate_auth_failure': simulateAuthFailure,
    };
  }
}

/// Session data for tracking connected clients
class MockSessionData {
  final String sessionId;
  String? userId;
  bool isAuthenticated = false;
  bool subscribeToAll = true;
  Set<String> subscribedEvents = {};
  DateTime lastActivity = DateTime.now();
  
  MockSessionData({required this.sessionId});
  
  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'user_id': userId,
      'is_authenticated': isAuthenticated,
      'subscribe_to_all': subscribeToAll,
      'subscribed_events': subscribedEvents.toList(),
      'last_activity': lastActivity.toIso8601String(),
    };
  }
}