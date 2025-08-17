import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import 'websocket_message_router.dart';
import 'websocket_connection_manager.dart';

/// Comprehensive event handler system for WebSocket events.
/// 
/// Provides specialized handlers for different types of server events,
/// with built-in UI integration, state management, and error handling.
class WebSocketEventHandlerSystem {
  final WebSocketConnectionManager _connectionManager;
  
  // Event handlers
  late final QueueEventHandler _queueHandler;
  late final AudioEventHandler _audioHandler;
  late final NotificationEventHandler _notificationHandler;
  late final SystemEventHandler _systemHandler;
  late final AuthEventHandler _authHandler;
  
  // Stream subscriptions
  final List<StreamSubscription> _subscriptions = [];
  
  // Configuration
  final EventHandlerConfig _config;
  
  WebSocketEventHandlerSystem({
    required WebSocketConnectionManager connectionManager,
    EventHandlerConfig? config,
  })  : _connectionManager = connectionManager,
        _config = config ?? EventHandlerConfig.defaultConfig() {
    _initialize();
  }
  
  /// Initialize all event handlers
  void _initialize() {
    _queueHandler = QueueEventHandler(_config.queueConfig);
    _audioHandler = AudioEventHandler(_config.audioConfig);
    _notificationHandler = NotificationEventHandler(_config.notificationConfig);
    _systemHandler = SystemEventHandler(_config.systemConfig);
    _authHandler = AuthEventHandler(_config.authConfig);
    
    _setupEventSubscriptions();
  }
  
  /// Set up subscriptions to all event streams
  void _setupEventSubscriptions() {
    // Queue events
    _subscriptions.add(
      _connectionManager.queueUpdates.listen(_queueHandler.handleQueueUpdate),
    );
    
    // Audio events
    _subscriptions.add(
      _connectionManager.audioChunks.listen(_audioHandler.handleAudioChunk),
    );
    _subscriptions.add(
      _connectionManager.ttsStatus.listen(_audioHandler.handleTTSStatus),
    );
    
    // Notification events
    _subscriptions.add(
      _connectionManager.notifications.listen(_notificationHandler.handleNotification),
    );
    
    // System events
    _subscriptions.add(
      _connectionManager.systemMessages.listen(_systemHandler.handleSystemMessage),
    );
    
    // Auth events
    _subscriptions.add(
      _connectionManager.authMessages.listen(_authHandler.handleAuthMessage),
    );
    
    // Error handling
    _subscriptions.add(
      _connectionManager.errors.listen(_handleError),
    );
  }
  
  /// Handle WebSocket errors
  void _handleError(ErrorMessage error) {
    print('[EventHandler] WebSocket error: ${error.error}');
    
    if (_config.enableErrorRecovery) {
      _attemptErrorRecovery(error);
    }
  }
  
  /// Attempt to recover from errors
  void _attemptErrorRecovery(ErrorMessage error) {
    // Implement intelligent error recovery
    if (error.error.contains('connection')) {
      print('[EventHandler] Attempting connection recovery...');
      _connectionManager.reconnectBoth();
    }
  }
  
  // Getter methods for individual handlers
  QueueEventHandler get queueHandler => _queueHandler;
  AudioEventHandler get audioHandler => _audioHandler;
  NotificationEventHandler get notificationHandler => _notificationHandler;
  SystemEventHandler get systemHandler => _systemHandler;
  AuthEventHandler get authHandler => _authHandler;
  
  /// Dispose all handlers and subscriptions
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    
    _queueHandler.dispose();
    _audioHandler.dispose();
    _notificationHandler.dispose();
    _systemHandler.dispose();
    _authHandler.dispose();
  }
}

/// Queue event handler for managing queue state and UI updates
class QueueEventHandler {
  final QueueEventConfig _config;
  
  // Queue state
  final Map<String, List<Map<String, dynamic>>> _queueStates = {
    'todo': [],
    'running': [],
    'done': [],
    'dead': [],
  };
  
  // Stream controllers for UI integration
  final StreamController<QueueStateUpdate> _stateController = 
      StreamController<QueueStateUpdate>.broadcast();
  final StreamController<QueueNotification> _notificationController = 
      StreamController<QueueNotification>.broadcast();
  
  // Public streams
  Stream<QueueStateUpdate> get stateUpdates => _stateController.stream;
  Stream<QueueNotification> get notifications => _notificationController.stream;
  
  QueueEventHandler(this._config);
  
  /// Handle queue update messages
  void handleQueueUpdate(QueueUpdateMessage message) {
    final queueType = message.queueType;
    final queueData = message.queueData;
    
    print('[QueueHandler] Queue update: $queueType - ${queueData.length} items');
    
    // Update internal state
    _queueStates[queueType] = List<Map<String, dynamic>>.from(queueData['items'] ?? []);
    
    // Emit state update
    _stateController.add(QueueStateUpdate(
      queueType: queueType,
      items: _queueStates[queueType]!,
      totalCount: _queueStates[queueType]!.length,
      timestamp: message.timestamp,
    ));
    
    // Check for important queue changes
    _checkForImportantChanges(message);
  }
  
  /// Check for important queue changes that need notifications
  void _checkForImportantChanges(QueueUpdateMessage message) {
    final queueType = message.queueType;
    final items = _queueStates[queueType]!;
    
    // Notify on queue completion
    if (queueType == 'done' && items.isNotEmpty) {
      _notificationController.add(QueueNotification(
        type: QueueNotificationType.taskCompleted,
        message: 'Task completed: ${items.last['name'] ?? 'Unknown'}',
        queueType: queueType,
        timestamp: DateTime.now(),
      ));
    }
    
    // Notify on queue errors
    if (queueType == 'dead' && items.isNotEmpty) {
      _notificationController.add(QueueNotification(
        type: QueueNotificationType.taskFailed,
        message: 'Task failed: ${items.last['name'] ?? 'Unknown'}',
        queueType: queueType,
        timestamp: DateTime.now(),
      ));
    }
    
    // Notify on long-running tasks
    if (queueType == 'running' && items.isNotEmpty) {
      final runningTask = items.first;
      final startTime = DateTime.tryParse(runningTask['start_time'] ?? '');
      if (startTime != null && 
          DateTime.now().difference(startTime) > _config.longRunningThreshold) {
        _notificationController.add(QueueNotification(
          type: QueueNotificationType.longRunningTask,
          message: 'Long running task: ${runningTask['name'] ?? 'Unknown'}',
          queueType: queueType,
          timestamp: DateTime.now(),
        ));
      }
    }
  }
  
  /// Get current queue summary
  Map<String, dynamic> getQueueSummary() {
    return {
      'todo': _queueStates['todo']!.length,
      'running': _queueStates['running']!.length,
      'done': _queueStates['done']!.length,
      'dead': _queueStates['dead']!.length,
      'total': _queueStates.values.fold(0, (sum, items) => sum + items.length),
      'last_updated': DateTime.now().toIso8601String(),
    };
  }
  
  void dispose() {
    _stateController.close();
    _notificationController.close();
  }
}

/// Audio event handler for TTS and audio streaming
class AudioEventHandler {
  final AudioEventConfig _config;
  
  // Audio state
  final Map<String, AudioStreamState> _activeStreams = {};
  final List<Uint8List> _audioBuffer = [];
  int _totalBytesReceived = 0;
  
  // Stream controllers
  final StreamController<AudioStreamProgress> _progressController = 
      StreamController<AudioStreamProgress>.broadcast();
  final StreamController<AudioPlaybackEvent> _playbackController = 
      StreamController<AudioPlaybackEvent>.broadcast();
  
  // Public streams
  Stream<AudioStreamProgress> get streamProgress => _progressController.stream;
  Stream<AudioPlaybackEvent> get playbackEvents => _playbackController.stream;
  
  AudioEventHandler(this._config);
  
  /// Handle audio chunk messages
  void handleAudioChunk(AudioChunkMessage message) {
    final audioData = message.audioData;
    final provider = message.provider ?? 'unknown';
    
    if (audioData != null && audioData.isNotEmpty) {
      _audioBuffer.add(audioData);
      _totalBytesReceived += audioData.length;
      
      print('[AudioHandler] Received audio chunk: ${audioData.length} bytes from $provider');
      
      // Update stream state
      final streamState = _activeStreams[provider] ?? AudioStreamState(provider: provider);
      streamState.bytesReceived += audioData.length;
      streamState.chunksReceived++;
      streamState.lastChunkTime = DateTime.now();
      _activeStreams[provider] = streamState;
      
      // Emit progress update
      _progressController.add(AudioStreamProgress(
        provider: provider,
        bytesReceived: streamState.bytesReceived,
        chunksReceived: streamState.chunksReceived,
        isComplete: message.isLastChunk,
        timestamp: DateTime.now(),
      ));
      
      // Handle stream completion
      if (message.isLastChunk) {
        _handleStreamCompletion(provider, streamState);
      }
    }
  }
  
  /// Handle TTS status messages
  void handleTTSStatus(TTSStatusMessage message) {
    final status = message.status;
    final provider = message.provider ?? 'unknown';
    
    print('[AudioHandler] TTS status: $status from $provider');
    
    switch (status) {
      case 'tts_start':
        _handleTTSStart(provider, message);
        break;
      case 'tts_complete':
        _handleTTSComplete(provider, message);
        break;
      case 'tts_error':
        _handleTTSError(provider, message);
        break;
    }
  }
  
  /// Handle TTS start
  void _handleTTSStart(String provider, TTSStatusMessage message) {
    _activeStreams[provider] = AudioStreamState(provider: provider);
    
    _playbackController.add(AudioPlaybackEvent(
      type: AudioPlaybackEventType.started,
      provider: provider,
      message: 'TTS generation started',
      timestamp: DateTime.now(),
    ));
  }
  
  /// Handle TTS completion
  void _handleTTSComplete(String provider, TTSStatusMessage message) {
    final streamState = _activeStreams[provider];
    if (streamState != null) {
      streamState.isComplete = true;
      _handleStreamCompletion(provider, streamState);
    }
  }
  
  /// Handle TTS error
  void _handleTTSError(String provider, TTSStatusMessage message) {
    _playbackController.add(AudioPlaybackEvent(
      type: AudioPlaybackEventType.error,
      provider: provider,
      message: 'TTS error: ${message.details?['error'] ?? 'Unknown error'}',
      timestamp: DateTime.now(),
    ));
    
    _activeStreams.remove(provider);
  }
  
  /// Handle stream completion
  void _handleStreamCompletion(String provider, AudioStreamState streamState) {
    _playbackController.add(AudioPlaybackEvent(
      type: AudioPlaybackEventType.completed,
      provider: provider,
      message: 'Audio stream completed: ${streamState.bytesReceived} bytes',
      timestamp: DateTime.now(),
    ));
    
    // Auto-play if enabled
    if (_config.enableAutoPlay) {
      _playbackController.add(AudioPlaybackEvent(
        type: AudioPlaybackEventType.autoPlayTriggered,
        provider: provider,
        message: 'Auto-playing received audio',
        timestamp: DateTime.now(),
      ));
    }
  }
  
  /// Get combined audio data
  Uint8List getCombinedAudio() {
    if (_audioBuffer.isEmpty) return Uint8List(0);
    
    final totalLength = _audioBuffer.fold(0, (sum, chunk) => sum + chunk.length);
    final combined = Uint8List(totalLength);
    
    int offset = 0;
    for (final chunk in _audioBuffer) {
      combined.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    
    return combined;
  }
  
  /// Clear audio buffer
  void clearAudioBuffer() {
    _audioBuffer.clear();
    _totalBytesReceived = 0;
  }
  
  /// Get audio statistics
  Map<String, dynamic> getAudioStats() {
    return {
      'total_bytes_received': _totalBytesReceived,
      'buffer_chunks': _audioBuffer.length,
      'active_streams': _activeStreams.length,
      'stream_details': _activeStreams.map(
        (provider, state) => MapEntry(provider, state.toJson()),
      ),
    };
  }
  
  void dispose() {
    _progressController.close();
    _playbackController.close();
    _audioBuffer.clear();
    _activeStreams.clear();
  }
}

/// Notification event handler for user notifications and alerts
class NotificationEventHandler {
  final NotificationEventConfig _config;
  
  // Stream controllers
  final StreamController<UserNotification> _notificationController = 
      StreamController<UserNotification>.broadcast();
  
  // Public streams
  Stream<UserNotification> get notifications => _notificationController.stream;
  
  NotificationEventHandler(this._config);
  
  /// Handle notification messages
  void handleNotification(NotificationMessage message) {
    final type = message.notificationType;
    final content = message.message ?? '';
    
    print('[NotificationHandler] Notification: $type - $content');
    
    switch (type) {
      case 'queue_update':
        _handleQueueNotification(message);
        break;
      case 'play_sound':
        _handleSoundNotification(message);
        break;
      default:
        _handleGenericNotification(message);
    }
  }
  
  /// Handle queue-related notifications
  void _handleQueueNotification(NotificationMessage message) {
    _notificationController.add(UserNotification(
      id: _generateNotificationId(),
      title: 'Queue Update',
      message: message.message ?? 'Queue status changed',
      type: UserNotificationType.info,
      priority: NotificationPriority.medium,
      timestamp: message.timestamp,
      autoHide: _config.autoHideQueueNotifications,
      hideDelay: _config.queueNotificationDelay,
    ));
  }
  
  /// Handle sound notification requests
  void _handleSoundNotification(NotificationMessage message) {
    _notificationController.add(UserNotification(
      id: _generateNotificationId(),
      title: 'Audio Notification',
      message: message.message ?? 'Sound notification',
      type: UserNotificationType.audio,
      priority: NotificationPriority.high,
      timestamp: message.timestamp,
      autoHide: true,
      hideDelay: const Duration(seconds: 3),
      data: message.data,
    ));
  }
  
  /// Handle generic notifications
  void _handleGenericNotification(NotificationMessage message) {
    _notificationController.add(UserNotification(
      id: _generateNotificationId(),
      title: 'System Notification',
      message: message.message ?? 'System notification',
      type: UserNotificationType.system,
      priority: NotificationPriority.medium,
      timestamp: message.timestamp,
      autoHide: _config.autoHideGenericNotifications,
      hideDelay: _config.genericNotificationDelay,
    ));
  }
  
  String _generateNotificationId() {
    return 'notif_${DateTime.now().millisecondsSinceEpoch}';
  }
  
  void dispose() {
    _notificationController.close();
  }
}

/// System event handler for system-level events
class SystemEventHandler {
  final SystemEventConfig _config;
  
  // System state
  DateTime? _lastPingTime;
  DateTime? _lastPongTime;
  Duration? _currentLatency;
  
  // Stream controllers
  final StreamController<SystemStatus> _statusController = 
      StreamController<SystemStatus>.broadcast();
  
  // Public streams
  Stream<SystemStatus> get statusUpdates => _statusController.stream;
  
  SystemEventHandler(this._config);
  
  /// Handle system messages
  void handleSystemMessage(SystemMessage message) {
    final type = message.systemType;
    
    switch (type) {
      case 'ping':
        _handlePing(message);
        break;
      case 'pong':
        _handlePong(message);
        break;
      case 'time_update':
        _handleTimeUpdate(message);
        break;
      default:
        print('[SystemHandler] Unknown system message: $type');
    }
  }
  
  /// Handle ping messages
  void _handlePing(SystemMessage message) {
    _lastPingTime = message.timestamp;
    print('[SystemHandler] Ping received at ${message.timestamp}');
  }
  
  /// Handle pong messages
  void _handlePong(SystemMessage message) {
    _lastPongTime = message.timestamp;
    
    if (_lastPingTime != null) {
      _currentLatency = message.timestamp.difference(_lastPingTime!);
      
      _statusController.add(SystemStatus(
        type: SystemStatusType.latencyUpdate,
        message: 'Latency: ${_currentLatency!.inMilliseconds}ms',
        latency: _currentLatency,
        timestamp: DateTime.now(),
      ));
      
      print('[SystemHandler] Pong received, latency: ${_currentLatency!.inMilliseconds}ms');
    }
  }
  
  /// Handle time update messages
  void _handleTimeUpdate(SystemMessage message) {
    final serverTime = message.data?['server_time'];
    if (serverTime != null) {
      _statusController.add(SystemStatus(
        type: SystemStatusType.timeSync,
        message: 'Server time: $serverTime',
        data: message.data,
        timestamp: DateTime.now(),
      ));
      
      print('[SystemHandler] Server time update: $serverTime');
    }
  }
  
  /// Get current system stats
  Map<String, dynamic> getSystemStats() {
    return {
      'last_ping': _lastPingTime?.toIso8601String(),
      'last_pong': _lastPongTime?.toIso8601String(),
      'current_latency_ms': _currentLatency?.inMilliseconds,
      'ping_pong_active': _lastPingTime != null && _lastPongTime != null,
    };
  }
  
  void dispose() {
    _statusController.close();
  }
}

/// Authentication event handler
class AuthEventHandler {
  final AuthEventConfig _config;
  
  // Auth state
  bool _isAuthenticated = false;
  String? _currentUserId;
  DateTime? _lastAuthTime;
  
  // Stream controllers
  final StreamController<AuthStatus> _authController = 
      StreamController<AuthStatus>.broadcast();
  
  // Public streams
  Stream<AuthStatus> get authUpdates => _authController.stream;
  
  AuthEventHandler(this._config);
  
  /// Handle auth messages
  void handleAuthMessage(AuthMessage message) {
    final type = message.authType;
    
    switch (type) {
      case 'auth_success':
        _handleAuthSuccess(message);
        break;
      case 'auth_error':
        _handleAuthError(message);
        break;
      case 'connect':
        _handleConnect(message);
        break;
      default:
        print('[AuthHandler] Unknown auth message: $type');
    }
  }
  
  /// Handle authentication success
  void _handleAuthSuccess(AuthMessage message) {
    _isAuthenticated = true;
    _currentUserId = message.userId;
    _lastAuthTime = message.timestamp;
    
    _authController.add(AuthStatus(
      isAuthenticated: true,
      userId: message.userId,
      sessionId: message.sessionId,
      message: 'Authentication successful',
      timestamp: message.timestamp,
    ));
    
    print('[AuthHandler] Authentication successful for user: ${message.userId}');
  }
  
  /// Handle authentication error
  void _handleAuthError(AuthMessage message) {
    _isAuthenticated = false;
    _currentUserId = null;
    
    _authController.add(AuthStatus(
      isAuthenticated: false,
      userId: null,
      sessionId: message.sessionId,
      message: 'Authentication failed: ${message.message}',
      timestamp: message.timestamp,
      error: message.message,
    ));
    
    print('[AuthHandler] Authentication failed: ${message.message}');
  }
  
  /// Handle connection confirmation
  void _handleConnect(AuthMessage message) {
    _authController.add(AuthStatus(
      isAuthenticated: _isAuthenticated,
      userId: _currentUserId,
      sessionId: message.sessionId,
      message: 'WebSocket connection established',
      timestamp: message.timestamp,
    ));
    
    print('[AuthHandler] Connection confirmed for session: ${message.sessionId}');
  }
  
  /// Get current auth state
  Map<String, dynamic> getAuthState() {
    return {
      'is_authenticated': _isAuthenticated,
      'current_user_id': _currentUserId,
      'last_auth_time': _lastAuthTime?.toIso8601String(),
      'auth_age_minutes': _lastAuthTime != null 
          ? DateTime.now().difference(_lastAuthTime!).inMinutes 
          : null,
    };
  }
  
  void dispose() {
    _authController.close();
  }
}

// ============================================================================
// Configuration Classes
// ============================================================================

class EventHandlerConfig {
  final QueueEventConfig queueConfig;
  final AudioEventConfig audioConfig;
  final NotificationEventConfig notificationConfig;
  final SystemEventConfig systemConfig;
  final AuthEventConfig authConfig;
  final bool enableErrorRecovery;
  
  const EventHandlerConfig({
    this.queueConfig = const QueueEventConfig(),
    this.audioConfig = const AudioEventConfig(),
    this.notificationConfig = const NotificationEventConfig(),
    this.systemConfig = const SystemEventConfig(),
    this.authConfig = const AuthEventConfig(),
    this.enableErrorRecovery = true,
  });
  
  factory EventHandlerConfig.defaultConfig() {
    return const EventHandlerConfig();
  }
}

class QueueEventConfig {
  final Duration longRunningThreshold;
  final bool enableStateTracking;
  final bool enableNotifications;
  
  const QueueEventConfig({
    this.longRunningThreshold = const Duration(minutes: 5),
    this.enableStateTracking = true,
    this.enableNotifications = true,
  });
}

class AudioEventConfig {
  final bool enableAutoPlay;
  final bool enableBuffering;
  final int maxBufferSize;
  
  const AudioEventConfig({
    this.enableAutoPlay = false,
    this.enableBuffering = true,
    this.maxBufferSize = 1048576, // 1MB
  });
}

class NotificationEventConfig {
  final bool autoHideQueueNotifications;
  final bool autoHideGenericNotifications;
  final Duration queueNotificationDelay;
  final Duration genericNotificationDelay;
  
  const NotificationEventConfig({
    this.autoHideQueueNotifications = true,
    this.autoHideGenericNotifications = true,
    this.queueNotificationDelay = const Duration(seconds: 5),
    this.genericNotificationDelay = const Duration(seconds: 3),
  });
}

class SystemEventConfig {
  final bool enableLatencyTracking;
  final bool enableTimeSync;
  
  const SystemEventConfig({
    this.enableLatencyTracking = true,
    this.enableTimeSync = true,
  });
}

class AuthEventConfig {
  final bool enableAutoReauth;
  final Duration reauthThreshold;
  
  const AuthEventConfig({
    this.enableAutoReauth = true,
    this.reauthThreshold = const Duration(hours: 1),
  });
}

// ============================================================================
// Data Classes
// ============================================================================

class QueueStateUpdate {
  final String queueType;
  final List<Map<String, dynamic>> items;
  final int totalCount;
  final DateTime timestamp;
  
  const QueueStateUpdate({
    required this.queueType,
    required this.items,
    required this.totalCount,
    required this.timestamp,
  });
}

class QueueNotification {
  final QueueNotificationType type;
  final String message;
  final String queueType;
  final DateTime timestamp;
  
  const QueueNotification({
    required this.type,
    required this.message,
    required this.queueType,
    required this.timestamp,
  });
}

enum QueueNotificationType {
  taskCompleted,
  taskFailed,
  longRunningTask,
  queueEmpty,
  queueFull,
}

class AudioStreamState {
  final String provider;
  int bytesReceived = 0;
  int chunksReceived = 0;
  bool isComplete = false;
  DateTime? lastChunkTime;
  
  AudioStreamState({required this.provider});
  
  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'bytes_received': bytesReceived,
      'chunks_received': chunksReceived,
      'is_complete': isComplete,
      'last_chunk_time': lastChunkTime?.toIso8601String(),
    };
  }
}

class AudioStreamProgress {
  final String provider;
  final int bytesReceived;
  final int chunksReceived;
  final bool isComplete;
  final DateTime timestamp;
  
  const AudioStreamProgress({
    required this.provider,
    required this.bytesReceived,
    required this.chunksReceived,
    required this.isComplete,
    required this.timestamp,
  });
}

class AudioPlaybackEvent {
  final AudioPlaybackEventType type;
  final String provider;
  final String message;
  final DateTime timestamp;
  
  const AudioPlaybackEvent({
    required this.type,
    required this.provider,
    required this.message,
    required this.timestamp,
  });
}

enum AudioPlaybackEventType {
  started,
  completed,
  error,
  autoPlayTriggered,
}

class UserNotification {
  final String id;
  final String title;
  final String message;
  final UserNotificationType type;
  final NotificationPriority priority;
  final DateTime timestamp;
  final bool autoHide;
  final Duration hideDelay;
  final Map<String, dynamic>? data;
  
  const UserNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.priority,
    required this.timestamp,
    this.autoHide = true,
    this.hideDelay = const Duration(seconds: 5),
    this.data,
  });
}

enum UserNotificationType {
  info,
  warning,
  error,
  success,
  audio,
  system,
}

enum NotificationPriority {
  low,
  medium,
  high,
  critical,
}

class SystemStatus {
  final SystemStatusType type;
  final String message;
  final Duration? latency;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  const SystemStatus({
    required this.type,
    required this.message,
    this.latency,
    this.data,
    required this.timestamp,
  });
}

enum SystemStatusType {
  latencyUpdate,
  timeSync,
  healthCheck,
  connectionStatus,
}

class AuthStatus {
  final bool isAuthenticated;
  final String? userId;
  final String? sessionId;
  final String message;
  final DateTime timestamp;
  final String? error;
  
  const AuthStatus({
    required this.isAuthenticated,
    this.userId,
    this.sessionId,
    required this.message,
    required this.timestamp,
    this.error,
  });
}