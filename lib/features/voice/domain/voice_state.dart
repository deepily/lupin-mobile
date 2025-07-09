import 'package:equatable/equatable.dart';
import '../../../shared/models/models.dart';

abstract class VoiceState extends Equatable {
  const VoiceState();

  @override
  List<Object?> get props => [];
}

class VoiceInitial extends VoiceState {}

class VoicePermissionDenied extends VoiceState {
  final String message;

  const VoicePermissionDenied({required this.message});

  @override
  List<Object?> get props => [message];
}

class VoiceIdle extends VoiceState {
  final bool hasPermission;
  final Map<String, dynamic>? settings;

  const VoiceIdle({
    this.hasPermission = false,
    this.settings,
  });

  @override
  List<Object?> get props => [hasPermission, settings];
}

class VoiceRecording extends VoiceState {
  final VoiceInput voiceInput;
  final Duration elapsed;
  final double? amplitude;

  const VoiceRecording({
    required this.voiceInput,
    required this.elapsed,
    this.amplitude,
  });

  @override
  List<Object?> get props => [voiceInput, elapsed, amplitude];
}

class VoiceProcessing extends VoiceState {
  final VoiceInput voiceInput;
  final String status;

  const VoiceProcessing({
    required this.voiceInput,
    required this.status,
  });

  @override
  List<Object?> get props => [voiceInput, status];
}

class VoiceTranscribed extends VoiceState {
  final VoiceInput voiceInput;
  final String transcription;
  final double confidence;

  const VoiceTranscribed({
    required this.voiceInput,
    required this.transcription,
    required this.confidence,
  });

  @override
  List<Object?> get props => [voiceInput, transcription, confidence];
}

class VoiceEditing extends VoiceState {
  final String text;
  final VoiceInput? originalVoiceInput;

  const VoiceEditing({
    required this.text,
    this.originalVoiceInput,
  });

  @override
  List<Object?> get props => [text, originalVoiceInput];
}

class VoiceSubmitting extends VoiceState {
  final String text;
  final String sessionId;

  const VoiceSubmitting({
    required this.text,
    required this.sessionId,
  });

  @override
  List<Object?> get props => [text, sessionId];
}

class VoiceSubmitted extends VoiceState {
  final String text;
  final String sessionId;
  final String? jobId;

  const VoiceSubmitted({
    required this.text,
    required this.sessionId,
    this.jobId,
  });

  @override
  List<Object?> get props => [text, sessionId, jobId];
}

class VoiceError extends VoiceState {
  final String message;
  final VoiceInput? voiceInput;

  const VoiceError({
    required this.message,
    this.voiceInput,
  });

  @override
  List<Object?> get props => [message, voiceInput];
}