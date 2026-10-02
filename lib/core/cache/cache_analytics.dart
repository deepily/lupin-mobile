import 'dart:async';
import 'dart:collection';
import '../storage/storage_manager.dart';

/// Cache analytics and metrics tracking
class CacheAnalytics {
  static CacheAnalytics? _instance;
  late final StorageManager _storage;
  
  // Metrics tracking
  final Map<String, CacheMetrics> _providerMetrics = {};
  final Map<String, CacheMetrics> _typeMetrics = {};
  final Queue<CacheAccessRecord> _accessHistory = Queue();
  final int _maxHistorySize = 1000;
  
  // Real-time counters
  int _totalHits = 0;
  int _totalMisses = 0;
  int _totalStores = 0;
  int _totalEvictions = 0;
  int _totalBytesStored = 0;
  int _totalBytesRetrieved = 0;
  int _totalCompressionSaved = 0;
  
  // Performance tracking
  final Map<String, List<Duration>> _operationLatencies = {
    'store': [],
    'retrieve': [],
    'evict': [],
  };
  
  // Analytics period
  DateTime _periodStart = DateTime.now();
  Timer? _periodicSaveTimer;
  
  // Stream controller
  final _analyticsController = StreamController<AnalyticsEvent>.broadcast();
  
  /// Emits an event for each cache operation recorded.
  Stream<AnalyticsEvent> get analyticsStream => _analyticsController.stream;
  
  CacheAnalytics._();
  
  /// Get singleton instance
  static Future<CacheAnalytics> getInstance() async {
    if (_instance == null) {
      _instance = CacheAnalytics._();
      await _instance!._initialize();
    }
    return _instance!;
  }
  
  /// Initialize analytics
  Future<void> _initialize() async {
    _storage = await StorageManager.getInstance();
    await _loadPersistedMetrics();
    
    // Set up periodic save
    _periodicSaveTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _persistMetrics();
    });
  }
  
  /// Initialize analytics (public method for cache manager)
  Future<void> initialize() async {
    // Already initialized in getInstance
  }
  
  /// Record cache store operation
  void recordCacheStore({
    required String type,
    required String provider,
    required int sizeBytes,
    int? compressedSizeBytes,
    Duration? latency,
    Map<String, dynamic>? metadata,
  }) {
    _totalStores++;
    _totalBytesStored += sizeBytes;
    
    if (compressedSizeBytes != null && compressedSizeBytes < sizeBytes) {
      _totalCompressionSaved += (sizeBytes - compressedSizeBytes);
    }
    
    // Update provider metrics
    _updateMetrics(
      _providerMetrics,
      provider,
      isHit: false,
      sizeBytes: sizeBytes,
      operation: 'store',
    );
    
    // Update type metrics
    _updateMetrics(
      _typeMetrics,
      type,
      isHit: false,
      sizeBytes: sizeBytes,
      operation: 'store',
    );
    
    // Record latency
    if (latency != null) {
      _recordLatency('store', latency);
    }
    
    // Add to history
    _addAccessRecord(CacheAccessRecord(
      type: type,
      provider: provider,
      operation: 'store',
      sizeBytes: sizeBytes,
      timestamp: DateTime.now(),
      metadata: metadata,
    ));
    
    _analyticsController.add(CacheStoreEvent(
      type: type,
      provider: provider,
      sizeBytes: sizeBytes,
      compressionRatio: compressedSizeBytes != null 
          ? compressedSizeBytes / sizeBytes 
          : 1.0,
    ));
  }
  
  /// Record cache hit
  void recordCacheHit({
    required String type,
    required String provider,
    int? sizeBytes,
    Duration? latency,
    Map<String, dynamic>? metadata,
  }) {
    _totalHits++;
    
    if (sizeBytes != null) {
      _totalBytesRetrieved += sizeBytes;
    }
    
    // Update provider metrics
    _updateMetrics(
      _providerMetrics,
      provider,
      isHit: true,
      sizeBytes: sizeBytes,
      operation: 'retrieve',
    );
    
    // Update type metrics
    _updateMetrics(
      _typeMetrics,
      type,
      isHit: true,
      sizeBytes: sizeBytes,
      operation: 'retrieve',
    );
    
    // Record latency
    if (latency != null) {
      _recordLatency('retrieve', latency);
    }
    
    // Add to history
    _addAccessRecord(CacheAccessRecord(
      type: type,
      provider: provider,
      operation: 'hit',
      sizeBytes: sizeBytes,
      timestamp: DateTime.now(),
      metadata: metadata,
    ));
    
    _analyticsController.add(CacheHitEvent(
      type: type,
      provider: provider,
      hitRate: overallHitRate,
    ));
  }
  
  /// Record cache miss
  void recordCacheMiss({
    required String type,
    required String provider,
    Duration? latency,
    Map<String, dynamic>? metadata,
  }) {
    _totalMisses++;
    
    // Update provider metrics
    _updateMetrics(
      _providerMetrics,
      provider,
      isHit: false,
      operation: 'retrieve',
    );
    
    // Update type metrics
    _updateMetrics(
      _typeMetrics,
      type,
      isHit: false,
      operation: 'retrieve',
    );
    
    // Record latency
    if (latency != null) {
      _recordLatency('retrieve', latency);
    }
    
    // Add to history
    _addAccessRecord(CacheAccessRecord(
      type: type,
      provider: provider,
      operation: 'miss',
      timestamp: DateTime.now(),
      metadata: metadata,
    ));
    
    _analyticsController.add(CacheMissEvent(
      type: type,
      provider: provider,
      hitRate: overallHitRate,
    ));
  }
  
  /// Record cache eviction
  void recordEviction({
    required String reason,
    required int itemCount,
    required int bytesFreed,
    Duration? latency,
  }) {
    _totalEvictions += itemCount;
    
    // Record latency
    if (latency != null) {
      _recordLatency('evict', latency);
    }
    
    _analyticsController.add(CacheEvictionEvent(
      reason: reason,
      itemCount: itemCount,
      bytesFreed: bytesFreed,
    ));
  }
  
  /// Get analytics data
  Future<CacheAnalyticsData> getAnalytics() async {
    final period = DateTime.now().difference(_periodStart);
    
    return CacheAnalyticsData(
      periodStart: _periodStart,
      periodDuration: period,
      totalHits: _totalHits,
      totalMisses: _totalMisses,
      totalStores: _totalStores,
      totalEvictions: _totalEvictions,
      totalBytesStored: _totalBytesStored,
      totalBytesRetrieved: _totalBytesRetrieved,
      totalCompressionSaved: _totalCompressionSaved,
      overallHitRate: overallHitRate,
      compressionRatio: compressionRatio,
      providerMetrics: Map.from(_providerMetrics),
      typeMetrics: Map.from(_typeMetrics),
      operationLatencies: _getLatencyStats(),
      recentAccess: _accessHistory.toList(),
    );
  }
  
  /// Get hit rate by provider
  double getProviderHitRate(String provider) {
    final metrics = _providerMetrics[provider];
    if (metrics == null) return 0.0;
    return metrics.hitRate;
  }
  
  /// Get hit rate by type
  double getTypeHitRate(String type) {
    final metrics = _typeMetrics[type];
    if (metrics == null) return 0.0;
    return metrics.hitRate;
  }
  
  /// Get operation latency percentiles
  Map<String, LatencyStats> getLatencyStats() {
    return _getLatencyStats();
  }
  
  /// Refreshes the derived metrics; called periodically.
  void updateMetrics() {
    // Persist current metrics
    _persistMetrics();
    
    // Clean up old history
    while (_accessHistory.length > _maxHistorySize) {
      _accessHistory.removeFirst();
    }
    
    // Emit periodic update
    _analyticsController.add(AnalyticsUpdateEvent(
      hitRate: overallHitRate,
      compressionRatio: compressionRatio,
      totalBytes: _totalBytesStored + _totalBytesRetrieved,
    ));
  }
  
  /// Reset analytics for new period
  void resetPeriod() {
    _periodStart = DateTime.now();
    _totalHits = 0;
    _totalMisses = 0;
    _totalStores = 0;
    _totalEvictions = 0;
    _totalBytesStored = 0;
    _totalBytesRetrieved = 0;
    _totalCompressionSaved = 0;
    _providerMetrics.clear();
    _typeMetrics.clear();
    _operationLatencies.forEach((key, value) => value.clear());
    _accessHistory.clear();
  }
  
  /// Export analytics report
  Future<String> exportReport({
    DateTime? startDate,
    DateTime? endDate,
    String format = 'json',
  }) async {
    final analytics = await getAnalytics();
    
    // Filter by date range if provided
    List<CacheAccessRecord> filteredHistory = analytics.recentAccess;
    if (startDate != null || endDate != null) {
      filteredHistory = filteredHistory.where((record) {
        if (startDate != null && record.timestamp.isBefore(startDate)) {
          return false;
        }
        if (endDate != null && record.timestamp.isAfter(endDate)) {
          return false;
        }
        return true;
      }).toList();
    }
    
    // Generate report
    if (format == 'json') {
      return _generateJsonReport(analytics, filteredHistory);
    } else if (format == 'csv') {
      return _generateCsvReport(analytics, filteredHistory);
    } else {
      return _generateTextReport(analytics, filteredHistory);
    }
  }
  
  /// Dispose resources
  void dispose() {
    _periodicSaveTimer?.cancel();
    _persistMetrics();
    _analyticsController.close();
  }
  
  // Getters
  
  /// Hits divided by lookups across all providers.
  double get overallHitRate {
    final total = _totalHits + _totalMisses;
    return total > 0 ? _totalHits / total : 0.0;
  }
  
  /// Overall compression ratio.
  double get compressionRatio {
    return _totalBytesStored > 0 
        ? 1.0 - (_totalCompressionSaved / _totalBytesStored)
        : 1.0;
  }
  
  // Private methods
  
  void _updateMetrics(
    Map<String, CacheMetrics> metricsMap,
    String key,
    {
      required bool isHit,
      int? sizeBytes,
      required String operation,
    }
  ) {
    final metrics = metricsMap.putIfAbsent(
      key,
      () => CacheMetrics(key: key),
    );
    
    if (operation == 'store') {
      metrics.stores++;
      if (sizeBytes != null) {
        metrics.bytesStored += sizeBytes;
      }
    } else if (operation == 'retrieve') {
      if (isHit) {
        metrics.hits++;
        if (sizeBytes != null) {
          metrics.bytesRetrieved += sizeBytes;
        }
      } else {
        metrics.misses++;
      }
    }
    
    metrics.lastAccess = DateTime.now();
  }
  
  void _recordLatency(String operation, Duration latency) {
    final latencies = _operationLatencies.putIfAbsent(operation, () => []);
    latencies.add(latency);
    
    // Keep only recent latencies (last 1000)
    if (latencies.length > 1000) {
      latencies.removeAt(0);
    }
  }
  
  void _addAccessRecord(CacheAccessRecord record) {
    _accessHistory.add(record);
    
    // Maintain history size
    while (_accessHistory.length > _maxHistorySize) {
      _accessHistory.removeFirst();
    }
  }
  
  Map<String, LatencyStats> _getLatencyStats() {
    final stats = <String, LatencyStats>{};
    
    _operationLatencies.forEach((operation, latencies) {
      if (latencies.isEmpty) return;
      
      final sorted = List<Duration>.from(latencies)
        ..sort((a, b) => a.compareTo(b));
      
      stats[operation] = LatencyStats(
        count: sorted.length,
        min: sorted.first,
        max: sorted.last,
        average: Duration(
          microseconds: sorted.fold(0, (sum, d) => sum + d.inMicroseconds) ~/ 
              sorted.length,
        ),
        p50: sorted[sorted.length ~/ 2],
        p90: sorted[(sorted.length * 0.9).floor()],
        p99: sorted[(sorted.length * 0.99).floor()],
      );
    });
    
    return stats;
  }
  
  Future<void> _loadPersistedMetrics() async {
    // Load persisted metrics from storage
    final data = await _storage.getString('cache_analytics_metrics');
    if (data != null) {
      // Parse and restore metrics
      // Implementation would deserialize the metrics
    }
  }
  
  Future<void> _persistMetrics() async {
    // Persist current metrics to storage
    final data = {
      'period_start': _periodStart.toIso8601String(),
      'total_hits': _totalHits,
      'total_misses': _totalMisses,
      'total_stores': _totalStores,
      'total_evictions': _totalEvictions,
      'total_bytes_stored': _totalBytesStored,
      'total_bytes_retrieved': _totalBytesRetrieved,
      'total_compression_saved': _totalCompressionSaved,
      // Add other metrics as needed
    };
    
    await _storage.setString('cache_analytics_metrics', data.toString());
  }
  
  String _generateJsonReport(
    CacheAnalyticsData analytics,
    List<CacheAccessRecord> history,
  ) {
    // Generate JSON report
    return '{}'; // Placeholder
  }
  
  String _generateCsvReport(
    CacheAnalyticsData analytics,
    List<CacheAccessRecord> history,
  ) {
    // Generate CSV report
    return ''; // Placeholder
  }
  
  String _generateTextReport(
    CacheAnalyticsData analytics,
    List<CacheAccessRecord> history,
  ) {
    // Generate text report
    return ''; // Placeholder
  }
}

/// Cache metrics for a specific key (provider or type)
class CacheMetrics {
  /// Key identifying the entry.
  final String key;
  /// Number of cache hits.
  int hits = 0;
  /// Number of cache misses.
  int misses = 0;
  /// Number of stores.
  int stores = 0;
  /// Bytes stored.
  int bytesStored = 0;
  /// Bytes retrieved.
  int bytesRetrieved = 0;
  /// When the key was last accessed, or null.
  DateTime? lastAccess;
  
  /// Creates a [CacheMetrics].
  CacheMetrics({required this.key});
  
  /// Hits divided by lookups, or 0 when there were none.
  double get hitRate {
    final total = hits + misses;
    return total > 0 ? hits / total : 0.0;
  }
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'hits': hits,
      'misses': misses,
      'stores': stores,
      'bytes_stored': bytesStored,
      'bytes_retrieved': bytesRetrieved,
      'hit_rate': hitRate,
      'last_access': lastAccess?.toIso8601String(),
    };
  }
}

/// Cache access record
class CacheAccessRecord {
  /// Kind of cached item.
  final String type;
  /// TTS provider that produced the audio.
  final String provider;
  /// Operation performed.
  final String operation;
  /// Size in bytes.
  final int? sizeBytes;
  /// When the object was created.
  final DateTime timestamp;
  /// Extra metadata for the entry.
  final Map<String, dynamic>? metadata;
  
  /// Creates a [CacheAccessRecord].
  const CacheAccessRecord({
    required this.type,
    required this.provider,
    required this.operation,
    this.sizeBytes,
    required this.timestamp,
    this.metadata,
  });
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'provider': provider,
      'operation': operation,
      'size_bytes': sizeBytes,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }
}

/// Cache analytics data
class CacheAnalyticsData {
  /// Start of the reporting period.
  final DateTime periodStart;
  /// Length of the reporting period.
  final Duration periodDuration;
  /// Hits in the period.
  final int totalHits;
  /// Misses in the period.
  final int totalMisses;
  /// Stores in the period.
  final int totalStores;
  /// Evictions in the period.
  final int totalEvictions;
  /// Bytes stored in the period.
  final int totalBytesStored;
  /// Bytes retrieved in the period.
  final int totalBytesRetrieved;
  /// Bytes saved by compression in the period.
  final int totalCompressionSaved;
  /// Hit rate across all lookups.
  final double overallHitRate;
  /// Compression ratio achieved.
  final double compressionRatio;
  /// Metrics per provider.
  final Map<String, CacheMetrics> providerMetrics;
  /// Metrics per item type.
  final Map<String, CacheMetrics> typeMetrics;
  /// Latency statistics per operation.
  final Map<String, LatencyStats> operationLatencies;
  /// Most recent access records.
  final List<CacheAccessRecord> recentAccess;
  
  /// Creates a [CacheAnalyticsData].
  const CacheAnalyticsData({
    required this.periodStart,
    required this.periodDuration,
    required this.totalHits,
    required this.totalMisses,
    required this.totalStores,
    required this.totalEvictions,
    required this.totalBytesStored,
    required this.totalBytesRetrieved,
    required this.totalCompressionSaved,
    required this.overallHitRate,
    required this.compressionRatio,
    required this.providerMetrics,
    required this.typeMetrics,
    required this.operationLatencies,
    required this.recentAccess,
  });
}

/// Latency statistics
class LatencyStats {
  /// Number of samples.
  final int count;
  /// Smallest sample.
  final Duration min;
  /// Largest sample.
  final Duration max;
  /// Mean of the samples.
  final Duration average;
  /// Median sample.
  final Duration p50;
  /// 90th percentile sample.
  final Duration p90;
  /// 99th percentile sample.
  final Duration p99;
  
  /// Creates a [LatencyStats].
  const LatencyStats({
    required this.count,
    required this.min,
    required this.max,
    required this.average,
    required this.p50,
    required this.p90,
    required this.p99,
  });
  
  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'count': count,
      'min_ms': min.inMilliseconds,
      'max_ms': max.inMilliseconds,
      'avg_ms': average.inMilliseconds,
      'p50_ms': p50.inMilliseconds,
      'p90_ms': p90.inMilliseconds,
      'p99_ms': p99.inMilliseconds,
    };
  }
}

/// Base analytics event
abstract class AnalyticsEvent {
  /// When the event was created.
  final DateTime timestamp = DateTime.now();
}

/// Cache store event
class CacheStoreEvent extends AnalyticsEvent {
  /// Kind of cached item.
  final String type;
  /// TTS provider that produced the audio.
  final String provider;
  /// Size in bytes.
  final int sizeBytes;
  /// Compression ratio achieved.
  final double compressionRatio;
  
  /// Creates the event.
  CacheStoreEvent({
    required this.type,
    required this.provider,
    required this.sizeBytes,
    required this.compressionRatio,
  });
}

/// Cache hit event
class CacheHitEvent extends AnalyticsEvent {
  /// Kind of cached item.
  final String type;
  /// TTS provider that produced the audio.
  final String provider;
  /// Hit rate.
  final double hitRate;
  
  /// Creates the event.
  CacheHitEvent({
    required this.type,
    required this.provider,
    required this.hitRate,
  });
}

/// Cache miss event
class CacheMissEvent extends AnalyticsEvent {
  /// Kind of cached item.
  final String type;
  /// TTS provider that produced the audio.
  final String provider;
  /// Hit rate.
  final double hitRate;
  
  /// Creates the event.
  CacheMissEvent({
    required this.type,
    required this.provider,
    required this.hitRate,
  });
}

/// Cache eviction event
class CacheEvictionEvent extends AnalyticsEvent {
  /// Why the eviction happened.
  final String reason;
  /// Number of items.
  final int itemCount;
  /// Bytes freed.
  final int bytesFreed;
  
  /// Creates the event.
  CacheEvictionEvent({
    required this.reason,
    required this.itemCount,
    required this.bytesFreed,
  });
}

/// Analytics update event
class AnalyticsUpdateEvent extends AnalyticsEvent {
  /// Hit rate.
  final double hitRate;
  /// Compression ratio achieved.
  final double compressionRatio;
  /// Total bytes.
  final int totalBytes;
  
  /// Creates the event.
  AnalyticsUpdateEvent({
    required this.hitRate,
    required this.compressionRatio,
    required this.totalBytes,
  });
}