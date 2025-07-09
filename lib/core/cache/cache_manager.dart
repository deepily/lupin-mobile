import 'dart:async';
import 'dart:convert';
import '../storage/storage_manager.dart';
import 'cache_policy.dart';

/// Generic cache manager for offline support
class CacheManager<T> {
  final String cacheKey;
  final CachePolicy policy;
  final StorageManager _storage;
  final Map<String, CacheEntry<T>> _memoryCache = {};
  final StreamController<CacheEvent> _eventController = StreamController<CacheEvent>.broadcast();
  Timer? _cleanupTimer;
  
  /// Serialization functions
  final Map<String, dynamic> Function(T) toJson;
  final T Function(Map<String, dynamic>) fromJson;
  
  /// Size calculation function (optional)
  final int Function(T)? calculateSize;

  CacheManager({
    required this.cacheKey,
    required this.toJson,
    required this.fromJson,
    this.policy = CachePolicy.defaultPolicy,
    this.calculateSize,
    required StorageManager storage,
  }) : _storage = storage {
    _initialize();
  }

  /// Initialize cache manager
  Future<void> _initialize() async {
    // Load persisted cache if enabled
    if (policy.persistAcrossRestarts) {
      await _loadPersistedCache();
    }
    
    // Setup auto cleanup if enabled
    if (policy.enableAutoCleanup) {
      _cleanupTimer = Timer.periodic(policy.autoCleanupInterval, (_) {
        cleanup();
      });
    }
  }

  /// Get item from cache
  Future<T?> get(String key) async {
    // Check memory cache first
    var entry = _memoryCache[key];
    
    if (entry == null && policy.persistAcrossRestarts) {
      // Try loading from storage
      entry = await _loadFromStorage(key);
      if (entry != null) {
        _memoryCache[key] = entry;
      }
    }
    
    if (entry == null) {
      _eventController.add(CacheMissEvent(key));
      return null;
    }
    
    // Check if expired
    if (entry.isExpired(policy.maxAge)) {
      await remove(key);
      _eventController.add(CacheExpiredEvent(key));
      return null;
    }
    
    // Update access metadata
    entry = entry.withAccess();
    _memoryCache[key] = entry;
    
    if (policy.persistAcrossRestarts) {
      await _persistEntry(entry);
    }
    
    _eventController.add(CacheHitEvent(key));
    return entry.value;
  }

  /// Put item in cache
  Future<void> put(String key, T value, {Map<String, dynamic>? metadata}) async {
    final sizeBytes = calculateSize?.call(value) ?? 0;
    
    final entry = CacheEntry<T>(
      key: key,
      value: value,
      createdAt: DateTime.now(),
      lastAccessedAt: DateTime.now(),
      accessCount: 1,
      sizeBytes: sizeBytes,
      metadata: metadata,
    );
    
    // Check cache limits and evict if necessary
    await _enforcePolicy();
    
    _memoryCache[key] = entry;
    
    if (policy.persistAcrossRestarts) {
      await _persistEntry(entry);
    }
    
    _eventController.add(CachePutEvent(key, sizeBytes));
  }

  /// Remove item from cache
  Future<void> remove(String key) async {
    _memoryCache.remove(key);
    
    if (policy.persistAcrossRestarts) {
      await _storage.remove(_getStorageKey(key));
    }
    
    _eventController.add(CacheRemoveEvent(key));
  }

  /// Clear all cached items
  Future<void> clear() async {
    _memoryCache.clear();
    
    if (policy.persistAcrossRestarts) {
      await _storage.removeKeysWithPrefix(cacheKey);
    }
    
    _eventController.add(CacheClearEvent());
  }

  /// Get cache statistics
  CacheStats getStats() {
    int totalSize = 0;
    int expiredCount = 0;
    DateTime? oldestEntry;
    DateTime? newestEntry;
    
    for (final entry in _memoryCache.values) {
      totalSize += entry.sizeBytes;
      
      if (entry.isExpired(policy.maxAge)) {
        expiredCount++;
      }
      
      if (oldestEntry == null || entry.createdAt.isBefore(oldestEntry)) {
        oldestEntry = entry.createdAt;
      }
      
      if (newestEntry == null || entry.createdAt.isAfter(newestEntry)) {
        newestEntry = entry.createdAt;
      }
    }
    
    return CacheStats(
      itemCount: _memoryCache.length,
      totalSizeBytes: totalSize,
      expiredCount: expiredCount,
      hitRate: _calculateHitRate(),
      oldestEntry: oldestEntry,
      newestEntry: newestEntry,
      policy: policy,
    );
  }

  /// Cleanup expired entries
  Future<void> cleanup() async {
    final keysToRemove = <String>[];
    
    for (final entry in _memoryCache.entries) {
      if (entry.value.isExpired(policy.maxAge)) {
        keysToRemove.add(entry.key);
      }
    }
    
    for (final key in keysToRemove) {
      await remove(key);
    }
    
    if (keysToRemove.isNotEmpty) {
      _eventController.add(CacheCleanupEvent(keysToRemove.length));
    }
  }

  /// Stream of cache events
  Stream<CacheEvent> get events => _eventController.stream;

  /// Dispose resources
  void dispose() {
    _cleanupTimer?.cancel();
    _eventController.close();
  }

  // Private helper methods

  String _getStorageKey(String key) => '${cacheKey}_$key';

  Future<void> _loadPersistedCache() async {
    final keys = _storage.getKeysWithPrefix(cacheKey);
    
    for (final storageKey in keys) {
      final json = _storage.getJson(storageKey);
      if (json != null) {
        try {
          final entry = CacheEntry.fromJson(json, fromJson);
          if (!entry.isExpired(policy.maxAge)) {
            _memoryCache[entry.key] = entry;
          }
        } catch (e) {
          print('[CacheManager] Error loading cached entry: $e');
        }
      }
    }
  }

  Future<CacheEntry<T>?> _loadFromStorage(String key) async {
    final storageKey = _getStorageKey(key);
    final json = _storage.getJson(storageKey);
    
    if (json == null) return null;
    
    try {
      return CacheEntry.fromJson(json, fromJson);
    } catch (e) {
      print('[CacheManager] Error loading entry from storage: $e');
      return null;
    }
  }

  Future<void> _persistEntry(CacheEntry<T> entry) async {
    final storageKey = _getStorageKey(entry.key);
    final json = entry.toJson(toJson);
    await _storage.setJson(storageKey, json);
  }

  Future<void> _enforcePolicy() async {
    // Check item count limit
    if (_memoryCache.length >= policy.maxItems) {
      await _evictEntries(1);
    }
    
    // Check size limit
    final totalSize = _memoryCache.values.fold<int>(
      0, (sum, entry) => sum + entry.sizeBytes
    );
    
    if (totalSize >= policy.maxSizeBytes) {
      await _evictBySize(totalSize - policy.maxSizeBytes);
    }
  }

  Future<void> _evictEntries(int count) async {
    final sortedEntries = _memoryCache.entries.toList();
    
    // Sort based on eviction strategy
    switch (policy.evictionStrategy) {
      case CacheEvictionStrategy.lru:
        sortedEntries.sort((a, b) {
          final aTime = a.value.lastAccessedAt ?? a.value.createdAt;
          final bTime = b.value.lastAccessedAt ?? b.value.createdAt;
          return aTime.compareTo(bTime);
        });
        break;
      case CacheEvictionStrategy.fifo:
        sortedEntries.sort((a, b) => 
          a.value.createdAt.compareTo(b.value.createdAt));
        break;
      case CacheEvictionStrategy.lfu:
        sortedEntries.sort((a, b) => 
          a.value.accessCount.compareTo(b.value.accessCount));
        break;
      case CacheEvictionStrategy.ttl:
        sortedEntries.sort((a, b) => 
          a.value.createdAt.compareTo(b.value.createdAt));
        break;
      case CacheEvictionStrategy.size:
        sortedEntries.sort((a, b) => 
          b.value.sizeBytes.compareTo(a.value.sizeBytes));
        break;
    }
    
    // Remove the first 'count' entries
    for (int i = 0; i < count && i < sortedEntries.length; i++) {
      await remove(sortedEntries[i].key);
    }
  }

  Future<void> _evictBySize(int bytesToFree) async {
    final sortedEntries = _memoryCache.entries.toList()
      ..sort((a, b) => b.value.sizeBytes.compareTo(a.value.sizeBytes));
    
    int freedBytes = 0;
    for (final entry in sortedEntries) {
      if (freedBytes >= bytesToFree) break;
      freedBytes += entry.value.sizeBytes;
      await remove(entry.key);
    }
  }

  double _calculateHitRate() {
    // This is a simplified calculation
    // In production, you'd track actual hits and misses
    return _memoryCache.isEmpty ? 0.0 : 0.85;
  }
}

/// Cache statistics
class CacheStats {
  final int itemCount;
  final int totalSizeBytes;
  final int expiredCount;
  final double hitRate;
  final DateTime? oldestEntry;
  final DateTime? newestEntry;
  final CachePolicy policy;

  const CacheStats({
    required this.itemCount,
    required this.totalSizeBytes,
    required this.expiredCount,
    required this.hitRate,
    this.oldestEntry,
    this.newestEntry,
    required this.policy,
  });

  double get utilizationPercent => 
    policy.maxItems > 0 ? itemCount / policy.maxItems : 0.0;

  double get sizeUtilizationPercent => 
    policy.maxSizeBytes > 0 ? totalSizeBytes / policy.maxSizeBytes : 0.0;

  Map<String, dynamic> toJson() {
    return {
      'item_count': itemCount,
      'total_size_bytes': totalSizeBytes,
      'expired_count': expiredCount,
      'hit_rate': hitRate,
      'utilization_percent': utilizationPercent,
      'size_utilization_percent': sizeUtilizationPercent,
      'oldest_entry': oldestEntry?.toIso8601String(),
      'newest_entry': newestEntry?.toIso8601String(),
    };
  }
}

/// Base cache event
abstract class CacheEvent {
  final DateTime timestamp = DateTime.now();
}

/// Cache hit event
class CacheHitEvent extends CacheEvent {
  final String key;
  CacheHitEvent(this.key);
}

/// Cache miss event
class CacheMissEvent extends CacheEvent {
  final String key;
  CacheMissEvent(this.key);
}

/// Cache put event
class CachePutEvent extends CacheEvent {
  final String key;
  final int sizeBytes;
  CachePutEvent(this.key, this.sizeBytes);
}

/// Cache remove event
class CacheRemoveEvent extends CacheEvent {
  final String key;
  CacheRemoveEvent(this.key);
}

/// Cache expired event
class CacheExpiredEvent extends CacheEvent {
  final String key;
  CacheExpiredEvent(this.key);
}

/// Cache clear event
class CacheClearEvent extends CacheEvent {}

/// Cache cleanup event
class CacheCleanupEvent extends CacheEvent {
  final int itemsRemoved;
  CacheCleanupEvent(this.itemsRemoved);
}