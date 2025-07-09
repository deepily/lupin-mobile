import 'dart:typed_data';
import 'package:equatable/equatable.dart';

enum VoiceInputStatus {
  idle,
  recording,
  processing,
  transcribing,
  completed,
  error,
  cancelled,
}

enum AudioFormat {
  wav,
  mp3,
  m4a,
  webm,
  ogg,
}

class VoiceInput extends Equatable {
  final String id;
  final String sessionId;
  final VoiceInputStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final Duration? duration;
  final String? transcription;
  final double? confidence;
  final Uint8List? audioData;
  final AudioFormat? audioFormat;
  final int? sampleRate;
  final String? error;
  final Map<String, dynamic>? metadata;

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

  bool get isCompleted => status == VoiceInputStatus.completed;
  bool get hasError => status == VoiceInputStatus.error;
  bool get isProcessing => [
        VoiceInputStatus.recording,
        VoiceInputStatus.processing,
        VoiceInputStatus.transcribing,
      ].contains(status);

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