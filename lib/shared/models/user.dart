import 'package:equatable/equatable.dart';

/// The permission level of a user.
enum UserRole {
  /// An ordinary user.
  user,
  /// An administrator.
  admin,
  /// A moderator.
  moderator,
}

/// The standing of a user account.
enum UserStatus {
  /// The account is in good standing.
  active,
  /// The account is not in use.
  inactive,
  /// The account is blocked.
  suspended,
  /// The account is waiting for activation.
  pending,
}

/// One user account.
class User extends Equatable {
  /// Unique user identifier.
  final String id;
  /// The user's email address.
  final String email;
  /// The name to show, or null to show the email.
  final String? displayName;
  /// Where the avatar image is, or null.
  final String? avatarUrl;
  /// The user's permission level.
  final UserRole role;
  /// The account standing.
  final UserStatus status;
  /// When the account was created.
  final DateTime createdAt;
  /// The last login, or null if the user never logged in.
  final DateTime? lastLoginAt;
  /// The user's saved settings, or null.
  final Map<String, dynamic>? preferences;
  /// Free-form extra fields, or null.
  final Map<String, dynamic>? metadata;

  /// Creates a user.
  const User({
    required this.id,
    required this.email,
    this.displayName,
    this.avatarUrl,
    this.role = UserRole.user,
    this.status = UserStatus.active,
    required this.createdAt,
    this.lastLoginAt,
    this.preferences,
    this.metadata,
  });

  /// Returns a copy with the given fields replaced.
  User copyWith({
    String? id,
    String? email,
    String? displayName,
    String? avatarUrl,
    UserRole? role,
    UserStatus? status,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    Map<String, dynamic>? preferences,
    Map<String, dynamic>? metadata,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      preferences: preferences ?? this.preferences,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Builds a user from its wire map.
  ///
  /// An unknown role becomes user and an unknown status becomes active.
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      role: UserRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => UserRole.user,
      ),
      status: UserStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => UserStatus.active,
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.parse(json['last_login_at'] as String)
          : null,
      preferences: json['preferences'] as Map<String, dynamic>?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Returns the wire map for this user.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'role': role.name,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'last_login_at': lastLoginAt?.toIso8601String(),
      'preferences': preferences,
      'metadata': metadata,
    };
  }

  @override
  List<Object?> get props => [
        id,
        email,
        displayName,
        avatarUrl,
        role,
        status,
        createdAt,
        lastLoginAt,
        preferences,
        metadata,
      ];
}