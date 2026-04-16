import '../../../core/use_cases/base_use_case.dart';
import '../../../core/repositories/interfaces/voice_repository.dart';
import '../../../core/repositories/interfaces/session_repository.dart';
import '../../../core/error_handling/error_handler.dart';
import '../../../shared/models/models.dart';

/// Parameters for starting voice recording
class StartVoiceRecordingParams {
  final String sessionId;
  final String? deviceId;
  final Map<String, dynamic>? metadata;

  const StartVoiceRecordingParams({
    required this.sessionId,
    this.deviceId,
    this.metadata,
  });

  @override
  String toString() => 'StartVoiceRecordingParams(sessionId: $sessionId, deviceId: $deviceId)';
}

/// Use case for starting voice recording
class StartVoiceRecordingUseCase extends ParameterizedUseCase<VoiceInput, StartVoiceRecordingParams> {
  final VoiceRepository _voiceRepository;
  final SessionRepository _sessionRepository;

  StartVoiceRecordingUseCase(
    this._voiceRepository,
    this._sessionRepository,
  );

  @override
  AppError? validateParams(StartVoiceRecordingParams params) {
    if (params.sessionId.isEmpty) {
      return ValidationError.required('sessionId');
    }
    return null;
  }

  @override
  Future<UseCaseResult<VoiceInput>> executeInternal(StartVoiceRecordingParams params) async {
    try {
      // Validate session exists and is active
      final session = await _sessionRepository.findById(params.sessionId);
      if (session == null) {
        return UseCaseResult.failure(
          AuthError('SESSION_NOT_FOUND', 'Session not found: ${params.sessionId}'),
        );
      }

      if (session.status != SessionStatus.active) {
        return UseCaseResult.failure(
          AuthError('SESSION_INACTIVE', 'Session is not active: ${params.sessionId}'),
        );
      }

      // Check if there's already an active voice input for this session
      final activeVoiceInputs = await _voiceRepository.getActiveVoiceInputs();
      final sessionActiveInputs = activeVoiceInputs.where(
        (input) => input.sessionId == params.sessionId,
      ).toList();

      if (sessionActiveInputs.isNotEmpty) {
        return UseCaseResult.failure(
          VoiceError(
            'VOICE_RECORDING_ALREADY_ACTIVE',
            'Voice recording already active for session: ${params.sessionId}',
            voiceInputId: sessionActiveInputs.first.id,
            userMessage: 'Voice recording is already in progress.',
          ),
        );
      }

      // Create new voice input
      final voiceInput = VoiceInput(
        id: _generateVoiceInputId(),
        sessionId: params.sessionId,
        status: VoiceInputStatus.recording,
        timestamp: DateTime.now(),
        metadata: {
          ...?params.metadata,
          if (params.deviceId != null) 'deviceId': params.deviceId,
          'startedAt': DateTime.now().toIso8601String(),
        },
      );

      // Save voice input
      final createdVoiceInput = await _voiceRepository.create(voiceInput);

      // Update session activity
      await _sessionRepository.updateActivity(params.sessionId);

      return UseCaseResult.success(createdVoiceInput);

    } catch (error) {
      if (error is AppError) {
        return UseCaseResult.failure(error);
      }
      
      return UseCaseResult.failure(
        VoiceError.recordingFailed()..metadata?.addAll({
          'sessionId': params.sessionId,
          'originalError': error.toString(),
        }),
      );
    }
  }

  String _generateVoiceInputId() {
    return 'voice_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomSuffix()}';
  }

  String _generateRandomSuffix() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().microsecond;
    return List.generate(4, (index) => chars[random % chars.length]).join();
  }
}