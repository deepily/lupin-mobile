import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// What produced an audio chunk.
enum AudioChunkType {
  /// Speech synthesized from text.
  tts,
  /// A recording of the user's voice.
  voice,
  /// A sound that accompanies a notification.
  notification,
  /// An application sound.
  system,
}

/// Playback state of an audio chunk.
enum AudioChunkStatus {
  /// Waiting to be played.
  pending,
  /// Playing now.
  playing,
  /// Played to the end.
  completed,
  /// Playback failed.
  failed,
  /// Stored locally and ready to replay.
  cached,
}

/// One piece of streamed or cached audio with its playback state.
class AudioChunk extends Equatable {
  /// Unique chunk identifier.
  final String id;
  /// What produced this chunk.
  final AudioChunkType type;
  /// Current playback state.
  final AudioChunkStatus status;
  /// The encoded audio bytes.
  final Uint8List data;
  /// The text that was spoken, or null when not known.
  final String? text;
  /// Name of the speech provider, or null.
  final String? provider;
  /// Provider voice identifier, or null.
  final String? voiceId;
  /// Zero-based position within a multi-chunk stream, or null for a single chunk.
  final int? sequenceNumber;
  /// Number of chunks in the stream, or null when not known.
  final int? totalChunks;
  /// When the chunk was produced.
  final DateTime timestamp;
  /// Playing time, or null when not known.
  final Duration? duration;
  /// Sample rate in hertz, or null.
  final int? sampleRate;
  /// Bit rate in bits per second, or null.
  final int? bitRate;
  /// Container or codec name, or null.
  final String? format;
  /// Free-form extra fields, or null.
  final Map<String, dynamic>? metadata;

  /// Creates an audio chunk.
  const AudioChunk({
    required this.id,
    required this.type,
    this.status = AudioChunkStatus.pending,
    required this.data,
    this.text,
    this.provider,
    this.voiceId,
    this.sequenceNumber,
    this.totalChunks,
    required this.timestamp,
    this.duration,
    this.sampleRate,
    this.bitRate,
    this.format,
    this.metadata,
  });

  /// Returns a copy with the given fields replaced.
  AudioChunk copyWith({
    String? id,
    AudioChunkType? type,
    AudioChunkStatus? status,
    Uint8List? data,
    String? text,
    String? provider,
    String? voiceId,
    int? sequenceNumber,
    int? totalChunks,
    DateTime? timestamp,
    Duration? duration,
    int? sampleRate,
    int? bitRate,
    String? format,
    Map<String, dynamic>? metadata,
  }) {
    return AudioChunk(
      id: id ?? this.id,
      type: type ?? this.type,
      status: status ?? this.status,
      data: data ?? this.data,
      text: text ?? this.text,
      provider: provider ?? this.provider,
      voiceId: voiceId ?? this.voiceId,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      totalChunks: totalChunks ?? this.totalChunks,
      timestamp: timestamp ?? this.timestamp,
      duration: duration ?? this.duration,
      sampleRate: sampleRate ?? this.sampleRate,
      bitRate: bitRate ?? this.bitRate,
      format: format ?? this.format,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Whether this is the final chunk of its stream; false when position or total is unknown.
  bool get isLastChunk {
    return sequenceNumber != null && 
           totalChunks != null && 
           sequenceNumber! >= totalChunks! - 1;
  }

  /// Whether this is the first chunk of its stream.
  bool get isFirstChunk {
    return sequenceNumber == 0;
  }

  /// Whether the chunk is waiting or cached, so playing it makes sense.
  bool get canPlay {
    return status == AudioChunkStatus.pending || 
           status == AudioChunkStatus.cached;
  }

  /// The size of the audio data in bytes.
  int get sizeInBytes => data.length;

  /// Builds a chunk from its wire map; unknown type or status fall back to tts and pending.
  factory AudioChunk.fromJson(Map<String, dynamic> json) {
    return AudioChunk(
      id: json['id'] as String,
      type: AudioChunkType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => AudioChunkType.tts,
      ),
      status: AudioChunkStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => AudioChunkStatus.pending,
      ),
      data: Uint8List.fromList((json['data'] as List<dynamic>).cast<int>()),
      text: json['text'] as String?,
      provider: json['provider'] as String?,
      voiceId: json['voice_id'] as String?,
      sequenceNumber: json['sequence_number'] as int?,
      totalChunks: json['total_chunks'] as int?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'] as int)
          : null,
      sampleRate: json['sample_rate'] as int?,
      bitRate: json['bit_rate'] as int?,
      format: json['format'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Returns the wire map for this chunk.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'status': status.name,
      'data': data.toList(),
      'text': text,
      'provider': provider,
      'voice_id': voiceId,
      'sequence_number': sequenceNumber,
      'total_chunks': totalChunks,
      'timestamp': timestamp.toIso8601String(),
      'duration': duration?.inMilliseconds,
      'sample_rate': sampleRate,
      'bit_rate': bitRate,
      'format': format,
      'metadata': metadata,
    };
  }

  @override
  List<Object?> get props => [
        id,
        type,
        status,
        data,
        text,
        provider,
        voiceId,
        sequenceNumber,
        totalChunks,
        timestamp,
        duration,
        sampleRate,
        bitRate,
        format,
        metadata,
      ];
}