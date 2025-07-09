import 'dart:typed_data';
import 'package:equatable/equatable.dart';

enum AudioChunkType {
  tts,
  voice,
  notification,
  system,
}

enum AudioChunkStatus {
  pending,
  playing,
  completed,
  failed,
  cached,
}

class AudioChunk extends Equatable {
  final String id;
  final AudioChunkType type;
  final AudioChunkStatus status;
  final Uint8List data;
  final String? text;
  final String? provider;
  final String? voiceId;
  final int? sequenceNumber;
  final int? totalChunks;
  final DateTime timestamp;
  final Duration? duration;
  final int? sampleRate;
  final int? bitRate;
  final String? format;
  final Map<String, dynamic>? metadata;

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

  bool get isLastChunk {
    return sequenceNumber != null && 
           totalChunks != null && 
           sequenceNumber! >= totalChunks! - 1;
  }

  bool get isFirstChunk {
    return sequenceNumber == 0;
  }

  bool get canPlay {
    return status == AudioChunkStatus.pending || 
           status == AudioChunkStatus.cached;
  }

  int get sizeInBytes => data.length;

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