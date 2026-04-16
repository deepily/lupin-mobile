import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../lib/core/repositories/impl/session_repository_impl.dart';
import '../../lib/shared/models/models.dart';

void main() {
  group('SessionRepository Tests', () {
    late SessionRepositoryImpl repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repository = SessionRepositoryImpl();
    });

    group('Basic CRUD Operations', () {
      test('should create and retrieve session', () async {
        final session = Session(
          id: 'session_1',
          userId: 'user_1',
          token: 'test_token',
          status: SessionStatus.active,
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(Duration(hours: 24)),
          lastActivityAt: DateTime.now(),
        );

        // Create session
        final createdSession = await repository.create(session);
        expect(createdSession.id, equals('session_1'));
        expect(createdSession.userId, equals('user_1'));
        expect(createdSession.token, equals('test_token'));

        // Retrieve session
        final retrievedSession = await repository.findById('session_1');
        expect(retrievedSession, isNotNull);
        expect(retrievedSession!.userId, equals('user_1'));
        expect(retrievedSession.token, equals('test_token'));
        expect(retrievedSession.status, equals(SessionStatus.active));
      });

      test('should update session', () async {
        final session = Session(
          id: 'session_1',
          userId: 'user_1',
          token: 'test_token',
          status: SessionStatus.active,
          createdAt: DateTime.now(),
          lastActivityAt: DateTime.now(),
        );

        await repository.create(session);

        // Update session
        final updatedSession = session.copyWith(
          status: SessionStatus.terminated,
          lastActivityAt: DateTime.now().add(Duration(minutes: 30)),
        );
        
        await repository.update(updatedSession);

        // Verify update
        final retrievedSession = await repository.findById('session_1');
        expect(retrievedSession!.status, equals(SessionStatus.terminated));
        expect(retrievedSession.userId, equals('user_1')); // Should remain unchanged
      });

      test('should delete session', () async {
        final session = Session(
          id: 'session_1',
          userId: 'user_1',
          token: 'test_token',
          status: SessionStatus.active,
          createdAt: DateTime.now(),
          lastActivityAt: DateTime.now(),
        );

        await repository.create(session);
        expect(await repository.exists('session_1'), isTrue);

        await repository.deleteById('session_1');
        expect(await repository.exists('session_1'), isFalse);
        expect(await repository.findById('session_1'), isNull);
      });
    });

    group('Session Creation and Management', () {
      test('should create session with all parameters', () async {
        final createdAt = DateTime.now();
        final deviceId = 'device_123';
        final deviceInfo = 'iPhone 14 Pro';
        final ipAddress = '192.168.1.100';
        
        final session = await repository.createSession(
          'user_1',
          'token_123',
          expiresIn: Duration(hours: 2),
          deviceId: deviceId,
          deviceInfo: deviceInfo,
          ipAddress: ipAddress,
        );

        expect(session.userId, equals('user_1'));
        expect(session.token, equals('token_123'));
        expect(session.status, equals(SessionStatus.active));
        expect(session.deviceId, equals(deviceId));
        expect(session.deviceInfo, equals(deviceInfo));
        expect(session.ipAddress, equals(ipAddress));
        expect(session.expiresAt, isNotNull);
        expect(session.expiresAt!.isAfter(createdAt), isTrue);
      });

      test('should create session without optional parameters', () async {
        final session = await repository.createSession('user_1', 'token_123');

        expect(session.userId, equals('user_1'));
        expect(session.token, equals('token_123'));
        expect(session.status, equals(SessionStatus.active));
        expect(session.deviceId, isNull);
        expect(session.deviceInfo, isNull);
        expect(session.ipAddress, isNull);
        expect(session.expiresAt, isNull);
      });

      test('should update session activity', () async {
        final session = await repository.createSession('user_1', 'token_123');
        final originalActivity = session.lastActivityAt;

        // Wait a bit to ensure time difference
        await Future.delayed(Duration(milliseconds: 10));

        final updatedSession = await repository.updateActivity(session.id);
        
        expect(updatedSession.lastActivityAt.isAfter(originalActivity), isTrue);
        expect(updatedSession.userId, equals('user_1'));
        expect(updatedSession.token, equals('token_123'));
      });

      test('should extend session expiration', () async {
        final session = await repository.createSession(
          'user_1',
          'token_123',
          expiresIn: Duration(hours: 1),
        );
        
        final originalExpiry = session.expiresAt!;
        
        final extendedSession = await repository.extendSession(
          session.id,
          Duration(hours: 2),
        );
        
        expect(extendedSession.expiresAt!.isAfter(originalExpiry), isTrue);
        expect(extendedSession.userId, equals('user_1'));
      });

      test('should extend session without original expiry', () async {
        final session = await repository.createSession('user_1', 'token_123');
        expect(session.expiresAt, isNull);
        
        final extendedSession = await repository.extendSession(
          session.id,
          Duration(hours: 2),
        );
        
        expect(extendedSession.expiresAt, isNotNull);
        expect(extendedSession.expiresAt!.isAfter(DateTime.now()), isTrue);
      });

      test('should terminate session', () async {
        final session = await repository.createSession('user_1', 'token_123');
        expect(session.status, equals(SessionStatus.active));
        
        await repository.terminateSession(session.id);
        
        final terminatedSession = await repository.findById(session.id);
        expect(terminatedSession!.status, equals(SessionStatus.terminated));
      });

      test('should terminate all user sessions', () async {
        // Create multiple sessions for the same user
        final session1 = await repository.createSession('user_1', 'token_1');
        final session2 = await repository.createSession('user_1', 'token_2');
        final session3 = await repository.createSession('user_2', 'token_3');
        
        expect(session1.status, equals(SessionStatus.active));
        expect(session2.status, equals(SessionStatus.active));
        expect(session3.status, equals(SessionStatus.active));
        
        await repository.terminateAllUserSessions('user_1');
        
        final terminatedSession1 = await repository.findById(session1.id);
        final terminatedSession2 = await repository.findById(session2.id);
        final untouchedSession3 = await repository.findById(session3.id);
        
        expect(terminatedSession1!.status, equals(SessionStatus.terminated));
        expect(terminatedSession2!.status, equals(SessionStatus.terminated));
        expect(untouchedSession3!.status, equals(SessionStatus.active));
      });
    });

    group('Session Queries', () {
      late List<Session> testSessions;

      setUp(() async {
        final now = DateTime.now();
        testSessions = [
          Session(
            id: 'session_1',
            userId: 'user_1',
            token: 'token_1',
            status: SessionStatus.active,
            createdAt: now.subtract(Duration(hours: 2)),
            expiresAt: now.add(Duration(hours: 22)),
            lastActivityAt: now.subtract(Duration(minutes: 10)),
            deviceId: 'device_1',
            ipAddress: '192.168.1.100',
          ),
          Session(
            id: 'session_2',
            userId: 'user_1',
            token: 'token_2',
            status: SessionStatus.terminated,
            createdAt: now.subtract(Duration(hours: 4)),
            expiresAt: now.subtract(Duration(hours: 2)),
            lastActivityAt: now.subtract(Duration(hours: 3)),
            deviceId: 'device_1',
            ipAddress: '192.168.1.100',
          ),
          Session(
            id: 'session_3',
            userId: 'user_2',
            token: 'token_3',
            status: SessionStatus.active,
            createdAt: now.subtract(Duration(hours: 1)),
            expiresAt: now.add(Duration(hours: 23)),
            lastActivityAt: now.subtract(Duration(minutes: 5)),
            deviceId: 'device_2',
            ipAddress: '192.168.1.101',
          ),
        ];

        for (final session in testSessions) {
          await repository.create(session);
        }
      });

      test('should find sessions by user', () async {
        final user1Sessions = await repository.findByUser('user_1');
        expect(user1Sessions, hasLength(2));
        expect(user1Sessions.map((s) => s.id), containsAll(['session_1', 'session_2']));

        final user2Sessions = await repository.findByUser('user_2');
        expect(user2Sessions, hasLength(1));
        expect(user2Sessions.first.id, equals('session_3'));

        final noSessions = await repository.findByUser('user_nonexistent');
        expect(noSessions, isEmpty);
      });

      test('should find active sessions', () async {
        final activeSessions = await repository.findActiveSessions();
        expect(activeSessions, hasLength(2));
        expect(activeSessions.map((s) => s.id), containsAll(['session_1', 'session_3']));
      });

      test('should find sessions by status', () async {
        final activeSessions = await repository.findByStatus(SessionStatus.active);
        expect(activeSessions, hasLength(2));
        expect(activeSessions.map((s) => s.id), containsAll(['session_1', 'session_3']));

        final terminatedSessions = await repository.findByStatus(SessionStatus.terminated);
        expect(terminatedSessions, hasLength(1));
        expect(terminatedSessions.first.id, equals('session_2'));
      });

      test('should find expired sessions', () async {
        final expiredSessions = await repository.findExpiredSessions();
        expect(expiredSessions, hasLength(1));
        expect(expiredSessions.first.id, equals('session_2'));
      });

      test('should find sessions by device', () async {
        final device1Sessions = await repository.findByDevice('device_1');
        expect(device1Sessions, hasLength(2));
        expect(device1Sessions.map((s) => s.id), containsAll(['session_1', 'session_2']));

        final device2Sessions = await repository.findByDevice('device_2');
        expect(device2Sessions, hasLength(1));
        expect(device2Sessions.first.id, equals('session_3'));
      });

      test('should find sessions by IP address', () async {
        final ip1Sessions = await repository.findByIpAddress('192.168.1.100');
        expect(ip1Sessions, hasLength(2));
        expect(ip1Sessions.map((s) => s.id), containsAll(['session_1', 'session_2']));

        final ip2Sessions = await repository.findByIpAddress('192.168.1.101');
        expect(ip2Sessions, hasLength(1));
        expect(ip2Sessions.first.id, equals('session_3'));
      });

      test('should get current session for user', () async {
        final currentSession = await repository.getCurrentSession('user_1');
        expect(currentSession, isNotNull);
        expect(currentSession!.id, equals('session_1')); // Most recent active session

        final noCurrentSession = await repository.getCurrentSession('user_nonexistent');
        expect(noCurrentSession, isNull);
      });

      test('should validate session token', () async {
        final isValid = await repository.validateToken('session_1', 'token_1');
        expect(isValid, isTrue);

        final isInvalidToken = await repository.validateToken('session_1', 'wrong_token');
        expect(isInvalidToken, isFalse);

        final isInvalidSession = await repository.validateToken('nonexistent', 'token_1');
        expect(isInvalidSession, isFalse);

        final isTerminatedSession = await repository.validateToken('session_2', 'token_2');
        expect(isTerminatedSession, isFalse); // Terminated session should be invalid
      });
    });

    group('Session Cleanup', () {
      test('should cleanup expired sessions', () async {
        final now = DateTime.now();
        
        // Create expired sessions
        final expiredSession1 = Session(
          id: 'expired_1',
          userId: 'user_1',
          token: 'token_1',
          status: SessionStatus.active,
          createdAt: now.subtract(Duration(hours: 2)),
          expiresAt: now.subtract(Duration(hours: 1)),
          lastActivityAt: now.subtract(Duration(hours: 1)),
        );
        
        final expiredSession2 = Session(
          id: 'expired_2',
          userId: 'user_2',
          token: 'token_2',
          status: SessionStatus.active,
          createdAt: now.subtract(Duration(hours: 3)),
          expiresAt: now.subtract(Duration(hours: 2)),
          lastActivityAt: now.subtract(Duration(hours: 2)),
        );
        
        // Create active session
        final activeSession = Session(
          id: 'active_1',
          userId: 'user_1',
          token: 'token_3',
          status: SessionStatus.active,
          createdAt: now.subtract(Duration(hours: 1)),
          expiresAt: now.add(Duration(hours: 23)),
          lastActivityAt: now.subtract(Duration(minutes: 5)),
        );
        
        await repository.create(expiredSession1);
        await repository.create(expiredSession2);
        await repository.create(activeSession);
        
        expect(await repository.count(), equals(3));
        
        final cleanedCount = await repository.cleanupExpiredSessions();
        expect(cleanedCount, equals(2));
        expect(await repository.count(), equals(1));
        
        final remainingSession = await repository.findById('active_1');
        expect(remainingSession, isNotNull);
      });
    });

    group('Session Statistics', () {
      test('should get session statistics', () async {
        final now = DateTime.now();
        
        // Create test sessions
        final sessions = [
          Session(
            id: 'session_1',
            userId: 'user_1',
            token: 'token_1',
            status: SessionStatus.active,
            createdAt: now.subtract(Duration(hours: 2)),
            lastActivityAt: now.subtract(Duration(minutes: 10)),
          ),
          Session(
            id: 'session_2',
            userId: 'user_1',
            token: 'token_2',
            status: SessionStatus.terminated,
            createdAt: now.subtract(Duration(hours: 4)),
            lastActivityAt: now.subtract(Duration(hours: 3)),
          ),
          Session(
            id: 'session_3',
            userId: 'user_2',
            token: 'token_3',
            status: SessionStatus.active,
            createdAt: now.subtract(Duration(hours: 1)),
            expiresAt: now.subtract(Duration(minutes: 30)),
            lastActivityAt: now.subtract(Duration(minutes: 5)),
          ),
        ];
        
        for (final session in sessions) {
          await repository.create(session);
        }
        
        final stats = await repository.getSessionStats();
        expect(stats.totalSessions, equals(3));
        expect(stats.activeSessions, equals(2));
        expect(stats.expiredSessions, equals(1));
        expect(stats.averageSessionDuration, isA<Duration>());
        expect(stats.lastActivity, isNotNull);
        
        // Test user-specific stats
        final userStats = await repository.getSessionStats(userId: 'user_1');
        expect(userStats.totalSessions, equals(2));
        expect(userStats.activeSessions, equals(1));
      });
    });

    group('Error Handling', () {
      test('should handle operations on non-existent sessions', () async {
        expect(
          () => repository.updateActivity('nonexistent'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Session with id nonexistent not found'),
          )),
        );

        expect(
          () => repository.extendSession('nonexistent', Duration(hours: 1)),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Session with id nonexistent not found'),
          )),
        );

        expect(
          () => repository.terminateSession('nonexistent'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Session with id nonexistent not found'),
          )),
        );
      });
    });
  });
}