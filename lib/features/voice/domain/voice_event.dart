import 'package:equatable/equatable.dart';
import '../../../shared/models/models.dart';

abstract class VoiceEvent extends Equatable {
  const VoiceEvent();

  @override
  List<Object?> get props => [];
}

class VoiceRecordingStarted extends VoiceEvent {
  final String sessionId;

  const VoiceRecordingStarted({required this.sessionId});

  @override
  List<Object?> get props => [sessionId];
}

class VoiceRecordingStopped extends VoiceEvent {}

class VoiceRecordingCancelled extends VoiceEvent {}

class VoiceTranscriptionRequested extends VoiceEvent {
  final VoiceInput voiceInput;

  const VoiceTranscriptionRequested({required this.voiceInput});

  @override
  List<Object?> get props => [voiceInput];
}

class VoiceTextEdited extends VoiceEvent {
  final String text;

  const VoiceTextEdited({required this.text});

  @override
  List<Object?> get props => [text];
}

class VoiceInputSubmitted extends VoiceEvent {
  final String text;
  final String sessionId;

  const VoiceInputSubmitted({
    required this.text,
    required this.sessionId,
  });

  @override
  List<Object?> get props => [text, sessionId];
}

class VoiceInputCleared extends VoiceEvent {}

class VoicePermissionRequested extends VoiceEvent {}

class VoiceSettingsUpdated extends VoiceEvent {
  final Map<String, dynamic> settings;

  const VoiceSettingsUpdated({required this.settings});

  @override
  List<Object?> get props => [settings];
}