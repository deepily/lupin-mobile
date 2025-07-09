import 'dart:async';
import '../../shared/models/models.dart';
import 'base_repository.dart';

/// Repository interface for VoiceInput entities
abstract class VoiceRepository extends BaseRepository<VoiceInput, String> {
  /// Find voice inputs by session
  Future<List<VoiceInput>> findBySession(String sessionId);
  
  /// Find voice inputs by status
  Future<List<VoiceInput>> findByStatus(VoiceInputStatus status);
  
  /// Find voice inputs by time range
  Future<List<VoiceInput>> findByTimeRange(DateTime start, DateTime end);
  
  /// Find voice inputs by transcription search
  Future<List<VoiceInput>> findByTranscriptionSearch(String query);
  
  /// Get voice input statistics
  Future<VoiceStats> getVoiceStats({String? sessionId});
  
  /// Get average transcription confidence
  Future<double> getAverageConfidence({String? sessionId});
  
  /// Get most common transcriptions
  Future<List<String>> getCommonTranscriptions({int limit = 10});
  
  /// Update transcription
  Future<VoiceInput> updateTranscription(
    String voiceInputId, 
    String transcription, 
    double confidence,
  );
  
  /// Save audio data
  Future<VoiceInput> saveAudioData(String voiceInputId, List<int> audioData);
  
  /// Get audio data
  Future<List<int>?> getAudioData(String voiceInputId);
  
  /// Delete audio data (keep metadata)
  Future<void> deleteAudioData(String voiceInputId);
  
  /// Find incomplete voice inputs
  Future<List<VoiceInput>> findIncompleteInputs();
  
  /// Cleanup old voice inputs
  Future<int> cleanupOldInputs({Duration? olderThan});
}

/// Voice input statistics
class VoiceStats {
  final int totalInputs;
  final int completedInputs;
  final int failedInputs;
  final double averageConfidence;
  final Duration averageProcessingTime;
  final Map<String, int> inputsByHour;
  final Map<String, int> inputsByConfidenceRange;
  final List<String> commonPhrases;

  const VoiceStats({
    required this.totalInputs,
    required this.completedInputs,
    required this.failedInputs,
    required this.averageConfidence,
    required this.averageProcessingTime,
    this.inputsByHour = const {},
    this.inputsByConfidenceRange = const {},
    this.commonPhrases = const [],
  });

  double get successRate => 
      totalInputs > 0 ? completedInputs / totalInputs : 0.0;

  Map<String, dynamic> toJson() {
    return {
      'total_inputs': totalInputs,
      'completed_inputs': completedInputs,
      'failed_inputs': failedInputs,
      'average_confidence': averageConfidence,
      'average_processing_time': averageProcessingTime.inMilliseconds,
      'success_rate': successRate,
      'inputs_by_hour': inputsByHour,
      'inputs_by_confidence_range': inputsByConfidenceRange,
      'common_phrases': commonPhrases,
    };
  }
}