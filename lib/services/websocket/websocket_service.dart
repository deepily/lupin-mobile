import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';

/// WebSocket service for real-time communication with Lupin backend.
/// 
/// Manages WebSocket connections, reconnection logic, and message streaming.
/// Follows the singleton pattern for consistent connection management.
class WebSocketService {
  final Dio _dio;
  WebSocketChannel? _channel;
  StreamController<dynamic>? _messageController;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  
  bool _isConnected = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  static const Duration reconnectDelay = Duration(seconds: 5);
  static const Duration pingInterval = Duration(seconds: 30);

  String? _sessionId;
  String? _userId;

  // Public getters
  bool get isConnected => _isConnected;
  String? get sessionId => _sessionId;
  Stream<dynamic> get stream => _messageController?.stream ?? const Stream.empty();

  WebSocketService(this._dio) {
    _messageController = StreamController<dynamic>.broadcast();
  }

  /// Establishes WebSocket connection to the Lupin backend.
  /// 
  /// Requires:
  ///   - WebSocket service must not already be connected
  ///   - Backend API must be accessible
  /// 
  /// Ensures:
  ///   - WebSocket connection is established if successful
  ///   - Session ID is obtained and stored
  ///   - Message stream is active and ready
  ///   - Automatic reconnection is enabled
  /// 
  /// Throws:
  ///   - [DioException] if session ID request fails
  ///   - [WebSocketChannelException] if WebSocket connection fails
  Future<void> connect({String? userId}) async {
    if (_isConnected) {
      return;
    }

    _userId = userId;
    _shouldReconnect = true;
    await _establishConnection();
  }

  /// Internal method to establish WebSocket connection.
  /// 
  /// Requires:
  ///   - Valid session ID must be obtainable from backend
  ///   - WebSocket endpoint must be accessible
  /// 
  /// Ensures:
  ///   - Connection is established with proper authentication
  ///   - Ping timer is started for keepalive
  ///   - Message listeners are set up
  ///   - Reconnection counter is reset on success
  Future<void> _establishConnection() async {
    try {
      // Step 1: Get session ID from FastAPI (like the web client does)
      final sessionResponse = await _dio.get('${AppConstants.apiBaseUrl}/api/get-session-id');
      final sessionData = sessionResponse.data;
      _sessionId = sessionData['session_id'];
      
      print('[WebSocket] Got session ID: $_sessionId');
      
      // Step 2: Connect to WebSocket with session ID in URL
      final uri = Uri.parse('${AppConstants.wsBaseUrl}/ws/$_sessionId');
      
      _channel = WebSocketChannel.connect(uri);
      
      // Wait for connection to be established
      await _channel!.ready;
      
      _isConnected = true;
      _reconnectAttempts = 0;
      
      print('[WebSocket] Connected to ${uri.toString()}');
      
      // Start listening to messages
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnection,
      );
      
      // Step 3: Send authentication message (like the web client does)
      if (_userId != null) {
        await _authenticate(_userId!);
      }
      
      // Start ping timer
      _startPingTimer();
      
    } catch (e) {
      print('[WebSocket] Connection failed: $e');
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  /// Authenticates the WebSocket connection.
  /// 
  /// Requires:
  ///   - userId must be non-empty string
  ///   - WebSocket connection must be established
  ///   - sessionId must be available
  /// 
  /// Ensures:
  ///   - Authentication message is sent to backend
  ///   - Mock token is generated for the user
  ///   - Session ID is included in auth message
  Future<void> _authenticate(String userId) async {
    try {
      // Create mock auth token (like the web client does)
      final authToken = 'mock_token_email_$userId';
      
      final authMessage = {
        'type': 'auth',
        'token': authToken,
        'session_id': _sessionId,
      };
      
      await sendMessage(authMessage);
      print('[WebSocket] Authentication sent for user: $userId with session: $_sessionId');
    } catch (e) {
      print('[WebSocket] Authentication failed: $e');
    }
  }

  /// Handles incoming WebSocket messages.
  /// 
  /// Requires:
  ///   - Message must be either List<int> (binary) or JSON string
  ///   - Message controller must be initialized
  /// 
  /// Ensures:
  ///   - Binary messages are wrapped as audio chunks
  ///   - JSON messages are parsed and forwarded
  ///   - Authentication responses update session ID
  ///   - Ping messages receive pong responses
  ///   - All valid messages are added to stream
  void _handleMessage(dynamic message) {
    try {
      // Handle binary audio data
      if (message is List<int>) {
        print('[WebSocket] Received binary audio data: ${message.length} bytes');
        _messageController?.add({
          'type': 'audio_chunk',
          'data': message,
          'provider': 'elevenlabs'
        });
        return;
      }
      
      // Handle text/JSON messages
      final decoded = jsonDecode(message);
      
      // Handle authentication response
      if (decoded['type'] == 'auth_success') {
        _sessionId = decoded['session_id'];
        print('[WebSocket] Authentication successful, session: $_sessionId');
      }
      
      // Handle ping/pong
      if (decoded['type'] == 'ping') {
        sendMessage({'type': 'pong'});
        return;
      }
      
      if (decoded['type'] == 'pong') {
        return;
      }
      
      // Handle TTS status updates
      if (decoded['type'] == 'status' || decoded['type'] == 'audio_complete' || decoded['type'] == 'error') {
        print('[WebSocket] TTS ${decoded['type']}: ${decoded['text']}');
      }
      
      // Forward message to listeners
      _messageController?.add(decoded);
      
    } catch (e) {
      print('[WebSocket] Message parsing error: $e');
      // Forward raw message if JSON parsing fails
      _messageController?.add(message);
    }
  }

  /// Handles WebSocket errors.
  /// 
  /// Requires:
  ///   - Error object from WebSocket stream
  /// 
  /// Ensures:
  ///   - Connection status is set to disconnected
  ///   - Reconnection is scheduled if enabled
  ///   - Error is logged for debugging
  void _handleError(error) {
    print('[WebSocket] Error: $error');
    _isConnected = false;
    _scheduleReconnect();
  }

  /// Handles WebSocket disconnection.
  /// 
  /// Ensures:
  ///   - Connection status is updated
  ///   - Ping timer is cancelled
  ///   - Reconnection is scheduled if shouldReconnect is true
  ///   - Resources are cleaned up properly
  void _handleDisconnection() {
    print('[WebSocket] Connection closed');
    _isConnected = false;
    _pingTimer?.cancel();
    
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _reconnectAttempts >= maxReconnectAttempts) {
      print('[WebSocket] Max reconnect attempts reached or reconnection disabled');
      return;
    }
    
    _reconnectAttempts++;
    final delay = Duration(seconds: reconnectDelay.inSeconds * _reconnectAttempts);
    
    print('[WebSocket] Scheduling reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s');
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_shouldReconnect && !_isConnected) {
        _establishConnection();
      }
    });
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (timer) {
      if (_isConnected) {
        sendMessage({'type': 'ping'});
      }
    });
  }

  Future<void> sendMessage(Map<String, dynamic> message) async {
    if (!_isConnected || _channel == null) {
      throw Exception('WebSocket not connected');
    }

    try {
      final encoded = jsonEncode(message);
      _channel!.sink.add(encoded);
    } catch (e) {
      print('[WebSocket] Failed to send message: $e');
      throw e;
    }
  }

  Future<void> sendBinary(List<int> data) async {
    if (!_isConnected || _channel == null) {
      throw Exception('WebSocket not connected');
    }

    try {
      _channel!.sink.add(data);
    } catch (e) {
      print('[WebSocket] Failed to send binary data: $e');
      throw e;
    }
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    
    if (_channel != null) {
      await _channel!.sink.close(status.goingAway);
      _channel = null;
    }
    
    _isConnected = false;
    _sessionId = null;
    
    print('[WebSocket] Disconnected');
  }

  void dispose() {
    disconnect();
    _messageController?.close();
    _messageController = null;
  }
}