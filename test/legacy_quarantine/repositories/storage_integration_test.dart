import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../lib/core/storage/storage_manager.dart';
import '../../lib/core/repositories/impl/user_repository_impl.dart';
import '../../lib/core/repositories/impl/session_repository_impl.dart';
import '../../lib/core/repositories/impl/job_repository_impl.dart';
import '../../lib/core/repositories/impl/voice_repository_impl.dart';
import '../../lib/core/repositories/impl/audio_repository_impl.dart';
import '../../lib/shared/models/models.dart';

void main() {
  group('Storage Integration Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('StorageManager should initialize correctly', () async {
      final storage = await StorageManager.getInstance();
      expect(storage, isNotNull);
      
      // Test basic operations
      await storage.setString('test_key', 'test_value');
      expect(storage.getString('test_key'), equals('test_value'));
      
      await storage.setJson('test_json', {'key': 'value'});
      expect(storage.getJson('test_json'), equals({'key': 'value'}));
      
      // Test statistics
      final stats = storage.getStorageStats();
      expect(stats.totalKeys, greaterThan(0));
    });

    test('UserRepositoryImpl should create and retrieve users', () async {
      final repository = UserRepositoryImpl();
      
      final user = User(
        id: 'user_123',
        email: 'test@example.com',
        displayName: 'Test User',
        role: UserRole.user,
        status: UserStatus.active,
        createdAt: DateTime.now(),
      );
      
      // Create user
      final createdUser = await repository.create(user);
      expect(createdUser.id, equals('user_123'));
      
      // Retrieve user
      final retrievedUser = await repository.findById('user_123');
      expect(retrievedUser, isNotNull);
      expect(retrievedUser!.email, equals('test@example.com'));
      
      // Test user queries
      final activeUsers = await repository.findByStatus(UserStatus.active);
      expect(activeUsers.length, equals(1));
      expect(activeUsers.first.id, equals('user_123'));
    });

    test('SessionRepositoryImpl should manage sessions', () async {
      final repository = SessionRepositoryImpl();
      
      final session = await repository.createSession(
        'user_123',
        'token_abc',
        expiresIn: Duration(hours: 1),
        deviceId: 'device_456',
      );
      
      expect(session.userId, equals('user_123'));
      expect(session.token, equals('token_abc'));
      expect(session.deviceId, equals('device_456'));
      expect(session.isActive, isTrue);
      
      // Test session queries
      final userSessions = await repository.findByUser('user_123');
      expect(userSessions.length, equals(1));
      
      final currentSession = await repository.getCurrentSession('user_123');
      expect(currentSession, isNotNull);
      expect(currentSession!.id, equals(session.id));
    });

    test('JobRepositoryImpl should handle job operations', () async {
      final repository = JobRepositoryImpl();
      
      final job = Job(
        id: 'job_789',
        text: 'Test job',
        status: JobStatus.todo,
        createdAt: DateTime.now(),
        metadata: {'user_id': 'user_123'},
      );
      
      // Create job
      final createdJob = await repository.create(job);
      expect(createdJob.id, equals('job_789'));
      
      // Update job status
      final updatedJob = await repository.updateStatus('job_789', JobStatus.completed);
      expect(updatedJob.status, equals(JobStatus.completed));
      
      // Test job queries
      final todoJobs = await repository.findByStatus(JobStatus.todo);
      expect(todoJobs.length, equals(0));
      
      final completedJobs = await repository.findByStatus(JobStatus.completed);
      expect(completedJobs.length, equals(1));
      
      // Test job statistics
      final stats = await repository.getJobStats();
      expect(stats.totalJobs, equals(1));
      expect(stats.completedJobs, equals(1));
    });

    test('Repository clear operations should work', () async {
      final userRepo = UserRepositoryImpl();
      final sessionRepo = SessionRepositoryImpl();
      
      // Create test data
      final user = User(
        id: 'user_test',
        email: 'clear@example.com',
        displayName: 'Clear Test',
        role: UserRole.user,
        status: UserStatus.active,
        createdAt: DateTime.now(),
      );
      
      await userRepo.create(user);
      await sessionRepo.createSession('user_test', 'token_test');
      
      // Verify data exists
      expect(await userRepo.count(), equals(1));
      expect(await sessionRepo.count(), equals(1));
      
      // Clear repositories
      await userRepo.clear();
      await sessionRepo.clear();
      
      // Verify data is cleared
      expect(await userRepo.count(), equals(0));
      expect(await sessionRepo.count(), equals(0));
    });
  });
}