import 'package:equatable/equatable.dart';

/// Lifecycle state of a login session.
enum SessionStatus {
  /// In use and accepting activity.
  active,
  /// Idle.
  inactive,
  /// Past its expiry time.
  expired,
  /// Ended explicitly.
  terminated,
}

/// One login session on one device.
class Session extends Equatable {
  /// Unique session identifier.
  final String id;
  /// The user who owns the session.
  final String userId;
  /// The credential that authenticates the session.
  final String token;
  /// Current lifecycle state.
  final SessionStatus status;
  /// When the session started.
  final DateTime createdAt;
  /// When the session ends, or null if it does not expire.
  final DateTime? expiresAt;
  /// The last time the session was used, or null if never.
  final DateTime? lastActivityAt;
  /// Identifier of the device, or null.
  final String? deviceId;
  /// Description of the device, or null.
  final String? deviceInfo;
  /// Network address the session came from, or null.
  final String? ipAddress;
  /// Free-form extra fields, or null.
  final Map<String, dynamic>? metadata;

  /// Creates a session.
  const Session({
    required this.id,
    required this.userId,
    required this.token,
    this.status = SessionStatus.active,
    required this.createdAt,
    this.expiresAt,
    this.lastActivityAt,
    this.deviceId,
    this.deviceInfo,
    this.ipAddress,
    this.metadata,
  });

  /// Returns a copy with the given fields replaced.
  Session copyWith({
    String? id,
    String? userId,
    String? token,
    SessionStatus? status,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? lastActivityAt,
    String? deviceId,
    String? deviceInfo,
    String? ipAddress,
    Map<String, dynamic>? metadata,
  }) {
    return Session(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      token: token ?? this.token,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      deviceId: deviceId ?? this.deviceId,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      ipAddress: ipAddress ?? this.ipAddress,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Whether the expiry time has passed; a session with no expiry never expires.
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Whether the status is active and the session has not expired.
  bool get isActive {
    return status == SessionStatus.active && !isExpired;
  }

  /// Builds a session from its wire map; an unknown status becomes active.
  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      token: json['token'] as String,
      status: SessionStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SessionStatus.active,
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      lastActivityAt: json['last_activity_at'] != null
          ? DateTime.parse(json['last_activity_at'] as String)
          : null,
      deviceId: json['device_id'] as String?,
      deviceInfo: json['device_info'] as String?,
      ipAddress: json['ip_address'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Returns the wire map for this session.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'token': token,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'last_activity_at': lastActivityAt?.toIso8601String(),
      'device_id': deviceId,
      'device_info': deviceInfo,
      'ip_address': ipAddress,
      'metadata': metadata,
    };
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        token,
        status,
        createdAt,
        expiresAt,
        lastActivityAt,
        deviceId,
        deviceInfo,
        ipAddress,
        metadata,
      ];
}