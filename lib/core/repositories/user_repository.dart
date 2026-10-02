import 'dart:async';
import '../../shared/models/models.dart';
import 'base_repository.dart';

/// Repository interface for User entities
abstract class UserRepository extends CachedRepository<User, String> {
  /// Find user by email
  Future<User?> findByEmail(String email);
  
  /// Find users by role
  Future<List<User>> findByRole(UserRole role);
  
  /// Find users by status
  Future<List<User>> findByStatus(UserStatus status);
  
  /// Stores the user's preferences
  Future<User> updatePreferences(String userId, Map<String, dynamic> preferences);
  
  /// Stores the user's last login time
  Future<User> updateLastLogin(String userId, DateTime lastLogin);
  
  /// Get user statistics
  Future<UserStats> getUserStats(String userId);
  
  /// Search users by name or email
  Future<List<User>> searchUsers(String query);
  
  /// Get active users
  Future<List<User>> getActiveUsers();
  
  /// Get recently active users
  Future<List<User>> getRecentlyActiveUsers({Duration? since});
}

/// User statistics
class UserStats {
  /// Number of sessions.
  final int totalSessions;
  /// Number of jobs.
  final int totalJobs;
  /// Number of audio requests.
  final int totalAudioRequests;
  /// Total time the user was active.
  final Duration totalActiveTime;
  /// Time of the most recent activity, or null when there is none.
  final DateTime? lastActivity;
  /// The user's stored preferences.
  final Map<String, dynamic> preferences;
  /// Use counts by feature.
  final Map<String, int> featureUsage;

  /// Creates the stats; every field is required.
  const UserStats({
    required this.totalSessions,
    required this.totalJobs,
    required this.totalAudioRequests,
    required this.totalActiveTime,
    this.lastActivity,
    this.preferences = const {},
    this.featureUsage = const {},
  });

  /// Serializes the stats.
  Map<String, dynamic> toJson() {
    return {
      'total_sessions': totalSessions,
      'total_jobs': totalJobs,
      'total_audio_requests': totalAudioRequests,
      'total_active_time': totalActiveTime.inMilliseconds,
      'last_activity': lastActivity?.toIso8601String(),
      'preferences': preferences,
      'feature_usage': featureUsage,
    };
  }
}