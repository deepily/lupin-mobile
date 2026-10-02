import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// Where one voice-input attempt is in its life.
enum VoiceInputStatus {
  /// Nothing is happening.
  idle,
  /// The microphone is capturing.
  recording,
  /// The recording is being prepared.
  processing,
  /// The recording is being turned into text.
  transcribing,
  /// The transcription is ready.
  completed,
  /// The attempt failed.
  error,
  /// The user cancelled the attempt.
  cancelled,
}

/// The encoding of recorded audio.
enum AudioFormat {
  /// Uncompressed WAV.
  wav,
  /// MP3.
  mp3,
  /// M4A.
  m4a,
  /// WebM.
  webm,
  /// Ogg.
  ogg,
}

/// One voice-input attempt, from recording to transcription.
class VoiceInput extends Equatable {
  /// Unique attempt identifier.
  final String id;
  /// The session the attempt belongs to.
  final String sessionId;
  /// Where the attempt is now.
  final VoiceInputStatus status;
  /// When recording started.
  final DateTime startedAt;
  /// When the attempt ended, or null while it is running.
  final DateTime? completedAt;
  /// Length of the recording, or null when not known.
  final Duration? duration;
  /// The recognized text, or null until it is ready.
  final String? transcription;
  /// The recognizer's confidence, or null.
  final double? confidence;
  /// The encoded recording, or null when it was not kept.
  final Uint8List? audioData;
  /// The encoding of [audioData], or null.
  final AudioFormat? audioFormat;
  /// Sample rate in hertz, or null.
  final int? sampleRate;
  /// The failure message, or null when there is none.
  final String? error;
  /// Free-form extra fields, or null.
  final Map<String, dynamic>? metadata;

  /// Creates a voice-input attempt.
  const VoiceInput({
    required this.id,
    required this.sessionId,
    this.status = VoiceInputStatus.idle,
    required this.startedAt,
    this.completedAt,
    this.duration,
    this.transcription,
    this.confidence,
    this.audioData,
    this.audioFormat,
    this.sampleRate,
    this.error,
    this.metadata,
  });

  /// Returns a copy with the given fields replaced.
  VoiceInput copyWith({
    String? id,
    String? sessionId,
    VoiceInputStatus? status,
    DateTime? startedAt,
    DateTime? completedAt,
    Duration? duration,
    String? transcription,
    double? confidence,
    Uint8List? audioData,
    AudioFormat? audioFormat,
    int? sampleRate,
    String? error,
    Map<String, dynamic>? metadata,
  }) {
    return VoiceInput(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      duration: duration ?? this.duration,
      transcription: transcription ?? this.transcription,
      confidence: confidence ?? this.confidence,
      audioData: audioData ?? this.audioData,
      audioFormat: audioFormat ?? this.audioFormat,
      sampleRate: sampleRate ?? this.sampleRate,
      error: error ?? this.error,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Whether the transcription is ready.
  bool get isCompleted => status == VoiceInputStatus.completed;
  /// Whether the attempt failed.
  bool get hasError => status == VoiceInputStatus.error;
  /// Whether the attempt is recording, processing or transcribing.
  bool get isProcessing => [
        VoiceInputStatus.recording,
        VoiceInputStatus.processing,
        VoiceInputStatus.transcribing,
      ].contains(status);

  /// Builds an attempt from its wire map.
  ///
  /// An unknown status becomes idle and an unknown format becomes wav.
  factory VoiceInput.fromJson(Map<String, dynamic> json) {
    return VoiceInput(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      status: VoiceInputStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => VoiceInputStatus.idle,
      ),
      startedAt: DateTime.parse(json['started_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'] as int)
          : null,
      transcription: json['transcription'] as String?,
      confidence: json['confidence'] as double?,
      audioFormat: json['audio_format'] != null
          ? AudioFormat.values.firstWhere(
              (e) => e.name == json['audio_format'],
              orElse: () => AudioFormat.wav,
            )
          : null,
      sampleRate: json['sample_rate'] as int?,
      error: json['error'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Returns the wire map for this attempt.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'status': status.name,
      'started_at': startedAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'duration': duration?.inMilliseconds,
      'transcription': transcription,
      'confidence': confidence,
      'audio_format': audioFormat?.name,
      'sample_rate': sampleRate,
      'error': error,
      'metadata': metadata,
    };
  }

  @override
  List<Object?> get props => [
        id,
        sessionId,
        status,
        startedAt,
        completedAt,
        duration,
        transcription,
        confidence,
        audioFormat,
        sampleRate,
        error,
        metadata,
      ];
}