import 'dart:async';
import 'dart:collection';
import '../../core/constants/app_constants.dart';
import 'enhanced_websocket_service.dart';

/// Manages WebSocket event subscriptions with intelligent filtering and dynamic updates.
/// 
/// Provides fine-grained control over which server events the client receives,
/// supporting both static subscription lists and dynamic subscription changes.
/// Optimizes bandwidth usage by filtering events at the client level.
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
  Set<String> get subscribedEvents => Set.unmodifiable(_subscribedEvents);
  Set<String> get availableEvents => Set.unmodifiable(_allAvailableEvents);
  bool get isSubscribedToAll => _subscribeToAll;
  Stream<SubscriptionChange> get subscriptionChanges => _subscriptionController.stream;
  Stream<EventFilterResult> get filterResults => _filterController.stream;
  
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
  
  /// Update server subscriptions
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

/// Configuration for subscription manager
class SubscriptionManagerConfig {
  final bool enableAutoUpdates;
  final Duration updateThrottleDelay;
  final bool enableFilterLogging;
  final int maxFilterHistory;
  
  const SubscriptionManagerConfig({
    this.enableAutoUpdates = true,
    this.updateThrottleDelay = const Duration(milliseconds: 500),
    this.enableFilterLogging = true,
    this.maxFilterHistory = 100,
  });
  
  factory SubscriptionManagerConfig.defaultConfig() {
    return const SubscriptionManagerConfig();
  }
  
  factory SubscriptionManagerConfig.minimal() {
    return const SubscriptionManagerConfig(
      enableAutoUpdates: false,
      enableFilterLogging: false,
      maxFilterHistory: 10,
    );
  }
}

/// Subscription change notification
class SubscriptionChange {
  final SubscriptionChangeType type;
  final Set<String> events;
  final DateTime timestamp;
  
  SubscriptionChange({
    required this.type,
    required this.events,
    required this.timestamp,
  });
}

/// Types of subscription changes
enum SubscriptionChangeType {
  subscribeAll,
  subscribeSpecific,
  addEvents,
  removeEvents,
  filterUpdate,
}

/// Event filter result
class EventFilterResult {
  final String eventType;
  final bool allowed;
  final String filteredBy;
  final DateTime timestamp;
  
  EventFilterResult({
    required this.eventType,
    required this.allowed,
    required this.filteredBy,
    required this.timestamp,
  });
}

/// Abstract event filter
abstract class EventFilter {
  bool shouldProcess(Map<String, dynamic>? eventData);
}

/// Session-based event filter
class SessionEventFilter extends EventFilter {
  final String targetSessionId;
  
  SessionEventFilter(this.targetSessionId);
  
  @override
  bool shouldProcess(Map<String, dynamic>? eventData) {
    if (eventData == null) return true;
    final sessionId = eventData['session_id'] as String?;
    return sessionId == null || sessionId == targetSessionId;
  }
}

/// User-based event filter
class UserEventFilter extends EventFilter {
  final String targetUserId;
  
  UserEventFilter(this.targetUserId);
  
  @override
  bool shouldProcess(Map<String, dynamic>? eventData) {
    if (eventData == null) return true;
    final userId = eventData['user_id'] as String?;
    return userId == null || userId == targetUserId;
  }
}

/// Priority-based event filter
class PriorityEventFilter extends EventFilter {
  final Set<String> allowedPriorities;
  
  PriorityEventFilter(this.allowedPriorities);
  
  @override
  bool shouldProcess(Map<String, dynamic>? eventData) {
    if (eventData == null) return true;
    final priority = eventData['priority'] as String?;
    return priority == null || allowedPriorities.contains(priority);
  }
}