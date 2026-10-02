import 'package:equatable/equatable.dart';
import '../../../shared/models/models.dart';

/// Base type of every event the voice bloc handles.
abstract class VoiceEvent extends Equatable {
  /// Creates an event with no payload.
  const VoiceEvent();

  @override
  List<Object?> get props => [];
}

/// Starts a recording for a session.
class VoiceRecordingStarted extends VoiceEvent {
  /// The session the recording belongs to.
  final String sessionId;

  /// Creates the event for [sessionId].
  const VoiceRecordingStarted({required this.sessionId});

  @override
  List<Object?> get props => [sessionId];
}

/// Stops the active recording and moves on to transcription.
class VoiceRecordingStopped extends VoiceEvent {}

/// Abandons the active recording without transcribing it.
class VoiceRecordingCancelled extends VoiceEvent {}

/// Asks for an existing voice input to be transcribed.
class VoiceTranscriptionRequested extends VoiceEvent {
  /// The voice input to transcribe.
  final VoiceInput voiceInput;

  /// Creates the event for [voiceInput].
  const VoiceTranscriptionRequested({required this.voiceInput});

  @override
  List<Object?> get props => [voiceInput];
}

/// Reports that the user changed the transcribed text.
class VoiceTextEdited extends VoiceEvent {
  /// The full text after the edit.
  final String text;

  /// Creates the event for [text].
  const VoiceTextEdited({required this.text});

  @override
  List<Object?> get props => [text];
}

/// Submits the final text to a session.
class VoiceInputSubmitted extends VoiceEvent {
  /// The text to send.
  final String text;

  /// The session that receives the text.
  final String sessionId;

  /// Creates the event for [text] and [sessionId].
  const VoiceInputSubmitted({
    required this.text,
    required this.sessionId,
  });

  @override
  List<Object?> get props => [text, sessionId];
}

/// Discards the current voice input and returns to idle.
class VoiceInputCleared extends VoiceEvent {}

/// Asks for the recording permission to be checked.
class VoicePermissionRequested extends VoiceEvent {}

/// Replaces the voice settings held while idle.
class VoiceSettingsUpdated extends VoiceEvent {
  /// The new settings, keyed by name.
  final Map<String, dynamic> settings;

  /// Creates the event for [settings].
  const VoiceSettingsUpdated({required this.settings});

  @override
  List<Object?> get props => [settings];
}
