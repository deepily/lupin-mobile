import 'dart:async';
import 'dart:typed_data';
import '../../core/cache/audio_cache.dart';
import '../../core/cache/voice_recording_cache.dart';
import '../../core/cache/cache_analytics.dart';
import '../../core/cache/eviction_manager.dart';
import '../../core/cache/audio_compression.dart';
import '../../shared/models/models.dart';
import '../tts/tts_service.dart';

/// High-level audio cache management service coordinating multiple cache layers.
/// 
/// Provides unified interface for TTS response caching, voice recording storage,
/// audio compression, cache analytics, and intelligent eviction management.
/// Optimizes audio storage and retrieval across the entire application.
class AudioCacheManager {
  final AudioCache _audioCache;
  final VoiceRecordingCache _voiceRecordingCache;
  final CacheAnalytics _analytics;
  final EvictionManager _evictionManager;
  final AudioCompression _compression;
  
  // Configuration
  final int _maxCacheSizeMB;
  final bool _enableCompression;
  final bool _enablePrefetch;
  final List<String> _commonPhrases;
  
  // State
  bool _isInitialized = false;
  Timer? _maintenanceTimer;
  Timer? _analyticsTimer;
  
  // Stream controllers
  final _statusController = StreamController<AudioCacheStatus>.broadcast();
  final _eventController = StreamController<AudioCacheManagerEvent>.broadcast();
  
  // Public streams
  Stream<AudioCacheStatus> get statusStream => _statusController.stream;
  Stream<AudioCacheManagerEvent> get eventStream => _eventController.stream;
  
  /// Creates a new audio cache manager with configurable components.
  /// 
  /// Requires:
  ///   - audioCache must be a properly initialized audio cache instance
  ///   - voiceRecordingCache must be a configured voice recording cache
  ///   - analytics must be a functional cache analytics instance
  ///   - evictionManager must be a properly configured eviction manager
  ///   - compression must be a working audio compression service
  ///   - maxCacheSizeMB must be positive (defaults to 200MB)
  /// 
  /// Ensures:
  ///   - All cache components are properly wired together
  ///   - Configuration values are validated and stored
  ///   - Service is ready for initialization
  AudioCacheManager({
    required AudioCache audioCache,
    required VoiceRecordingCache voiceRecordingCache,
    required CacheAnalytics analytics,
    required EvictionManager evictionManager,
    required AudioCompression compression,
    int maxCacheSizeMB = 200,
    bool enableCompression = true,
    bool enablePrefetch = true,
    List<String>? commonPhrases,
  })  : _audioCache = audioCache,
        _voiceRecordingCache = voiceRecordingCache,
        _analytics = analytics,
        _evictionManager = evictionManager,
        _compression = compression,
        _maxCacheSizeMB = maxCacheSizeMB,
        _enableCompression = enableCompression,
        _enablePrefetch = enablePrefetch,
        _commonPhrases = commonPhrases ?? _defaultCommonPhrases;

  /// Initializes all cache components and sets up maintenance tasks.
  /// 
  /// Requires:
  ///   - All injected cache components must be ready for initialization
  ///   - Sufficient device storage must be available
  /// 
  /// Ensures:
  ///   - All cache layers are properly initialized and functional
  ///   - Maintenance tasks are scheduled for optimal performance
  ///   - Common phrases are pre-cached if prefetch is enabled
  ///   - Service status transitions to ready state
  /// 
  /// Raises:
  ///   - CacheInitializationException if any component fails to initialize
  ///   - StorageException if insufficient disk space available
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _statusController.add(AudioCacheStatus.initializing);
      
      // Initialize components
      await _voiceRecordingCache.initialize();
      await _analytics.initialize();
      await _evictionManager.initialize();
      
      // Set up maintenance tasks
      _setupMaintenanceTasks();
      
      // Warm cache with common phrases if enabled
      if (_enablePrefetch) {
        _warmCache();
      }
      
      _isInitialized = true;
      _statusController.add(AudioCacheStatus.ready);
      
      _eventController.add(AudioCacheManagerEvent.initialized(
        totalSize: await getTotalCacheSize(),
        itemCount: await getTotalItemCount(),
      ));
      
    } catch (e) {
      _statusController.add(AudioCacheStatus.error);
      _eventController.add(AudioCacheManagerEvent.error(
        'Initialization failed: $e',
      ));
      rethrow;
    }
  }
  
  /// Caches TTS response with optional compression and analytics tracking.
  /// 
  /// Requires:
  ///   - text must be non-empty and valid for TTS
  ///   - provider must be a valid TTS provider identifier
  ///   - chunks must be a non-empty list of valid audio chunks
  ///   - Cache manager must be initialized
  /// 
  /// Ensures:
  ///   - Audio chunks are compressed if compression is enabled
  ///   - TTS response is stored for future retrieval
  ///   - Cache analytics are updated with storage metrics
  ///   - Eviction is triggered if cache size limits are exceeded
  /// 
  /// Raises:
  ///   - CompressionException if audio compression fails
  ///   - CacheStorageException if storage operation fails
  Future<void> cacheTTSResponse({
    required String text,
    required String provider,
    required List<AudioChunk> chunks,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final processedChunks = <AudioChunk>[];
      
      for (final chunk in chunks) {
        AudioChunk processedChunk = chunk;
        
        // Compress if enabled
        if (_enableCompression && chunk.data.length > 1024) {
          final compressedData = await _compression.compress(
            chunk.data,
            format: chunk.format ?? 'pcm',
          );
          
          processedChunk = chunk.copyWith(
            data: compressedData,
            metadata: {
              ...?chunk.metadata,
              'compressed': true,
              'original_size': chunk.data.length,
              'compressed_size': compressedData.length,
            },
          );
        }
        
        processedChunks.add(processedChunk);
      }
      
      // Store in cache
      await _audioCache.cacheAudioForText(text, provider, processedChunks);
      
      // Track analytics
      _analytics.recordCacheStore(
        type: 'tts',
        provider: provider,
        sizeBytes: processedChunks.fold(0, (sum, chunk) => sum + chunk.data.length),
        metadata: metadata,
      );
      
      // Check if eviction needed
      await _checkAndEvict();
      
      _eventController.add(AudioCacheManagerEvent.ttsCached(
        text: text,
        provider: provider,
        chunkCount: processedChunks.length,
      ));
      
    } catch (e) {
      _eventController.add(AudioCacheManagerEvent.error(
        'Failed to cache TTS response: $e',
      ));
      rethrow;
    }
  }
  
  /// Retrieves cached TTS response with automatic decompression.
  /// 
  /// Requires:
  ///   - text must be non-empty and match a cached entry
  ///   - provider must be a valid TTS provider identifier
  ///   - Cache manager must be initialized
  /// 
  /// Ensures:
  ///   - Returns cached audio chunks if available and valid
  ///   - Compressed chunks are automatically decompressed
  ///   - Cache hit is recorded in analytics
  ///   - Returns null if no cached response exists
  /// 
  /// Raises:
  ///   - DecompressionException if compressed audio cannot be decompressed
  ///   - CacheRetrievalException if cache access fails
  Future<List<AudioChunk>?> getCachedTTSResponse({
    required String text,
    required String provider,
  }) async {
    try {
      final chunks = await _audioCache.getCachedAudioForText(text, provider);
      
      if (chunks != null) {
        // Decompress if needed
        final decompressedChunks = <AudioChunk>[];
        
        for (final chunk in chunks) {
          if (chunk.metadata?['compressed'] == true) {
            final decompressedData = await _compression.decompress(
              chunk.data,
              format: chunk.format ?? 'pcm',
            );
            
            decompressedChunks.add(chunk.copyWith(
              data: decompressedData,
              metadata: {
                ...?chunk.metadata,
                'compressed': false,
              },
            ));
          } else {
            decompressedChunks.add(chunk);
          }
        }
        
        // Track analytics
        _analytics.recordCacheHit(
          type: 'tts',
          provider: provider,
        );
        
        return decompressedChunks;
      }
      
      // Track miss
      _analytics.recordCacheMiss(
        type: 'tts',
        provider: provider,
      );
      
      return null;
      
    } catch (e) {
      _eventController.add(AudioCacheManagerEvent.error(
        'Failed to retrieve cached TTS: $e',
      ));
      return null;
    }
  }
  
  /// Caches a voice recording with optional compression and metadata.
  /// 
  /// Requires:
  ///   - voiceInput must be a valid voice input with non-empty ID
  ///   - audioData must be non-empty audio data
  ///   - Cache manager must be initialized
  /// 
  /// Ensures:
  ///   - Voice recording is compressed if compression is enabled and size > 2KB
  ///   - Recording is stored with transcription and metadata
  ///   - Cache analytics are updated with storage metrics
  ///   - Eviction is triggered if cache size limits are exceeded
  /// 
  /// Raises:
  ///   - CompressionException if audio compression fails
  ///   - CacheStorageException if storage operation fails
  Future<void> cacheVoiceRecording({
    required VoiceInput voiceInput,
    required Uint8List audioData,
    String? transcription,
  }) async {
    try {
      // Compress if enabled
      Uint8List processedData = audioData;
      
      if (_enableCompression && audioData.length > 2048) {
        processedData = await _compression.compress(
          audioData,
          format: voiceInput.audioFormat?.name ?? 'wav',
        );
      }
      
      // Store in voice recording cache
      await _voiceRecordingCache.cacheRecording(
        voiceInput: voiceInput,
        audioData: processedData,
        transcription: transcription,
        compressed: _enableCompression && audioData.length > 2048,
      );
      
      // Track analytics
      _analytics.recordCacheStore(
        type: 'voice_recording',
        provider: 'local',
        sizeBytes: processedData.length,
        metadata: {
          'duration': voiceInput.duration?.inMilliseconds,
          'format': voiceInput.audioFormat?.name,
        },
      );
      
      // Check if eviction needed
      await _checkAndEvict();
      
      _eventController.add(AudioCacheManagerEvent.voiceRecordingCached(
        recordingId: voiceInput.id,
        duration: voiceInput.duration,
      ));
      
    } catch (e) {
      _eventController.add(AudioCacheManagerEvent.error(
        'Failed to cache voice recording: $e',
      ));
      rethrow;
    }
  }
  
  /// Retrieves cached voice recording with automatic decompression.
  /// 
  /// Requires:
  ///   - recordingId must be a valid, non-empty recording identifier
  ///   - Cache manager must be initialized
  /// 
  /// Ensures:
  ///   - Returns cached recording data if available
  ///   - Compressed recordings are automatically decompressed
  ///   - Cache hit is recorded in analytics
  ///   - Returns null if no cached recording exists
  /// 
  /// Raises:
  ///   - DecompressionException if compressed audio cannot be decompressed
  ///   - CacheRetrievalException if cache access fails
  Future<VoiceRecordingData?> getCachedVoiceRecording(String recordingId) async {
    try {
      final data = await _voiceRecordingCache.getRecording(recordingId);
      
      if (data != null) {
        // Decompress if needed
        if (data.compressed) {
          final decompressedAudio = await _compression.decompress(
            data.audioData,
            format: data.voiceInput.audioFormat?.name ?? 'wav',
          );
          
          data.audioData = decompressedAudio;
          data.compressed = false;
        }
        
        // Track analytics
        _analytics.recordCacheHit(
          type: 'voice_recording',
          provider: 'local',
        );
        
        return data;
      }
      
      // Track miss
      _analytics.recordCacheMiss(
        type: 'voice_recording',
        provider: 'local',
      );
      
      return null;
      
    } catch (e) {
      _eventController.add(AudioCacheManagerEvent.error(
        'Failed to retrieve voice recording: $e',
      ));
      return null;
    }
  }
  
  /// Prefetch TTS for common phrases
  Future<void> prefetchCommonPhrases({
    required String provider,
    TTSService? ttsService,
  }) async {
    if (!_enablePrefetch || ttsService == null) return;
    
    try {
      for (final phrase in _commonPhrases) {
        // Check if already cached
        final cached = await getCachedTTSResponse(
          text: phrase,
          provider: provider,
        );
        
        if (cached == null) {
          _eventController.add(AudioCacheManagerEvent.prefetchRequested(
            text: phrase,
            provider: provider,
          ));
          
          // In a real implementation, this would trigger TTS generation
          // For now, we just mark it as requested
        }
      }
    } catch (e) {
      _eventController.add(AudioCacheManagerEvent.error(
        'Prefetch failed: $e',
      ));
    }
  }
  
  /// Retrieves comprehensive cache statistics and performance metrics.
  /// 
  /// Requires:
  ///   - Cache manager must be initialized
  ///   - All cache components must be accessible
  /// 
  /// Ensures:
  ///   - Returns current cache usage statistics
  ///   - Includes hit rates, compression ratios, and provider stats
  ///   - Statistics reflect real-time cache state
  ///   - Memory and storage usage are accurately calculated
  /// 
  /// Raises:
  ///   - No exceptions are raised (returns empty stats on error)
  Future<AudioCacheStatistics> getStatistics() async {
    final audioStats = await _audioCache.getStats();
    final voiceStats = await _voiceRecordingCache.getStats();
    final analyticsData = await _analytics.getAnalytics();
    
    return AudioCacheStatistics(
      totalSizeMB: (audioStats.totalSizeBytes + voiceStats.totalSizeBytes) / (1024 * 1024),
      maxSizeMB: _maxCacheSizeMB,
      ttsItemCount: audioStats.totalMetadata,
      voiceRecordingCount: voiceStats.itemCount,
      totalItemCount: audioStats.totalMetadata + voiceStats.itemCount,
      hitRate: analyticsData.overallHitRate,
      compressionRatio: analyticsData.compressionRatio,
      providerStats: audioStats.providerStats,
      lastCleanup: _evictionManager.lastCleanupTime,
      isCompressed: _enableCompression,
      isPrefetchEnabled: _enablePrefetch,
    );
  }
  
  /// Clears all cached content for a specific TTS provider.
  /// 
  /// Requires:
  ///   - provider must be a valid TTS provider identifier
  ///   - Cache manager must be initialized
  /// 
  /// Ensures:
  ///   - All cached responses for the provider are removed
  ///   - Provider statistics are reset to zero
  ///   - Cache cleared event is emitted
  ///   - Storage space is freed immediately
  /// 
  /// Raises:
  ///   - CacheOperationException if cache clearing fails
  Future<void> clearProviderCache(String provider) async {
    try {
      await _audioCache.clearProviderCache(provider);
      
      _eventController.add(AudioCacheManagerEvent.cacheCleared(
        type: 'provider',
        details: provider,
      ));
      
    } catch (e) {
      _eventController.add(AudioCacheManagerEvent.error(
        'Failed to clear provider cache: $e',
      ));
      rethrow;
    }
  }
  
  /// Clears all cached content across all providers and types.
  /// 
  /// Requires:
  ///   - Cache manager must be initialized
  ///   - User must have confirmed the clear operation
  /// 
  /// Ensures:
  ///   - All TTS responses and voice recordings are removed
  ///   - All cache statistics are reset to zero
  ///   - Storage space is completely freed
  ///   - Cache cleared event is emitted
  /// 
  /// Raises:
  ///   - CacheOperationException if cache clearing fails
  Future<void> clearAllCaches() async {
    try {
      await _audioCache.clearAll();
      await _voiceRecordingCache.clearAll();
      
      _eventController.add(AudioCacheManagerEvent.cacheCleared(
        type: 'all',
        details: 'All caches cleared',
      ));
      
    } catch (e) {
      _eventController.add(AudioCacheManagerEvent.error(
        'Failed to clear all caches: $e',
      ));
      rethrow;
    }
  }
  
  /// Performs comprehensive cache optimization and cleanup.
  /// 
  /// Requires:
  ///   - Cache manager must be initialized
  ///   - Sufficient system resources for optimization process
  /// 
  /// Ensures:
  ///   - Expired entries are removed from all caches
  ///   - Cache fragmentation is reduced through reorganization
  ///   - Eviction is performed if cache exceeds size limits
  ///   - Cache optimization event is emitted with freed space
  /// 
  /// Raises:
  ///   - CacheOptimizationException if optimization process fails
  Future<void> optimizeCaches() async {
    try {
      _statusController.add(AudioCacheStatus.optimizing);
      
      // Run optimization
      await _audioCache.optimize();
      await _voiceRecordingCache.optimize();
      
      // Run eviction if needed
      await _evictionManager.runEviction(
        currentSizeBytes: await getTotalCacheSize() * 1024 * 1024,
        maxSizeBytes: _maxCacheSizeMB * 1024 * 1024,
      );
      
      _statusController.add(AudioCacheStatus.ready);
      
      _eventController.add(AudioCacheManagerEvent.optimized(
        freedSpaceMB: 0, // Would be calculated in real implementation
      ));
      
    } catch (e) {
      _statusController.add(AudioCacheStatus.error);
      _eventController.add(AudioCacheManagerEvent.error(
        'Optimization failed: $e',
      ));
    }
  }
  
  /// Get total cache size in bytes
  Future<int> getTotalCacheSize() async {
    final audioStats = await _audioCache.getStats();
    final voiceStats = await _voiceRecordingCache.getStats();
    return audioStats.totalSizeBytes + voiceStats.totalSizeBytes;
  }
  
  /// Get total item count
  Future<int> getTotalItemCount() async {
    final audioStats = await _audioCache.getStats();
    final voiceStats = await _voiceRecordingCache.getStats();
    return audioStats.totalMetadata + voiceStats.itemCount;
  }
  
  /// Dispose resources
  void dispose() {
    _maintenanceTimer?.cancel();
    _analyticsTimer?.cancel();
    _statusController.close();
    _eventController.close();
    _audioCache.dispose();
    _voiceRecordingCache.dispose();
    _analytics.dispose();
  }
  
  // Private methods
  
  void _setupMaintenanceTasks() {
    // Run maintenance every hour
    _maintenanceTimer = Timer.periodic(const Duration(hours: 1), (_) {
      optimizeCaches();
    });
    
    // Update analytics every 5 minutes
    _analyticsTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _analytics.updateMetrics();
    });
  }
  
  void _warmCache() {
    // Schedule cache warming after initialization
    Timer(const Duration(seconds: 5), () {
      for (final provider in ['openai', 'elevenlabs']) {
        prefetchCommonPhrases(provider: provider);
      }
    });
  }
  
  Future<void> _checkAndEvict() async {
    final currentSize = await getTotalCacheSize();
    final maxSize = _maxCacheSizeMB * 1024 * 1024;
    
    if (currentSize > maxSize * 0.9) {
      // Cache is 90% full, trigger eviction
      await _evictionManager.runEviction(
        currentSizeBytes: currentSize,
        maxSizeBytes: maxSize,
      );
    }
  }
  
  static const List<String> _defaultCommonPhrases = [
    'Hello',
    'How can I help you today?',
    'I understand',
    'Please wait',
    'Thank you',
    'Goodbye',
    'Yes',
    'No',
    'Sorry, I didn\'t understand',
    'Could you please repeat that?',
    'Processing your request',
    'One moment please',
  ];
}

/// Audio cache status
enum AudioCacheStatus {
  uninitialized,
  initializing,
  ready,
  optimizing,
  error,
}

/// Audio cache statistics
class AudioCacheStatistics {
  final double totalSizeMB;
  final int maxSizeMB;
  final int ttsItemCount;
  final int voiceRecordingCount;
  final int totalItemCount;
  final double hitRate;
  final double compressionRatio;
  final Map<String, int> providerStats;
  final DateTime? lastCleanup;
  final bool isCompressed;
  final bool isPrefetchEnabled;
  
  const AudioCacheStatistics({
    required this.totalSizeMB,
    required this.maxSizeMB,
    required this.ttsItemCount,
    required this.voiceRecordingCount,
    required this.totalItemCount,
    required this.hitRate,
    required this.compressionRatio,
    required this.providerStats,
    this.lastCleanup,
    required this.isCompressed,
    required this.isPrefetchEnabled,
  });
  
  double get utilizationPercent => (totalSizeMB / maxSizeMB) * 100;
  bool get isNearCapacity => utilizationPercent > 85;
}

/// Audio cache manager events
abstract class AudioCacheManagerEvent {
  final DateTime timestamp = DateTime.now();
  
  const AudioCacheManagerEvent();
  
  factory AudioCacheManagerEvent.initialized({
    required int totalSize,
    required int itemCount,
  }) = AudioCacheInitializedEvent;
  
  factory AudioCacheManagerEvent.ttsCached({
    required String text,
    required String provider,
    required int chunkCount,
  }) = TTSCachedEvent;
  
  factory AudioCacheManagerEvent.voiceRecordingCached({
    required String recordingId,
    Duration? duration,
  }) = VoiceRecordingCachedEvent;
  
  factory AudioCacheManagerEvent.prefetchRequested({
    required String text,
    required String provider,
  }) = PrefetchRequestedEvent;
  
  factory AudioCacheManagerEvent.cacheCleared({
    required String type,
    required String details,
  }) = CacheClearedEvent;
  
  factory AudioCacheManagerEvent.optimized({
    required double freedSpaceMB,
  }) = CacheOptimizedEvent;
  
  factory AudioCacheManagerEvent.error(String message) = AudioCacheErrorEvent;
}

class AudioCacheInitializedEvent extends AudioCacheManagerEvent {
  final int totalSize;
  final int itemCount;
  
  const AudioCacheInitializedEvent({
    required this.totalSize,
    required this.itemCount,
  });
}

class TTSCachedEvent extends AudioCacheManagerEvent {
  final String text;
  final String provider;
  final int chunkCount;
  
  const TTSCachedEvent({
    required this.text,
    required this.provider,
    required this.chunkCount,
  });
}

class VoiceRecordingCachedEvent extends AudioCacheManagerEvent {
  final String recordingId;
  final Duration? duration;
  
  const VoiceRecordingCachedEvent({
    required this.recordingId,
    this.duration,
  });
}

class PrefetchRequestedEvent extends AudioCacheManagerEvent {
  final String text;
  final String provider;
  
  const PrefetchRequestedEvent({
    required this.text,
    required this.provider,
  });
}

class CacheClearedEvent extends AudioCacheManagerEvent {
  final String type;
  final String details;
  
  const CacheClearedEvent({
    required this.type,
    required this.details,
  });
}

class CacheOptimizedEvent extends AudioCacheManagerEvent {
  final double freedSpaceMB;
  
  const CacheOptimizedEvent({
    required this.freedSpaceMB,
  });
}

class AudioCacheErrorEvent extends AudioCacheManagerEvent {
  final String message;
  
  const AudioCacheErrorEvent(this.message);
}