import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';
import '../../core/logging/logger.dart';
import '../auth/auth_token_provider.dart';
import 'ws_reconnect_coordinator.dart';
import 'ws_resume_store.dart';

/// Singleton WebSocket service for real-time communication with the Lupin backend.
///
/// Manages the connection, reconnection logic and message streaming.
class WebSocketService implements WsReconnectTarget {
  final Dio _dio;
  WebSocketChannel? _channel;
  /// The listener on [_channel].
  ///
  /// It is cancelled whenever that channel is retired, so a replaced channel cannot speak.
  StreamSubscription<dynamic>? _channelSub;
  StreamController<dynamic>? _messageController;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  
  bool _isConnected = false;
  bool _shouldReconnect = true;

  /// True from the start of a connect attempt until it succeeds or fails.
  ///
  /// A second attempt in that window would open a second channel for one device slot, and the server answers
  /// that with close code 4004.
  bool _connecting = false;

  /// Set when [connect] arrives during an attempt.
  ///
  /// The attempt then runs once more if it ends without a socket.
  bool _connectAgain = false;

  /// The observable behind [connectionStream].
  ///
  /// `isConnected` alone is a sync getter over a private bool, so any predicate built on it goes stale silently.
  /// The socket drops, a screen's record button stays enabled, and nothing repaints to say otherwise.
  final StreamController<bool> _connectionCtrl = StreamController<bool>.broadcast();
  int _reconnectAttempts = 0;
  /// Reconnect attempts before giving up.
  static const int maxReconnectAttempts = 5;
  /// Default wait before a reconnect attempt.
  static const Duration reconnectDelay = Duration(seconds: 5);
  /// Longest a session-id request or a handshake may take before the attempt fails.
  static const Duration connectTimeout = Duration(seconds: 15);
  /// Interval between keepalive pings.
  static const Duration pingInterval = Duration(seconds: 30);

  /// Close code the server sends when a newer socket claimed this device's slot.
  ///
  /// It is permanent. Reconnecting would bump the newer socket and start a loop between two sockets of one install.
  static const int closeCodeSuperseded = 4004;

  final WsResumeStore?                _injectedStore;
  final WebSocketChannel Function( Uri ) _channelFactory;
  final Duration                      _reconnectBaseDelay;
  final Duration                      _connectTimeout;
  WsResumeStore?                      _lazyStore;

  /// The highest frame `seq` processed on this install.
  ///
  /// Loaded from the store on every auth, then set from `resume_complete.seq` and from each live frame.
  int _lastSeq = 0;

  /// Lazily built so a service that never authenticates never touches prefs.
  WsResumeStore get _store => _injectedStore ?? ( _lazyStore ??= WsResumeStore() );

  String? _sessionId;
  String? _userId;

  // Public getters
  /// True while the socket is connected.
  @override
  bool get isConnected => _isConnected;

  /// True while a connect attempt is running.
  @override
  bool get isConnecting => _connecting;

  /// Failures counted toward [maxReconnectAttempts] since the last success or manual trigger.
  ///
  /// One failure counts once, however many of its callbacks fire.
  @visibleForTesting
  int get reconnectAttempts => _reconnectAttempts;

  /// True while a retry timer is waiting to fire.
  @override
  bool get isRetryPending => _reconnectTimer?.isActive ?? false;

  /// True when this service is allowed to open a socket on its own.
  ///
  /// False before the first [connect], after [disconnect] (sign-out) and after a 4004 close.
  @override
  bool get wantsConnection => _shouldReconnect && _userId != null;

  /// Connection state as a stream that emits on change and replays on subscribe.
  ///
  /// It has three properties, of which `pausedStream` (the nearest in-tree pattern) has only the second:
  ///   1. It emits at all five sites that mutate `_isConnected`. A stream wired at two of five is worse than none, because it looks observable.
  ///   2. It is distinct-until-changed, applied at the mutation site (`tts_orchestrator.dart`). Three of the five sites set false, so otherwise one disconnect emits false repeatedly.
  ///   3. It replays the current value on subscribe. A listener attached while already disconnected must learn at once, not at the next transition.
  Stream<bool> get connectionStream {
    late StreamController<bool> out;
    StreamSubscription<bool>?   sub;
    out = StreamController<bool>(
      onListen: () {
        // Replay-on-subscribe, then follow. Both happen in one synchronous
        // block, so no transition can slip between them.
        out.add( _isConnected );
        sub = _connectionCtrl.stream.listen( out.add, onError: out.addError );
      },
      onCancel: () async {
        await sub?.cancel();
        sub = null;
      },
    );
    return out.stream;
  }

  /// The only writer of `_isConnected`.
  ///
  /// Distinct-until-changed lives here, at the mutation site, so every call site gets it and a later one cannot forget it.
  void _setConnected( bool value ) {
    if ( _isConnected == value ) return;
    _isConnected = value;
    if ( !_connectionCtrl.isClosed ) _connectionCtrl.add( value );
  }
  /// Session id obtained from the backend, or null before connecting.
  String? get sessionId => _sessionId;
  /// Decoded incoming messages; empty before the service is built.
  Stream<dynamic> get stream => _messageController?.stream ?? const Stream.empty();

  /// Creates the service on [dio], the shared client; the named parameters exist for tests.
  WebSocketService(
    this._dio, {
    WsResumeStore?                store,
    WebSocketChannel Function( Uri )? channelFactory,
    Duration?                     reconnectBaseDelay,
    Duration?                     connectTimeout,
  })  : _injectedStore      = store,
        _connectTimeout     = connectTimeout ?? WebSocketService.connectTimeout,
        _channelFactory     = channelFactory ?? WebSocketChannel.connect,
        _reconnectBaseDelay = reconnectBaseDelay ?? reconnectDelay {
    _messageController = StreamController<dynamic>.broadcast();
  }

  /// Log context naming the current session, so a line can be matched to server logs.
  LogContext get _logContext => LogContext( sessionId: _sessionId );

  /// Validates session ID format as "adjective noun" with space.
  /// 
  /// Requires:
  ///   - sessionId must be non-null string
  /// 
  /// Ensures:
  ///   - Returns true if format matches "word word" pattern
  ///   - Both words must be lowercase letters only
  ///   - Exactly one space separator required
  /// 
  /// Examples of valid session IDs:
  ///   - "wise penguin"
  ///   - "clever dolphin" 
  ///   - "happy turtle"
  bool _isValidSessionFormat(String sessionId) {
    final parts = sessionId.split(' ');
    return parts.length == 2 && 
           parts[0].isNotEmpty && 
           parts[1].isNotEmpty &&
           RegExp(r'^[a-z]+$').hasMatch(parts[0]) &&
           RegExp(r'^[a-z]+$').hasMatch(parts[1]);
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

    // Recorded even when an attempt is already running: a sign-out then sign-in during an attempt must not
    // leave the service refusing to connect. The running attempt is re-run if it was cancelled.
    _userId = userId;
    _shouldReconnect = true;
    if ( _connecting ) {
      _connectAgain = true;
      return;
    }
    await _establishConnection();
  }

  /// Tries once to bring a dropped socket back, as a trigger would.
  ///
  /// The triggers are resume, network restored, push wake-up and the retry loop.
  ///
  /// Requires:
  ///   - none; it checks its own preconditions and returns false when they fail
  ///
  /// Ensures:
  ///   - returns false and does nothing when connected, when a connect is running, or when [wantsConnection] is false
  ///   - otherwise cancels a pending retry timer, resets the retry counter and makes one attempt
  ///   - at most one channel is ever opened, however many triggers arrive together
  ///   - returns true when this call started an attempt, whether or not it succeeded
  @override
  Future<bool> reconnectNow() async {
    if ( _isConnected || _connecting || !wantsConnection ) return false;
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    await _establishConnection();
    return true;
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
    if ( _connecting ) return;
    _connecting = true;
    try {
      do {
        _connectAgain = false;
        await _attemptOnce();
      } while ( _connectAgain && !_isConnected && _shouldReconnect );
    } finally {
      _connecting = false;
    }
  }

  /// One connect attempt: session id, channel, handshake. Its failure schedules a retry.
  ///
  /// Each network wait is bounded by [connectTimeout], so a stalled handshake cannot hold the single-flight flag.
  /// The fetched session id is held in a local.
  /// It becomes [sessionId] only once the socket is up, so a failed or superseded attempt never leaves an id with no connection.
  Future<void> _attemptOnce() async {
    WebSocketChannel? channel;
    try {
      // Step 1: Get session ID from FastAPI (like the web client does)
      final sessionResponse = await _dio.get('${AppConstants.apiBaseUrl}/api/get-session-id').timeout( _connectTimeout );
      final sessionData = sessionResponse.data;
      final fetchedId   = sessionData['session_id'];
      
      // Validate session ID format
      if ( fetchedId is! String || !_isValidSessionFormat( fetchedId ) ) {
        throw Exception('Invalid session ID format received: $fetchedId. Expected "adjective noun" format.');
      }
      
      debugPrint('[WebSocket] Got valid session ID: $fetchedId');
      
      // Step 2: Connect to WebSocket with session ID in URL  
      final uri = Uri.parse('${AppConstants.wsBaseUrl}${AppConstants.wsQueueEndpoint}/$fetchedId');
      
      // Whatever channel is still held is dead or half dead; it must not stay open behind the new one.
      _retireChannel();
      final opened = _channelFactory( uri );
      channel = opened;
      _channel = opened;
      
      // Wait for connection to be established
      await opened.ready.timeout( _connectTimeout );

      // A disconnect() (sign-out) or a 4004 that landed while this attempt was in flight must not be undone by it.
      // A disconnect() also drops this channel from _channel, so a later connect() runs a fresh attempt.
      if ( !_shouldReconnect || !identical( _channel, opened ) ) {
        await opened.sink.close( status.goingAway );
        if ( identical( _channel, opened ) ) _channel = null;
        return;
      }
      
      _sessionId = fetchedId;
      _setConnected( true );
      _reconnectAttempts = 0;
      
      debugPrint('[WebSocket] Connected to ${uri.toString()}');
      
      // Start listening to messages. Each callback is bound to ITS channel, so a late done or error from a
      // channel that has since been replaced cannot be read as the live channel's.
      _channelSub = opened.stream.listen(
        ( Object? message ) {
          if ( identical( _channel, opened ) ) _handleMessage( message );
        },
        onError: ( Object error, [ StackTrace? st ] ) => _handleError( opened, error, st ),
        onDone: () => _handleDisconnection( opened ),
      );
      
      // Step 3: Send authentication message (like the web client does)
      if (_userId != null) {
        await _authenticate(_userId!);
      }
      
      // Start ping timer
      _startPingTimer();
      
    } catch (e, st) {
      Logger.error( 'Connection failed', tag: 'WebSocket', error: e, stackTrace: st, context: _logContext );
      _setConnected( false );
      // A timed-out handshake leaves a half-open channel; close it so it cannot connect later.
      final stale = channel;
      if ( stale != null ) {
        if ( identical( _channel, stale ) ) _channel = null;
        unawaited( stale.sink.close( status.goingAway ).catchError( ( Object _ ) {} ) );
      }
      _scheduleReconnect();
    }
  }

  /// Builds the `auth_request` payload; static so a test can pin its shape.
  ///
  /// No live socket is needed.
  ///
  /// `client_type: "mobile"` lets the parent tell this mobile socket from web sessions. The FCM wake trigger fires
  /// on "no live mobile WS", so a desktop browser must not suppress the phone's wake. An absent marker makes the
  /// parent treat the client as web, which is backward-compatible.
  static Map<String, dynamic> buildAuthRequestMessage({
    required String bearerToken,
    required String? sessionId,
    String? deviceId,
    int?    lastSeq,
  }) {
    return {
      'type': 'auth_request',
      'token': bearerToken,
      'session_id': sessionId,
      'subscribed_events': [], // Empty array = receive all events
      'client_type': 'mobile', // F-S6-1 marker (S6 §3.0 / S5 §3.1)
      // Row dc446601: the per-install slot key, and the resume cursor. Absent
      // last_seq (or 0) tells the server this is a fresh client.
      if ( deviceId != null ) 'device_id': deviceId,
      if ( lastSeq != null && lastSeq > 0 ) 'last_seq': lastSeq,
    };
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
  ///   - Bearer token is generated for the user
  ///   - Session ID is included in auth message
  ///   - Subscribed events array is included (empty = receive all events)
  ///   - client_type "mobile" marker is included
  Future<void> _authenticate(String userId) async {
    try {
      // Bearer auth token sourced from AuthBloc (set on login / refresh).
      final accessToken = readAccessToken();
      if (accessToken == null) {
        Logger.warning( 'No access token available — auth skipped', tag: 'WebSocket', context: _logContext );
        return;
      }
      final authToken = 'Bearer $accessToken';

      // 🔴 Read through the async store on EVERY auth: the FCM isolate may have
      // advanced last_seq since this isolate last looked.
      _lastSeq = await _store.lastSeq();
      final authMessage = buildAuthRequestMessage(
        bearerToken : authToken,
        sessionId   : _sessionId,
        deviceId    : await _store.deviceId(),
        lastSeq     : _lastSeq,
      );

      await sendMessage(authMessage);
      debugPrint('[WebSocket] Authentication sent for user: $userId with session: $_sessionId');
    } catch (e, st) {
      Logger.error( 'Authentication failed', tag: 'WebSocket', error: e, stackTrace: st, context: _logContext );
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
      // Handle binary audio data. Backend sends raw ElevenLabs PCM chunks
      // (per src/cosa/rest/routers/speech.py websocket.send_bytes loop);
      // wrap with the canonical backend event name so downstream handlers
      // don't have to guess.
      if (message is List<int>) {
        _messageController?.add({
          'type': AppConstants.eventAudioStreamingChunk,
          'data': message,
          'provider': 'elevenlabs'
        });
        return;
      }
      
      // Handle text/JSON messages
      final decoded = jsonDecode(message);
      
      // Handle authentication response
      if (decoded['type'] == AppConstants.eventAuthSuccess) {
        _sessionId = decoded['session_id'];
        debugPrint('[WebSocket] Authentication successful, session: $_sessionId');
      }
      
      if (decoded['type'] == AppConstants.eventAuthError) {
        Logger.warning( 'Authentication rejected by server: ${decoded['message'] ?? 'Unknown error'}', tag: 'WebSocket', context: _logContext );
      }
      
      // Row 281a10d6: backlog is over. seq here is the SERVER's current seq —
      // adopt it, never echo ours. gap is acted on by the app-level dispatcher,
      // so the frame is forwarded below.
      if ( decoded['type'] == AppConstants.eventResumeComplete ) {
        final serverSeq = decoded['seq'];
        if ( serverSeq is int && serverSeq >= 0 ) {
          _lastSeq = serverSeq;
          _persistAndAck( serverSeq );
        }
        _messageController?.add( decoded );
        return;
      }

      // Handle ping/pong
      if (decoded['type'] == AppConstants.eventSysPing) {
        sendMessage({'type': AppConstants.eventSysPong});
        return;
      }
      
      if (decoded['type'] == AppConstants.eventSysPong) {
        return;
      }
      
      // Handle TTS status updates
      if (decoded['type'] == 'status' || decoded['type'] == 'audio_complete' || decoded['type'] == 'error') {
        debugPrint('[WebSocket] TTS ${decoded['type']}: ${decoded['text']}');
      }
      
      // Forward message to listeners
      _messageController?.add(decoded);

      // Row 281a10d6: a slot holder's frames carry seq. Advance the cursor and
      // ack only AFTER the frame is handed on, so "processed" is true.
      final seq = decoded['seq'];
      if ( seq is int && seq > 0 ) {
        _lastSeq = seq;
        _persistAndAck( seq );
      }
      
    } catch (e, st) {
      Logger.warning( 'Message parsing error', tag: 'WebSocket', error: e, stackTrace: st, context: _logContext );
      // Forward raw message if JSON parsing fails
      _messageController?.add(message);
    }
  }

  /// Cancels the listener on, and closes, the channel this service holds, then forgets it.
  ///
  /// Requires:
  ///   - none; a null channel is a no-op
  ///
  /// Ensures:
  ///   - [_channel] is null and its listener is cancelled, so no later callback from it is delivered
  ///   - a close with `goingAway` is requested, and its failure is ignored
  void _retireChannel() {
    final old = _channel;
    unawaited( _channelSub?.cancel() );
    _channelSub = null;
    _channel    = null;
    if ( old != null ) unawaited( old.sink.close( status.goingAway ).catchError( ( Object _ ) {} ) );
  }

  /// Handles a WebSocket error on [source].
  ///
  /// Requires:
  ///   - [source] is the channel whose stream raised [error]
  ///
  /// Ensures:
  ///   - an error from a channel that is no longer current is ignored
  ///   - otherwise the channel is retired, the state is disconnected, and exactly one reconnect is scheduled
  ///     (the done that usually follows an error finds the channel retired and does nothing)
  void _handleError( WebSocketChannel source, Object error, [StackTrace? st] ) {
    if ( !identical( _channel, source ) ) {
      debugPrint('[WebSocket] Ignoring an error from a replaced channel');
      return;
    }
    Logger.error( 'Stream error', tag: 'WebSocket', error: error, stackTrace: st, context: _logContext );
    _retireChannel();
    _setConnected( false );
    _pingTimer?.cancel();
    _scheduleReconnect();
  }

  /// Handles the end of [source]'s stream.
  ///
  /// Requires:
  ///   - [source] is the channel whose stream ended; its own close code is the one read
  ///
  /// Ensures:
  ///   - a done from a channel that is no longer current is ignored, so it cannot clear the live connection or
  ///     schedule a reconnect (this service closed that channel itself, so a 4004 on it is its own doing)
  ///   - otherwise the channel is retired, the state is disconnected and the ping timer is cancelled
  ///   - 4004 on the current channel stops reconnection; any other code schedules one reconnect if allowed
  void _handleDisconnection( WebSocketChannel source ) {
    final code    = source.closeCode;
    final current = identical( _channel, source );
    debugPrint('[WebSocket] Connection closed (code: $code${current ? "" : ", replaced channel"})');

    if ( !current ) return;

    _retireChannel();
    _setConnected( false );
    _pingTimer?.cancel();

    // Row dc446601: a newer socket owns this device's slot. Do NOT reconnect
    // this one. Every other code (incl. 4001, whose refresh/sign-out is
    // handled by the auth layer, and 4003) reconnects as before.
    if ( code == closeCodeSuperseded ) {
      debugPrint('[WebSocket] Superseded by a newer socket (4004) — not reconnecting');
      _shouldReconnect = false;
      _reconnectTimer?.cancel();
      return;
    }
    
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _reconnectAttempts >= maxReconnectAttempts) {
      Logger.warning( 'Max reconnect attempts reached or reconnection disabled', tag: 'WebSocket', context: _logContext );
      return;
    }
    
    _reconnectAttempts++;
    final delay = _reconnectBaseDelay * _reconnectAttempts;
    
    debugPrint('[WebSocket] Scheduling reconnect attempt $_reconnectAttempts in ${delay.inMilliseconds}ms');
    
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
        sendMessage({'type': AppConstants.eventSysPing});
      }
    });
  }

  /// Sends [message] as JSON.
  ///
  /// Throws when the socket is not connected or the send fails.
  Future<void> sendMessage(Map<String, dynamic> message) async {
    if (!_isConnected || _channel == null) {
      throw Exception('WebSocket not connected');
    }

    try {
      final encoded = jsonEncode(message);
      _channel!.sink.add(encoded);
    } catch (e, st) {
      Logger.error( 'Failed to send message', tag: 'WebSocket', error: e, stackTrace: st, context: _logContext );
      rethrow;
    }
  }

  /// Persists the cursor and tells the server it may drop frames through [seq].
  ///
  /// A failed write or a dead socket is logged, never thrown into the message handler.
  void _persistAndAck( int seq ) {
    _store.setLastSeq( seq ).catchError( ( Object e, StackTrace st ) => Logger.warning( 'last_seq persist failed', tag: 'WebSocket', error: e, stackTrace: st, context: _logContext ) );
    sendMessage( { 'type': 'ack', 'seq': seq } ).catchError( ( Object e, StackTrace st ) => Logger.warning( 'ack failed', tag: 'WebSocket', error: e, stackTrace: st, context: _logContext ) );
  }

  /// Sends [data] as a binary frame.
  ///
  /// Throws when the socket is not connected or the send fails.
  Future<void> sendBinary(List<int> data) async {
    if (!_isConnected || _channel == null) {
      throw Exception('WebSocket not connected');
    }

    try {
      _channel!.sink.add(data);
    } catch (e, st) {
      Logger.error( 'Failed to send binary data', tag: 'WebSocket', error: e, stackTrace: st, context: _logContext );
      rethrow;
    }
  }

  /// Closes the socket, stops reconnection and clears the session id.
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    
    unawaited( _channelSub?.cancel() );
    _channelSub = null;
    if (_channel != null) {
      await _channel!.sink.close(status.goingAway);
      _channel = null;
    }
    
    _setConnected( false );
    _sessionId = null;
    
    debugPrint('[WebSocket] Disconnected');
  }

  /// Disconnects and closes the message and connection streams.
  void dispose() {
    disconnect();
    _messageController?.close();
    _messageController = null;
    _connectionCtrl.close();
  }
}