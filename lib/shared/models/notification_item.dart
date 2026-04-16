import 'package:equatable/equatable.dart';

enum NotificationType {
  info,
  warning,
  error,
  success,
  jobStarted,
  jobCompleted,
  jobFailed,
  jobPaused,
  jobResumed,
  userMessage,
  systemAlert,
  maintenanceNotice,
  audioResponse,
  voiceCommand,
  audioAlert,
  liveUpdate,
  dataSync,
  connectionStatus,
}

class NotificationItem extends Equatable {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  final bool isRead;
  final bool hasAudio;
  final String? audioText;
  final Map<String, dynamic>? metadata;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.hasAudio = false,
    this.audioText,
    this.metadata,
  });

  NotificationItem copyWith({
    String? id,
    String? title,
    String? message,
    NotificationType? type,
    DateTime? timestamp,
    bool? isRead,
    bool? hasAudio,
    String? audioText,
    Map<String, dynamic>? metadata,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      hasAudio: hasAudio ?? this.hasAudio,
      audioText: audioText ?? this.audioText,
      metadata: metadata ?? this.metadata,
    );
  }

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      type: NotificationType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => NotificationType.info,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: json['is_read'] as bool? ?? false,
      hasAudio: json['has_audio'] as bool? ?? false,
      audioText: json['audio_text'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'is_read': isRead,
      'has_audio': hasAudio,
      'audio_text': audioText,
      'metadata': metadata,
    };
  }

  @override
  List<Object?> get props => [
        id,
        title,
        message,
        type,
        timestamp,
        isRead,
        hasAudio,
        audioText,
        metadata,
      ];
}