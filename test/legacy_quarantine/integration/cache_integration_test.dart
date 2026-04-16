import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../lib/core/cache/cache_manager.dart';
import '../../lib/core/storage/storage_manager.dart';
import '../../lib/core/repositories/impl/session_repository_impl.dart';
import '../../lib/core/repositories/impl/voice_repository_impl.dart';
import '../../lib/core/repositories/impl/audio_repository_impl.dart';
import '../../lib/services/network/http_service.dart';
import '../../lib/shared/models/models.dart';
import 'package:dio/dio.dart';

void main() {
  group('Cache Integration Tests', () {
    late CacheManager<Map<String, dynamic>> httpCache;
    late CacheManager<List<int>> audioCache;
    late CacheManager<Session> sessionCache;
    late StorageManager storage;
    late SessionRepositoryImpl sessionRepo;
    late VoiceRepositoryImpl voiceRepo;
    late AudioRepositoryImpl audioRepo;
    late HttpService httpService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      
      storage = await StorageManager.getInstance();
      
      httpCache = CacheManager<Map<String, dynamic>>(
        'http_cache',
        CachePolicy.memoryFirst,
        storage,
      );
      
      audioCache = CacheManager<List<int>>(
        'audio_cache',
        CachePolicy.diskFirst,
        storage,
      );
      
      sessionCache = CacheManager<Session>(
        'session_cache',
        CachePolicy.memoryOnly,
        storage,
      );
      
      sessionRepo = SessionRepositoryImpl();
      voiceRepo = VoiceRepositoryImpl();
      audioRepo = AudioRepositoryImpl();
      httpService = HttpService(Dio());
    });

    tearDown(() async {
      await httpCache.clear();
      await audioCache.clear();
      await sessionCache.clear();
      sessionRepo.dispose();
      voiceRepo.dispose();
      audioRepo.dispose();
    });

    group('HTTP Response Caching', () {
      test('should cache HTTP responses with TTL', () async {
        final responseData = {
          'session_id': 'session_123',
          'user_id': 'user_456',
          'data': 'test response data',
          'timestamp': DateTime.now().toIso8601String(),
        };

        // Cache HTTP response with 1 hour TTL
        await httpCache.put(
          'api_response_sessions',
          responseData,
          ttl: Duration(hours: 1),
        );

        // Retrieve from cache
        final cachedResponse = await httpCache.get('api_response_sessions');
        expect(cachedResponse, isNotNull);
        expect(cachedResponse!['session_id'], equals('session_123'));
        expect(cachedResponse['data'], equals('test response data'));

        // Verify cache stats
        final stats = await httpCache.getStats();
        expect(stats.totalEntries, equals(1));
        expect(stats.memoryEntries, equals(1));
        expect(stats.hitRate, equals(1.0)); // 100% hit rate
      });

      test('should handle cache expiration', () async {
        final shortLivedData = {
          'data': 'expires quickly',
          'timestamp': DateTime.now().toIso8601String(),
        };

        // Cache with very short TTL
        await httpCache.put(
          'short_lived',
          shortLivedData,
          ttl: Duration(milliseconds: 100),
        );

        // Should be available immediately
        final immediate = await httpCache.get('short_lived');
        expect(immediate, isNotNull);

        // Wait for expiration
        await Future.delayed(Duration(milliseconds: 150));

        // Should be expired
        final expired = await httpCache.get('short_lived');
        expect(expired, isNull);

        // Verify cache stats show eviction
        final stats = await httpCache.getStats();
        expect(stats.evictionCount, greaterThan(0));
      });

      test('should integrate HTTP cache with repository data', () async {
        // Create session in repository
        final session = await sessionRepo.createSession('user_1', 'token_123');
        
        // Cache session data for HTTP requests
        final sessionData = {
          'id': session.id,
          'user_id': session.userId,
          'token': session.token,
          'status': session.status.toString(),
          'created_at': session.createdAt.toIso8601String(),
        };

        await httpCache.put('current_session', sessionData);

        // Simulate HTTP service using cached session data
        final cachedSession = await httpCache.get('current_session');
        expect(cachedSession!['token'], equals('token_123'));

        // Update session in repository
        await sessionRepo.updateActivity(session.id);

        // Update cache with fresh data
        final updatedSession = await sessionRepo.findById(session.id);
        final updatedSessionData = {
          'id': updatedSession!.id,
          'user_id': updatedSession.userId,
          'token': updatedSession.token,
          'status': updatedSession.status.toString(),
          'last_activity': updatedSession.lastActivityAt.toIso8601String(),
        };

        await httpCache.put('current_session', updatedSessionData);

        // Verify cache has updated data
        final refreshedCache = await httpCache.get('current_session');
        expect(refreshedCache!['last_activity'], isNotNull);
      });
    });

    group('Audio Data Caching', () {
      test('should cache audio chunks with disk persistence', () async {
        // Create audio chunk in repository
        final audioChunk = AudioChunk(
          id: 'audio_1',
          sessionId: 'session_1',
          jobId: 'job_1',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/temp/audio.mp3',
          timestamp: DateTime.now(),
          duration: Duration(seconds: 3),
          metadata: {'size_bytes': 1024},
        );
        await audioRepo.create(audioChunk);

        // Simulate audio data
        final audioData = List.generate(1024, (i) => i % 256);

        // Cache audio data
        await audioCache.put('audio_${audioChunk.id}', audioData);

        // Update repository with cache status
        await audioRepo.updateCacheStatus(audioChunk.id, true, '/cached/audio.mp3');

        // Verify audio data in cache
        final cachedAudio = await audioCache.get('audio_${audioChunk.id}');
        expect(cachedAudio, isNotNull);
        expect(cachedAudio!.length, equals(1024));

        // Verify repository reflects cache status
        final updatedChunk = await audioRepo.findById(audioChunk.id);
        expect(updatedChunk!.metadata?['is_cached'], equals(true));

        // Test cache persistence (should survive cache manager recreation)
        final newAudioCache = CacheManager<List<int>>(
          'audio_cache',
          CachePolicy.diskFirst,
          storage,
        );

        final persistedAudio = await newAudioCache.get('audio_${audioChunk.id}');
        expect(persistedAudio, isNotNull);
        expect(persistedAudio!.length, equals(1024));
      });

      test('should handle audio cache size limits', () async {
        final audioChunks = <AudioChunk>[];
        
        // Create multiple large audio chunks
        for (int i = 1; i <= 10; i++) {
          final chunk = AudioChunk(
            id: 'audio_$i',
            sessionId: 'session_1',
            jobId: 'job_$i',
            chunkIndex: 0,
            type: AudioChunkType.output,
            localPath: '/temp/audio$i.mp3',
            timestamp: DateTime.now().subtract(Duration(minutes: i)),
            duration: Duration(seconds: i),
            metadata: {'size_bytes': i * 1000},
          );
          
          await audioRepo.create(chunk);
          audioChunks.add(chunk);

          // Cache large audio data
          final audioData = List.generate(i * 1000, (j) => j % 256);
          await audioCache.put('audio_${chunk.id}', audioData);
          
          await audioRepo.updateCacheStatus(chunk.id, true, '/cached/audio$i.mp3');
        }

        // Check cache size and eviction behavior
        final stats = await audioCache.getStats();
        expect(stats.totalEntries, lessThanOrEqualTo(10));

        // Get cached audio chunks from repository
        final cachedChunks = await audioRepo.getCachedAudio();
        expect(cachedChunks.length, greaterThan(0));

        // Test cache cleanup
        await audioRepo.clearCache(keepRecent: true);

        // Verify recent chunks are kept, old ones evicted
        final postCleanupStats = await audioCache.getStats();
        expect(postCleanupStats.totalEntries, lessThan(stats.totalEntries));
      });

      test('should coordinate audio caching with TTS pipeline', () async {
        // Create voice input
        final voiceInput = VoiceInput(
          id: 'voice_1',
          sessionId: 'session_1',
          status: VoiceInputStatus.transcribed,
          timestamp: DateTime.now(),
          transcription: 'Hello world',
          response: 'Hello! How can I help you?',
        );
        await voiceRepo.create(voiceInput);

        // Create TTS job
        final ttsJob = Job(
          id: 'tts_job_1',
          text: 'TTS: Hello! How can I help you?',
          status: JobStatus.running,
          createdAt: DateTime.now(),
          metadata: {'voice_input_id': 'voice_1', 'type': 'tts'},
        );

        // Simulate TTS processing and audio generation
        final generatedAudio = List.generate(2048, (i) => (i * 31) % 256);
        
        // Cache the generated audio
        await audioCache.put('tts_audio_${ttsJob.id}', generatedAudio);

        // Create audio chunk record
        final audioChunk = AudioChunk(
          id: 'audio_tts_1',
          sessionId: 'session_1',
          jobId: ttsJob.id,
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/cached/tts_audio.mp3',
          timestamp: DateTime.now(),
          duration: Duration(seconds: 4),
          metadata: {
            'voice_input_id': 'voice_1',
            'size_bytes': 2048,
            'is_cached': true,
            'tts_job_id': ttsJob.id,
          },
        );
        await audioRepo.create(audioChunk);

        // Verify complete TTS pipeline caching
        final cachedAudio = await audioCache.get('tts_audio_${ttsJob.id}');
        expect(cachedAudio, isNotNull);
        expect(cachedAudio!.length, equals(2048));

        final audioRecord = await audioRepo.findById('audio_tts_1');
        expect(audioRecord!.metadata?['voice_input_id'], equals('voice_1'));
        expect(audioRecord.metadata?['is_cached'], equals(true));

        final voiceRecord = await voiceRepo.findById('voice_1');
        expect(voiceRecord!.response, equals('Hello! How can I help you?'));
      });
    });

    group('Session Caching', () {
      test('should cache active sessions in memory', () async {
        // Create multiple sessions
        final sessions = [
          await sessionRepo.createSession('user_1', 'token_1'),
          await sessionRepo.createSession('user_1', 'token_2'),
          await sessionRepo.createSession('user_2', 'token_3'),
        ];

        // Cache active sessions
        for (final session in sessions) {
          await sessionCache.put('session_${session.id}', session);
        }

        // Verify sessions in cache
        for (final session in sessions) {
          final cached = await sessionCache.get('session_${session.id}');
          expect(cached, isNotNull);
          expect(cached!.id, equals(session.id));
          expect(cached.userId, equals(session.userId));
        }

        // Test cache performance
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 100; i++) {
          await sessionCache.get('session_${sessions[0].id}');
        }
        
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(100)); // Should be very fast for memory cache

        // Verify cache stats
        final stats = await sessionCache.getStats();
        expect(stats.totalEntries, equals(3));
        expect(stats.memoryEntries, equals(3));
        expect(stats.diskEntries, equals(0)); // Memory-only cache
      });

      test('should handle session cache invalidation', () async {
        final session = await sessionRepo.createSession('user_1', 'token_123');
        
        // Cache session
        await sessionCache.put('current_session', session);

        // Verify cached
        final cached = await sessionCache.get('current_session');
        expect(cached, isNotNull);

        // Terminate session in repository
        await sessionRepo.terminateSession(session.id);

        // Invalidate cache
        await sessionCache.remove('current_session');

        // Verify cache is cleared
        final afterInvalidation = await sessionCache.get('current_session');
        expect(afterInvalidation, isNull);

        // Re-cache with updated session data
        final updatedSession = await sessionRepo.findById(session.id);
        await sessionCache.put('current_session', updatedSession!);

        final reCached = await sessionCache.get('current_session');
        expect(reCached!.status, equals(SessionStatus.terminated));
      });
    });

    group('Cache Coordination and Consistency', () {
      test('should maintain cache consistency across services', () async {
        // Create session
        final session = await sessionRepo.createSession('user_1', 'token_123');
        
        // Cache session in HTTP cache
        await httpCache.put('auth_session', {
          'id': session.id,
          'token': session.token,
          'user_id': session.userId,
        });

        // Cache session object in session cache
        await sessionCache.put('current_session', session);

        // Create voice input linked to session
        final voiceInput = VoiceInput(
          id: 'voice_1',
          sessionId: session.id,
          status: VoiceInputStatus.recording,
          timestamp: DateTime.now(),
        );
        await voiceRepo.create(voiceInput);

        // Update session activity
        await sessionRepo.updateActivity(session.id);
        final updatedSession = await sessionRepo.findById(session.id);

        // Update all caches to maintain consistency
        await httpCache.put('auth_session', {
          'id': updatedSession!.id,
          'token': updatedSession.token,
          'user_id': updatedSession.userId,
          'last_activity': updatedSession.lastActivityAt.toIso8601String(),
        });

        await sessionCache.put('current_session', updatedSession);

        // Verify consistency across caches
        final httpCachedSession = await httpCache.get('auth_session');
        final sessionCachedSession = await sessionCache.get('current_session');

        expect(httpCachedSession!['id'], equals(sessionCachedSession!.id));
        expect(httpCachedSession['token'], equals(sessionCachedSession.token));
        expect(httpCachedSession['last_activity'], isNotNull);
      });

      test('should handle cache eviction policies', () async {
        // Test LRU eviction for HTTP cache
        final httpCacheLRU = CacheManager<Map<String, dynamic>>(
          'http_cache_lru',
          CachePolicy.memoryFirst,
          storage,
          maxMemoryEntries: 3,
        );

        // Fill cache beyond capacity
        for (int i = 1; i <= 5; i++) {
          await httpCacheLRU.put('item_$i', {'data': 'item $i'});
        }

        // Check that only the most recent items remain
        final stats = await httpCacheLRU.getStats();
        expect(stats.memoryEntries, equals(3));

        // Verify LRU behavior
        final item1 = await httpCacheLRU.get('item_1'); // Should be evicted
        final item5 = await httpCacheLRU.get('item_5'); // Should be present

        expect(item1, isNull);
        expect(item5, isNotNull);

        await httpCacheLRU.clear();
      });

      test('should handle concurrent cache operations', () async {
        final futures = <Future>[];
        
        // Perform concurrent cache operations
        for (int i = 1; i <= 20; i++) {
          futures.add(() async {
            final session = await sessionRepo.createSession('user_$i', 'token_$i');
            
            await sessionCache.put('session_$i', session);
            
            await httpCache.put('http_session_$i', {
              'id': session.id,
              'user_id': session.userId,
              'token': session.token,
            });
            
            final audioData = List.generate(100, (j) => j % 256);
            await audioCache.put('audio_$i', audioData);
          }());
        }
        
        await Future.wait(futures);
        
        // Verify all operations completed successfully
        final sessionStats = await sessionCache.getStats();
        final httpStats = await httpCache.getStats();
        final audioStats = await audioCache.getStats();
        
        expect(sessionStats.totalEntries, equals(20));
        expect(httpStats.totalEntries, equals(20));
        expect(audioStats.totalEntries, equals(20));
        
        // Test concurrent reads
        final readFutures = <Future>[];
        
        for (int i = 1; i <= 20; i++) {
          readFutures.add(() async {
            final session = await sessionCache.get('session_$i');
            final http = await httpCache.get('http_session_$i');
            final audio = await audioCache.get('audio_$i');
            
            expect(session, isNotNull);
            expect(http, isNotNull);
            expect(audio, isNotNull);
          }());
        }
        
        await Future.wait(readFutures);
      });
    });

    group('Cache Performance and Optimization', () {
      test('should demonstrate cache performance benefits', () async {
        final stopwatch = Stopwatch();
        
        // Test without cache (repository access only)
        stopwatch.start();
        for (int i = 1; i <= 100; i++) {
          final session = await sessionRepo.createSession('user_$i', 'token_$i');
          await sessionRepo.findById(session.id);
        }
        stopwatch.stop();
        final noCacheTime = stopwatch.elapsed;
        
        // Reset and test with cache
        stopwatch.reset();
        stopwatch.start();
        
        for (int i = 1; i <= 100; i++) {
          final cacheKey = 'perf_session_$i';
          
          // Try cache first
          var session = await sessionCache.get(cacheKey);
          
          if (session == null) {
            // Cache miss - get from repository and cache
            session = await sessionRepo.createSession('cached_user_$i', 'cached_token_$i');
            await sessionCache.put(cacheKey, session);
          }
        }
        
        stopwatch.stop();
        final withCacheTime = stopwatch.elapsed;
        
        // Cache should provide performance benefit
        print('No cache: ${noCacheTime.inMilliseconds}ms');
        print('With cache: ${withCacheTime.inMilliseconds}ms');
        
        // Verify cache stats show good hit rate
        final stats = await sessionCache.getStats();
        expect(stats.hitRate, greaterThan(0.0));
      });
    });
  });
}