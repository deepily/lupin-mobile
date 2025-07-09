import 'dart:async';
import '../../../shared/models/models.dart';
import '../audio_repository.dart';
import '../base_repository.dart';
import 'shared_preferences_repository.dart';

class AudioRepositoryImpl extends SharedPreferencesRepository<AudioChunk, String> 
    implements AudioRepository {
  
  final StreamController<List<AudioChunk>> _audioStreamController = 
      StreamController<List<AudioChunk>>.broadcast();
  
  AudioRepositoryImpl() : super('audio');
  
  @override
  Map<String, dynamic> toJson(AudioChunk entity) => entity.toJson();
  
  @override
  AudioChunk fromJson(Map<String, dynamic> json) => AudioChunk.fromJson(json);
  
  @override
  String getId(AudioChunk entity) => entity.id;
  
  @override
  Future<AudioChunk> create(AudioChunk entity) async {
    final result = await super.create(entity);
    _notifyListeners();
    return result;
  }
  
  @override
  Future<AudioChunk> update(AudioChunk entity) async {
    final result = await super.update(entity);
    _notifyListeners();
    return result;
  }
  
  @override
  Future<void> deleteById(String id) async {
    await super.deleteById(id);
    _notifyListeners();
  }
  
  @override
  Future<List<AudioChunk>> findBySession(String sessionId) async {
    return await findWhere((audio) => audio.sessionId == sessionId);
  }
  
  @override
  Future<List<AudioChunk>> findByJobId(String jobId) async {
    return await findWhere((audio) => audio.jobId == jobId);
  }
  
  @override
  Future<List<AudioChunk>> findByType(AudioChunkType type) async {
    return await findWhere((audio) => audio.type == type);
  }
  
  @override
  Future<List<AudioChunk>> findByTimeRange(DateTime start, DateTime end) async {
    return await findWhere((audio) => 
        audio.timestamp.isAfter(start) && audio.timestamp.isBefore(end));
  }
  
  @override
  Future<AudioChunk> updatePlaybackState(String audioId, bool isPlaying) async {
    final audio = await findById(audioId);
    if (audio == null) {
      throw Exception('AudioChunk with id $audioId not found');
    }
    
    final updatedAudio = audio.copyWith(
      metadata: {
        ...audio.metadata ?? {},
        'is_playing': isPlaying,
        'last_played': isPlaying ? DateTime.now().toIso8601String() : null,
      },
    );
    return await update(updatedAudio);
  }
  
  @override
  Future<List<AudioChunk>> getRecentAudio(String sessionId, {int? limit}) async {
    List<AudioChunk> audioChunks = await findBySession(sessionId);
    
    // Sort by timestamp (newest first)
    audioChunks.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    if (limit != null && audioChunks.length > limit) {
      audioChunks = audioChunks.sublist(0, limit);
    }
    
    return audioChunks;
  }
  
  @override
  Future<List<AudioChunk>> getCachedAudio() async {
    return await findWhere((audio) {
      final isCached = audio.metadata?['is_cached'] == true;
      final hasLocalPath = audio.localPath != null;
      return isCached && hasLocalPath;
    });
  }
  
  @override
  Future<AudioStats> getAudioStats({String? sessionId}) async {
    List<AudioChunk> audioChunks = await findAll();
    
    if (sessionId != null) {
      audioChunks = audioChunks.where((audio) => 
          audio.sessionId == sessionId).toList();
    }
    
    final totalChunks = audioChunks.length;
    final cachedChunks = audioChunks.where((audio) => 
        audio.metadata?['is_cached'] == true).length;
    
    // Calculate total size (approximate)
    final totalSize = audioChunks.fold<int>(0, (sum, audio) => 
        sum + (audio.metadata?['size_bytes'] as int? ?? 0));
    
    // Calculate total duration
    final totalDuration = audioChunks.fold<Duration>(Duration.zero, (sum, audio) => 
        sum + (audio.duration ?? Duration.zero));
    
    // Count by type
    final inputChunks = audioChunks.where((audio) => 
        audio.type == AudioChunkType.input).length;
    final outputChunks = audioChunks.where((audio) => 
        audio.type == AudioChunkType.output).length;
    
    // Get last activity
    final lastActivity = audioChunks.isNotEmpty
        ? audioChunks.map((a) => a.timestamp)
                     .reduce((a, b) => a.isAfter(b) ? a : b)
        : null;
    
    return AudioStats(
      totalChunks: totalChunks,
      cachedChunks: cachedChunks,
      totalSize: totalSize,
      totalDuration: totalDuration,
      inputChunks: inputChunks,
      outputChunks: outputChunks,
      lastActivity: lastActivity,
    );
  }
  
  @override
  Future<void> cleanupOldAudio({Duration? olderThan}) async {
    final cutoff = olderThan != null 
        ? DateTime.now().subtract(olderThan)
        : DateTime.now().subtract(Duration(days: 7));
    
    final oldAudio = await findWhere((audio) => 
        audio.timestamp.isBefore(cutoff));
    
    for (final audio in oldAudio) {
      await deleteById(audio.id);
    }
  }
  
  @override
  Future<void> updateCacheStatus(String audioId, bool isCached, String? localPath) async {
    final audio = await findById(audioId);
    if (audio == null) {
      throw Exception('AudioChunk with id $audioId not found');
    }
    
    final updatedAudio = audio.copyWith(
      localPath: localPath,
      metadata: {
        ...audio.metadata ?? {},
        'is_cached': isCached,
        'cached_at': isCached ? DateTime.now().toIso8601String() : null,
      },
    );
    await update(updatedAudio);
  }
  
  @override
  Future<int> getTotalCacheSize() async {
    final cachedAudio = await getCachedAudio();
    return cachedAudio.fold<int>(0, (sum, audio) => 
        sum + (audio.metadata?['size_bytes'] as int? ?? 0));
  }
  
  @override
  Future<void> clearCache({bool keepRecent = true}) async {
    if (keepRecent) {
      // Keep audio from last 24 hours
      final cutoff = DateTime.now().subtract(Duration(hours: 24));
      final oldCachedAudio = await findWhere((audio) => 
          audio.metadata?['is_cached'] == true &&
          audio.timestamp.isBefore(cutoff));
      
      for (final audio in oldCachedAudio) {
        await updateCacheStatus(audio.id, false, null);
      }
    } else {
      // Clear all cached audio
      final cachedAudio = await getCachedAudio();
      for (final audio in cachedAudio) {
        await updateCacheStatus(audio.id, false, null);
      }
    }
  }
  
  // PaginatedRepository methods
  @override
  Future<PaginatedResult<AudioChunk>> findPaginated({
    int page = 0,
    int size = 20,
    String? sortBy,
    bool ascending = true,
    Map<String, dynamic>? filters,
  }) async {
    List<AudioChunk> allAudio = await findAll();
    
    // Apply filters
    if (filters != null) {
      allAudio = allAudio.where((audio) {
        return filters.entries.every((entry) {
          final key = entry.key;
          final value = entry.value;
          
          switch (key) {
            case 'type':
              return audio.type.name == value;
            case 'session_id':
              return audio.sessionId == value;
            case 'job_id':
              return audio.jobId == value;
            case 'is_cached':
              return audio.metadata?['is_cached'] == value;
            default:
              return true;
          }
        });
      }).toList();
    }
    
    // Sort
    if (sortBy != null) {
      allAudio.sort((a, b) {
        dynamic aValue, bValue;
        
        switch (sortBy) {
          case 'timestamp':
            aValue = a.timestamp;
            bValue = b.timestamp;
            break;
          case 'duration':
            aValue = a.duration?.inMilliseconds ?? 0;
            bValue = b.duration?.inMilliseconds ?? 0;
            break;
          case 'size':
            aValue = a.metadata?['size_bytes'] ?? 0;
            bValue = b.metadata?['size_bytes'] ?? 0;
            break;
          default:
            aValue = a.timestamp;
            bValue = b.timestamp;
        }
        
        final comparison = aValue.compareTo(bValue);
        return ascending ? comparison : -comparison;
      });
    }
    
    // Paginate
    final startIndex = page * size;
    final endIndex = (startIndex + size).clamp(0, allAudio.length);
    final pageItems = allAudio.sublist(startIndex, endIndex);
    
    return PaginatedResult(
      items: pageItems,
      totalCount: allAudio.length,
      page: page,
      size: size,
      hasNext: endIndex < allAudio.length,
      hasPrevious: page > 0,
    );
  }
  
  @override
  Future<PaginatedResult<AudioChunk>> search(
    String query, {
    int page = 0,
    int size = 20,
    List<String>? searchFields,
  }) async {
    // For audio, search in metadata and job IDs
    final searchResults = await findWhere((audio) {
      final jobId = audio.jobId.toLowerCase();
      final sessionId = audio.sessionId.toLowerCase();
      final metadata = audio.metadata?.toString().toLowerCase() ?? '';
      final lowercaseQuery = query.toLowerCase();
      
      return jobId.contains(lowercaseQuery) ||
             sessionId.contains(lowercaseQuery) ||
             metadata.contains(lowercaseQuery);
    });
    
    final startIndex = page * size;
    final endIndex = (startIndex + size).clamp(0, searchResults.length);
    final pageItems = searchResults.sublist(startIndex, endIndex);
    
    return PaginatedResult(
      items: pageItems,
      totalCount: searchResults.length,
      page: page,
      size: size,
      hasNext: endIndex < searchResults.length,
      hasPrevious: page > 0,
    );
  }
  
  // RealtimeRepository methods
  @override
  Stream<List<AudioChunk>> watchAll() {
    return _audioStreamController.stream;
  }
  
  @override
  Stream<AudioChunk?> watchById(String id) {
    return _audioStreamController.stream.map((audioChunks) {
      try {
        return audioChunks.firstWhere((audio) => audio.id == id);
      } catch (e) {
        return null;
      }
    });
  }
  
  @override
  Stream<List<AudioChunk>> watchWhere(Map<String, dynamic> criteria) {
    return _audioStreamController.stream.map((audioChunks) {
      return audioChunks.where((audio) {
        return criteria.entries.every((entry) {
          final key = entry.key;
          final value = entry.value;
          
          switch (key) {
            case 'type':
              return audio.type.name == value;
            case 'session_id':
              return audio.sessionId == value;
            case 'job_id':
              return audio.jobId == value;
            default:
              return true;
          }
        });
      }).toList();
    });
  }
  
  Future<void> _notifyListeners() async {
    final allAudio = await findAll();
    _audioStreamController.add(allAudio);
  }
  
  void dispose() {
    _audioStreamController.close();
  }
}