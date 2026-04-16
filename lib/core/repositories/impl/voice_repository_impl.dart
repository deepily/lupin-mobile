import 'dart:async';
import '../../../shared/models/models.dart';
import '../voice_repository.dart';
import '../base_repository.dart';
import 'shared_preferences_repository.dart';

class VoiceRepositoryImpl extends SharedPreferencesRepository<VoiceInput, String> 
    implements VoiceRepository {
  
  final StreamController<List<VoiceInput>> _voiceStreamController = 
      StreamController<List<VoiceInput>>.broadcast();
  
  VoiceRepositoryImpl() : super('voice');
  
  @override
  Map<String, dynamic> toJson(VoiceInput entity) => entity.toJson();
  
  @override
  VoiceInput fromJson(Map<String, dynamic> json) => VoiceInput.fromJson(json);
  
  @override
  String getId(VoiceInput entity) => entity.id;
  
  @override
  Future<VoiceInput> create(VoiceInput entity) async {
    final result = await super.create(entity);
    _notifyListeners();
    return result;
  }
  
  @override
  Future<VoiceInput> update(VoiceInput entity) async {
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
  Future<List<VoiceInput>> findBySession(String sessionId) async {
    return await findWhere((voice) => voice.sessionId == sessionId);
  }
  
  @override
  Future<List<VoiceInput>> findByStatus(VoiceInputStatus status) async {
    return await findWhere((voice) => voice.status == status);
  }
  
  @override
  Future<List<VoiceInput>> findByTimeRange(DateTime start, DateTime end) async {
    return await findWhere((voice) => 
        voice.timestamp.isAfter(start) && voice.timestamp.isBefore(end));
  }
  
  @override
  Future<VoiceInput> updateStatus(String voiceId, VoiceInputStatus status) async {
    final voice = await findById(voiceId);
    if (voice == null) {
      throw Exception('VoiceInput with id $voiceId not found');
    }
    
    final updatedVoice = voice.copyWith(status: status);
    return await update(updatedVoice);
  }
  
  @override
  Future<VoiceInput> updateTranscription(String voiceId, String transcription) async {
    final voice = await findById(voiceId);
    if (voice == null) {
      throw Exception('VoiceInput with id $voiceId not found');
    }
    
    final updatedVoice = voice.copyWith(
      transcription: transcription,
      status: VoiceInputStatus.transcribed,
    );
    return await update(updatedVoice);
  }
  
  @override
  Future<VoiceInput> updateResponse(String voiceId, String response) async {
    final voice = await findById(voiceId);
    if (voice == null) {
      throw Exception('VoiceInput with id $voiceId not found');
    }
    
    final updatedVoice = voice.copyWith(
      response: response,
      status: VoiceInputStatus.completed,
    );
    return await update(updatedVoice);
  }
  
  @override
  Future<List<VoiceInput>> getActiveVoiceInputs() async {
    return await findWhere((voice) => voice.isProcessing);
  }
  
  @override
  Future<List<VoiceInput>> getRecentVoiceInputs(String sessionId, {int? limit}) async {
    List<VoiceInput> voices = await findBySession(sessionId);
    
    // Sort by timestamp (newest first)
    voices.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    if (limit != null && voices.length > limit) {
      voices = voices.sublist(0, limit);
    }
    
    return voices;
  }
  
  @override
  Future<VoiceStats> getVoiceStats({String? sessionId}) async {
    List<VoiceInput> voices = await findAll();
    
    if (sessionId != null) {
      voices = voices.where((voice) => voice.sessionId == sessionId).toList();
    }
    
    final totalInputs = voices.length;
    final completedInputs = voices.where((voice) => 
        voice.status == VoiceInputStatus.completed).length;
    final failedInputs = voices.where((voice) => 
        voice.status == VoiceInputStatus.failed).length;
    
    // Calculate average recording duration
    final recordingsWithDuration = voices.where((voice) => 
        voice.duration != null);
    final totalDuration = recordingsWithDuration.fold<Duration>(
      Duration.zero,
      (sum, voice) => sum + voice.duration!,
    );
    final averageRecordingDuration = recordingsWithDuration.isNotEmpty
        ? Duration(milliseconds: totalDuration.inMilliseconds ~/ recordingsWithDuration.length)
        : Duration.zero;
    
    // Calculate success rate
    final successRate = totalInputs > 0 ? completedInputs / totalInputs : 0.0;
    
    // Get last activity
    final lastActivity = voices.isNotEmpty
        ? voices.map((v) => v.timestamp)
                  .reduce((a, b) => a.isAfter(b) ? a : b)
        : null;
    
    return VoiceStats(
      totalInputs: totalInputs,
      completedInputs: completedInputs,
      failedInputs: failedInputs,
      averageRecordingDuration: averageRecordingDuration,
      successRate: successRate,
      lastActivity: lastActivity,
    );
  }
  
  @override
  Future<List<VoiceInput>> findByTranscriptionSearch(String query) async {
    final lowercaseQuery = query.toLowerCase();
    return await findWhere((voice) {
      final transcription = voice.transcription?.toLowerCase() ?? '';
      final response = voice.response?.toLowerCase() ?? '';
      return transcription.contains(lowercaseQuery) || 
             response.contains(lowercaseQuery);
    });
  }
  
  @override
  Future<void> deleteOldVoiceInputs({Duration? olderThan}) async {
    final cutoff = olderThan != null 
        ? DateTime.now().subtract(olderThan)
        : DateTime.now().subtract(Duration(days: 30));
    
    final oldVoices = await findWhere((voice) => 
        voice.timestamp.isBefore(cutoff));
    
    for (final voice in oldVoices) {
      await deleteById(voice.id);
    }
  }
  
  // PaginatedRepository methods
  @override
  Future<PaginatedResult<VoiceInput>> findPaginated({
    int page = 0,
    int size = 20,
    String? sortBy,
    bool ascending = true,
    Map<String, dynamic>? filters,
  }) async {
    List<VoiceInput> allVoices = await findAll();
    
    // Apply filters
    if (filters != null) {
      allVoices = allVoices.where((voice) {
        return filters.entries.every((entry) {
          final key = entry.key;
          final value = entry.value;
          
          switch (key) {
            case 'status':
              return voice.status.name == value;
            case 'session_id':
              return voice.sessionId == value;
            default:
              return true;
          }
        });
      }).toList();
    }
    
    // Sort
    if (sortBy != null) {
      allVoices.sort((a, b) {
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
    final endIndex = (startIndex + size).clamp(0, allVoices.length);
    final pageItems = allVoices.sublist(startIndex, endIndex);
    
    return PaginatedResult(
      items: pageItems,
      totalCount: allVoices.length,
      page: page,
      size: size,
      hasNext: endIndex < allVoices.length,
      hasPrevious: page > 0,
    );
  }
  
  @override
  Future<PaginatedResult<VoiceInput>> search(
    String query, {
    int page = 0,
    int size = 20,
    List<String>? searchFields,
  }) async {
    final searchResults = await searchTranscriptions(query);
    
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
  Stream<List<VoiceInput>> watchAll() {
    return _voiceStreamController.stream;
  }
  
  @override
  Stream<VoiceInput?> watchById(String id) {
    return _voiceStreamController.stream.map((voices) {
      try {
        return voices.firstWhere((voice) => voice.id == id);
      } catch (e) {
        return null;
      }
    });
  }
  
  @override
  Stream<List<VoiceInput>> watchWhere(Map<String, dynamic> criteria) {
    return _voiceStreamController.stream.map((voices) {
      return voices.where((voice) {
        return criteria.entries.every((entry) {
          final key = entry.key;
          final value = entry.value;
          
          switch (key) {
            case 'status':
              return voice.status.name == value;
            case 'session_id':
              return voice.sessionId == value;
            default:
              return true;
          }
        });
      }).toList();
    });
  }
  
  Future<void> _notifyListeners() async {
    final allVoices = await findAll();
    _voiceStreamController.add(allVoices);
  }
  
  void dispose() {
    _voiceStreamController.close();
  }
}