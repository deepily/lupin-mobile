import 'dart:async';
import '../../../shared/models/models.dart';
import '../session_repository.dart';
import '../base_repository.dart';
import 'shared_preferences_repository.dart';

class SessionRepositoryImpl extends SharedPreferencesRepository<Session, String> 
    implements SessionRepository {
  
  SessionRepositoryImpl() : super('session');
  
  @override
  Map<String, dynamic> toJson(Session entity) => entity.toJson();
  
  @override
  Session fromJson(Map<String, dynamic> json) => Session.fromJson(json);
  
  @override
  String getId(Session entity) => entity.id;
  
  @override
  Future<List<Session>> findByUser(String userId) async {
    return await findWhere((session) => session.userId == userId);
  }
  
  @override
  Future<List<Session>> findActiveSessions() async {
    return await findWhere((session) => session.isActive);
  }
  
  @override
  Future<List<Session>> findByStatus(SessionStatus status) async {
    return await findWhere((session) => session.status == status);
  }
  
  @override
  Future<List<Session>> findExpiredSessions() async {
    return await findWhere((session) => session.isExpired);
  }
  
  @override
  Future<Session?> getCurrentSession(String userId) async {
    final userSessions = await findByUser(userId);
    final activeSessions = userSessions.where((session) => session.isActive);
    
    if (activeSessions.isEmpty) return null;
    
    // Return the most recent active session
    return activeSessions.reduce((a, b) => 
        a.createdAt.isAfter(b.createdAt) ? a : b);
  }
  
  @override
  Future<Session> createSession(
    String userId, 
    String token, {
    Duration? expiresIn,
    String? deviceId,
    String? deviceInfo,
    String? ipAddress,
  }) async {
    final now = DateTime.now();
    final expiresAt = expiresIn != null ? now.add(expiresIn) : null;
    
    final session = Session(
      id: 'session_${now.millisecondsSinceEpoch}',
      userId: userId,
      token: token,
      status: SessionStatus.active,
      createdAt: now,
      expiresAt: expiresAt,
      lastActivityAt: now,
      deviceId: deviceId,
      deviceInfo: deviceInfo,
      ipAddress: ipAddress,
    );
    
    return await create(session);
  }
  
  @override
  Future<Session> updateActivity(String sessionId) async {
    final session = await findById(sessionId);
    if (session == null) {
      throw Exception('Session with id $sessionId not found');
    }
    
    final updatedSession = session.copyWith(
      lastActivityAt: DateTime.now(),
    );
    
    return await update(updatedSession);
  }
  
  @override
  Future<Session> extendSession(String sessionId, Duration extension) async {
    final session = await findById(sessionId);
    if (session == null) {
      throw Exception('Session with id $sessionId not found');
    }
    
    final newExpiresAt = session.expiresAt?.add(extension) ?? 
                         DateTime.now().add(extension);
    
    final updatedSession = session.copyWith(
      expiresAt: newExpiresAt,
      lastActivityAt: DateTime.now(),
    );
    
    return await update(updatedSession);
  }
  
  @override
  Future<void> terminateSession(String sessionId) async {
    final session = await findById(sessionId);
    if (session == null) {
      throw Exception('Session with id $sessionId not found');
    }
    
    final updatedSession = session.copyWith(
      status: SessionStatus.terminated,
      lastActivityAt: DateTime.now(),
    );
    
    await update(updatedSession);
  }
  
  @override
  Future<void> terminateAllUserSessions(String userId) async {
    final userSessions = await findByUser(userId);
    
    for (final session in userSessions) {
      if (session.isActive) {
        await terminateSession(session.id);
      }
    }
  }
  
  @override
  Future<int> cleanupExpiredSessions() async {
    final expiredSessions = await findExpiredSessions();
    
    for (final session in expiredSessions) {
      await deleteById(session.id);
    }
    
    return expiredSessions.length;
  }
  
  @override
  Future<SessionStats> getSessionStats({String? userId}) async {
    List<Session> sessions = await findAll();
    
    if (userId != null) {
      sessions = sessions.where((session) => session.userId == userId).toList();
    }
    
    final totalSessions = sessions.length;
    final activeSessions = sessions.where((session) => session.isActive).length;
    final expiredSessions = sessions.where((session) => session.isExpired).length;
    
    // Calculate average session duration
    final completedSessions = sessions.where((session) => 
        session.status == SessionStatus.terminated &&
        session.lastActivityAt != null);
    
    final totalDuration = completedSessions.fold<Duration>(
      Duration.zero,
      (sum, session) => sum + session.lastActivityAt!.difference(session.createdAt),
    );
    
    final averageSessionDuration = completedSessions.isNotEmpty
        ? Duration(milliseconds: totalDuration.inMilliseconds ~/ completedSessions.length)
        : Duration.zero;
    
    // Get last activity
    final lastActivity = sessions.isNotEmpty
        ? sessions.map((s) => s.lastActivityAt ?? s.createdAt)
                  .reduce((a, b) => a.isAfter(b) ? a : b)
        : null;
    
    return SessionStats(
      totalSessions: totalSessions,
      activeSessions: activeSessions,
      expiredSessions: expiredSessions,
      averageSessionDuration: averageSessionDuration,
      lastActivity: lastActivity,
    );
  }
  
  @override
  Future<List<Session>> findByDevice(String deviceId) async {
    return await findWhere((session) => session.deviceId == deviceId);
  }
  
  @override
  Future<List<Session>> findByIpAddress(String ipAddress) async {
    return await findWhere((session) => session.ipAddress == ipAddress);
  }
  
  @override
  Future<bool> validateToken(String sessionId, String token) async {
    final session = await findById(sessionId);
    if (session == null) return false;
    
    return session.token == token && session.isActive;
  }
}