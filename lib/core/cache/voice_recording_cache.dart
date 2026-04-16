import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../shared/models/models.dart';
import '../storage/storage_manager.dart';
import 'cache_manager.dart';
import 'cache_policy.dart';
import 'offline_manager.dart';

/// Dedicated cache for voice recordings
class VoiceRecordingCache {
  static VoiceRecordingCache? _instance;
  late final CacheManager<VoiceRecordingData> _recordingCache;
  late final CacheManager<TranscriptionData> _transcriptionCache;
  late final OfflineManager _offlineManager;
  
  final StreamController<VoiceRecordingCacheEvent> _eventController = 
      StreamController<VoiceRecordingCacheEvent>.broadcast();
  
  // Index for fast lookups
  final Map<String, RecordingMetadata> _metadataIndex = {};
  
  VoiceRecordingCache._(OfflineManager offlineManager) 
      : _offlineManager = offlineManager {
    _initialize();
  }
  
  /// Get singleton instance
  static Future<VoiceRecordingCache> getInstance() async {
    if (_instance == null) {
      final offlineManager = await OfflineManager.getInstance();
      _instance = VoiceRecordingCache._(offlineManager);
    }
    return _instance!;
  }
  
  /// Create instance for testing (bypasses singleton)
  static Future<VoiceRecordingCache> createForTesting(OfflineManager offlineManager) async {
    return VoiceRecordingCache._(offlineManager);
  }
  
  /// Initialize voice recording cache
  void _initialize() {
    _recordingCache = _offlineManager.getCacheManager<VoiceRecordingData>(
      cacheKey: 'voice_recordings',
      toJson: (data) => data.toJson(),
      fromJson: (json) => VoiceRecordingData.fromJson(json),
      policy: CachePolicy(
        maxAge: const Duration(days: 30),
        maxItems: 100,
        maxSizeBytes: 100 * 1024 * 1024, // 100MB for recordings
        persistAcrossRestarts: true,
        evictionStrategy: CacheEvictionStrategy.lru,
      ),
      calculateSize: (data) => data.audioData.length,
    );
    
    _transcriptionCache = _offlineManager.getCacheManager<TranscriptionData>(
      cacheKey: 'voice_transcriptions',
      toJson: (data) => data.toJson(),
      fromJson: (json) => TranscriptionData.fromJson(json),
      policy: CachePolicy(
        maxAge: const Duration(days: 90),
        maxItems: 500,
        maxSizeBytes: 10 * 1024 * 1024, // 10MB for transcriptions
        persistAcrossRestarts: true,
      ),
    );
  }
  
  /// Initialize and load metadata index
  Future<void> initialize() async {
    // Load existing metadata
    await _loadMetadataIndex();
  }
  
  /// Cache a voice recording
  Future<void> cacheRecording({
    required VoiceInput voiceInput,
    required Uint8List audioData,
    String? transcription,
    bool compressed = false,
  }) async {
    final recordingData = VoiceRecordingData(
      voiceInput: voiceInput,
      audioData: audioData,
      compressed: compressed,
      cachedAt: DateTime.now(),
    );
    
    // Store recording
    await _recordingCache.put(voiceInput.id, recordingData);
    
    // Store transcription if available
    if (transcription != null) {
      final transcriptionData = TranscriptionData(
        recordingId: voiceInput.id,
        transcription: transcription,
        confidence: voiceInput.confidence ?? 0.0,
        language: _detectLanguage(transcription),
        createdAt: DateTime.now(),
      );
      
      await _transcriptionCache.put(
        '${voiceInput.id}_transcription',
        transcriptionData,
      );
    }
    
    // Update metadata index
    final metadata = RecordingMetadata(
      recordingId: voiceInput.id,
      sessionId: voiceInput.sessionId,
      duration: voiceInput.duration ?? Duration.zero,
      sizeBytes: audioData.length,
      compressed: compressed,
      hasTranscription: transcription != null,
      createdAt: voiceInput.startedAt,
      lastAccessedAt: DateTime.now(),
      accessCount: 0,
    );
    
    _metadataIndex[voiceInput.id] = metadata;
    await _saveMetadataIndex();
    
    _eventController.add(VoiceRecordingStoredEvent(
      voiceInput.id,
      audioData.length,
      transcription != null,
    ));
  }
  
  /// Get cached recording
  Future<VoiceRecordingData?> getRecording(String recordingId) async {
    final data = await _recordingCache.get(recordingId);
    
    if (data != null) {
      // Update access metadata
      final metadata = _metadataIndex[recordingId];
      if (metadata != null) {
        _metadataIndex[recordingId] = metadata.copyWith(
          lastAccessedAt: DateTime.now(),
          accessCount: metadata.accessCount + 1,
        );
        await _saveMetadataIndex();
      }
      
      _eventController.add(VoiceRecordingAccessedEvent(recordingId, true));
      return data;
    }
    
    _eventController.add(VoiceRecordingAccessedEvent(recordingId, false));
    return null;
  }
  
  /// Get transcription for recording
  Future<TranscriptionData?> getTranscription(String recordingId) async {
    return await _transcriptionCache.get('${recordingId}_transcription');
  }
  
  /// Get recordings by session
  Future<List<RecordingMetadata>> getRecordingsBySession(String sessionId) async {
    return _metadataIndex.values
        .where((metadata) => metadata.sessionId == sessionId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
  
  /// Get recent recordings
  Future<List<RecordingMetadata>> getRecentRecordings({
    int limit = 10,
    Duration? within,
  }) async {
    final cutoff = within != null 
        ? DateTime.now().subtract(within)
        : DateTime.fromMillisecondsSinceEpoch(0);
    
    final recent = _metadataIndex.values
        .where((metadata) => metadata.createdAt.isAfter(cutoff))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    return recent.take(limit).toList();
  }
  
  /// Search recordings by transcription
  Future<List<RecordingSearchResult>> searchByTranscription(
    String query, {
    int limit = 20,
  }) async {
    final results = <RecordingSearchResult>[];
    final lowerQuery = query.toLowerCase();
    
    for (final recordingId in _metadataIndex.keys) {
      final transcription = await getTranscription(recordingId);
      if (transcription != null) {
        final lowerText = transcription.transcription.toLowerCase();
        if (lowerText.contains(lowerQuery)) {
          final metadata = _metadataIndex[recordingId]!;
          
          // Calculate relevance score
          final score = _calculateRelevanceScore(
            lowerText,
            lowerQuery,
            transcription.confidence,
          );
          
          results.add(RecordingSearchResult(
            recordingId: recordingId,
            transcription: transcription.transcription,
            metadata: metadata,
            relevanceScore: score,
            matchedQuery: query,
          ));
        }
      }
    }
    
    // Sort by relevance score
    results.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
    
    return results.take(limit).toList();
  }
  
  /// Get cache statistics
  Future<VoiceRecordingCacheStats> getStats() async {
    final recordingStats = _recordingCache.getStats();
    final transcriptionStats = _transcriptionCache.getStats();
    
    // Calculate duration stats
    Duration totalDuration = Duration.zero;
    int compressedCount = 0;
    int transcribedCount = 0;
    
    for (final metadata in _metadataIndex.values) {
      totalDuration += metadata.duration;
      if (metadata.compressed) compressedCount++;
      if (metadata.hasTranscription) transcribedCount++;
    }
    
    return VoiceRecordingCacheStats(
      itemCount: _metadataIndex.length,
      totalSizeBytes: recordingStats.totalSizeBytes,
      totalDuration: totalDuration,
      compressedCount: compressedCount,
      transcribedCount: transcribedCount,
      averageDuration: _metadataIndex.isNotEmpty
          ? Duration(
              milliseconds: totalDuration.inMilliseconds ~/ _metadataIndex.length,
            )
          : Duration.zero,
      hitRate: recordingStats.hitRate,
    );
  }
  
  /// Remove old recordings
  Future<int> removeOldRecordings(Duration olderThan) async {
    final cutoff = DateTime.now().subtract(olderThan);
    final toRemove = <String>[];
    
    for (final entry in _metadataIndex.entries) {
      if (entry.value.createdAt.isBefore(cutoff)) {
        toRemove.add(entry.key);
      }
    }
    
    for (final recordingId in toRemove) {
      await _recordingCache.remove(recordingId);
      await _transcriptionCache.remove('${recordingId}_transcription');
      _metadataIndex.remove(recordingId);
    }
    
    await _saveMetadataIndex();
    
    _eventController.add(VoiceRecordingCleanupEvent(toRemove.length));
    
    return toRemove.length;
  }
  
  /// Optimize cache
  Future<void> optimize() async {
    // Remove recordings that haven't been accessed in 30 days
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final toRemove = <String>[];
    
    for (final entry in _metadataIndex.entries) {
      if (entry.value.lastAccessedAt.isBefore(cutoff) && 
          entry.value.accessCount < 2) {
        toRemove.add(entry.key);
      }
    }
    
    for (final recordingId in toRemove) {
      await _recordingCache.remove(recordingId);
      await _transcriptionCache.remove('${recordingId}_transcription');
      _metadataIndex.remove(recordingId);
    }
    
    // Clean up orphaned transcriptions
    await _recordingCache.cleanup();
    await _transcriptionCache.cleanup();
    
    await _saveMetadataIndex();
    
    _eventController.add(VoiceRecordingOptimizeEvent(toRemove.length));
  }
  
  /// Clear all recordings
  Future<void> clearAll() async {
    await _recordingCache.clear();
    await _transcriptionCache.clear();
    _metadataIndex.clear();
    await _saveMetadataIndex();
    
    _eventController.add(VoiceRecordingClearEvent());
  }
  
  /// Export recordings to file
  Future<String> exportRecordings({
    List<String>? recordingIds,
    bool includeAudio = true,
    bool includeTranscriptions = true,
  }) async {
    // Implementation would export to a file
    // For now, return a placeholder path
    return '/storage/emulated/0/Download/voice_recordings_export.zip';
  }
  
  /// Stream of cache events
  Stream<VoiceRecordingCacheEvent> get events => _eventController.stream;
  
  /// Dispose resources
  void dispose() {
    _eventController.close();
  }
  
  // Private helper methods
  
  Future<void> _loadMetadataIndex() async {
    final storage = await StorageManager.getInstance();
    final data = await storage.getString('voice_recording_metadata_index');
    
    if (data != null) {
      final Map<String, dynamic> json = jsonDecode(data);
      _metadataIndex.clear();
      
      json.forEach((key, value) {
        _metadataIndex[key] = RecordingMetadata.fromJson(value);
      });
    }
  }
  
  Future<void> _saveMetadataIndex() async {
    final storage = await StorageManager.getInstance();
    final json = <String, dynamic>{};
    
    _metadataIndex.forEach((key, value) {
      json[key] = value.toJson();
    });
    
    await storage.setString('voice_recording_metadata_index', jsonEncode(json));
  }
  
  String _detectLanguage(String text) {
    // Simple language detection - in real implementation would use ML
    if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(text)) return 'zh';
    if (RegExp(r'[\u3040-\u309f\u30a0-\u30ff]').hasMatch(text)) return 'ja';
    if (RegExp(r'[\u0600-\u06ff]').hasMatch(text)) return 'ar';
    if (RegExp(r'[\u0400-\u04ff]').hasMatch(text)) return 'ru';
    return 'en';
  }
  
  double _calculateRelevanceScore(
    String text,
    String query,
    double confidence,
  ) {
    // Simple relevance scoring
    double score = 0.0;
    
    // Exact match bonus
    if (text == query) {
      score += 10.0;
    } else if (text.startsWith(query)) {
      score += 5.0;
    } else if (text.contains(' $query ')) {
      score += 3.0;
    } else {
      score += 1.0;
    }
    
    // Apply confidence multiplier
    score *= confidence;
    
    // Position bonus (earlier occurrence scores higher)
    final position = text.indexOf(query);
    if (position >= 0) {
      score += (1.0 - (position / text.length)) * 2.0;
    }
    
    return score;
  }
}

/// Voice recording data
class VoiceRecordingData {
  final VoiceInput voiceInput;
  Uint8List audioData;
  bool compressed;
  final DateTime cachedAt;
  
  VoiceRecordingData({
    required this.voiceInput,
    required this.audioData,
    required this.compressed,
    required this.cachedAt,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'voice_input': voiceInput.toJson(),
      'audio_data': audioData.toList(),
      'compressed': compressed,
      'cached_at': cachedAt.toIso8601String(),
    };
  }
  
  factory VoiceRecordingData.fromJson(Map<String, dynamic> json) {
    return VoiceRecordingData(
      voiceInput: VoiceInput.fromJson(json['voice_input']),
      audioData: Uint8List.fromList((json['audio_data'] as List<dynamic>).cast<int>()),
      compressed: json['compressed'] ?? false,
      cachedAt: DateTime.parse(json['cached_at']),
    );
  }
}

/// Transcription data
class TranscriptionData {
  final String recordingId;
  final String transcription;
  final double confidence;
  final String language;
  final DateTime createdAt;
  final Map<String, dynamic>? alternatives;
  
  const TranscriptionData({
    required this.recordingId,
    required this.transcription,
    required this.confidence,
    required this.language,
    required this.createdAt,
    this.alternatives,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'recording_id': recordingId,
      'transcription': transcription,
      'confidence': confidence,
      'language': language,
      'created_at': createdAt.toIso8601String(),
      'alternatives': alternatives,
    };
  }
  
  factory TranscriptionData.fromJson(Map<String, dynamic> json) {
    return TranscriptionData(
      recordingId: json['recording_id'],
      transcription: json['transcription'],
      confidence: (json['confidence'] as num).toDouble(),
      language: json['language'],
      createdAt: DateTime.parse(json['created_at']),
      alternatives: json['alternatives'],
    );
  }
}

/// Recording metadata for indexing
class RecordingMetadata {
  final String recordingId;
  final String sessionId;
  final Duration duration;
  final int sizeBytes;
  final bool compressed;
  final bool hasTranscription;
  final DateTime createdAt;
  final DateTime lastAccessedAt;
  final int accessCount;
  
  const RecordingMetadata({
    required this.recordingId,
    required this.sessionId,
    required this.duration,
    required this.sizeBytes,
    required this.compressed,
    required this.hasTranscription,
    required this.createdAt,
    required this.lastAccessedAt,
    required this.accessCount,
  });
  
  RecordingMetadata copyWith({
    DateTime? lastAccessedAt,
    int? accessCount,
  }) {
    return RecordingMetadata(
      recordingId: recordingId,
      sessionId: sessionId,
      duration: duration,
      sizeBytes: sizeBytes,
      compressed: compressed,
      hasTranscription: hasTranscription,
      createdAt: createdAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      accessCount: accessCount ?? this.accessCount,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'recording_id': recordingId,
      'session_id': sessionId,
      'duration': duration.inMilliseconds,
      'size_bytes': sizeBytes,
      'compressed': compressed,
      'has_transcription': hasTranscription,
      'created_at': createdAt.toIso8601String(),
      'last_accessed_at': lastAccessedAt.toIso8601String(),
      'access_count': accessCount,
    };
  }
  
  factory RecordingMetadata.fromJson(Map<String, dynamic> json) {
    return RecordingMetadata(
      recordingId: json['recording_id'],
      sessionId: json['session_id'],
      duration: Duration(milliseconds: json['duration']),
      sizeBytes: json['size_bytes'],
      compressed: json['compressed'],
      hasTranscription: json['has_transcription'],
      createdAt: DateTime.parse(json['created_at']),
      lastAccessedAt: DateTime.parse(json['last_accessed_at']),
      accessCount: json['access_count'],
    );
  }
}

/// Recording search result
class RecordingSearchResult {
  final String recordingId;
  final String transcription;
  final RecordingMetadata metadata;
  final double relevanceScore;
  final String matchedQuery;
  
  const RecordingSearchResult({
    required this.recordingId,
    required this.transcription,
    required this.metadata,
    required this.relevanceScore,
    required this.matchedQuery,
  });
}

/// Voice recording cache statistics
class VoiceRecordingCacheStats {
  final int itemCount;
  final int totalSizeBytes;
  final Duration totalDuration;
  final int compressedCount;
  final int transcribedCount;
  final Duration averageDuration;
  final double hitRate;
  
  const VoiceRecordingCacheStats({
    required this.itemCount,
    required this.totalSizeBytes,
    required this.totalDuration,
    required this.compressedCount,
    required this.transcribedCount,
    required this.averageDuration,
    required this.hitRate,
  });
  
  double get compressionRate => itemCount > 0 
      ? compressedCount / itemCount 
      : 0.0;
      
  double get transcriptionRate => itemCount > 0 
      ? transcribedCount / itemCount 
      : 0.0;
}

/// Base voice recording cache event
abstract class VoiceRecordingCacheEvent {
  final DateTime timestamp = DateTime.now();
}

/// Voice recording stored event
class VoiceRecordingStoredEvent extends VoiceRecordingCacheEvent {
  final String recordingId;
  final int sizeBytes;
  final bool hasTranscription;
  
  VoiceRecordingStoredEvent(
    this.recordingId,
    this.sizeBytes,
    this.hasTranscription,
  );
}

/// Voice recording accessed event
class VoiceRecordingAccessedEvent extends VoiceRecordingCacheEvent {
  final String recordingId;
  final bool found;
  
  VoiceRecordingAccessedEvent(this.recordingId, this.found);
}

/// Voice recording cleanup event
class VoiceRecordingCleanupEvent extends VoiceRecordingCacheEvent {
  final int removedCount;
  
  VoiceRecordingCleanupEvent(this.removedCount);
}

/// Voice recording optimize event
class VoiceRecordingOptimizeEvent extends VoiceRecordingCacheEvent {
  final int optimizedCount;
  
  VoiceRecordingOptimizeEvent(this.optimizedCount);
}

/// Voice recording clear event
class VoiceRecordingClearEvent extends VoiceRecordingCacheEvent {}