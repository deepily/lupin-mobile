import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../shared/models/models.dart';
import '../storage/storage_manager.dart';
import 'cache_manager.dart';
import 'cache_policy.dart';
import 'offline_manager.dart';

/// Specialized cache for audio data
class AudioCache {
  static AudioCache? _instance;
  late final CacheManager<AudioChunk> _chunkCache;
  late final CacheManager<AudioMetadata> _metadataCache;
  late final OfflineManager _offlineManager;
  
  final StreamController<AudioCacheEvent> _eventController = 
      StreamController<AudioCacheEvent>.broadcast();

  AudioCache._(OfflineManager offlineManager) : _offlineManager = offlineManager {
    _initialize();
  }

  /// Get singleton instance
  static Future<AudioCache> getInstance() async {
    if (_instance == null) {
      final offlineManager = await OfflineManager.getInstance();
      _instance = AudioCache._(offlineManager);
    }
    return _instance!;
  }

  /// Initialize audio cache
  void _initialize() {
    _chunkCache = _offlineManager.getCacheManager<AudioChunk>(
      cacheKey: 'audio_chunks',
      toJson: (chunk) => chunk.toJson(),
      fromJson: (json) => AudioChunk.fromJson(json),
      policy: CachePolicy.audio,
      calculateSize: (chunk) => chunk.metadata?['size_bytes'] ?? 0,
    );
    
    _metadataCache = _offlineManager.getCacheManager<AudioMetadata>(
      cacheKey: 'audio_metadata',
      toJson: (metadata) => metadata.toJson(),
      fromJson: (json) => AudioMetadata.fromJson(json),
      policy: CachePolicy.longLived,
    );
  }

  /// Cache audio chunks for text
  Future<void> cacheAudioForText(
    String text,
    String provider,
    List<AudioChunk> chunks,
  ) async {
    final textHash = _hashText(text);
    final cacheKey = '${provider}_$textHash';
    
    // Cache metadata
    final metadata = AudioMetadata(
      textHash: textHash,
      originalText: text,
      provider: provider,
      chunkCount: chunks.length,
      totalDuration: chunks.fold(
        Duration.zero,
        (sum, chunk) => sum + (chunk.duration ?? Duration.zero),
      ),
      createdAt: DateTime.now(),
      lastAccessedAt: DateTime.now(),
    );
    
    await _metadataCache.put(cacheKey, metadata);
    
    // Cache individual chunks
    for (int i = 0; i < chunks.length; i++) {
      final chunkKey = '${cacheKey}_chunk_$i';
      await _chunkCache.put(chunkKey, chunks[i]);
    }
    
    _eventController.add(AudioCacheStoreEvent(text, provider, chunks.length));
  }

  /// Get cached audio for text
  Future<List<AudioChunk>?> getCachedAudioForText(
    String text,
    String provider,
  ) async {
    final textHash = _hashText(text);
    final cacheKey = '${provider}_$textHash';
    
    // Check if metadata exists
    final metadata = await _metadataCache.get(cacheKey);
    if (metadata == null) {
      _eventController.add(AudioCacheMissEvent(text, provider));
      return null;
    }
    
    // Load chunks
    final chunks = <AudioChunk>[];
    for (int i = 0; i < metadata.chunkCount; i++) {
      final chunkKey = '${cacheKey}_chunk_$i';
      final chunk = await _chunkCache.get(chunkKey);
      if (chunk == null) {
        _eventController.add(AudioCacheMissEvent(text, provider));
        return null;
      }
      chunks.add(chunk);
    }
    
    // Update metadata access time
    final updatedMetadata = metadata.copyWith(
      lastAccessedAt: DateTime.now(),
      accessCount: metadata.accessCount + 1,
    );
    await _metadataCache.put(cacheKey, updatedMetadata);
    
    _eventController.add(AudioCacheHitEvent(text, provider, chunks.length));
    return chunks;
  }

  /// Pre-cache common phrases
  Future<void> precacheCommonPhrases(
    List<String> phrases,
    String provider,
  ) async {
    for (final phrase in phrases) {
      final cached = await getCachedAudioForText(phrase, provider);
      if (cached == null) {
        // Add to precache queue - in real implementation, this would
        // trigger TTS generation
        _eventController.add(AudioPrecacheRequestEvent(phrase, provider));
      }
    }
  }

  /// Get cache statistics
  Future<AudioCacheStats> getStats() async {
    final chunkStats = _chunkCache.getStats();
    final metadataStats = _metadataCache.getStats();
    
    // Count by provider
    final providerStats = <String, int>{};
    final metadataKeys = _metadataCache.memoryCache.keys;
    
    for (final key in metadataKeys) {
      final parts = key.split('_');
      if (parts.isNotEmpty) {
        final provider = parts[0];
        providerStats[provider] = (providerStats[provider] ?? 0) + 1;
      }
    }
    
    return AudioCacheStats(
      totalChunks: chunkStats.itemCount,
      totalMetadata: metadataStats.itemCount,
      totalSizeBytes: chunkStats.totalSizeBytes,
      providerStats: providerStats,
      chunkHitRate: chunkStats.hitRate,
      metadataHitRate: metadataStats.hitRate,
    );
  }

  /// Clear cache for specific provider
  Future<void> clearProviderCache(String provider) async {
    // Find all entries for this provider
    final metadataKeys = _metadataCache.memoryCache.keys
        .where((key) => key.startsWith('${provider}_'))
        .toList();
    
    int removedCount = 0;
    
    for (final key in metadataKeys) {
      final metadata = await _metadataCache.get(key);
      if (metadata != null) {
        // Remove chunks
        for (int i = 0; i < metadata.chunkCount; i++) {
          final chunkKey = '${key}_chunk_$i';
          await _chunkCache.remove(chunkKey);
        }
        
        // Remove metadata
        await _metadataCache.remove(key);
        removedCount++;
      }
    }
    
    _eventController.add(AudioCacheClearEvent(provider, removedCount));
  }

  /// Clear all cached audio
  Future<void> clearAll() async {
    await _chunkCache.clear();
    await _metadataCache.clear();
    _eventController.add(AudioCacheClearEvent('all', 0));
  }

  /// Get cached phrases for provider
  Future<List<String>> getCachedPhrases(String provider) async {
    final phrases = <String>[];
    final metadataKeys = _metadataCache.memoryCache.keys
        .where((key) => key.startsWith('${provider}_'));
    
    for (final key in metadataKeys) {
      final metadata = await _metadataCache.get(key);
      if (metadata != null) {
        phrases.add(metadata.originalText);
      }
    }
    
    return phrases;
  }

  /// Optimize cache (remove duplicates, compress)
  Future<void> optimize() async {
    // This would implement cache optimization logic
    // For now, just cleanup expired entries
    await _chunkCache.cleanup();
    await _metadataCache.cleanup();
    
    _eventController.add(AudioCacheOptimizeEvent());
  }

  /// Stream of audio cache events
  Stream<AudioCacheEvent> get events => _eventController.stream;

  /// Dispose resources
  void dispose() {
    _eventController.close();
  }

  // Private helper methods
  String _hashText(String text) {
    final bytes = utf8.encode(text.toLowerCase().trim());
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}

/// Audio metadata for caching
class AudioMetadata {
  final String textHash;
  final String originalText;
  final String provider;
  final int chunkCount;
  final Duration totalDuration;
  final DateTime createdAt;
  final DateTime lastAccessedAt;
  final int accessCount;

  const AudioMetadata({
    required this.textHash,
    required this.originalText,
    required this.provider,
    required this.chunkCount,
    required this.totalDuration,
    required this.createdAt,
    required this.lastAccessedAt,
    this.accessCount = 0,
  });

  AudioMetadata copyWith({
    String? textHash,
    String? originalText,
    String? provider,
    int? chunkCount,
    Duration? totalDuration,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
    int? accessCount,
  }) {
    return AudioMetadata(
      textHash: textHash ?? this.textHash,
      originalText: originalText ?? this.originalText,
      provider: provider ?? this.provider,
      chunkCount: chunkCount ?? this.chunkCount,
      totalDuration: totalDuration ?? this.totalDuration,
      createdAt: createdAt ?? this.createdAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      accessCount: accessCount ?? this.accessCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text_hash': textHash,
      'original_text': originalText,
      'provider': provider,
      'chunk_count': chunkCount,
      'total_duration': totalDuration.inMilliseconds,
      'created_at': createdAt.toIso8601String(),
      'last_accessed_at': lastAccessedAt.toIso8601String(),
      'access_count': accessCount,
    };
  }

  factory AudioMetadata.fromJson(Map<String, dynamic> json) {
    return AudioMetadata(
      textHash: json['text_hash'],
      originalText: json['original_text'],
      provider: json['provider'],
      chunkCount: json['chunk_count'],
      totalDuration: Duration(milliseconds: json['total_duration']),
      createdAt: DateTime.parse(json['created_at']),
      lastAccessedAt: DateTime.parse(json['last_accessed_at']),
      accessCount: json['access_count'] ?? 0,
    );
  }
}

/// Audio cache statistics
class AudioCacheStats {
  final int totalChunks;
  final int totalMetadata;
  final int totalSizeBytes;
  final Map<String, int> providerStats;
  final double chunkHitRate;
  final double metadataHitRate;

  const AudioCacheStats({
    required this.totalChunks,
    required this.totalMetadata,
    required this.totalSizeBytes,
    required this.providerStats,
    required this.chunkHitRate,
    required this.metadataHitRate,
  });

  Map<String, dynamic> toJson() {
    return {
      'total_chunks': totalChunks,
      'total_metadata': totalMetadata,
      'total_size_bytes': totalSizeBytes,
      'provider_stats': providerStats,
      'chunk_hit_rate': chunkHitRate,
      'metadata_hit_rate': metadataHitRate,
    };
  }
}

/// Base audio cache event
abstract class AudioCacheEvent {
  final DateTime timestamp = DateTime.now();
}

/// Audio cache store event
class AudioCacheStoreEvent extends AudioCacheEvent {
  final String text;
  final String provider;
  final int chunkCount;
  
  AudioCacheStoreEvent(this.text, this.provider, this.chunkCount);
}

/// Audio cache hit event
class AudioCacheHitEvent extends AudioCacheEvent {
  final String text;
  final String provider;
  final int chunkCount;
  
  AudioCacheHitEvent(this.text, this.provider, this.chunkCount);
}

/// Audio cache miss event
class AudioCacheMissEvent extends AudioCacheEvent {
  final String text;
  final String provider;
  
  AudioCacheMissEvent(this.text, this.provider);
}

/// Audio precache request event
class AudioPrecacheRequestEvent extends AudioCacheEvent {
  final String text;
  final String provider;
  
  AudioPrecacheRequestEvent(this.text, this.provider);
}

/// Audio cache clear event
class AudioCacheClearEvent extends AudioCacheEvent {
  final String provider;
  final int removedCount;
  
  AudioCacheClearEvent(this.provider, this.removedCount);
}

/// Audio cache optimize event
class AudioCacheOptimizeEvent extends AudioCacheEvent {}