import '../../../core/use_cases/base_use_case.dart';
import '../../../core/error_handling/error_handler.dart';
import '../../../shared/models/models.dart';
import 'start_voice_recording_use_case.dart';
import 'stop_voice_recording_use_case.dart';
import 'process_voice_input_use_case.dart';
import '../../audio/use_cases/generate_tts_audio_use_case.dart';

/// Parameters for complete voice interaction
class VoiceInteractionParams {
  final String sessionId;
  final String? deviceId;
  final bool enableTTS;
  final Map<String, dynamic>? voiceSettings;
  final Map<String, dynamic>? ttsSettings;

  const VoiceInteractionParams({
    required this.sessionId,
    this.deviceId,
    this.enableTTS = true,
    this.voiceSettings,
    this.ttsSettings,
  });

  @override
  String toString() => 'VoiceInteractionParams(sessionId: $sessionId, enableTTS: $enableTTS)';
}

/// Result of complete voice interaction
class VoiceInteractionResult {
  final VoiceInput voiceInput;
  final AudioChunk? ttsAudio;
  final Duration totalProcessingTime;
  final Map<String, dynamic> metrics;

  const VoiceInteractionResult({
    required this.voiceInput,
    this.ttsAudio,
    required this.totalProcessingTime,
    required this.metrics,
  });

  Map<String, dynamic> toJson() {
    return {
      'voice_input_id': voiceInput.id,
      'transcription': voiceInput.transcription,
      'response': voiceInput.response,
      'status': voiceInput.status.toString(),
      'has_tts_audio': ttsAudio != null,
      'total_processing_time_ms': totalProcessingTime.inMilliseconds,
      'metrics': metrics,
    };
  }
}

/// Orchestrator for complete voice interaction workflow
class VoiceInteractionOrchestrator extends ParameterizedUseCase<VoiceInteractionResult, VoiceInteractionParams> {
  final StartVoiceRecordingUseCase _startRecordingUseCase;
  final StopVoiceRecordingUseCase _stopRecordingUseCase;
  final ProcessVoiceInputUseCase _processVoiceUseCase;
  final GenerateTTSAudioUseCase _generateTTSUseCase;
  final WatchVoiceProcessingProgressUseCase _watchProgressUseCase;

  VoiceInteractionOrchestrator(
    this._startRecordingUseCase,
    this._stopRecordingUseCase,
    this._processVoiceUseCase,
    this._generateTTSUseCase,
    this._watchProgressUseCase,
  );

  @override
  AppError? validateParams(VoiceInteractionParams params) {
    if (params.sessionId.isEmpty) {
      return ValidationError.required('sessionId');
    }
    return null;
  }

  @override
  Future<UseCaseResult<VoiceInteractionResult>> executeInternal(VoiceInteractionParams params) async {
    final stopwatch = Stopwatch()..start();
    final metrics = <String, dynamic>{};
    
    try {
      // Step 1: Start voice recording
      metrics['step1_start'] = DateTime.now().toIso8601String();
      final startResult = await _startRecordingUseCase.execute(
        StartVoiceRecordingParams(
          sessionId: params.sessionId,
          deviceId: params.deviceId,
          metadata: params.voiceSettings,
        ),
      );

      if (startResult.isFailure) {
        return UseCaseResult.failure(startResult.error!);
      }

      final voiceInput = startResult.data!;
      metrics['step1_duration_ms'] = DateTime.now().difference(
        DateTime.parse(metrics['step1_start']),
      ).inMilliseconds;

      // Step 2: Simulate recording time (in real app, this would be user input)
      await Future.delayed(Duration(seconds: 2)); // Simulate 2-second recording

      // Step 3: Stop voice recording with simulated audio data
      metrics['step3_start'] = DateTime.now().toIso8601String();
      final audioData = _generateMockAudioData(); // In real app, this comes from microphone
      
      final stopResult = await _stopRecordingUseCase.execute(
        StopVoiceRecordingParams(
          voiceInputId: voiceInput.id,
          audioData: audioData,
          recordingDuration: Duration(seconds: 2),
          metadata: {'recorded_samples': audioData.length},
        ),
      );

      if (stopResult.isFailure) {
        return UseCaseResult.failure(stopResult.error!);
      }

      final stoppedVoiceInput = stopResult.data!;
      metrics['step3_duration_ms'] = DateTime.now().difference(
        DateTime.parse(metrics['step3_start']),
      ).inMilliseconds;

      // Step 4: Process voice input (transcription and response generation)
      metrics['step4_start'] = DateTime.now().toIso8601String();
      final processResult = await _processVoiceUseCase.execute(
        ProcessVoiceInputParams(
          voiceInputId: stoppedVoiceInput.id,
          enableTranscription: true,
          enableResponseGeneration: true,
          processingOptions: params.voiceSettings,
        ),
      );

      if (processResult.isFailure) {
        return UseCaseResult.failure(processResult.error!);
      }

      metrics['step4_duration_ms'] = DateTime.now().difference(
        DateTime.parse(metrics['step4_start']),
      ).inMilliseconds;

      // Step 5: Wait for transcription and response (simulated)
      final completedVoiceInput = await _waitForVoiceProcessingCompletion(
        stoppedVoiceInput.id,
        timeout: Duration(seconds: 30),
      );

      if (completedVoiceInput == null) {
        return UseCaseResult.failure(
          VoiceError(
            'PROCESSING_TIMEOUT',
            'Voice processing timed out',
            voiceInputId: stoppedVoiceInput.id,
            userMessage: 'Voice processing is taking too long. Please try again.',
          ),
        );
      }

      // Step 6: Generate TTS audio if enabled and response is available
      AudioChunk? ttsAudio;
      if (params.enableTTS && completedVoiceInput.response != null) {
        metrics['step6_start'] = DateTime.now().toIso8601String();
        
        final ttsResult = await _generateTTSUseCase.execute(
          GenerateTTSAudioParams(
            voiceInputId: completedVoiceInput.id,
            text: completedVoiceInput.response!,
            ttsSettings: params.ttsSettings,
          ),
        );

        if (ttsResult.isSuccess) {
          ttsAudio = ttsResult.data!;
        }

        metrics['step6_duration_ms'] = DateTime.now().difference(
          DateTime.parse(metrics['step6_start']),
        ).inMilliseconds;
      }

      stopwatch.stop();
      
      // Compile final metrics
      metrics.addAll({
        'total_steps': 6,
        'transcription_length': completedVoiceInput.transcription?.length ?? 0,
        'response_length': completedVoiceInput.response?.length ?? 0,
        'tts_generated': ttsAudio != null,
        'audio_data_size': audioData.length,
        'confidence_score': completedVoiceInput.confidence ?? 0.0,
      });

      final result = VoiceInteractionResult(
        voiceInput: completedVoiceInput,
        ttsAudio: ttsAudio,
        totalProcessingTime: stopwatch.elapsed,
        metrics: metrics,
      );

      return UseCaseResult.success(result);

    } catch (error) {
      stopwatch.stop();
      
      if (error is AppError) {
        return UseCaseResult.failure(error);
      }
      
      return UseCaseResult.failure(
        VoiceError(
          'VOICE_INTERACTION_FAILED',
          'Voice interaction orchestration failed: $error',
          userMessage: 'Voice interaction failed. Please try again.',
        ),
      );
    }
  }

  /// Wait for voice processing to complete with timeout
  Future<VoiceInput?> _waitForVoiceProcessingCompletion(
    String voiceInputId, {
    required Duration timeout,
  }) async {
    final completer = Completer<VoiceInput?>();
    late StreamSubscription subscription;

    // Set up timeout
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.complete(null);
      }
    });

    // Watch for completion
    subscription = _watchProgressUseCase.execute(voiceInputId).listen(
      (result) {
        if (result.isSuccess) {
          final voiceInput = result.data!;
          
          if (voiceInput.status == VoiceInputStatus.completed) {
            timer.cancel();
            subscription.cancel();
            if (!completer.isCompleted) {
              completer.complete(voiceInput);
            }
          } else if (voiceInput.status == VoiceInputStatus.failed) {
            timer.cancel();
            subscription.cancel();
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        } else {
          timer.cancel();
          subscription.cancel();
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        }
      },
      onError: (error) {
        timer.cancel();
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
    );

    return completer.future;
  }

  /// Generate mock audio data for testing
  List<int> _generateMockAudioData() {
    // Generate 2 seconds of mock 16kHz audio data
    const sampleRate = 16000;
    const duration = 2;
    const totalSamples = sampleRate * duration;
    
    return List.generate(totalSamples, (index) {
      // Generate a simple sine wave for testing
      final frequency = 440.0; // A4 note
      final sample = (32767 * 0.5 * Math.sin(2 * Math.pi * frequency * index / sampleRate)).round();
      return sample.clamp(-32768, 32767);
    });
  }
}

/// Simplified voice interaction for quick testing
class QuickVoiceInteractionUseCase extends ParameterizedUseCase<VoiceInteractionResult, String> {
  final VoiceInteractionOrchestrator _orchestrator;

  QuickVoiceInteractionUseCase(this._orchestrator);

  @override
  AppError? validateParams(String sessionId) {
    if (sessionId.isEmpty) {
      return ValidationError.required('sessionId');
    }
    return null;
  }

  @override
  Future<UseCaseResult<VoiceInteractionResult>> executeInternal(String sessionId) async {
    return await _orchestrator.execute(
      VoiceInteractionParams(
        sessionId: sessionId,
        enableTTS: true,
        voiceSettings: {
          'language': 'en-US',
          'model': 'whisper-1',
        },
        ttsSettings: {
          'voice_model': 'eleven_labs_v2',
          'speed': 1.0,
          'pitch': 1.0,
        },
      ),
    );
  }
}

// Required for mock audio generation
import 'dart:math' as Math;
import 'dart:async';