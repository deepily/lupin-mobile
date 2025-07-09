import 'dart:async';
import '../../shared/models/models.dart';
import 'base_repository.dart';

/// Repository interface for AudioChunk entities
abstract class AudioRepository extends BaseRepository<AudioChunk, String> {
  /// Find audio chunks by type
  Future<List<AudioChunk>> findByType(AudioChunkType type);
  
  /// Find audio chunks by provider
  Future<List<AudioChunk>> findByProvider(String provider);
  
  /// Find audio chunks by text
  Future<List<AudioChunk>> findByText(String text);
  
  /// Find audio chunks by sequence
  Future<List<AudioChunk>> findBySequence(String textHash, {int? totalChunks});
  
  /// Get cached audio for text
  Future<List<AudioChunk>?> getCachedAudio(String text, String provider);
  
  /// Cache audio chunks
  Future<void> cacheAudio(List<AudioChunk> chunks);
  
  /// Get audio cache statistics
  Future<AudioCacheStats> getCacheStats();
  
  /// Cleanup old cached audio
  Future<int> cleanupOldCache({Duration? olderThan});
  
  /// Get cache size in bytes
  Future<int> getCacheSize();
  
  /// Clear cache by provider
  Future<void> clearCacheByProvider(String provider);
  
  /// Clear cache by type
  Future<void> clearCacheByType(AudioChunkType type);
  
  /// Find chunks by status
  Future<List<AudioChunk>> findByStatus(AudioChunkStatus status);
  
  /// Update chunk status
  Future<AudioChunk> updateStatus(String chunkId, AudioChunkStatus status);
  
  /// Get most frequently cached audio
  Future<List<String>> getMostCachedTexts({int limit = 10});
  
  /// Optimize cache (remove duplicates, compress, etc.)
  Future<void> optimizeCache();
  
  /// Export cache for backup
  Future<Map<String, dynamic>> exportCache();
  
  /// Import cache from backup
  Future<void> importCache(Map<String, dynamic> cacheData);
}

/// Audio cache statistics
class AudioCacheStats {
  final int totalChunks;
  final int cacheHits;
  final int cacheMisses;
  final int totalSizeBytes;
  final int maxSizeBytes;
  final Map<String, int> chunksByProvider;
  final Map<String, int> chunksByType;
  final Map<String, double> averageChunkSize;
  final Duration oldestCacheEntry;
  final Duration newestCacheEntry;

  const AudioCacheStats({
    required this.totalChunks,
    required this.cacheHits,
    required this.cacheMisses,
    required this.totalSizeBytes,
    required this.maxSizeBytes,
    this.chunksByProvider = const {},
    this.chunksByType = const {},
    this.averageChunkSize = const {},
    required this.oldestCacheEntry,
    required this.newestCacheEntry,
  });

  double get hitRate => 
      (cacheHits + cacheMisses) > 0 ? cacheHits / (cacheHits + cacheMisses) : 0.0;

  double get cacheUtilization => 
      maxSizeBytes > 0 ? totalSizeBytes / maxSizeBytes : 0.0;

  Map<String, dynamic> toJson() {
    return {
      'total_chunks': totalChunks,
      'cache_hits': cacheHits,
      'cache_misses': cacheMisses,
      'total_size_bytes': totalSizeBytes,
      'max_size_bytes': maxSizeBytes,
      'hit_rate': hitRate,
      'cache_utilization': cacheUtilization,
      'chunks_by_provider': chunksByProvider,
      'chunks_by_type': chunksByType,
      'average_chunk_size': averageChunkSize,
      'oldest_cache_entry': oldestCacheEntry.inMilliseconds,
      'newest_cache_entry': newestCacheEntry.inMilliseconds,
    };
  }
}