import 'dart:async';
import '../../shared/models/models.dart';
import 'base_repository.dart';

/// Repository interface for Session entities
abstract class SessionRepository extends BaseRepository<Session, String> {
  /// Find sessions by user
  Future<List<Session>> findByUser(String userId);
  
  /// Find active sessions
  Future<List<Session>> findActiveSessions();
  
  /// Find sessions by status
  Future<List<Session>> findByStatus(SessionStatus status);
  
  /// Find expired sessions
  Future<List<Session>> findExpiredSessions();
  
  /// Get current session for user
  Future<Session?> getCurrentSession(String userId);
  
  /// Create new session
  Future<Session> createSession(
    String userId, 
    String token, {
    Duration? expiresIn,
    String? deviceId,
    String? deviceInfo,
    String? ipAddress,
  });
  
  /// Records activity on a session
  Future<Session> updateActivity(String sessionId);
  
  /// Extend session expiration
  Future<Session> extendSession(String sessionId, Duration extension);
  
  /// Terminate session
  Future<void> terminateSession(String sessionId);
  
  /// Terminate all sessions for user
  Future<void> terminateAllUserSessions(String userId);
  
  /// Cleanup expired sessions
  Future<int> cleanupExpiredSessions();
  
  /// Get session statistics
  Future<SessionStats> getSessionStats({String? userId});
  
  /// Find sessions by device
  Future<List<Session>> findByDevice(String deviceId);
  
  /// Find sessions by IP address
  Future<List<Session>> findByIpAddress(String ipAddress);
  
  /// Validate session token
  Future<bool> validateToken(String sessionId, String token);
}

/// Session statistics
class SessionStats {
  /// Number of sessions.
  final int totalSessions;
  /// Sessions that are still active.
  final int activeSessions;
  /// Sessions that have expired.
  final int expiredSessions;
  /// Mean session length.
  final Duration averageSessionDuration;
  /// Session counts by device.
  final Map<String, int> sessionsByDevice;
  /// Session counts by location.
  final Map<String, int> sessionsByLocation;
  /// Time of the most recent activity, or null when there is none.
  final DateTime? lastActivity;

  /// Creates the stats; every field is required.
  const SessionStats({
    required this.totalSessions,
    required this.activeSessions,
    required this.expiredSessions,
    required this.averageSessionDuration,
    this.sessionsByDevice = const {},
    this.sessionsByLocation = const {},
    this.lastActivity,
  });

  /// Serializes the stats.
  Map<String, dynamic> toJson() {
    return {
      'total_sessions': totalSessions,
      'active_sessions': activeSessions,
      'expired_sessions': expiredSessions,
      'average_session_duration': averageSessionDuration.inMilliseconds,
      'sessions_by_device': sessionsByDevice,
      'sessions_by_location': sessionsByLocation,
      'last_activity': lastActivity?.toIso8601String(),
    };
  }
}