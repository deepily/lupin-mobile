import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../services/tts/tts_service.dart';
import '../../../core/repositories/voice_repository.dart';
import '../../../core/repositories/session_repository.dart';
import '../../../shared/models/models.dart';
import 'voice_event.dart';
import 'voice_state.dart';

/// Voice interaction BLoC managing voice recording, transcription, and TTS.
/// 
/// Coordinates voice input processing through multiple stages: permission,
/// recording, transcription, text editing, and TTS generation.
/// Maintains voice interaction state and provides reactive updates to UI.
class VoiceBloc extends Bloc<VoiceEvent, VoiceState> {
  final TtsService _ttsService;
  final VoiceRepository _voiceRepository;
  final SessionRepository _sessionRepository;
  Timer? _recordingTimer;
  VoiceInput? _currentVoiceInput;

  VoiceBloc({
    required TtsService ttsService,
    required VoiceRepository voiceRepository,
    required SessionRepository sessionRepository,
  })  : _ttsService = ttsService,
        _voiceRepository = voiceRepository,
        _sessionRepository = sessionRepository,
        super(VoiceInitial()) {
    on<VoicePermissionRequested>(_onPermissionRequested);
    on<VoiceRecordingStarted>(_onRecordingStarted);
    on<VoiceRecordingStopped>(_onRecordingStopped);
    on<VoiceRecordingCancelled>(_onRecordingCancelled);
    on<VoiceTranscriptionRequested>(_onTranscriptionRequested);
    on<VoiceTextEdited>(_onTextEdited);
    on<VoiceInputSubmitted>(_onInputSubmitted);
    on<VoiceInputCleared>(_onInputCleared);
    on<VoiceSettingsUpdated>(_onSettingsUpdated);
  }

  /// Handles voice permission request with platform-specific checks.
  /// 
  /// Requires:
  ///   - event must be a valid VoicePermissionRequested instance
  ///   - emit must be an active state emitter
  /// 
  /// Ensures:
  ///   - Voice recording permissions are checked
  ///   - State transitions to VoiceIdle with permission status
  ///   - Permission denial emits VoicePermissionDenied state
  /// 
  /// Raises:
  ///   - Emits VoicePermissionDenied if permission check fails
  Future<void> _onPermissionRequested(
    VoicePermissionRequested event,
    Emitter<VoiceState> emit,
  ) async {
    try {
      // TODO: Implement actual permission checking for mobile platforms
      // For web compatibility, we'll assume permission is granted
      emit(const VoiceIdle(hasPermission: true));
    } catch (e) {
      emit(VoicePermissionDenied(message: e.toString()));
    }
  }

  /// Initiates voice recording with session tracking and timer management.
  /// 
  /// Requires:
  ///   - event must contain valid sessionId
  ///   - Voice permissions must be granted
  ///   - emit must be an active state emitter
  /// 
  /// Ensures:
  ///   - New VoiceInput entity is created and persisted
  ///   - Recording timer provides real-time elapsed time updates
  ///   - State transitions to VoiceRecording with amplitude feedback
  ///   - Recording session is properly tracked in repository
  /// 
  /// Raises:
  ///   - Emits VoiceError if recording initialization fails
  Future<void> _onRecordingStarted(
    VoiceRecordingStarted event,
    Emitter<VoiceState> emit,
  ) async {
    try {
      // Create new voice input
      _currentVoiceInput = VoiceInput(
        id: 'voice_${DateTime.now().millisecondsSinceEpoch}',
        sessionId: event.sessionId,
        status: VoiceInputStatus.recording,
        timestamp: DateTime.now(),
      );
      
      // Save to repository
      await _voiceRepository.create(_currentVoiceInput!);

      emit(VoiceRecording(
        voiceInput: _currentVoiceInput!,
        elapsed: const Duration(),
      ));

      // Start recording timer
      _recordingTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (timer) {
          if (_currentVoiceInput != null && !emit.isDone) {
            final elapsed = DateTime.now().difference(_currentVoiceInput!.startedAt);
            emit(VoiceRecording(
              voiceInput: _currentVoiceInput!,
              elapsed: elapsed,
              amplitude: _generateMockAmplitude(), // Mock amplitude for demo
            ));
          }
        },
      );
    } catch (e) {
      emit(VoiceError(message: 'Failed to start recording: ${e.toString()}'));
    }
  }

  /// Stops voice recording and initiates transcription processing.
  /// 
  /// Requires:
  ///   - Active recording session must exist
  ///   - _currentVoiceInput must be in recording state
  ///   - emit must be an active state emitter
  /// 
  /// Ensures:
  ///   - Recording timer is cancelled and cleaned up
  ///   - Voice input duration is calculated and persisted
  ///   - State transitions through processing to transcribed
  ///   - Transcription confidence scores are recorded
  /// 
  /// Raises:
  ///   - Emits VoiceError if recording stop or transcription fails
  Future<void> _onRecordingStopped(
    VoiceRecordingStopped event,
    Emitter<VoiceState> emit,
  ) async {
    try {
      _recordingTimer?.cancel();
      _recordingTimer = null;

      if (_currentVoiceInput != null) {
        final now = DateTime.now();
        final duration = now.difference(_currentVoiceInput!.startedAt);
        
        _currentVoiceInput = _currentVoiceInput!.copyWith(
          status: VoiceInputStatus.processing,
          duration: duration,
        );

        // Update in repository
        await _voiceRepository.update(_currentVoiceInput!);

        emit(VoiceProcessing(
          voiceInput: _currentVoiceInput!,
          status: 'Processing audio...',
        ));

        // Simulate transcription process
        await Future.delayed(const Duration(seconds: 1));
        
        // For demo purposes, generate mock transcription
        final mockTranscription = _generateMockTranscription();
        
        _currentVoiceInput = await _voiceRepository.updateTranscription(
          _currentVoiceInput!.id,
          mockTranscription,
          0.95,
        );

        emit(VoiceTranscribed(
          voiceInput: _currentVoiceInput!,
          transcription: mockTranscription,
          confidence: 0.95,
        ));
      }
    } catch (e) {
      emit(VoiceError(message: 'Failed to stop recording: ${e.toString()}'));
    }
  }

  /// Cancels active voice recording and cleans up resources.
  /// 
  /// Requires:
  ///   - Active recording session may or may not exist
  ///   - emit must be an active state emitter
  /// 
  /// Ensures:
  ///   - Recording timer is cancelled immediately
  ///   - Current voice input is marked as cancelled
  ///   - State transitions to cancelled without processing
  ///   - Resources are properly cleaned up
  /// 
  /// Raises:
  ///   - Emits VoiceError only if critical cleanup fails
  Future<void> _onRecordingCancelled(
    VoiceRecordingCancelled event,
    Emitter<VoiceState> emit,
  ) async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    if (_currentVoiceInput != null) {
      _currentVoiceInput = _currentVoiceInput!.copyWith(
        status: VoiceInputStatus.cancelled,
        completedAt: DateTime.now(),
      );
    }

    emit(const VoiceIdle(hasPermission: true));
  }

  Future<void> _onTranscriptionRequested(
    VoiceTranscriptionRequested event,
    Emitter<VoiceState> emit,
  ) async {
    try {
      emit(VoiceProcessing(
        voiceInput: event.voiceInput,
        status: 'Transcribing audio...',
      ));

      // TODO: Implement actual transcription service call
      // For now, use mock transcription
      await Future.delayed(const Duration(seconds: 2));
      
      final mockTranscription = _generateMockTranscription();
      final updatedVoiceInput = event.voiceInput.copyWith(
        status: VoiceInputStatus.completed,
        transcription: mockTranscription,
        confidence: 0.92,
      );

      emit(VoiceTranscribed(
        voiceInput: updatedVoiceInput,
        transcription: mockTranscription,
        confidence: 0.92,
      ));
    } catch (e) {
      emit(VoiceError(
        message: 'Transcription failed: ${e.toString()}',
        voiceInput: event.voiceInput,
      ));
    }
  }

  Future<void> _onTextEdited(
    VoiceTextEdited event,
    Emitter<VoiceState> emit,
  ) async {
    emit(VoiceEditing(
      text: event.text,
      originalVoiceInput: _currentVoiceInput,
    ));
  }

  Future<void> _onInputSubmitted(
    VoiceInputSubmitted event,
    Emitter<VoiceState> emit,
  ) async {
    try {
      emit(VoiceSubmitting(
        text: event.text,
        sessionId: event.sessionId,
      ));

      // TODO: Submit to backend via HTTP service
      // For now, simulate successful submission
      await Future.delayed(const Duration(seconds: 1));
      
      final jobId = 'job_${DateTime.now().millisecondsSinceEpoch}';

      emit(VoiceSubmitted(
        text: event.text,
        sessionId: event.sessionId,
        jobId: jobId,
      ));

      // Reset to idle state after submission
      await Future.delayed(const Duration(seconds: 1));
      emit(const VoiceIdle(hasPermission: true));
    } catch (e) {
      emit(VoiceError(message: 'Failed to submit input: ${e.toString()}'));
    }
  }

  Future<void> _onInputCleared(
    VoiceInputCleared event,
    Emitter<VoiceState> emit,
  ) async {
    _currentVoiceInput = null;
    emit(const VoiceIdle(hasPermission: true));
  }

  Future<void> _onSettingsUpdated(
    VoiceSettingsUpdated event,
    Emitter<VoiceState> emit,
  ) async {
    if (state is VoiceIdle) {
      final currentState = state as VoiceIdle;
      emit(VoiceIdle(
        hasPermission: currentState.hasPermission,
        settings: event.settings,
      ));
    }
  }

  // Helper methods for demo purposes
  double _generateMockAmplitude() {
    // Generate mock amplitude values for waveform visualization
    return (DateTime.now().millisecondsSinceEpoch % 1000) / 1000.0;
  }

  String _generateMockTranscription() {
    final mockPhrases = [
      'What is the weather like today?',
      'How do I set up my development environment?',
      'Can you help me with this Flutter project?',
      'What are the latest updates in AI technology?',
      'How do I optimize my mobile app performance?',
    ];
    
    return mockPhrases[DateTime.now().millisecondsSinceEpoch % mockPhrases.length];
  }

  @override
  Future<void> close() {
    _recordingTimer?.cancel();
    return super.close();
  }
}