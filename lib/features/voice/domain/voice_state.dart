import 'package:equatable/equatable.dart';
import '../../../shared/models/models.dart';

/// Base type of every state the voice bloc emits.
abstract class VoiceState extends Equatable {
  /// Creates a state with no payload.
  const VoiceState();

  @override
  List<Object?> get props => [];
}

/// Nothing has happened yet, and permission has not been checked.
class VoiceInitial extends VoiceState {}

/// The permission check failed.
class VoicePermissionDenied extends VoiceState {
  /// Why the check failed.
  final String message;

  /// Creates the state with [message].
  const VoicePermissionDenied({required this.message});

  @override
  List<Object?> get props => [message];
}

/// Ready to record, with no input in progress.
class VoiceIdle extends VoiceState {
  /// Whether recording is allowed.
  final bool hasPermission;

  /// The voice settings in effect, or null when none were set.
  final Map<String, dynamic>? settings;

  /// Creates an idle state, without permission and without settings by default.
  const VoiceIdle({
    this.hasPermission = false,
    this.settings,
  });

  @override
  List<Object?> get props => [hasPermission, settings];
}

/// A recording is in progress.
class VoiceRecording extends VoiceState {
  /// The input being recorded.
  final VoiceInput voiceInput;

  /// Time since the recording started.
  final Duration elapsed;

  /// The latest input level between 0 and 1, or null before the first sample.
  final double? amplitude;

  /// Creates a recording state.
  const VoiceRecording({
    required this.voiceInput,
    required this.elapsed,
    this.amplitude,
  });

  @override
  List<Object?> get props => [voiceInput, elapsed, amplitude];
}

/// Audio is being transcribed.
class VoiceProcessing extends VoiceState {
  /// The input being processed.
  final VoiceInput voiceInput;

  /// A short progress line for the user.
  final String status;

  /// Creates a processing state.
  const VoiceProcessing({
    required this.voiceInput,
    required this.status,
  });

  @override
  List<Object?> get props => [voiceInput, status];
}

/// Transcription finished and the text is ready to review.
class VoiceTranscribed extends VoiceState {
  /// The input that was transcribed.
  final VoiceInput voiceInput;

  /// The transcribed text.
  final String transcription;

  /// The transcriber's confidence between 0 and 1.
  final double confidence;

  /// Creates a transcribed state.
  const VoiceTranscribed({
    required this.voiceInput,
    required this.transcription,
    required this.confidence,
  });

  @override
  List<Object?> get props => [voiceInput, transcription, confidence];
}

/// The user is editing the text before sending it.
class VoiceEditing extends VoiceState {
  /// The text as edited so far.
  final String text;

  /// The recording the text came from, or null when there is none.
  final VoiceInput? originalVoiceInput;

  /// Creates an editing state.
  const VoiceEditing({
    required this.text,
    this.originalVoiceInput,
  });

  @override
  List<Object?> get props => [text, originalVoiceInput];
}

/// The text is being sent to a session.
class VoiceSubmitting extends VoiceState {
  /// The text being sent.
  final String text;

  /// The session receiving the text.
  final String sessionId;

  /// Creates a submitting state.
  const VoiceSubmitting({
    required this.text,
    required this.sessionId,
  });

  @override
  List<Object?> get props => [text, sessionId];
}

/// The text reached the session.
class VoiceSubmitted extends VoiceState {
  /// The text that was sent.
  final String text;

  /// The session that received the text.
  final String sessionId;

  /// The job created for the text, or null when none was reported.
  final String? jobId;

  /// Creates a submitted state.
  const VoiceSubmitted({
    required this.text,
    required this.sessionId,
    this.jobId,
  });

  @override
  List<Object?> get props => [text, sessionId, jobId];
}

/// A step failed.
class VoiceError extends VoiceState {
  /// What went wrong.
  final String message;

  /// The input involved, or null when the failure was not tied to one.
  final VoiceInput? voiceInput;

  /// Creates an error state.
  const VoiceError({
    required this.message,
    this.voiceInput,
  });

  @override
  List<Object?> get props => [message, voiceInput];
}
