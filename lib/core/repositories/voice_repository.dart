import 'dart:async';
import '../../shared/models/models.dart';
import 'base_repository.dart';

/// Repository interface for VoiceInput entities
abstract class VoiceRepository extends BaseRepository<VoiceInput, String> {
  /// Find voice inputs by session.
  /// 
  /// Requires:
  ///   - sessionId must be non-empty string
  ///   - sessionId must exist in the system
  /// 
  /// Ensures:
  ///   - Returns all voice inputs for the given session
  ///   - Results are ordered by creation time (newest first)
  ///   - Empty list returned if no inputs found
  Future<List<VoiceInput>> findBySession(String sessionId);
  
  /// Find voice inputs by status
  Future<List<VoiceInput>> findByStatus(VoiceInputStatus status);
  
  /// Find voice inputs by time range.
  /// 
  /// Requires:
  ///   - start must be before end
  ///   - Both dates must be valid DateTime objects
  /// 
  /// Ensures:
  ///   - Returns inputs where startedAt is within [start, end]
  ///   - Results are ordered by startedAt ascending
  ///   - Empty list returned if no inputs in range
  Future<List<VoiceInput>> findByTimeRange(DateTime start, DateTime end);
  
  /// Find voice inputs by transcription search
  Future<List<VoiceInput>> findByTranscriptionSearch(String query);
  
  /// Get voice input statistics
  Future<VoiceStats> getVoiceStats({String? sessionId});
  
  /// Get average transcription confidence
  Future<double> getAverageConfidence({String? sessionId});
  
  /// Get most common transcriptions
  Future<List<String>> getCommonTranscriptions({int limit = 10});
  
  /// Update transcription for a voice input.
  /// 
  /// Requires:
  ///   - voiceInputId must exist in repository
  ///   - transcription must be non-empty string
  ///   - confidence must be between 0.0 and 1.0
  /// 
  /// Ensures:
  ///   - Voice input transcription is updated
  ///   - Status is set to completed
  ///   - CompletedAt timestamp is set
  ///   - Updated entity is persisted and returned
  /// 
  /// Throws:
  ///   - [NotFoundException] if voiceInputId doesn't exist
  ///   - [ArgumentError] if confidence is out of range
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
  
  /// Cleanup old voice inputs.
  /// 
  /// Requires:
  ///   - olderThan duration must be positive if provided
  /// 
  /// Ensures:
  ///   - Deletes voice inputs older than specified duration
  ///   - Default duration is 30 days if not specified
  ///   - Audio data is deleted along with metadata
  ///   - Returns count of deleted inputs
  /// 
  /// Note: This operation is irreversible
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