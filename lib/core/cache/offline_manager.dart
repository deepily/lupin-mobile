import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../logging/logger.dart';
import '../storage/storage_manager.dart';
import 'cache_manager.dart';
import 'cache_policy.dart';

/// Offline support manager
class OfflineManager {
  static OfflineManager? _instance;
  final StorageManager _storage;
  final Connectivity _connectivity = Connectivity();
  final Map<String, CacheManager> _cacheManagers = {};
  
  late StreamSubscription _connectivitySubscription;
  final StreamController<OfflineEvent> _eventController = StreamController<OfflineEvent>.broadcast();
  
  bool _isOnline = true;
  final Set<String> _queuedRequests = {};
  final Map<String, dynamic> _requestQueue = {};

  OfflineManager._(this._storage) {
    _initialize();
  }

  /// Get singleton instance
  static Future<OfflineManager> getInstance() async {
    if (_instance == null) {
      final storage = await StorageManager.getInstance();
      _instance = OfflineManager._(storage);
    }
    return _instance!;
  }

  /// Initialize offline manager
  Future<void> _initialize() async {
    // Load offline state
    await _loadOfflineState();
    
    // Setup connectivity monitoring
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (ConnectivityResult result) => _onConnectivityChanged([result]),
    );
    
    // Check initial connectivity
    final result = await _connectivity.checkConnectivity();
    _onConnectivityChanged([result]);
  }

  /// Check if device is online
  bool get isOnline => _isOnline;

  /// Check if device is offline
  bool get isOffline => !_isOnline;

  /// Get cache manager for a specific type
  CacheManager<T> getCacheManager<T>({
    required String cacheKey,
    required Map<String, dynamic> Function(T) toJson,
    required T Function(Map<String, dynamic>) fromJson,
    CachePolicy policy = CachePolicy.defaultPolicy,
    int Function(T)? calculateSize,
  }) {
    final key = '${cacheKey}_${T.toString()}';
    
    if (!_cacheManagers.containsKey(key)) {
      _cacheManagers[key] = CacheManager<T>(
        cacheKey: cacheKey,
        toJson: toJson,
        fromJson: fromJson,
        policy: policy,
        calculateSize: calculateSize,
        storage: _storage,
      );
    }
    
    return _cacheManagers[key] as CacheManager<T>;
  }

  /// Cache data for offline use
  Future<void> cacheForOffline<T>(
    String cacheKey,
    String itemKey,
    T data, {
    Map<String, dynamic>? metadata,
    CachePolicy? policy,
    required Map<String, dynamic> Function(T) toJson,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    final cacheManager = getCacheManager<T>(
      cacheKey: cacheKey,
      toJson: toJson,
      fromJson: fromJson,
      policy: policy ?? CachePolicy.offlineFirst,
    );
    
    await cacheManager.put(itemKey, data, metadata: metadata);
    _eventController.add(OfflineCacheEvent(cacheKey, itemKey));
  }

  /// Get cached data (offline-first)
  Future<T?> getCachedData<T>(
    String cacheKey,
    String itemKey, {
    required Map<String, dynamic> Function(T) toJson,
    required T Function(Map<String, dynamic>) fromJson,
    CachePolicy? policy,
  }) async {
    final cacheManager = getCacheManager<T>(
      cacheKey: cacheKey,
      toJson: toJson,
      fromJson: fromJson,
      policy: policy ?? CachePolicy.offlineFirst,
    );
    
    return await cacheManager.get(itemKey);
  }

  /// Queue request for when online
  Future<void> queueRequest(String requestKey, Map<String, dynamic> requestData) async {
    _queuedRequests.add(requestKey);
    _requestQueue[requestKey] = {
      'data': requestData,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    // Persist queue
    await _storage.setJson('offline_queue', _requestQueue);
    
    _eventController.add(OfflineQueueEvent(requestKey, true));
  }

  /// Remove request from queue
  Future<void> removeFromQueue(String requestKey) async {
    _queuedRequests.remove(requestKey);
    _requestQueue.remove(requestKey);
    
    // Persist queue
    await _storage.setJson('offline_queue', _requestQueue);
    
    _eventController.add(OfflineQueueEvent(requestKey, false));
  }

  /// Get queued requests
  List<QueuedRequest> getQueuedRequests() {
    return _requestQueue.entries.map((entry) {
      final data = entry.value;
      return QueuedRequest(
        key: entry.key,
        data: data['data'],
        timestamp: DateTime.parse(data['timestamp']),
      );
    }).toList();
  }

  /// Process queued requests (call when online)
  Future<void> processQueuedRequests() async {
    if (!_isOnline) return;
    
    final requests = getQueuedRequests();
    
    for (final request in requests) {
      try {
        // Process request (this would be implemented by the caller)
        _eventController.add(OfflineRequestProcessedEvent(request.key, true));
        await removeFromQueue(request.key);
      } catch (e, st) {
        Logger.error( 'Error processing queued request ${request.key}', tag: 'OfflineManager', error: e, stackTrace: st, context: LogContext( metadata: { 'requestKey': request.key } ) );
        _eventController.add(OfflineRequestProcessedEvent(request.key, false));
      }
    }
  }

  /// Enable offline mode manually
  Future<void> enableOfflineMode() async {
    _isOnline = false;
    await _storage.setBool('offline_mode', true);
    _eventController.add(OfflineStatusEvent(false));
  }

  /// Disable offline mode manually
  Future<void> disableOfflineMode() async {
    _isOnline = true;
    await _storage.setBool('offline_mode', false);
    _eventController.add(OfflineStatusEvent(true));
  }

  /// Get offline statistics
  Future<OfflineStats> getOfflineStats() async {
    int totalCachedItems = 0;
    int totalCacheSize = 0;
    final cacheManagerStats = <String, CacheStats>{};
    
    for (final entry in _cacheManagers.entries) {
      final stats = entry.value.getStats();
      cacheManagerStats[entry.key] = stats;
      totalCachedItems += stats.itemCount;
      totalCacheSize += stats.totalSizeBytes;
    }
    
    return OfflineStats(
      isOnline: _isOnline,
      queuedRequestCount: _queuedRequests.length,
      totalCachedItems: totalCachedItems,
      totalCacheSize: totalCacheSize,
      cacheManagerStats: cacheManagerStats,
    );
  }

  /// Clear all offline data
  Future<void> clearOfflineData() async {
    // Clear all cache managers
    for (final cacheManager in _cacheManagers.values) {
      await cacheManager.clear();
    }
    
    // Clear request queue
    _queuedRequests.clear();
    _requestQueue.clear();
    await _storage.remove('offline_queue');
    
    _eventController.add(OfflineClearEvent());
  }

  /// Stream of offline events
  Stream<OfflineEvent> get events => _eventController.stream;

  /// Dispose resources
  void dispose() {
    _connectivitySubscription.cancel();
    _eventController.close();
    
    for (final cacheManager in _cacheManagers.values) {
      cacheManager.dispose();
    }
    _cacheManagers.clear();
  }

  // Private methods

  Future<void> _loadOfflineState() async {
    // Load manual offline mode setting
    final manualOfflineMode = _storage.getBool('offline_mode') ?? false;
    if (manualOfflineMode) {
      _isOnline = false;
    }
    
    // Load request queue
    final queueData = _storage.getJson('offline_queue');
    if (queueData != null) {
      _requestQueue.addAll(queueData.cast<String, dynamic>());
      _queuedRequests.addAll(_requestQueue.keys);
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    
    // Check if any connection type indicates online status
    _isOnline = results.any((result) => 
      result != ConnectivityResult.none &&
      !_storage.getBool('offline_mode')!
    );
    
    if (wasOnline != _isOnline) {
      _eventController.add(OfflineStatusEvent(_isOnline));
      
      // Process queued requests when coming back online
      if (_isOnline) {
        processQueuedRequests();
      }
    }
  }
}

/// Queued request data
class QueuedRequest {
  /// Key identifying the entry.
  final String key;
  /// The data.
  final Map<String, dynamic> data;
  /// When the object was created.
  final DateTime timestamp;

  /// Creates a [QueuedRequest].
  const QueuedRequest({
    required this.key,
    required this.data,
    required this.timestamp,
  });
}

/// Offline statistics
class OfflineStats {
  /// Whether the device is online.
  final bool isOnline;
  /// Requests waiting to be sent.
  final int queuedRequestCount;
  /// Items cached across all managers.
  final int totalCachedItems;
  /// Total size of all caches.
  final int totalCacheSize;
  /// Statistics per cache manager.
  final Map<String, CacheStats> cacheManagerStats;

  /// Creates a [OfflineStats].
  const OfflineStats({
    required this.isOnline,
    required this.queuedRequestCount,
    required this.totalCachedItems,
    required this.totalCacheSize,
    required this.cacheManagerStats,
  });

  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'is_online': isOnline,
      'queued_request_count': queuedRequestCount,
      'total_cached_items': totalCachedItems,
      'total_cache_size': totalCacheSize,
      'cache_manager_stats': cacheManagerStats.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
    };
  }
}

/// Base offline event
abstract class OfflineEvent {
  /// When the event was created.
  final DateTime timestamp = DateTime.now();
}

/// Offline status change event
class OfflineStatusEvent extends OfflineEvent {
  /// Whether the device is online.
  final bool isOnline;
  /// Creates the event.
  OfflineStatusEvent(this.isOnline);
}

/// Offline cache event
class OfflineCacheEvent extends OfflineEvent {
  /// Key of the cache this manager serves.
  final String cacheKey;
  /// Key of the item.
  final String itemKey;
  /// Creates the event.
  OfflineCacheEvent(this.cacheKey, this.itemKey);
}

/// Offline queue event
class OfflineQueueEvent extends OfflineEvent {
  /// Key of the queued request.
  final String requestKey;
  /// True when the request was added, false when removed.
  final bool added;
  /// Creates the event.
  OfflineQueueEvent(this.requestKey, this.added);
}

/// Offline request processed event
class OfflineRequestProcessedEvent extends OfflineEvent {
  /// Key of the queued request.
  final String requestKey;
  /// Whether the eviction succeeded.
  final bool success;
  /// Creates the event.
  OfflineRequestProcessedEvent(this.requestKey, this.success);
}

/// Offline clear event
class OfflineClearEvent extends OfflineEvent {}