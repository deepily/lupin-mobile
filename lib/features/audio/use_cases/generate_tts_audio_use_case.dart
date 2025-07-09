import '../../../core/use_cases/base_use_case.dart';
import '../../../core/repositories/interfaces/voice_repository.dart';
import '../../../core/repositories/interfaces/job_repository.dart';
import '../../../core/repositories/interfaces/audio_repository.dart';
import '../../../core/error_handling/error_handler.dart';
import '../../../shared/models/models.dart';

/// Parameters for generating TTS audio
class GenerateTTSAudioParams {
  final String voiceInputId;
  final String text;
  final String? voiceModel;
  final double? speed;
  final double? pitch;
  final Map<String, dynamic>? ttsSettings;

  const GenerateTTSAudioParams({
    required this.voiceInputId,
    required this.text,
    this.voiceModel,
    this.speed,
    this.pitch,
    this.ttsSettings,
  });

  @override
  String toString() => 'GenerateTTSAudioParams(voiceInputId: $voiceInputId, text: "${text.length > 50 ? '${text.substring(0, 50)}...' : text}")';
}

/// Use case for generating TTS audio from text
class GenerateTTSAudioUseCase extends ParameterizedUseCase<AudioChunk, GenerateTTSAudioParams> {
  final VoiceRepository _voiceRepository;
  final JobRepository _jobRepository;
  final AudioRepository _audioRepository;

  GenerateTTSAudioUseCase(
    this._voiceRepository,
    this._jobRepository,
    this._audioRepository,
  );

  @override
  AppError? validateParams(GenerateTTSAudioParams params) {
    if (params.voiceInputId.isEmpty) {
      return ValidationError.required('voiceInputId');
    }
    if (params.text.isEmpty) {
      return ValidationError.required('text');
    }
    if (params.text.length > 5000) {
      return ValidationError(
        'TEXT_TOO_LONG',
        'Text exceeds maximum length of 5000 characters',
        field: 'text',
        value: params.text.length,
        userMessage: 'Text is too long for audio generation.',
      );
    }
    return null;
  }

  @override
  Future<UseCaseResult<AudioChunk>> executeInternal(GenerateTTSAudioParams params) async {
    try {
      // Validate voice input exists
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

      // Check if TTS audio already exists
      final existingAudio = await _audioRepository.findBySession(voiceInput.sessionId);
      final existingTTSAudio = existingAudio.where(
        (audio) => audio.metadata?['voice_input_id'] == params.voiceInputId && 
                   audio.type == AudioChunkType.output,
      ).toList();

      if (existingTTSAudio.isNotEmpty) {
        // Return existing audio if it matches the text
        final existingText = existingTTSAudio.first.metadata?['text'];
        if (existingText == params.text) {
          return UseCaseResult.success(existingTTSAudio.first);
        }
      }

      // Create TTS job
      final ttsJob = await _createTTSJob(voiceInput, params);

      // Create audio chunk placeholder
      final audioChunk = AudioChunk(
        id: 'audio_${params.voiceInputId}_${DateTime.now().millisecondsSinceEpoch}',
        sessionId: voiceInput.sessionId,
        jobId: ttsJob.id,
        chunkIndex: 0,
        type: AudioChunkType.output,
        localPath: null, // Will be set when audio is generated
        timestamp: DateTime.now(),
        metadata: {
          'voice_input_id': params.voiceInputId,
          'text': params.text,
          'voice_model': params.voiceModel ?? 'default',
          'speed': params.speed ?? 1.0,
          'pitch': params.pitch ?? 1.0,
          'status': 'generating',
          'tts_job_id': ttsJob.id,
          ...?params.ttsSettings,
        },
      );

      final createdAudioChunk = await _audioRepository.create(audioChunk);

      return UseCaseResult.success(createdAudioChunk);

    } catch (error) {
      if (error is AppError) {
        return UseCaseResult.failure(error);
      }
      
      return UseCaseResult.failure(
        VoiceError.ttsGenerationFailed(params.voiceInputId),
      );
    }
  }

  Future<Job> _createTTSJob(VoiceInput voiceInput, GenerateTTSAudioParams params) async {
    final ttsJob = Job(
      id: 'tts_${params.voiceInputId}_${DateTime.now().millisecondsSinceEpoch}',
      text: 'Generate TTS audio: ${params.text}',
      status: JobStatus.todo,
      createdAt: DateTime.now(),
      metadata: {
        'type': 'tts_generation',
        'voice_input_id': params.voiceInputId,
        'session_id': voiceInput.sessionId,
        'text': params.text,
        'voice_model': params.voiceModel ?? 'default',
        'speed': params.speed ?? 1.0,
        'pitch': params.pitch ?? 1.0,
        'priority': 'high',
        'estimated_duration_seconds': _estimateAudioDuration(params.text, params.speed ?? 1.0),
        ...?params.ttsSettings,
      },
    );

    return await _jobRepository.create(ttsJob);
  }

  int _estimateAudioDuration(String text, double speed) {
    // Rough estimation: ~150 words per minute at normal speed
    final wordCount = text.split(' ').length;
    final baseMinutes = wordCount / 150.0;
    final adjustedMinutes = baseMinutes / speed;
    return (adjustedMinutes * 60).ceil();
  }
}

/// Use case for playing audio
class PlayAudioUseCase extends ParameterizedUseCase<bool, String> {
  final AudioRepository _audioRepository;

  PlayAudioUseCase(this._audioRepository);

  @override
  AppError? validateParams(String audioChunkId) {
    if (audioChunkId.isEmpty) {
      return ValidationError.required('audioChunkId');
    }
    return null;
  }

  @override
  Future<UseCaseResult<bool>> executeInternal(String audioChunkId) async {
    try {
      // Get audio chunk
      final audioChunk = await _audioRepository.findById(audioChunkId);
      if (audioChunk == null) {
        return UseCaseResult.failure(
          VoiceError(
            'AUDIO_CHUNK_NOT_FOUND',
            'Audio chunk not found: $audioChunkId',
            audioPath: audioChunkId,
            userMessage: 'Audio file not found.',
          ),
        );
      }

      // Check if audio file exists
      if (audioChunk.localPath == null) {
        return UseCaseResult.failure(
          VoiceError(
            'AUDIO_FILE_NOT_READY',
            'Audio file not ready for playback: $audioChunkId',
            audioPath: audioChunk.localPath,
            userMessage: 'Audio is still being generated.',
          ),
        );
      }

      // Update playback state
      await _audioRepository.updatePlaybackState(audioChunkId, true);

      // TODO: Implement actual audio playback using platform-specific audio player
      // For now, we simulate playback by updating metadata
      
      return UseCaseResult.success(true);

    } catch (error) {
      if (error is AppError) {
        return UseCaseResult.failure(error);
      }
      
      return UseCaseResult.failure(
        VoiceError.audioPlaybackFailed(audioChunkId),
      );
    }
  }
}

/// Use case for stopping audio playback
class StopAudioUseCase extends ParameterizedUseCase<bool, String> {
  final AudioRepository _audioRepository;

  StopAudioUseCase(this._audioRepository);

  @override
  AppError? validateParams(String audioChunkId) {
    if (audioChunkId.isEmpty) {
      return ValidationError.required('audioChunkId');
    }
    return null;
  }

  @override
  Future<UseCaseResult<bool>> executeInternal(String audioChunkId) async {
    try {
      // Get audio chunk
      final audioChunk = await _audioRepository.findById(audioChunkId);
      if (audioChunk == null) {
        return UseCaseResult.failure(
          VoiceError(
            'AUDIO_CHUNK_NOT_FOUND',
            'Audio chunk not found: $audioChunkId',
            audioPath: audioChunkId,
          ),
        );
      }

      // Update playback state to stopped
      await _audioRepository.updatePlaybackState(audioChunkId, false);

      return UseCaseResult.success(true);

    } catch (error) {
      if (error is AppError) {
        return UseCaseResult.failure(error);
      }
      
      return UseCaseResult.failure(
        VoiceError(
          'STOP_AUDIO_FAILED',
          'Failed to stop audio playback: $error',
          audioPath: audioChunkId,
          userMessage: 'Failed to stop audio playback.',
        ),
      );
    }
  }
}

/// Stream use case for watching audio generation progress
class WatchAudioGenerationProgressUseCase extends StreamUseCase<AudioChunk, String> {
  final AudioRepository _audioRepository;

  WatchAudioGenerationProgressUseCase(this._audioRepository);

  @override
  Stream<UseCaseResult<AudioChunk>> call(String audioChunkId) async* {
    try {
      await for (final audioChunk in _audioRepository.watchById(audioChunkId)) {
        if (audioChunk != null) {
          yield UseCaseResult.success(audioChunk);
        } else {
          yield UseCaseResult.failure(
            VoiceError(
              'AUDIO_CHUNK_DELETED',
              'Audio chunk was deleted: $audioChunkId',
              audioPath: audioChunkId,
            ),
          );
          break;
        }
      }
    } catch (error) {
      yield UseCaseResult.failure(
        VoiceError(
          'WATCH_AUDIO_FAILED',
          'Failed to watch audio generation: $error',
          audioPath: audioChunkId,
        ),
      );
    }
  }
}