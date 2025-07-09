import 'package:equatable/equatable.dart';

enum SessionStatus {
  active,
  inactive,
  expired,
  terminated,
}

class Session extends Equatable {
  final String id;
  final String userId;
  final String token;
  final SessionStatus status;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? lastActivityAt;
  final String? deviceId;
  final String? deviceInfo;
  final String? ipAddress;
  final Map<String, dynamic>? metadata;

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

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  bool get isActive {
    return status == SessionStatus.active && !isExpired;
  }

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