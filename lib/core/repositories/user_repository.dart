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
  
  /// Update user preferences
  Future<User> updatePreferences(String userId, Map<String, dynamic> preferences);
  
  /// Update user last login
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
  final int totalSessions;
  final int totalJobs;
  final int totalAudioRequests;
  final Duration totalActiveTime;
  final DateTime? lastActivity;
  final Map<String, dynamic> preferences;
  final Map<String, int> featureUsage;

  const UserStats({
    required this.totalSessions,
    required this.totalJobs,
    required this.totalAudioRequests,
    required this.totalActiveTime,
    this.lastActivity,
    this.preferences = const {},
    this.featureUsage = const {},
  });

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