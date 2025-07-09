import '../../../core/use_cases/base_use_case.dart';
import '../../../core/repositories/interfaces/voice_repository.dart';
import '../../../core/repositories/interfaces/job_repository.dart';
import '../../../core/error_handling/error_handler.dart';
import '../../../shared/models/models.dart';

/// Parameters for processing voice input
class ProcessVoiceInputParams {
  final String voiceInputId;
  final bool enableTranscription;
  final bool enableResponseGeneration;
  final Map<String, dynamic>? processingOptions;

  const ProcessVoiceInputParams({
    required this.voiceInputId,
    this.enableTranscription = true,
    this.enableResponseGeneration = true,
    this.processingOptions,
  });

  @override
  String toString() => 'ProcessVoiceInputParams(voiceInputId: $voiceInputId, transcription: $enableTranscription, response: $enableResponseGeneration)';
}

/// Use case for processing voice input (transcription and response generation)
class ProcessVoiceInputUseCase extends ParameterizedUseCase<VoiceInput, ProcessVoiceInputParams> {
  final VoiceRepository _voiceRepository;
  final JobRepository _jobRepository;

  ProcessVoiceInputUseCase(
    this._voiceRepository,
    this._jobRepository,
  );

  @override
  AppError? validateParams(ProcessVoiceInputParams params) {
    if (params.voiceInputId.isEmpty) {
      return ValidationError.required('voiceInputId');
    }
    return null;
  }

  @override
  Future<UseCaseResult<VoiceInput>> executeInternal(ProcessVoiceInputParams params) async {
    try {
      // Get the voice input
      final voiceInput = await _voiceRepository.findById(params.voiceInputId);
      if (voiceInput == null) {
        return UseCaseResult.failure(
          VoiceError(
            'VOICE_INPUT_NOT_FOUND',
            'Voice input not found: ${params.voiceInputId}',
            voiceInputId: params.voiceInputId,
          ),
        );
      }

      // Validate voice input status
      if (voiceInput.status != VoiceInputStatus.processing) {
        return UseCaseResult.failure(
          VoiceError(
            'INVALID_VOICE_STATUS',
            'Voice input must be in processing status, current: ${voiceInput.status}',
            voiceInputId: params.voiceInputId,
            userMessage: 'Voice input is not ready for processing.',
          ),
        );
      }

      // Check if audio data exists
      final audioData = await _voiceRepository.getAudioData(params.voiceInputId);
      if (audioData == null) {
        return UseCaseResult.failure(
          VoiceError(
            'NO_AUDIO_DATA',
            'No audio data found for voice input: ${params.voiceInputId}',
            voiceInputId: params.voiceInputId,
            userMessage: 'No audio data available for processing.',
          ),
        );
      }

      // Create transcription job if enabled
      if (params.enableTranscription) {
        await _createTranscriptionJob(voiceInput, params.processingOptions);
      }

      // Update voice input metadata
      final updatedVoiceInput = voiceInput.copyWith(
        metadata: {
          ...?voiceInput.metadata,
          'processingStartedAt': DateTime.now().toIso8601String(),
          'transcriptionEnabled': params.enableTranscription,
          'responseGenerationEnabled': params.enableResponseGeneration,
          'audioDataSize': audioData.length,
          ...?params.processingOptions,
        },
      );

      await _voiceRepository.update(updatedVoiceInput);

      return UseCaseResult.success(updatedVoiceInput);

    } catch (error) {
      if (error is AppError) {
        return UseCaseResult.failure(error);
      }
      
      return UseCaseResult.failure(
        VoiceError(
          'VOICE_PROCESSING_FAILED',
          'Failed to process voice input: $error',
          voiceInputId: params.voiceInputId,
          userMessage: 'Voice processing failed. Please try again.',
        ),
      );
    }
  }

  Future<void> _createTranscriptionJob(
    VoiceInput voiceInput,
    Map<String, dynamic>? options,
  ) async {
    final transcriptionJob = Job(
      id: 'transcription_${voiceInput.id}_${DateTime.now().millisecondsSinceEpoch}',
      text: 'Transcribe voice input: ${voiceInput.id}',
      status: JobStatus.todo,
      createdAt: DateTime.now(),
      metadata: {
        'type': 'transcription',
        'voiceInputId': voiceInput.id,
        'sessionId': voiceInput.sessionId,
        'priority': 'high',
        ...?options,
      },
    );

    await _jobRepository.create(transcriptionJob);
  }
}

/// Stream use case for watching voice processing progress
class WatchVoiceProcessingProgressUseCase extends StreamUseCase<VoiceInput, String> {
  final VoiceRepository _voiceRepository;

  WatchVoiceProcessingProgressUseCase(this._voiceRepository);

  @override
  Stream<UseCaseResult<VoiceInput>> call(String voiceInputId) async* {
    try {
      await for (final voiceInput in _voiceRepository.watchById(voiceInputId)) {
        if (voiceInput != null) {
          yield UseCaseResult.success(voiceInput);
        } else {
          yield UseCaseResult.failure(
            VoiceError(
              'VOICE_INPUT_DELETED',
              'Voice input was deleted: $voiceInputId',
              voiceInputId: voiceInputId,
            ),
          );
          break;
        }
      }
    } catch (error) {
      yield UseCaseResult.failure(
        VoiceError(
          'WATCH_VOICE_PROCESSING_FAILED',
          'Failed to watch voice processing: $error',
          voiceInputId: voiceInputId,
        ),
      );
    }
  }
}