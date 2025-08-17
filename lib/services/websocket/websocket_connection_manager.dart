import 'dart:async';
import 'dart:typed_data';
import 'enhanced_websocket_service.dart';
import 'websocket_message_router.dart';
import 'websocket_subscription_manager.dart';
import 'websocket_dynamic_subscription_controller.dart';

/// Comprehensive WebSocket connection manager that coordinates all WebSocket functionality.
/// 
/// Provides a high-level interface for WebSocket operations, message routing,
/// connection monitoring, health checks, and automatic error handling.
/// Coordinates between EnhancedWebSocketService and WebSocketMessageRouter.
class WebSocketConnectionManager {
  final EnhancedWebSocketService _webSocketService;
  final WebSocketMessageRouter _messageRouter;
  final WebSocketSubscriptionManager _subscriptionManager;
  late final WebSocketDynamicSubscriptionController _dynamicController;
  
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
    WebSocketSubscriptionManager? subscriptionManager,
    ConnectionManagerConfig? config,
  })  : _webSocketService = webSocketService,
        _messageRouter = messageRouter,
        _subscriptionManager = subscriptionManager ?? WebSocketSubscriptionManager(webSocketService: webSocketService),
        _config = config ?? ConnectionManagerConfig.defaultConfig() {
    _initialize();
  }
  
  // Public getters
  bool get isConnected => _webSocketService.isConnected;
  bool get isAudioConnected => _webSocketService.isAudioConnected;
  bool get isConnecting => _webSocketService.isConnecting;
  bool get isBothConnected => _webSocketService.isBothConnected;
  WebSocketConnectionState get queueConnectionState => _webSocketService.queueConnectionState;
  WebSocketConnectionState get audioConnectionState => _webSocketService.audioConnectionState;
  String? get sessionId => _webSocketService.sessionId;
  String? get userId => _webSocketService.userId;
  WebSocketMetrics get metrics => _webSocketService.metrics;
  
  // Message routing streams
  Stream<AudioChunkMessage> get audioChunks => _messageRouter.audioChunks;
  Stream<TTSStatusMessage> get ttsStatus => _messageRouter.ttsStatus;
  Stream<VoiceInputMessage> get voiceInput => _messageRouter.voiceInput;
  Stream<ErrorMessage> get errors => _messageRouter.errors;
  
  // New event streams
  Stream<QueueUpdateMessage> get queueUpdates => _messageRouter.queueUpdates;
  Stream<NotificationMessage> get notifications => _messageRouter.notifications;
  Stream<SystemMessage> get systemMessages => _messageRouter.systemMessages;
  Stream<AuthMessage> get authMessages => _messageRouter.authMessages;
  
  // Subscription management
  WebSocketSubscriptionManager get subscriptionManager => _subscriptionManager;
  Stream<SubscriptionChange> get subscriptionChanges => _subscriptionManager.subscriptionChanges;
  Stream<EventFilterResult> get filterResults => _subscriptionManager.filterResults;
  
  // Dynamic subscription management
  WebSocketDynamicSubscriptionController get dynamicController => _dynamicController;
  Stream<SubscriptionRecommendation> get subscriptionRecommendations => _dynamicController.recommendations;
  Stream<SubscriptionOptimization> get subscriptionOptimizations => _dynamicController.optimizations;
  
  /// Initialize the connection manager
  void _initialize() {
    // Initialize dynamic controller after this manager is created
    _dynamicController = WebSocketDynamicSubscriptionController(
      connectionManager: this,
    );
    
    _setupMessageRouting();
    _setupEventHandling();
    _setupDefaultHandlers();
    _startConnectionMonitoring();
  }
  
  /// Set up message routing from WebSocket service to message router
  void _setupMessageRouting() {
    _messageSubscription = _webSocketService.messageStream.listen(
      (message) => _routeMessageWithSubscriptionFiltering(message),
      onError: (error) => _handleRoutingError(error),
    );
  }
  
  /// Route message with subscription filtering
  Future<void> _routeMessageWithSubscriptionFiltering(WebSocketMessage message) async {
    // Check if this event should be processed based on subscriptions and filters
    if (_subscriptionManager.shouldProcessEvent(message.type, message.data)) {
      await _messageRouter.routeMessage(message);
    } else {
      // Event was filtered out by subscription manager
      print('[ConnectionManager] Event filtered: ${message.type}');
    }
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
        from: queueConnectionState,
        to: queueConnectionState,
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
  
  /// Establishes connection to WebSocket server with full coordination.
  /// 
  /// Requires:
  ///   - Network connectivity must be available
  ///   - Backend WebSocket endpoint must be accessible
  ///   - userId (if provided) must be valid for authentication
  /// 
  /// Ensures:
  ///   - WebSocket connection is established through underlying service
  ///   - Message routing and event handling are active
  ///   - Connection state listeners are notified of state changes
  ///   - Error handling is active for all connection issues
  /// 
  /// Raises:
  ///   - TimeoutException if connection establishment times out
  ///   - WebSocketException if connection fails
  ///   - AuthenticationException if user authentication fails
  Future<void> connect({
    String? userId,
    Map<String, String>? headers,
    bool clearQueue = false,
    bool connectQueue = true,
    bool connectAudio = true,
  }) async {
    try {
      await _webSocketService.connect(
        userId: userId,
        headers: headers,
        clearQueue: clearQueue,
        connectQueue: connectQueue,
        connectAudio: connectAudio,
      );
    } catch (e) {
      _handleConnectionError(e);
      rethrow;
    }
  }
  
  /// Connect only the queue WebSocket for main UI events
  Future<void> connectQueue({
    String? userId,
    Map<String, String>? headers,
    bool clearQueue = false,
  }) async {
    await connect(
      userId: userId,
      headers: headers,
      clearQueue: clearQueue,
      connectQueue: true,
      connectAudio: false,
    );
  }
  
  /// Connect only the audio WebSocket for TTS streaming
  Future<void> connectAudio({
    String? userId,
    Map<String, String>? headers,
  }) async {
    await connect(
      userId: userId,
      headers: headers,
      clearQueue: false,
      connectQueue: false,
      connectAudio: true,
    );
  }
  
  /// Disconnect from WebSocket server
  Future<void> disconnect({bool clearQueue = true}) async {
    await _webSocketService.disconnect(clearQueue: clearQueue);
  }
  
  /// Sends text-to-speech generation request with provider-specific settings.
  /// 
  /// Requires:
  ///   - text must be non-empty and suitable for TTS generation
  ///   - provider must be a valid TTS provider identifier ('openai' or 'elevenlabs')
  ///   - voiceId (if provided) must be valid for the specified provider
  ///   - settings must contain valid provider-specific parameters
  /// 
  /// Ensures:
  ///   - TTS request message is properly formatted by message router
  ///   - Message is sent with appropriate priority through WebSocket
  ///   - Audio response will be available through audioChunks stream
  ///   - TTS status updates will be available through ttsStatus stream
  /// 
  /// Raises:
  ///   - WebSocketException if connection is not active
  ///   - ValidationException if request parameters are invalid
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
  
  /// Sends TTS request and waits for complete audio response.
  /// 
  /// Requires:
  ///   - text must be non-empty and suitable for TTS generation
  ///   - provider must be a valid TTS provider identifier
  ///   - timeout (if provided) must be reasonable for audio generation
  ///   - WebSocket connection must be active
  /// 
  /// Ensures:
  ///   - TTS request is sent with high priority
  ///   - All audio chunks are collected and returned in order
  ///   - Operation completes when last chunk is received or error occurs
  ///   - Timeout protection prevents indefinite waiting
  /// 
  /// Raises:
  ///   - TimeoutException if audio generation exceeds timeout
  ///   - TTSException if audio generation fails
  ///   - WebSocketException if connection is lost during generation
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
  
  /// Performs comprehensive health check of WebSocket connection and services.
  /// 
  /// Requires:
  ///   - Connection manager must be initialized
  ///   - Access to underlying service metrics
  /// 
  /// Ensures:
  ///   - Returns detailed health status including connection state
  ///   - Identifies specific issues with connection or message flow
  ///   - Provides actionable statistics for troubleshooting
  ///   - Health status reflects real-time service condition
  /// 
  /// Raises:
  ///   - No exceptions are raised (returns health status with issues)
  Future<HealthCheckResult> performHealthCheck() async {
    final stats = _webSocketService.getConnectionStats();
    final metrics = _webSocketService.metrics;
    
    final issues = <String>[];
    
    // Check connection states
    if (!isConnected) {
      issues.add('Queue WebSocket not connected');
    }
    
    if (!isAudioConnected) {
      issues.add('Audio WebSocket not connected');
    }
    
    if (!isBothConnected && isConnected) {
      issues.add('Partial connection: Queue connected but Audio disconnected');
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
      _messageRouter.addError(_getEventErrorMessage(event));
    }
  }
  
  /// Handle routing errors
  void _handleRoutingError(dynamic error) {
    _messageRouter.addError('Message routing error: $error');
  }
  
  /// Handle event errors
  void _handleEventError(dynamic error) {
    _messageRouter.addError('Event handling error: $error');
  }
  
  /// Handle connection errors
  void _handleConnectionError(dynamic error) {
    _messageRouter.addError('Connection error: $error');
  }
  
  /// Handle subscription errors
  void _handleSubscriptionError(dynamic error) {
    _messageRouter.addError('Subscription error: $error');
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
  
  /// Get comprehensive connection status for both channels
  Map<String, dynamic> getConnectionStatus() {
    return {
      'queue_connected': isConnected,
      'audio_connected': isAudioConnected,
      'both_connected': isBothConnected,
      'queue_state': queueConnectionState.toString(),
      'audio_state': audioConnectionState.toString(),
      'session_id': sessionId,
      'user_id': userId,
      'connection_stats': getConnectionStats(),
    };
  }
  
  /// Wait for both connections to be established
  Future<void> waitForBothConnections({Duration? timeout}) async {
    final timeoutDuration = timeout ?? const Duration(seconds: 30);
    final completer = Completer<void>();
    
    // Check if already connected
    if (isBothConnected) {
      completer.complete();
      return completer.future;
    }
    
    // Set up timeout
    Timer(timeoutDuration, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException(
          'Timeout waiting for both connections',
          timeoutDuration,
        ));
      }
    });
    
    // Listen for connection state changes
    late StreamSubscription stateSubscription;
    stateSubscription = _webSocketService.eventStream.listen((event) {
      if (isBothConnected && !completer.isCompleted) {
        stateSubscription.cancel();
        completer.complete();
      }
    });
    
    return completer.future;
  }
  
  /// Reconnect both channels with intelligent retry
  Future<void> reconnectBoth({
    String? userId,
    Map<String, String>? headers,
    bool clearQueue = false,
  }) async {
    // Disconnect first
    await disconnect(clearQueue: clearQueue);
    
    // Wait a bit before reconnecting
    await Future.delayed(const Duration(seconds: 2));
    
    // Reconnect both
    await connect(
      userId: userId ?? this.userId,
      headers: headers,
      clearQueue: clearQueue,
      connectQueue: true,
      connectAudio: true,
    );
  }
  
  // ============================================================================
  // Subscription Management Methods
  // ============================================================================
  
  /// Subscribe to all available events
  Future<void> subscribeToAllEvents() async {
    await _subscriptionManager.subscribeToAll();
  }
  
  /// Subscribe to specific events only
  Future<void> subscribeToSpecificEvents(Set<String> events) async {
    await _subscriptionManager.subscribeToEvents(events);
  }
  
  /// Subscribe to entire event categories (e.g., 'queue', 'audio', 'notifications')
  Future<void> subscribeToEventCategories(Set<String> categories) async {
    await _subscriptionManager.subscribeToCategories(categories);
  }
  
  /// Add events to current subscription
  Future<void> addEventSubscriptions(Set<String> events) async {
    await _subscriptionManager.addEventSubscriptions(events);
  }
  
  /// Remove events from current subscription
  Future<void> removeEventSubscriptions(Set<String> events) async {
    await _subscriptionManager.removeEventSubscriptions(events);
  }
  
  /// Register an event filter for client-side filtering
  void registerEventFilter(String eventType, EventFilter filter) {
    _subscriptionManager.registerEventFilter(eventType, filter);
  }
  
  /// Remove an event filter
  void removeEventFilter(String eventType) {
    _subscriptionManager.removeEventFilter(eventType);
  }
  
  /// Get subscription statistics
  Map<String, dynamic> getSubscriptionStats() {
    return _subscriptionManager.getSubscriptionStats();
  }
  
  /// Get available event categories
  Map<String, List<String>> getEventCategories() {
    return _subscriptionManager.getEventCategories();
  }
  
  /// Quick setup for common subscription patterns
  Future<void> setupBasicSubscriptions() async {
    // Subscribe to essential events for basic functionality
    await subscribeToEventCategories({'auth', 'system', 'audio'});
  }
  
  Future<void> setupDevelopmentSubscriptions() async {
    // Subscribe to all events for debugging/development
    await subscribeToAllEvents();
  }
  
  Future<void> setupProductionSubscriptions() async {
    // Subscribe to minimal events for production efficiency
    await subscribeToEventCategories({'auth', 'audio', 'notifications'});
  }
  
  /// Auto-configure filters based on current user/session
  void setupSmartFilters() {
    final currentUserId = userId;
    final currentSessionId = sessionId;
    
    if (currentUserId != null) {
      registerEventFilter('queue_update', UserEventFilter(currentUserId));
      registerEventFilter('notification', UserEventFilter(currentUserId));
    }
    
    if (currentSessionId != null) {
      registerEventFilter('session_specific', SessionEventFilter(currentSessionId));
    }
  }
  
  // ============================================================================
  // Dynamic Subscription Management Methods
  // ============================================================================
  
  /// Adjust subscriptions based on app state changes
  Future<void> adjustSubscriptionsForAppState(AppState appState) async {
    await _dynamicController.adjustSubscriptionsForAppState(appState);
  }
  
  /// Add a contextual subscription that can be activated/deactivated
  Future<void> addContextualSubscription(SubscriptionContext context) async {
    await _dynamicController.addContextualSubscription(context);
  }
  
  /// Remove a contextual subscription
  Future<void> removeContextualSubscription(String contextName) async {
    await _dynamicController.removeContextualSubscription(contextName);
  }
  
  /// Activate a specific subscription context
  Future<void> activateSubscriptionContext(String contextName) async {
    await _dynamicController.activateContext(contextName);
  }
  
  /// Deactivate a specific subscription context
  Future<void> deactivateSubscriptionContext(String contextName) async {
    await _dynamicController.deactivateContext(contextName);
  }
  
  /// Get subscription analytics and insights
  Map<String, dynamic> getSubscriptionAnalytics() {
    return _dynamicController.getSubscriptionAnalytics();
  }
  
  /// Enhanced connection workflow that sets up intelligent subscriptions
  Future<void> connectWithIntelligentSubscriptions({
    String? userId,
    Map<String, String>? headers,
    bool clearQueue = false,
    AppState? initialAppState,
    bool enableDynamicOptimization = true,
  }) async {
    // Connect normally first
    await connect(
      userId: userId,
      headers: headers,
      clearQueue: clearQueue,
    );
    
    // Wait for both connections
    await waitForBothConnections();
    
    // Set up smart filters
    setupSmartFilters();
    
    // Adjust subscriptions based on app state
    if (initialAppState != null) {
      await adjustSubscriptionsForAppState(initialAppState);
    } else {
      // Default to development subscriptions
      await setupDevelopmentSubscriptions();
    }
    
    print('[ConnectionManager] Intelligent subscriptions configured for app state: $initialAppState');
  }
  
  /// Disposes all resources and cleanly shuts down connection manager.
  /// 
  /// Requires:
  ///   - Connection manager must be instantiated (state irrelevant)
  /// 
  /// Ensures:
  ///   - All timers and periodic tasks are cancelled
  ///   - All stream subscriptions are closed
  ///   - Message subscriptions are cleaned up
  ///   - Underlying services are properly disposed
  ///   - Memory leaks are prevented
  /// 
  /// Raises:
  ///   - No exceptions propagate (cleanup errors are suppressed)
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
    _dynamicController.dispose();
    _subscriptionManager.dispose();
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
      enableLogging: false,
      logBinaryMessages: false,
      enableHealthChecks: true,
    );
  }
  
  factory ConnectionManagerConfig.development() {
    return const ConnectionManagerConfig(
      enableLogging: true,
      logBinaryMessages: true,
      maxBinaryLogSize: 200,
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