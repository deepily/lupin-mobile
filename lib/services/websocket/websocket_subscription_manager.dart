import 'dart:async';
import 'dart:collection';
import '../../core/constants/app_constants.dart';
import 'enhanced_websocket_service.dart';

/// Manages which server events the client subscribes to, and filters events on the client.
///
/// It supports static subscription lists and dynamic changes. Client-side filtering saves bandwidth.
class WebSocketSubscriptionManager {
  final EnhancedWebSocketService _webSocketService;
  
  // Subscription state
  final Set<String> _subscribedEvents = <String>{};
  final Set<String> _allAvailableEvents = <String>{};
  bool _subscribeToAll = true;
  bool _isInitialized = false;
  
  // Event filtering
  final Map<String, Set<String>> _eventCategories = {};
  final Map<String, EventFilter> _eventFilters = {};
  
  // Stream controllers for subscription events
  final StreamController<SubscriptionChange> _subscriptionController = 
      StreamController<SubscriptionChange>.broadcast();
  final StreamController<EventFilterResult> _filterController = 
      StreamController<EventFilterResult>.broadcast();
  
  // Configuration
  final SubscriptionManagerConfig _config;
  
  // Public getters
  /// Unmodifiable view of the subscribed event types.
  Set<String> get subscribedEvents => Set.unmodifiable(_subscribedEvents);
  /// Unmodifiable view of every event type the client knows.
  Set<String> get availableEvents => Set.unmodifiable(_allAvailableEvents);
  /// True while subscribed to every event.
  bool get isSubscribedToAll => _subscribeToAll;
  /// Emits each change to the subscription set.
  Stream<SubscriptionChange> get subscriptionChanges => _subscriptionController.stream;
  /// Emits the outcome of each filtered event.
  Stream<EventFilterResult> get filterResults => _filterController.stream;
  
  /// Creates a manager on [webSocketService].
  ///
  /// [config] defaults to [SubscriptionManagerConfig.defaultConfig].
  WebSocketSubscriptionManager({
    required EnhancedWebSocketService webSocketService,
    SubscriptionManagerConfig? config,
  })  : _webSocketService = webSocketService,
        _config = config ?? SubscriptionManagerConfig.defaultConfig() {
    _initializeEventCategories();
  }
  
  /// Initialize event categories and available events
  void _initializeEventCategories() {
    // Queue events
    _eventCategories['queue'] = {
      AppConstants.eventQueueTodoUpdate,
      AppConstants.eventQueueRunningUpdate,
      AppConstants.eventQueueDoneUpdate,
      AppConstants.eventQueueDeadUpdate,
    };
    
    // Audio/TTS events
    _eventCategories['audio'] = {
      AppConstants.eventTtsJobRequest,
      AppConstants.eventAudioStreamingChunk,
      AppConstants.eventAudioStreamingStatus,
      AppConstants.eventAudioStreamingComplete,
    };
    
    // Notification events
    _eventCategories['notifications'] = {
      AppConstants.eventNotificationQueueUpdate,
      AppConstants.eventNotificationPlaySound,
    };
    
    // System events
    _eventCategories['system'] = {
      AppConstants.eventSysTimeUpdate,
      AppConstants.eventSysPing,
      AppConstants.eventSysPong,
    };
    
    // Authentication events
    _eventCategories['auth'] = {
      AppConstants.eventAuthRequest,
      AppConstants.eventAuthSuccess,
      AppConstants.eventAuthError,
      AppConstants.eventConnect,
    };
    
    // Control events
    _eventCategories['control'] = {
      AppConstants.eventUpdateSubscriptions,
      AppConstants.eventSubscriptionUpdate,
    };
    
    // Build complete available events set
    for (final category in _eventCategories.values) {
      _allAvailableEvents.addAll(category);
    }
    
    _isInitialized = true;
  }
  
  /// Subscribe to all events (default behavior)
  Future<void> subscribeToAll() async {
    if (_subscribeToAll) return;
    
    _subscribeToAll = true;
    _subscribedEvents.clear();
    
    await _updateServerSubscriptions();
    
    _subscriptionController.add(SubscriptionChange(
      type: SubscriptionChangeType.subscribeAll,
      events: _allAvailableEvents,
      timestamp: DateTime.now(),
    ));
  }
  
  /// Subscribe to specific events only
  Future<void> subscribeToEvents(Set<String> events) async {
    final validEvents = events.intersection(_allAvailableEvents);
    
    if (validEvents.isEmpty) {
      throw ArgumentError('No valid events provided: ${events.difference(_allAvailableEvents)}');
    }
    
    _subscribeToAll = false;
    _subscribedEvents.clear();
    _subscribedEvents.addAll(validEvents);
    
    await _updateServerSubscriptions();
    
    _subscriptionController.add(SubscriptionChange(
      type: SubscriptionChangeType.subscribeSpecific,
      events: validEvents,
      timestamp: DateTime.now(),
    ));
  }
  
  /// Subscribe to entire event categories
  Future<void> subscribeToCategories(Set<String> categories) async {
    final events = <String>{};
    
    for (final category in categories) {
      final categoryEvents = _eventCategories[category];
      if (categoryEvents != null) {
        events.addAll(categoryEvents);
      }
    }
    
    if (events.isEmpty) {
      throw ArgumentError('No valid categories provided: $categories');
    }
    
    await subscribeToEvents(events);
  }
  
  /// Add events to current subscription
  Future<void> addEventSubscriptions(Set<String> events) async {
    final validEvents = events.intersection(_allAvailableEvents);
    
    if (validEvents.isEmpty) return;
    
    if (_subscribeToAll) {
      // Already subscribed to all, no change needed
      return;
    }
    
    final newEvents = validEvents.difference(_subscribedEvents);
    if (newEvents.isEmpty) return;
    
    _subscribedEvents.addAll(newEvents);
    await _updateServerSubscriptions();
    
    _subscriptionController.add(SubscriptionChange(
      type: SubscriptionChangeType.addEvents,
      events: newEvents,
      timestamp: DateTime.now(),
    ));
  }
  
  /// Remove events from current subscription
  Future<void> removeEventSubscriptions(Set<String> events) async {
    if (_subscribeToAll) {
      // Convert to specific subscription minus these events
      final remainingEvents = _allAvailableEvents.difference(events);
      await subscribeToEvents(remainingEvents);
      return;
    }
    
    final removedEvents = events.intersection(_subscribedEvents);
    if (removedEvents.isEmpty) return;
    
    _subscribedEvents.removeAll(removedEvents);
    await _updateServerSubscriptions();
    
    _subscriptionController.add(SubscriptionChange(
      type: SubscriptionChangeType.removeEvents,
      events: removedEvents,
      timestamp: DateTime.now(),
    ));
  }
  
  /// Register an event filter for client-side filtering
  void registerEventFilter(String eventType, EventFilter filter) {
    _eventFilters[eventType] = filter;
  }
  
  /// Remove an event filter
  void removeEventFilter(String eventType) {
    _eventFilters.remove(eventType);
  }
  
  /// Check if an event should be processed (subscription + filter check)
  bool shouldProcessEvent(String eventType, Map<String, dynamic>? eventData) {
    // Check subscription
    if (!_subscribeToAll && !_subscribedEvents.contains(eventType)) {
      return false;
    }
    
    // Check filters
    final filter = _eventFilters[eventType];
    if (filter != null) {
      final result = filter.shouldProcess(eventData);
      
      _filterController.add(EventFilterResult(
        eventType: eventType,
        allowed: result,
        filteredBy: filter.runtimeType.toString(),
        timestamp: DateTime.now(),
      ));
      
      return result;
    }
    
    return true;
  }
  
  /// Sends the current subscription set to the server; does nothing when not connected.
  Future<void> _updateServerSubscriptions() async {
    if (!_webSocketService.isConnected) {
      print('[SubscriptionManager] Cannot update subscriptions: not connected');
      return;
    }
    
    try {
      final subscriptionMessage = WebSocketMessage.custom(
        type: AppConstants.eventUpdateSubscriptions,
        data: {
          'subscribe_to_all': _subscribeToAll,
          'subscribed_events': _subscribeToAll ? [] : _subscribedEvents.toList(),
          'session_id': _webSocketService.sessionId,
          'timestamp': DateTime.now().toIso8601String(),
        },
        timestamp: DateTime.now(),
      );
      
      await _webSocketService.sendMessage(subscriptionMessage);
      
      print('[SubscriptionManager] Updated server subscriptions: '
            '${_subscribeToAll ? "ALL" : _subscribedEvents.join(", ")}');
            
    } catch (e) {
      print('[SubscriptionManager] Failed to update server subscriptions: $e');
      rethrow;
    }
  }
  
  /// Get subscription statistics
  Map<String, dynamic> getSubscriptionStats() {
    final categoryStats = <String, Map<String, dynamic>>{};
    
    for (final entry in _eventCategories.entries) {
      final category = entry.key;
      final categoryEvents = entry.value;
      final subscribedInCategory = _subscribeToAll 
          ? categoryEvents.length
          : categoryEvents.intersection(_subscribedEvents).length;
      
      categoryStats[category] = {
        'total_events': categoryEvents.length,
        'subscribed_events': subscribedInCategory,
        'subscription_rate': subscribedInCategory / categoryEvents.length,
        'events': categoryEvents.toList(),
      };
    }
    
    return {
      'subscribe_to_all': _subscribeToAll,
      'total_available_events': _allAvailableEvents.length,
      'total_subscribed_events': _subscribeToAll ? _allAvailableEvents.length : _subscribedEvents.length,
      'subscription_rate': _subscribeToAll ? 1.0 : _subscribedEvents.length / _allAvailableEvents.length,
      'category_breakdown': categoryStats,
      'active_filters': _eventFilters.keys.toList(),
    };
  }
  
  /// Get available event categories
  Map<String, List<String>> getEventCategories() {
    return _eventCategories.map(
      (category, events) => MapEntry(category, events.toList()),
    );
  }
  
  /// Reset to default subscription (all events)
  Future<void> resetToDefault() async {
    _eventFilters.clear();
    await subscribeToAll();
  }
  
  /// Dispose resources
  void dispose() {
    _subscriptionController.close();
    _filterController.close();
    _eventFilters.clear();
  }
}

/// Tuning for [WebSocketSubscriptionManager]; the manager stores it but does not read it yet.
class SubscriptionManagerConfig {
  /// Whether subscription changes are sent to the server automatically.
  final bool enableAutoUpdates;
  /// Delay used to throttle server updates.
  final Duration updateThrottleDelay;
  /// Whether filter outcomes are logged.
  final bool enableFilterLogging;
  /// Number of filter results kept.
  final int maxFilterHistory;
  
  /// Creates a config; the defaults match [SubscriptionManagerConfig.defaultConfig].
  const SubscriptionManagerConfig({
    this.enableAutoUpdates = true,
    this.updateThrottleDelay = const Duration(milliseconds: 500),
    this.enableFilterLogging = true,
    this.maxFilterHistory = 100,
  });
  
  /// The default config: updates and logging on, 500 ms throttle, 100 results kept.
  factory SubscriptionManagerConfig.defaultConfig() {
    return const SubscriptionManagerConfig();
  }
  
  /// Updates and logging off, 10 results kept.
  factory SubscriptionManagerConfig.minimal() {
    return const SubscriptionManagerConfig(
      enableAutoUpdates: false,
      enableFilterLogging: false,
      maxFilterHistory: 10,
    );
  }
}

/// Notice that the subscription set changed.
class SubscriptionChange {
  /// Kind of change.
  final SubscriptionChangeType type;
  /// Events affected by the change.
  final Set<String> events;
  /// When the change happened.
  final DateTime timestamp;
  
  /// Creates a notice; every field is required.
  SubscriptionChange({
    required this.type,
    required this.events,
    required this.timestamp,
  });
}

/// What kind of subscription change happened.
enum SubscriptionChangeType {
  /// Subscribed to every event.
  subscribeAll,
  /// Subscribed to a specific set.
  subscribeSpecific,
  /// Events were added.
  addEvents,
  /// Events were removed.
  removeEvents,
  /// A filter was changed.
  filterUpdate,
}

/// The outcome of filtering one event.
class EventFilterResult {
  /// The event type that was filtered.
  final String eventType;
  /// Whether the event was allowed through.
  final bool allowed;
  /// Name of the filter that decided.
  final String filteredBy;
  /// When the event was filtered.
  final DateTime timestamp;
  
  /// Creates a result; every field is required.
  EventFilterResult({
    required this.eventType,
    required this.allowed,
    required this.filteredBy,
    required this.timestamp,
  });
}

/// Decides whether an event should be processed, from its data.
abstract class EventFilter {
  /// True when the event should be processed; [eventData] is the event payload.
  bool shouldProcess(Map<String, dynamic>? eventData);
}

/// Passes events for one session, and events that name no session.
class SessionEventFilter extends EventFilter {
  /// Session whose events pass.
  final String targetSessionId;
  
  /// Creates a filter for [targetSessionId].
  SessionEventFilter(this.targetSessionId);
  
  @override
  bool shouldProcess(Map<String, dynamic>? eventData) {
    if (eventData == null) return true;
    final sessionId = eventData['session_id'] as String?;
    return sessionId == null || sessionId == targetSessionId;
  }
}

/// Passes events for one user, and events that name no user.
class UserEventFilter extends EventFilter {
  /// User whose events pass.
  final String targetUserId;
  
  /// Creates a filter for [targetUserId].
  UserEventFilter(this.targetUserId);
  
  @override
  bool shouldProcess(Map<String, dynamic>? eventData) {
    if (eventData == null) return true;
    final userId = eventData['user_id'] as String?;
    return userId == null || userId == targetUserId;
  }
}

/// Passes events whose priority is allowed, and events that carry none.
class PriorityEventFilter extends EventFilter {
  /// Priorities that pass.
  final Set<String> allowedPriorities;
  
  /// Creates a filter for [allowedPriorities].
  PriorityEventFilter(this.allowedPriorities);
  
  @override
  bool shouldProcess(Map<String, dynamic>? eventData) {
    if (eventData == null) return true;
    final priority = eventData['priority'] as String?;
    return priority == null || allowedPriorities.contains(priority);
  }
}