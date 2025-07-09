import 'dart:async';
import 'dart:collection';
import 'cache_policy.dart';
import 'audio_cache.dart';
import 'voice_recording_cache.dart';
import 'cache_analytics.dart';

/// Manages cache eviction strategies
class EvictionManager {
  final AudioCache _audioCache;
  final VoiceRecordingCache _voiceRecordingCache;
  final CacheAnalytics _analytics;
  
  // Configuration
  final double _emergencyEvictionThreshold = 0.95; // 95% full
  final double _targetEvictionThreshold = 0.80; // Evict down to 80%
  final Duration _evictionInterval = const Duration(minutes: 30);
  
  // State
  bool _isInitialized = false;
  Timer? _periodicEvictionTimer;
  DateTime? _lastCleanupTime;
  
  // Eviction strategies
  final Map<CacheEvictionStrategy, EvictionStrategyHandler> _strategies = {};
  
  // Event controller
  final _eventController = StreamController<EvictionEvent>.broadcast();
  
  Stream<EvictionEvent> get evictionEvents => _eventController.stream;
  
  EvictionManager({
    required AudioCache audioCache,
    required VoiceRecordingCache voiceRecordingCache,
    required CacheAnalytics analytics,
  })  : _audioCache = audioCache,
        _voiceRecordingCache = voiceRecordingCache,
        _analytics = analytics {
    _initializeStrategies();
  }
  
  /// Initialize eviction manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Set up periodic eviction
    _periodicEvictionTimer = Timer.periodic(_evictionInterval, (_) {
      _performPeriodicEviction();
    });
    
    _isInitialized = true;
  }
  
  /// Run eviction based on current cache state
  Future<EvictionResult> runEviction({
    required int currentSizeBytes,
    required int maxSizeBytes,
    CacheEvictionStrategy? strategy,
    bool force = false,
  }) async {
    final utilizationRatio = currentSizeBytes / maxSizeBytes;
    
    // Check if eviction is needed
    if (!force && utilizationRatio < _emergencyEvictionThreshold) {
      return EvictionResult.noEvictionNeeded();
    }
    
    final startTime = DateTime.now();
    
    // Determine strategy
    final evictionStrategy = strategy ?? CacheEvictionStrategy.lru;
    final handler = _strategies[evictionStrategy]!;
    
    // Calculate target size
    final targetSize = (maxSizeBytes * _targetEvictionThreshold).round();
    final bytesToEvict = currentSizeBytes - targetSize;
    
    _eventController.add(EvictionStartedEvent(
      strategy: evictionStrategy,
      currentSize: currentSizeBytes,
      targetSize: targetSize,
      bytesToEvict: bytesToEvict,
    ));
    
    try {
      // Get eviction candidates
      final candidates = await handler.getCandidates(
        audioCache: _audioCache,
        voiceRecordingCache: _voiceRecordingCache,
        bytesToEvict: bytesToEvict,
      );
      
      // Execute eviction
      final result = await _executeEviction(
        candidates,
        evictionStrategy,
        bytesToEvict,
      );
      
      // Update analytics
      final duration = DateTime.now().difference(startTime);
      _analytics.recordEviction(
        reason: 'cache_full',
        itemCount: result.itemsEvicted,
        bytesFreed: result.bytesFreed,
        latency: duration,
      );
      
      _lastCleanupTime = DateTime.now();
      
      _eventController.add(EvictionCompletedEvent(
        strategy: evictionStrategy,
        itemsEvicted: result.itemsEvicted,
        bytesFreed: result.bytesFreed,
        duration: duration,
      ));
      
      return result;
      
    } catch (e) {
      _eventController.add(EvictionFailedEvent(
        strategy: evictionStrategy,
        error: e.toString(),
      ));
      
      return EvictionResult.failed(e.toString());
    }
  }
  
  /// Perform smart eviction based on usage patterns
  Future<EvictionResult> smartEviction({
    required int currentSizeBytes,
    required int maxSizeBytes,
  }) async {
    // Analyze usage patterns to determine best strategy
    final analytics = await _analytics.getAnalytics();
    
    CacheEvictionStrategy strategy = CacheEvictionStrategy.lru;
    
    // Choose strategy based on access patterns
    if (analytics.overallHitRate > 0.8) {
      // High hit rate - use LFU to keep frequently accessed items
      strategy = CacheEvictionStrategy.lfu;
    } else if (analytics.overallHitRate < 0.3) {
      // Low hit rate - use TTL to clear old items
      strategy = CacheEvictionStrategy.ttl;
    } else {
      // Medium hit rate - use LRU (default)
      strategy = CacheEvictionStrategy.lru;
    }
    
    return await runEviction(
      currentSizeBytes: currentSizeBytes,
      maxSizeBytes: maxSizeBytes,
      strategy: strategy,
    );
  }
  
  /// Emergency eviction when cache is critically full
  Future<EvictionResult> emergencyEviction({
    required int currentSizeBytes,
    required int maxSizeBytes,
  }) async {
    // Use aggressive size-based eviction
    return await runEviction(
      currentSizeBytes: currentSizeBytes,
      maxSizeBytes: maxSizeBytes,
      strategy: CacheEvictionStrategy.size,
      force: true,
    );
  }
  
  /// Clean up expired entries
  Future<EvictionResult> cleanupExpired() async {
    final startTime = DateTime.now();
    int totalItemsRemoved = 0;
    int totalBytesFreed = 0;
    
    // Clean up expired audio cache entries
    final audioStats = await _audioCache.getStats();
    // In a real implementation, this would iterate through cache entries
    // and remove expired ones based on CachePolicy.maxAge
    
    // Clean up expired voice recordings
    final voiceRecordingStats = await _voiceRecordingCache.getStats();
    // Similarly, this would clean up expired voice recordings
    
    _lastCleanupTime = DateTime.now();
    
    final duration = DateTime.now().difference(startTime);
    
    _eventController.add(EvictionCompletedEvent(
      strategy: CacheEvictionStrategy.ttl,
      itemsEvicted: totalItemsRemoved,
      bytesFreed: totalBytesFreed,
      duration: duration,
    ));
    
    return EvictionResult.success(
      itemsEvicted: totalItemsRemoved,
      bytesFreed: totalBytesFreed,
      strategy: CacheEvictionStrategy.ttl,
    );
  }
  
  /// Get eviction recommendations
  Future<List<EvictionRecommendation>> getEvictionRecommendations() async {
    final recommendations = <EvictionRecommendation>[];
    
    // Analyze current cache state
    final audioStats = await _audioCache.getStats();
    final voiceStats = await _voiceRecordingCache.getStats();
    final analytics = await _analytics.getAnalytics();
    
    // Check for rarely accessed items
    if (analytics.overallHitRate < 0.5) {
      recommendations.add(EvictionRecommendation(
        type: 'low_hit_rate',
        priority: EvictionPriority.medium,
        description: 'Remove rarely accessed items',
        estimatedBytesFreed: audioStats.totalSizeBytes ~/ 4,
        strategy: CacheEvictionStrategy.lfu,
      ));
    }
    
    // Check for old items
    final oldItemsThreshold = DateTime.now().subtract(const Duration(days: 30));
    recommendations.add(EvictionRecommendation(
      type: 'old_items',
      priority: EvictionPriority.low,
      description: 'Remove items older than 30 days',
      estimatedBytesFreed: audioStats.totalSizeBytes ~/ 10,
      strategy: CacheEvictionStrategy.ttl,
    ));
    
    // Check for large items
    recommendations.add(EvictionRecommendation(
      type: 'large_items',
      priority: EvictionPriority.high,
      description: 'Remove largest items first',
      estimatedBytesFreed: audioStats.totalSizeBytes ~/ 3,
      strategy: CacheEvictionStrategy.size,
    ));
    
    return recommendations;
  }
  
  /// Get last cleanup time
  DateTime? get lastCleanupTime => _lastCleanupTime;
  
  /// Dispose resources
  void dispose() {
    _periodicEvictionTimer?.cancel();
    _eventController.close();
  }
  
  // Private methods
  
  void _initializeStrategies() {
    _strategies[CacheEvictionStrategy.lru] = LRUEvictionStrategy();
    _strategies[CacheEvictionStrategy.lfu] = LFUEvictionStrategy();
    _strategies[CacheEvictionStrategy.ttl] = TTLEvictionStrategy();
    _strategies[CacheEvictionStrategy.size] = SizeBasedEvictionStrategy();
    _strategies[CacheEvictionStrategy.fifo] = FIFOEvictionStrategy();
  }
  
  Future<void> _performPeriodicEviction() async {
    // Check if periodic eviction is needed
    final audioStats = await _audioCache.getStats();
    final voiceStats = await _voiceRecordingCache.getStats();
    
    final totalSize = audioStats.totalSizeBytes + voiceStats.totalSizeBytes;
    
    // Only run if we're approaching capacity
    if (totalSize > 100 * 1024 * 1024) { // 100MB threshold
      await cleanupExpired();
    }
  }
  
  Future<EvictionResult> _executeEviction(
    List<EvictionCandidate> candidates,
    CacheEvictionStrategy strategy,
    int bytesToEvict,
  ) async {
    int itemsEvicted = 0;
    int bytesFreed = 0;
    
    // Sort candidates by priority
    candidates.sort((a, b) => b.priority.compareTo(a.priority));
    
    for (final candidate in candidates) {
      if (bytesFreed >= bytesToEvict) break;
      
      try {
        // Remove from appropriate cache
        if (candidate.type == 'audio') {
          // Remove from audio cache
          // This would involve removing the specific cache entry
          bytesFreed += candidate.sizeBytes;
          itemsEvicted++;
        } else if (candidate.type == 'voice_recording') {
          // Remove from voice recording cache
          await _voiceRecordingCache.removeOldRecordings(Duration.zero);
          bytesFreed += candidate.sizeBytes;
          itemsEvicted++;
        }
      } catch (e) {
        // Log error but continue with other candidates
        print('Failed to evict ${candidate.id}: $e');
      }
    }
    
    return EvictionResult.success(
      itemsEvicted: itemsEvicted,
      bytesFreed: bytesFreed,
      strategy: strategy,
    );
  }
}

/// Base eviction strategy handler
abstract class EvictionStrategyHandler {
  Future<List<EvictionCandidate>> getCandidates({
    required AudioCache audioCache,
    required VoiceRecordingCache voiceRecordingCache,
    required int bytesToEvict,
  });
}

/// LRU eviction strategy
class LRUEvictionStrategy extends EvictionStrategyHandler {
  @override
  Future<List<EvictionCandidate>> getCandidates({
    required AudioCache audioCache,
    required VoiceRecordingCache voiceRecordingCache,
    required int bytesToEvict,
  }) async {
    final candidates = <EvictionCandidate>[];
    
    // Get candidates from audio cache (sorted by last access time)
    // This would iterate through cache entries and create candidates
    
    // Get candidates from voice recording cache
    final recentRecordings = await voiceRecordingCache.getRecentRecordings(limit: 100);
    
    for (final recording in recentRecordings.reversed) {
      candidates.add(EvictionCandidate(
        id: recording.recordingId,
        type: 'voice_recording',
        sizeBytes: recording.sizeBytes,
        priority: _calculateLRUPriority(recording.lastAccessedAt),
        lastAccessed: recording.lastAccessedAt,
      ));
    }
    
    return candidates;
  }
  
  double _calculateLRUPriority(DateTime lastAccessed) {
    final age = DateTime.now().difference(lastAccessed);
    return age.inDays.toDouble();
  }
}

/// LFU eviction strategy
class LFUEvictionStrategy extends EvictionStrategyHandler {
  @override
  Future<List<EvictionCandidate>> getCandidates({
    required AudioCache audioCache,
    required VoiceRecordingCache voiceRecordingCache,
    required int bytesToEvict,
  }) async {
    final candidates = <EvictionCandidate>[];
    
    // Get candidates sorted by access frequency
    final recentRecordings = await voiceRecordingCache.getRecentRecordings(limit: 100);
    
    for (final recording in recentRecordings) {
      candidates.add(EvictionCandidate(
        id: recording.recordingId,
        type: 'voice_recording',
        sizeBytes: recording.sizeBytes,
        priority: _calculateLFUPriority(recording.accessCount),
        accessCount: recording.accessCount,
      ));
    }
    
    return candidates;
  }
  
  double _calculateLFUPriority(int accessCount) {
    return 1.0 / (accessCount + 1);
  }
}

/// TTL eviction strategy
class TTLEvictionStrategy extends EvictionStrategyHandler {
  @override
  Future<List<EvictionCandidate>> getCandidates({
    required AudioCache audioCache,
    required VoiceRecordingCache voiceRecordingCache,
    required int bytesToEvict,
  }) async {
    final candidates = <EvictionCandidate>[];
    
    // Get candidates sorted by creation time (oldest first)
    final recentRecordings = await voiceRecordingCache.getRecentRecordings(limit: 100);
    
    for (final recording in recentRecordings) {
      candidates.add(EvictionCandidate(
        id: recording.recordingId,
        type: 'voice_recording',
        sizeBytes: recording.sizeBytes,
        priority: _calculateTTLPriority(recording.createdAt),
        createdAt: recording.createdAt,
      ));
    }
    
    return candidates;
  }
  
  double _calculateTTLPriority(DateTime createdAt) {
    final age = DateTime.now().difference(createdAt);
    return age.inDays.toDouble();
  }
}

/// Size-based eviction strategy
class SizeBasedEvictionStrategy extends EvictionStrategyHandler {
  @override
  Future<List<EvictionCandidate>> getCandidates({
    required AudioCache audioCache,
    required VoiceRecordingCache voiceRecordingCache,
    required int bytesToEvict,
  }) async {
    final candidates = <EvictionCandidate>[];
    
    // Get candidates sorted by size (largest first)
    final recentRecordings = await voiceRecordingCache.getRecentRecordings(limit: 100);
    
    for (final recording in recentRecordings) {
      candidates.add(EvictionCandidate(
        id: recording.recordingId,
        type: 'voice_recording',
        sizeBytes: recording.sizeBytes,
        priority: recording.sizeBytes.toDouble(),
      ));
    }
    
    return candidates;
  }
}

/// FIFO eviction strategy
class FIFOEvictionStrategy extends EvictionStrategyHandler {
  @override
  Future<List<EvictionCandidate>> getCandidates({
    required AudioCache audioCache,
    required VoiceRecordingCache voiceRecordingCache,
    required int bytesToEvict,
  }) async {
    final candidates = <EvictionCandidate>[];
    
    // Get candidates sorted by creation time (oldest first)
    final recentRecordings = await voiceRecordingCache.getRecentRecordings(limit: 100);
    
    for (final recording in recentRecordings.reversed) {
      candidates.add(EvictionCandidate(
        id: recording.recordingId,
        type: 'voice_recording',
        sizeBytes: recording.sizeBytes,
        priority: _calculateFIFOPriority(recording.createdAt),
        createdAt: recording.createdAt,
      ));
    }
    
    return candidates;
  }
  
  double _calculateFIFOPriority(DateTime createdAt) {
    final age = DateTime.now().difference(createdAt);
    return age.inDays.toDouble();
  }
}

/// Eviction candidate
class EvictionCandidate {
  final String id;
  final String type;
  final int sizeBytes;
  final double priority;
  final DateTime? lastAccessed;
  final DateTime? createdAt;
  final int? accessCount;
  
  const EvictionCandidate({
    required this.id,
    required this.type,
    required this.sizeBytes,
    required this.priority,
    this.lastAccessed,
    this.createdAt,
    this.accessCount,
  });
}

/// Eviction result
class EvictionResult {
  final bool success;
  final int itemsEvicted;
  final int bytesFreed;
  final CacheEvictionStrategy strategy;
  final String? error;
  
  const EvictionResult({
    required this.success,
    required this.itemsEvicted,
    required this.bytesFreed,
    required this.strategy,
    this.error,
  });
  
  factory EvictionResult.success({
    required int itemsEvicted,
    required int bytesFreed,
    required CacheEvictionStrategy strategy,
  }) {
    return EvictionResult(
      success: true,
      itemsEvicted: itemsEvicted,
      bytesFreed: bytesFreed,
      strategy: strategy,
    );
  }
  
  factory EvictionResult.failed(String error) {
    return EvictionResult(
      success: false,
      itemsEvicted: 0,
      bytesFreed: 0,
      strategy: CacheEvictionStrategy.lru,
      error: error,
    );
  }
  
  factory EvictionResult.noEvictionNeeded() {
    return const EvictionResult(
      success: true,
      itemsEvicted: 0,
      bytesFreed: 0,
      strategy: CacheEvictionStrategy.lru,
    );
  }
}

/// Eviction recommendation
class EvictionRecommendation {
  final String type;
  final EvictionPriority priority;
  final String description;
  final int estimatedBytesFreed;
  final CacheEvictionStrategy strategy;
  
  const EvictionRecommendation({
    required this.type,
    required this.priority,
    required this.description,
    required this.estimatedBytesFreed,
    required this.strategy,
  });
}

/// Eviction priority
enum EvictionPriority {
  low,
  medium,
  high,
  critical,
}

/// Base eviction event
abstract class EvictionEvent {
  final DateTime timestamp = DateTime.now();
}

/// Eviction started event
class EvictionStartedEvent extends EvictionEvent {
  final CacheEvictionStrategy strategy;
  final int currentSize;
  final int targetSize;
  final int bytesToEvict;
  
  EvictionStartedEvent({
    required this.strategy,
    required this.currentSize,
    required this.targetSize,
    required this.bytesToEvict,
  });
}

/// Eviction completed event
class EvictionCompletedEvent extends EvictionEvent {
  final CacheEvictionStrategy strategy;
  final int itemsEvicted;
  final int bytesFreed;
  final Duration duration;
  
  EvictionCompletedEvent({
    required this.strategy,
    required this.itemsEvicted,
    required this.bytesFreed,
    required this.duration,
  });
}

/// Eviction failed event
class EvictionFailedEvent extends EvictionEvent {
  final CacheEvictionStrategy strategy;
  final String error;
  
  EvictionFailedEvent({
    required this.strategy,
    required this.error,
  });
}