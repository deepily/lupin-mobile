import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';

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

  Future<void> connect({String? userId}) async {
    if (_isConnected) {
      return;
    }

    _userId = userId;
    _shouldReconnect = true;
    await _establishConnection();
  }

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

  void _handleError(error) {
    print('[WebSocket] Error: $error');
    _isConnected = false;
    _scheduleReconnect();
  }

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