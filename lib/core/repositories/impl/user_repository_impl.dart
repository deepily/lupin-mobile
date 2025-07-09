import 'dart:async';
import '../../../shared/models/models.dart';
import '../user_repository.dart';
import '../base_repository.dart';
import 'shared_preferences_repository.dart';

class UserRepositoryImpl extends SharedPreferencesRepository<User, String> 
    implements UserRepository {
  
  UserRepositoryImpl() : super('user');
  
  @override
  Map<String, dynamic> toJson(User entity) => entity.toJson();
  
  @override
  User fromJson(Map<String, dynamic> json) => User.fromJson(json);
  
  @override
  String getId(User entity) => entity.id;
  
  @override
  Future<User?> findByEmail(String email) async {
    return await findFirstWhere((user) => user.email == email);
  }
  
  @override
  Future<List<User>> findByRole(UserRole role) async {
    return await findWhere((user) => user.role == role);
  }
  
  @override
  Future<List<User>> findByStatus(UserStatus status) async {
    return await findWhere((user) => user.status == status);
  }
  
  @override
  Future<User> updatePreferences(
    String userId, 
    Map<String, dynamic> preferences,
  ) async {
    final user = await findById(userId);
    if (user == null) {
      throw Exception('User with id $userId not found');
    }
    
    final updatedUser = user.copyWith(preferences: preferences);
    return await update(updatedUser);
  }
  
  @override
  Future<User> updateLastLogin(String userId, DateTime lastLogin) async {
    final user = await findById(userId);
    if (user == null) {
      throw Exception('User with id $userId not found');
    }
    
    final updatedUser = user.copyWith(lastLoginAt: lastLogin);
    return await update(updatedUser);
  }
  
  @override
  Future<UserStats> getUserStats(String userId) async {
    final user = await findById(userId);
    if (user == null) {
      throw Exception('User with id $userId not found');
    }
    
    // Mock statistics - in real implementation, this would aggregate data
    // from other repositories (sessions, jobs, etc.)
    return UserStats(
      totalSessions: 0,
      totalJobs: 0,
      totalAudioRequests: 0,
      totalActiveTime: Duration.zero,
      lastActivity: user.lastLoginAt,
      preferences: user.preferences ?? {},
      featureUsage: {},
    );
  }
  
  @override
  Future<List<User>> searchUsers(String query) async {
    final lowercaseQuery = query.toLowerCase();
    return await findWhere((user) {
      final email = user.email.toLowerCase();
      final displayName = user.displayName?.toLowerCase() ?? '';
      return email.contains(lowercaseQuery) || displayName.contains(lowercaseQuery);
    });
  }
  
  @override
  Future<List<User>> getActiveUsers() async {
    return await findByStatus(UserStatus.active);
  }
  
  @override
  Future<List<User>> getRecentlyActiveUsers({Duration? since}) async {
    final cutoff = since != null 
        ? DateTime.now().subtract(since)
        : DateTime.now().subtract(Duration(days: 7));
    
    return await findWhere((user) {
      return user.lastLoginAt != null && 
             user.lastLoginAt!.isAfter(cutoff) &&
             user.status == UserStatus.active;
    });
  }
  
  // CachedRepository methods (simplified for SharedPreferences)
  @override
  Future<User?> findByIdCached(String id, {Duration? maxAge}) async {
    // For SharedPreferences, we don't need separate caching
    return await findById(id);
  }
  
  @override
  Future<void> refreshCache(String id) async {
    // No-op for SharedPreferences implementation
  }
  
  @override
  Future<void> clearCache() async {
    // No-op for SharedPreferences implementation
  }
  
  @override
  Future<CacheStats> getCacheStats() async {
    final totalCount = await count();
    return CacheStats(
      hitCount: totalCount,
      missCount: 0,
      entryCount: totalCount,
      maxSize: 1000,
      lastAccess: DateTime.now(),
    );
  }
}