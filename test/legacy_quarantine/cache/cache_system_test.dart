import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../lib/core/cache/cache_exports.dart';
import '../../lib/core/storage/storage_manager.dart';
import '../../lib/shared/models/models.dart';

void main() {
  group('Cache System Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('CachePolicy should create different configurations', () {
      const shortLived = CachePolicy.shortLived;
      const longLived = CachePolicy.longLived;
      const audio = CachePolicy.audio;
      
      expect(shortLived.maxAge, Duration(minutes: 30));
      expect(longLived.maxAge, Duration(days: 30));
      expect(audio.maxSizeBytes, 200 * 1024 * 1024);
      
      // Test copyWith
      final customPolicy = CachePolicy.defaultPolicy.copyWith(
        maxAge: Duration(hours: 2),
        maxItems: 500,
      );
      
      expect(customPolicy.maxAge, Duration(hours: 2));
      expect(customPolicy.maxItems, 500);
    });

    test('CacheManager should store and retrieve items', () async {
      final storage = await StorageManager.getInstance();
      final cacheManager = CacheManager<String>(
        cacheKey: 'test_cache',
        toJson: (value) => {'value': value},
        fromJson: (json) => json['value'] as String,
        storage: storage,
      );

      // Test put and get
      await cacheManager.put('key1', 'value1');
      final retrieved = await cacheManager.get('key1');
      expect(retrieved, 'value1');

      // Test cache miss
      final missing = await cacheManager.get('nonexistent');
      expect(missing, null);

      // Test cache stats
      final stats = cacheManager.getStats();
      expect(stats.itemCount, 1);
      expect(stats.hitRate, greaterThan(0.0));
    });

    test('CacheManager should handle expiration', () async {
      final storage = await StorageManager.getInstance();
      final shortPolicy = CachePolicy.defaultPolicy.copyWith(
        maxAge: Duration(milliseconds: 100),
      );
      
      final cacheManager = CacheManager<String>(
        cacheKey: 'expiry_test',
        toJson: (value) => {'value': value},
        fromJson: (json) => json['value'] as String,
        policy: shortPolicy,
        storage: storage,
      );

      // Add item
      await cacheManager.put('key1', 'value1');
      
      // Should be available immediately
      final immediate = await cacheManager.get('key1');
      expect(immediate, 'value1');
      
      // Wait for expiration
      await Future.delayed(Duration(milliseconds: 150));
      
      // Should be expired
      final expired = await cacheManager.get('key1');
      expect(expired, null);
    });

    test('CacheManager should enforce size limits', () async {
      final storage = await StorageManager.getInstance();
      final limitedPolicy = CachePolicy.defaultPolicy.copyWith(
        maxItems: 2,
      );
      
      final cacheManager = CacheManager<String>(
        cacheKey: 'size_limit_test',
        toJson: (value) => {'value': value},
        fromJson: (json) => json['value'] as String,
        policy: limitedPolicy,
        storage: storage,
      );

      // Add items up to limit
      await cacheManager.put('key1', 'value1');
      await cacheManager.put('key2', 'value2');
      
      // Stats should show 2 items
      final stats1 = cacheManager.getStats();
      expect(stats1.itemCount, 2);
      
      // Add one more item (should trigger eviction)
      await cacheManager.put('key3', 'value3');
      
      // Should still have 2 items
      final stats2 = cacheManager.getStats();
      expect(stats2.itemCount, 2);
      
      // First item should be evicted (LRU)
      final evicted = await cacheManager.get('key1');
      expect(evicted, null);
      
      // Newest item should be available
      final newest = await cacheManager.get('key3');
      expect(newest, 'value3');
    });

    test('OfflineManager should handle cache managers', () async {
      final offlineManager = await OfflineManager.getInstance();
      
      // Get cache manager for User entities
      final userCache = offlineManager.getCacheManager<User>(
        cacheKey: 'users',
        toJson: (user) => user.toJson(),
        fromJson: (json) => User.fromJson(json),
      );
      
      // Test caching a user
      final user = User(
        id: 'user1',
        email: 'test@example.com',
        displayName: 'Test User',
        role: UserRole.user,
        status: UserStatus.active,
        createdAt: DateTime.now(),
      );
      
      await userCache.put('user1', user);
      final retrievedUser = await userCache.get('user1');
      
      expect(retrievedUser, isNotNull);
      expect(retrievedUser!.email, 'test@example.com');
      expect(retrievedUser.displayName, 'Test User');
    });

    test('OfflineManager should queue requests when offline', () async {
      final offlineManager = await OfflineManager.getInstance();
      
      // Enable offline mode
      await offlineManager.enableOfflineMode();
      expect(offlineManager.isOffline, true);
      
      // Queue a request
      await offlineManager.queueRequest('test_request', {
        'method': 'POST',
        'url': '/api/test',
        'data': {'key': 'value'},
      });
      
      // Check queue
      final queued = offlineManager.getQueuedRequests();
      expect(queued.length, 1);
      expect(queued.first.key, 'test_request');
      expect(queued.first.data['method'], 'POST');
      
      // Remove from queue
      await offlineManager.removeFromQueue('test_request');
      final emptyQueue = offlineManager.getQueuedRequests();
      expect(emptyQueue.length, 0);
    });

    test('OfflineManager should provide statistics', () async {
      final offlineManager = await OfflineManager.getInstance();
      
      // Cache some data
      await offlineManager.cacheForOffline<String>(
        'test_cache',
        'item1',
        'value1',
        toJson: (value) => {'value': value},
        fromJson: (json) => json['value'] as String,
      );
      
      // Get stats
      final stats = await offlineManager.getOfflineStats();
      expect(stats.totalCachedItems, greaterThan(0));
      expect(stats.cacheManagerStats, isNotEmpty);
    });

    test('AudioCache should handle audio caching', () async {
      final audioCache = await AudioCache.getInstance();
      
      // Create test audio chunks
      final chunks = [
        AudioChunk(
          id: 'chunk1',
          sessionId: 'session1',
          jobId: 'job1',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/path/to/audio1.mp3',
          timestamp: DateTime.now(),
          duration: Duration(seconds: 2),
        ),
        AudioChunk(
          id: 'chunk2',
          sessionId: 'session1',
          jobId: 'job1',
          chunkIndex: 1,
          type: AudioChunkType.output,
          localPath: '/path/to/audio2.mp3',
          timestamp: DateTime.now(),
          duration: Duration(seconds: 3),
        ),
      ];
      
      // Cache audio for text
      await audioCache.cacheAudioForText(
        'Hello world',
        'elevenlabs',
        chunks,
      );
      
      // Retrieve cached audio
      final cached = await audioCache.getCachedAudioForText(
        'Hello world',
        'elevenlabs',
      );
      
      expect(cached, isNotNull);
      expect(cached!.length, 2);
      expect(cached.first.id, 'chunk1');
      expect(cached.last.id, 'chunk2');
      
      // Test cache miss
      final missing = await audioCache.getCachedAudioForText(
        'Different text',
        'elevenlabs',
      );
      expect(missing, null);
    });

    test('AudioCache should provide statistics', () async {
      final audioCache = await AudioCache.getInstance();
      
      // Cache some audio
      final chunks = [
        AudioChunk(
          id: 'chunk1',
          sessionId: 'session1',
          jobId: 'job1',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/path/to/audio1.mp3',
          timestamp: DateTime.now(),
          duration: Duration(seconds: 2),
        ),
      ];
      
      await audioCache.cacheAudioForText('Test', 'provider1', chunks);
      
      final stats = await audioCache.getStats();
      expect(stats.totalChunks, greaterThan(0));
      expect(stats.totalMetadata, greaterThan(0));
      expect(stats.providerStats.containsKey('provider1'), true);
    });

    test('AudioCache should clear provider-specific cache', () async {
      final audioCache = await AudioCache.getInstance();
      
      // Cache audio for different providers
      final chunks = [
        AudioChunk(
          id: 'chunk1',
          sessionId: 'session1',
          jobId: 'job1',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/path/to/audio1.mp3',
          timestamp: DateTime.now(),
          duration: Duration(seconds: 2),
        ),
      ];
      
      await audioCache.cacheAudioForText('Test', 'provider1', chunks);
      await audioCache.cacheAudioForText('Test', 'provider2', chunks);
      
      // Clear specific provider
      await audioCache.clearProviderCache('provider1');
      
      // Check that only provider2 remains
      final provider1Cache = await audioCache.getCachedAudioForText('Test', 'provider1');
      final provider2Cache = await audioCache.getCachedAudioForText('Test', 'provider2');
      
      expect(provider1Cache, null);
      expect(provider2Cache, isNotNull);
    });

    test('Cache system should handle cleanup', () async {
      final storage = await StorageManager.getInstance();
      final cacheManager = CacheManager<String>(
        cacheKey: 'cleanup_test',
        toJson: (value) => {'value': value},
        fromJson: (json) => json['value'] as String,
        policy: CachePolicy.defaultPolicy.copyWith(
          maxAge: Duration(milliseconds: 100),
        ),
        storage: storage,
      );

      // Add items
      await cacheManager.put('key1', 'value1');
      await cacheManager.put('key2', 'value2');
      
      // Wait for expiration
      await Future.delayed(Duration(milliseconds: 150));
      
      // Manual cleanup
      await cacheManager.cleanup();
      
      // Items should be removed
      final stats = cacheManager.getStats();
      expect(stats.itemCount, 0);
    });
  });
}