import '../../../core/use_cases/base_use_case.dart';
import '../../../core/repositories/interfaces/voice_repository.dart';
import '../../../core/error_handling/error_handler.dart';
import '../../../shared/models/models.dart';

/// Parameters for stopping voice recording
class StopVoiceRecordingParams {
  final String voiceInputId;
  final List<int>? audioData;
  final Duration? recordingDuration;
  final Map<String, dynamic>? metadata;

  const StopVoiceRecordingParams({
    required this.voiceInputId,
    this.audioData,
    this.recordingDuration,
    this.metadata,
  });

  @override
  String toString() => 'StopVoiceRecordingParams(voiceInputId: $voiceInputId, duration: $recordingDuration)';
}

/// Use case for stopping voice recording
class StopVoiceRecordingUseCase extends ParameterizedUseCase<VoiceInput, StopVoiceRecordingParams> {
  final VoiceRepository _voiceRepository;

  StopVoiceRecordingUseCase(this._voiceRepository);

  @override
  AppError? validateParams(StopVoiceRecordingParams params) {
    if (params.voiceInputId.isEmpty) {
      return ValidationError.required('voiceInputId');
    }
    return null;
  }

  @override
  Future<UseCaseResult<VoiceInput>> executeInternal(StopVoiceRecordingParams params) async {
    try {
      // Get the voice input
      final voiceInput = await _voiceRepository.findById(params.voiceInputId);
      if (voiceInput == null) {
        return UseCaseResult.failure(
          VoiceError(
            'VOICE_INPUT_NOT_FOUND',
            'Voice input not found: ${params.voiceInputId}',
            voiceInputId: params.voiceInputId,
            userMessage: 'Voice recording not found.',
          ),
        );
      }

      // Validate current status
      if (voiceInput.status != VoiceInputStatus.recording) {
        return UseCaseResult.failure(
          VoiceError(
            'VOICE_INPUT_NOT_RECORDING',
            'Voice input is not in recording state: ${voiceInput.status}',
            voiceInputId: params.voiceInputId,
            userMessage: 'Voice recording is not active.',
          ),
        );
      }

      // Calculate recording duration if not provided
      final duration = params.recordingDuration ?? 
          DateTime.now().difference(voiceInput.timestamp);

      // Validate minimum recording duration
      if (duration.inMilliseconds < 500) {
        return UseCaseResult.failure(
          VoiceError(
            'RECORDING_TOO_SHORT',
            'Recording duration too short: ${duration.inMilliseconds}ms',
            voiceInputId: params.voiceInputId,
            userMessage: 'Recording is too short. Please try again.',
          ),
        );
      }

      // Save audio data if provided
      if (params.audioData != null) {
        await _voiceRepository.saveAudioData(params.voiceInputId, params.audioData!);
      }

      // Update voice input status to processing
      final updatedVoiceInput = await _voiceRepository.updateStatus(
        params.voiceInputId,
        VoiceInputStatus.processing,
      );

      // Update metadata with recording info
      final finalVoiceInput = voiceInput.copyWith(
        status: VoiceInputStatus.processing,
        duration: duration,
        metadata: {
          ...?voiceInput.metadata,
          ...?params.metadata,
          'stoppedAt': DateTime.now().toIso8601String(),
          'recordingDurationMs': duration.inMilliseconds,
          'hasAudioData': params.audioData != null,
          if (params.audioData != null) 'audioDataSize': params.audioData!.length,
        },
      );

      await _voiceRepository.update(finalVoiceInput);

      return UseCaseResult.success(finalVoiceInput);

    } catch (error) {
      if (error is AppError) {
        return UseCaseResult.failure(error);
      }
      
      return UseCaseResult.failure(
        VoiceError(
          'STOP_RECORDING_FAILED',
          'Failed to stop voice recording: $error',
          voiceInputId: params.voiceInputId,
          userMessage: 'Failed to stop recording. Please try again.',
        ),
      );
    }
  }
}