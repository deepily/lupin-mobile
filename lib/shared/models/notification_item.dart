import 'package:equatable/equatable.dart';

/// What kind of event a notification reports.
enum NotificationType {
  /// General information.
  info,
  /// Something needs attention.
  warning,
  /// Something failed.
  error,
  /// Something succeeded.
  success,
  /// A job started.
  jobStarted,
  /// A job finished.
  jobCompleted,
  /// A job failed.
  jobFailed,
  /// A job was paused.
  jobPaused,
  /// A paused job resumed.
  jobResumed,
  /// A message from another user.
  userMessage,
  /// An alert from the system.
  systemAlert,
  /// A notice about planned maintenance.
  maintenanceNotice,
  /// A spoken response is available.
  audioResponse,
  /// A voice command was recognized.
  voiceCommand,
  /// An alert that is meant to be heard.
  audioAlert,
  /// A live change to something on screen.
  liveUpdate,
  /// A data synchronization event.
  dataSync,
  /// The connection to the server changed.
  connectionStatus,
}

/// One notification as the shared model layer sees it.
class NotificationItem extends Equatable {
  /// Unique notification identifier.
  final String id;
  /// Short heading.
  final String title;
  /// Body text.
  final String message;
  /// What kind of event this reports.
  final NotificationType type;
  /// When the notification was created.
  final DateTime timestamp;
  /// Whether the user has seen it.
  final bool isRead;
  /// Whether a spoken version exists.
  final bool hasAudio;
  /// The text to speak, or null when there is none.
  final String? audioText;
  /// Free-form extra fields, or null.
  final Map<String, dynamic>? metadata;

  /// Creates a notification.
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

  /// Returns a copy with the given fields replaced.
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

  /// Builds a notification from its wire map; an unknown type becomes info.
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

  /// Returns the wire map for this notification.
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