import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../lib/core/repositories/impl/user_repository_impl.dart';
import '../../lib/shared/models/models.dart';

void main() {
  group('UserRepository Tests', () {
    late UserRepositoryImpl repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repository = UserRepositoryImpl();
    });

    group('Basic CRUD Operations', () {
      test('should create and retrieve user', () async {
        final user = User(
          id: 'user_1',
          email: 'test@example.com',
          displayName: 'Test User',
          role: UserRole.user,
          status: UserStatus.active,
          createdAt: DateTime.now(),
        );

        // Create user
        final createdUser = await repository.create(user);
        expect(createdUser.id, equals('user_1'));
        expect(createdUser.email, equals('test@example.com'));

        // Retrieve user
        final retrievedUser = await repository.findById('user_1');
        expect(retrievedUser, isNotNull);
        expect(retrievedUser!.email, equals('test@example.com'));
        expect(retrievedUser.displayName, equals('Test User'));
        expect(retrievedUser.role, equals(UserRole.user));
        expect(retrievedUser.status, equals(UserStatus.active));
      });

      test('should update user', () async {
        final user = User(
          id: 'user_1',
          email: 'test@example.com',
          displayName: 'Test User',
          role: UserRole.user,
          status: UserStatus.active,
          createdAt: DateTime.now(),
        );

        await repository.create(user);

        // Update user
        final updatedUser = user.copyWith(
          displayName: 'Updated User',
          status: UserStatus.inactive,
        );
        
        await repository.update(updatedUser);

        // Verify update
        final retrievedUser = await repository.findById('user_1');
        expect(retrievedUser!.displayName, equals('Updated User'));
        expect(retrievedUser.status, equals(UserStatus.inactive));
        expect(retrievedUser.email, equals('test@example.com')); // Should remain unchanged
      });

      test('should delete user', () async {
        final user = User(
          id: 'user_1',
          email: 'test@example.com',
          displayName: 'Test User',
          role: UserRole.user,
          status: UserStatus.active,
          createdAt: DateTime.now(),
        );

        await repository.create(user);
        expect(await repository.exists('user_1'), isTrue);

        await repository.deleteById('user_1');
        expect(await repository.exists('user_1'), isFalse);
        expect(await repository.findById('user_1'), isNull);
      });

      test('should handle non-existent user', () async {
        expect(await repository.findById('non_existent'), isNull);
        expect(await repository.exists('non_existent'), isFalse);
      });
    });

    group('Query Operations', () {
      late List<User> testUsers;

      setUp(() async {
        testUsers = [
          User(
            id: 'user_1',
            email: 'user1@example.com',
            displayName: 'User One',
            role: UserRole.user,
            status: UserStatus.active,
            createdAt: DateTime.now().subtract(Duration(days: 1)),
            lastLoginAt: DateTime.now().subtract(Duration(hours: 2)),
          ),
          User(
            id: 'user_2',
            email: 'user2@example.com',
            displayName: 'User Two',
            role: UserRole.admin,
            status: UserStatus.active,
            createdAt: DateTime.now().subtract(Duration(days: 2)),
            lastLoginAt: DateTime.now().subtract(Duration(hours: 1)),
          ),
          User(
            id: 'user_3',
            email: 'user3@example.com',
            displayName: 'User Three',
            role: UserRole.user,
            status: UserStatus.inactive,
            createdAt: DateTime.now().subtract(Duration(days: 3)),
            lastLoginAt: DateTime.now().subtract(Duration(days: 1)),
          ),
        ];

        // Create all test users
        for (final user in testUsers) {
          await repository.create(user);
        }
      });

      test('should find all users', () async {
        final users = await repository.findAll();
        expect(users, hasLength(3));
        
        final emails = users.map((u) => u.email).toList();
        expect(emails, contains('user1@example.com'));
        expect(emails, contains('user2@example.com'));
        expect(emails, contains('user3@example.com'));
      });

      test('should find user by email', () async {
        final user = await repository.findByEmail('user2@example.com');
        expect(user, isNotNull);
        expect(user!.id, equals('user_2'));
        expect(user.displayName, equals('User Two'));

        final nonExistentUser = await repository.findByEmail('nonexistent@example.com');
        expect(nonExistentUser, isNull);
      });

      test('should find users by role', () async {
        final regularUsers = await repository.findByRole(UserRole.user);
        expect(regularUsers, hasLength(2));
        expect(regularUsers.map((u) => u.id), containsAll(['user_1', 'user_3']));

        final adminUsers = await repository.findByRole(UserRole.admin);
        expect(adminUsers, hasLength(1));
        expect(adminUsers.first.id, equals('user_2'));
      });

      test('should find users by status', () async {
        final activeUsers = await repository.findByStatus(UserStatus.active);
        expect(activeUsers, hasLength(2));
        expect(activeUsers.map((u) => u.id), containsAll(['user_1', 'user_2']));

        final inactiveUsers = await repository.findByStatus(UserStatus.inactive);
        expect(inactiveUsers, hasLength(1));
        expect(inactiveUsers.first.id, equals('user_3'));
      });

      test('should get active users', () async {
        final activeUsers = await repository.getActiveUsers();
        expect(activeUsers, hasLength(2));
        expect(activeUsers.map((u) => u.status), everyElement(equals(UserStatus.active)));
      });

      test('should get recently active users', () async {
        final recentUsers = await repository.getRecentlyActiveUsers(
          since: Duration(hours: 3),
        );
        expect(recentUsers, hasLength(2));
        expect(recentUsers.map((u) => u.id), containsAll(['user_1', 'user_2']));

        final veryRecentUsers = await repository.getRecentlyActiveUsers(
          since: Duration(minutes: 30),
        );
        expect(veryRecentUsers, hasLength(0));
      });

      test('should search users', () async {
        final searchResults = await repository.searchUsers('User T');
        expect(searchResults, hasLength(2));
        expect(searchResults.map((u) => u.id), containsAll(['user_2', 'user_3']));

        final emailSearch = await repository.searchUsers('user1@');
        expect(emailSearch, hasLength(1));
        expect(emailSearch.first.id, equals('user_1'));

        final noResults = await repository.searchUsers('nonexistent');
        expect(noResults, isEmpty);
      });
    });

    group('User Management Operations', () {
      late User testUser;

      setUp(() async {
        testUser = User(
          id: 'user_1',
          email: 'test@example.com',
          displayName: 'Test User',
          role: UserRole.user,
          status: UserStatus.active,
          createdAt: DateTime.now(),
          preferences: {'theme': 'dark', 'notifications': true},
        );
        await repository.create(testUser);
      });

      test('should update user preferences', () async {
        final newPreferences = {'theme': 'light', 'language': 'en'};
        
        final updatedUser = await repository.updatePreferences(
          'user_1',
          newPreferences,
        );
        
        expect(updatedUser.preferences, equals(newPreferences));
        
        // Verify persistence
        final retrievedUser = await repository.findById('user_1');
        expect(retrievedUser!.preferences, equals(newPreferences));
      });

      test('should update last login', () async {
        final loginTime = DateTime.now();
        
        final updatedUser = await repository.updateLastLogin('user_1', loginTime);
        
        expect(updatedUser.lastLoginAt, equals(loginTime));
        
        // Verify persistence
        final retrievedUser = await repository.findById('user_1');
        expect(retrievedUser!.lastLoginAt, equals(loginTime));
      });

      test('should get user statistics', () async {
        final stats = await repository.getUserStats('user_1');
        
        expect(stats.totalSessions, equals(0)); // Mock value
        expect(stats.totalJobs, equals(0)); // Mock value
        expect(stats.totalAudioRequests, equals(0)); // Mock value
        expect(stats.totalActiveTime, equals(Duration.zero)); // Mock value
        expect(stats.preferences, equals(testUser.preferences));
      });

      test('should handle non-existent user in operations', () async {
        expect(
          () => repository.updatePreferences('non_existent', {}),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('User with id non_existent not found'),
          )),
        );

        expect(
          () => repository.updateLastLogin('non_existent', DateTime.now()),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('User with id non_existent not found'),
          )),
        );

        expect(
          () => repository.getUserStats('non_existent'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('User with id non_existent not found'),
          )),
        );
      });
    });

    group('Cached Repository Operations', () {
      late User testUser;

      setUp(() async {
        testUser = User(
          id: 'user_1',
          email: 'test@example.com',
          displayName: 'Test User',
          role: UserRole.user,
          status: UserStatus.active,
          createdAt: DateTime.now(),
        );
        await repository.create(testUser);
      });

      test('should support cached operations', () async {
        // Test findByIdCached (simplified for SharedPreferences)
        final cachedUser = await repository.findByIdCached('user_1');
        expect(cachedUser, isNotNull);
        expect(cachedUser!.id, equals('user_1'));

        // Test cache operations (no-ops for SharedPreferences)
        await repository.refreshCache('user_1');
        await repository.clearCache();
        
        final stats = await repository.getCacheStats();
        expect(stats.hitCount, greaterThan(0));
      });
    });

    group('Repository Statistics', () {
      test('should count users correctly', () async {
        expect(await repository.count(), equals(0));

        final user1 = User(
          id: 'user_1',
          email: 'user1@example.com',
          displayName: 'User One',
          role: UserRole.user,
          status: UserStatus.active,
          createdAt: DateTime.now(),
        );
        await repository.create(user1);
        expect(await repository.count(), equals(1));

        final user2 = User(
          id: 'user_2',
          email: 'user2@example.com',
          displayName: 'User Two',
          role: UserRole.admin,
          status: UserStatus.active,
          createdAt: DateTime.now(),
        );
        await repository.create(user2);
        expect(await repository.count(), equals(2));

        await repository.deleteById('user_1');
        expect(await repository.count(), equals(1));
      });

      test('should clear all users', () async {
        // Create multiple users
        for (int i = 1; i <= 3; i++) {
          final user = User(
            id: 'user_$i',
            email: 'user$i@example.com',
            displayName: 'User $i',
            role: UserRole.user,
            status: UserStatus.active,
            createdAt: DateTime.now(),
          );
          await repository.create(user);
        }

        expect(await repository.count(), equals(3));

        await repository.clear();
        expect(await repository.count(), equals(0));
        expect(await repository.findAll(), isEmpty);
      });
    });

    group('Error Handling', () {
      test('should handle update on non-existent user', () async {
        final nonExistentUser = User(
          id: 'non_existent',
          email: 'test@example.com',
          displayName: 'Test User',
          role: UserRole.user,
          status: UserStatus.active,
          createdAt: DateTime.now(),
        );

        expect(
          () => repository.update(nonExistentUser),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Entity with id non_existent does not exist'),
          )),
        );
      });

      test('should handle serialization errors gracefully', () async {
        // This would test error handling in fromJson/toJson
        // For now, we'll test that the repository handles basic operations
        final user = User(
          id: 'user_1',
          email: 'test@example.com',
          displayName: 'Test User',
          role: UserRole.user,
          status: UserStatus.active,
          createdAt: DateTime.now(),
        );

        expect(repository.toJson(user), isA<Map<String, dynamic>>());
        
        final json = repository.toJson(user);
        final deserializedUser = repository.fromJson(json);
        expect(deserializedUser.id, equals(user.id));
        expect(deserializedUser.email, equals(user.email));
      });
    });
  });
}