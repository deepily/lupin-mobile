import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../../lib/services/network/http_service.dart';
import '../../lib/services/network/websocket_service.dart';
import '../../lib/services/tts/tts_service.dart';
import '../../lib/core/cache/cache_manager.dart';
import '../../lib/core/storage/storage_manager.dart';
import '../../lib/core/repositories/impl/session_repository_impl.dart';
import '../../lib/core/repositories/impl/job_repository_impl.dart';
import '../../lib/core/repositories/impl/voice_repository_impl.dart';
import '../../lib/core/repositories/impl/audio_repository_impl.dart';
import '../../lib/shared/models/models.dart';

void main() {
  group('Service Integration Tests', () {
    late HttpService httpService;
    late WebSocketService webSocketService;
    late TTSService ttsService;
    late CacheManager<Map<String, dynamic>> cache;
    late StorageManager storage;
    late SessionRepositoryImpl sessionRepo;
    late JobRepositoryImpl jobRepo;
    late VoiceRepositoryImpl voiceRepo;
    late AudioRepositoryImpl audioRepo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      
      // Initialize storage
      storage = await StorageManager.getInstance();
      
      // Initialize cache
      cache = CacheManager<Map<String, dynamic>>(
        'test_cache',
        CachePolicy.memoryFirst,
        storage,
      );
      
      // Initialize services
      final dio = Dio();
      httpService = HttpService(dio);
      webSocketService = WebSocketService();
      ttsService = TTSService();
      
      // Initialize repositories
      sessionRepo = SessionRepositoryImpl();
      jobRepo = JobRepositoryImpl();
      voiceRepo = VoiceRepositoryImpl();
      audioRepo = AudioRepositoryImpl();
    });

    tearDown(() async {
      await webSocketService.disconnect();
      await cache.clear();
      sessionRepo.dispose();
      jobRepo.dispose();
      voiceRepo.dispose();
      audioRepo.dispose();
    });

    group('HTTP Service Integration', () {
      test('should integrate with session repository for authentication', () async {
        // Create a session in repository
        final session = await sessionRepo.createSession(
          'user_1',
          'test_token_123',
          expiresIn: Duration(hours: 24),
        );

        // Store session data in cache for HTTP service
        await cache.put('current_session', {
          'id': session.id,
          'token': session.token,
          'userId': session.userId,
        });

        // Retrieve session data for HTTP requests
        final cachedSession = await cache.get('current_session');
        expect(cachedSession, isNotNull);
        expect(cachedSession!['token'], equals('test_token_123'));

        // Verify session exists in repository
        final retrievedSession = await sessionRepo.findById(session.id);
        expect(retrievedSession, isNotNull);
        expect(retrievedSession!.token, equals('test_token_123'));
      });

      test('should cache HTTP responses with repository data', () async {
        // Create test job
        final job = Job(
          id: 'job_1',
          text: 'Test job for HTTP cache',
          status: JobStatus.todo,
          createdAt: DateTime.now(),
        );
        await jobRepo.create(job);

        // Simulate caching HTTP response with job data
        final responseData = {
          'job_id': job.id,
          'status': job.status.toString(),
          'text': job.text,
          'timestamp': job.createdAt.toIso8601String(),
        };

        await cache.put('job_${job.id}', responseData);

        // Retrieve from cache
        final cachedData = await cache.get('job_${job.id}');
        expect(cachedData, isNotNull);
        expect(cachedData!['job_id'], equals('job_1'));
        expect(cachedData['text'], equals('Test job for HTTP cache'));

        // Verify job still exists in repository
        final repoJob = await jobRepo.findById('job_1');
        expect(repoJob, isNotNull);
        expect(repoJob!.text, equals('Test job for HTTP cache'));
      });

      test('should handle session expiration and refresh', () async {
        // Create expired session
        final expiredSession = await sessionRepo.createSession(
          'user_1',
          'expired_token',
          expiresIn: Duration(milliseconds: -1000), // Already expired
        );

        // Store in cache
        await cache.put('current_session', {
          'id': expiredSession.id,
          'token': expiredSession.token,
          'userId': expiredSession.userId,
          'expiresAt': expiredSession.expiresAt?.toIso8601String(),
        });

        // Check if session is expired
        final cachedSession = await cache.get('current_session');
        final expiryDate = DateTime.parse(cachedSession!['expiresAt']);
        final isExpired = expiryDate.isBefore(DateTime.now());
        expect(isExpired, isTrue);

        // Create new session (simulating refresh)
        final newSession = await sessionRepo.createSession(
          'user_1',
          'new_token',
          expiresIn: Duration(hours: 24),
        );

        // Update cache with new session
        await cache.put('current_session', {
          'id': newSession.id,
          'token': newSession.token,
          'userId': newSession.userId,
          'expiresAt': newSession.expiresAt?.toIso8601String(),
        });

        // Verify new session is active
        final updatedCachedSession = await cache.get('current_session');
        expect(updatedCachedSession!['token'], equals('new_token'));
      });
    });

    group('WebSocket Service Integration', () {
      test('should handle voice input real-time updates', () async {
        final voiceUpdates = <VoiceInput>[];
        
        // Create initial voice input
        final voiceInput = VoiceInput(
          id: 'voice_1',
          sessionId: 'session_1',
          status: VoiceInputStatus.recording,
          timestamp: DateTime.now(),
        );
        await voiceRepo.create(voiceInput);

        // Watch for updates
        final subscription = voiceRepo.watchById('voice_1').listen((voice) {
          if (voice != null) voiceUpdates.add(voice);
        });

        // Simulate WebSocket message updating voice status
        await voiceRepo.updateStatus('voice_1', VoiceInputStatus.processing);
        await voiceRepo.updateTranscription('voice_1', 'Hello world', 0.95);

        // Wait for updates
        await Future.delayed(Duration(milliseconds: 100));

        expect(voiceUpdates.length, greaterThanOrEqualTo(2));
        expect(voiceUpdates.last.status, equals(VoiceInputStatus.transcribed));
        expect(voiceUpdates.last.transcription, equals('Hello world'));

        await subscription.cancel();
      });

      test('should sync job status updates across services', () async {
        final jobUpdates = <Job>[];
        
        // Create job
        final job = Job(
          id: 'job_1',
          text: 'WebSocket test job',
          status: JobStatus.todo,
          createdAt: DateTime.now(),
        );
        await jobRepo.create(job);

        // Watch for job updates
        final subscription = jobRepo.watchById('job_1').listen((job) {
          if (job != null) jobUpdates.add(job);
        });

        // Simulate WebSocket messages updating job status
        await jobRepo.updateStatus('job_1', JobStatus.running);
        await Future.delayed(Duration(milliseconds: 50));
        
        await jobRepo.updateResult('job_1', 'Job completed successfully');
        await Future.delayed(Duration(milliseconds: 50));

        expect(jobUpdates.length, greaterThanOrEqualTo(2));
        expect(jobUpdates.last.status, equals(JobStatus.completed));
        expect(jobUpdates.last.result, equals('Job completed successfully'));

        await subscription.cancel();
      });

      test('should handle audio chunk streaming', () async {
        final audioUpdates = <AudioChunk>[];
        
        // Create audio chunk
        final audioChunk = AudioChunk(
          id: 'audio_1',
          sessionId: 'session_1',
          jobId: 'job_1',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/temp/audio.mp3',
          timestamp: DateTime.now(),
        );
        await audioRepo.create(audioChunk);

        // Watch for updates
        final subscription = audioRepo.watchById('audio_1').listen((chunk) {
          if (chunk != null) audioUpdates.add(chunk);
        });

        // Simulate WebSocket audio chunk updates
        await audioRepo.updatePlaybackState('audio_1', true);
        await audioRepo.updateCacheStatus('audio_1', true, '/cached/audio.mp3');

        await Future.delayed(Duration(milliseconds: 100));

        expect(audioUpdates.length, greaterThanOrEqualTo(2));
        expect(audioUpdates.last.metadata?['is_playing'], equals(true));
        expect(audioUpdates.last.metadata?['is_cached'], equals(true));

        await subscription.cancel();
      });
    });

    group('TTS Service Integration', () {
      test('should integrate with audio repository for caching', () async {
        // Create voice input for TTS
        final voiceInput = VoiceInput(
          id: 'voice_1',
          sessionId: 'session_1',
          status: VoiceInputStatus.transcribed,
          timestamp: DateTime.now(),
          transcription: 'Hello world',
          response: 'Hello! How can I help you?',
        );
        await voiceRepo.create(voiceInput);

        // Create audio chunk for TTS output
        final audioChunk = AudioChunk(
          id: 'audio_1',
          sessionId: 'session_1',
          jobId: 'tts_job_1',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/temp/tts_output.mp3',
          timestamp: DateTime.now(),
          duration: Duration(seconds: 3),
          metadata: {
            'voice_input_id': 'voice_1',
            'text': 'Hello! How can I help you?',
            'voice_model': 'eleven_labs',
            'size_bytes': 1024,
          },
        );
        await audioRepo.create(audioChunk);

        // Cache TTS settings
        await cache.put('tts_settings', {
          'voice_model': 'eleven_labs',
          'speed': 1.0,
          'pitch': 1.0,
          'volume': 0.8,
        });

        // Verify integration
        final cachedSettings = await cache.get('tts_settings');
        expect(cachedSettings, isNotNull);
        expect(cachedSettings!['voice_model'], equals('eleven_labs'));

        final audioChunkFromRepo = await audioRepo.findById('audio_1');
        expect(audioChunkFromRepo, isNotNull);
        expect(audioChunkFromRepo!.metadata?['voice_input_id'], equals('voice_1'));
        expect(audioChunkFromRepo.type, equals(AudioChunkType.output));
      });

      test('should handle TTS queue management', () async {
        // Create multiple voice inputs for TTS queue
        final voiceInputs = [
          VoiceInput(
            id: 'voice_1',
            sessionId: 'session_1',
            status: VoiceInputStatus.transcribed,
            timestamp: DateTime.now().subtract(Duration(minutes: 3)),
            transcription: 'First message',
            response: 'This is the first response',
          ),
          VoiceInput(
            id: 'voice_2',
            sessionId: 'session_1',
            status: VoiceInputStatus.transcribed,
            timestamp: DateTime.now().subtract(Duration(minutes: 2)),
            transcription: 'Second message',
            response: 'This is the second response',
          ),
          VoiceInput(
            id: 'voice_3',
            sessionId: 'session_1',
            status: VoiceInputStatus.transcribed,
            timestamp: DateTime.now().subtract(Duration(minutes: 1)),
            transcription: 'Third message',
            response: 'This is the third response',
          ),
        ];

        for (final voice in voiceInputs) {
          await voiceRepo.create(voice);
        }

        // Create TTS jobs for each voice input
        final ttsJobs = [
          Job(
            id: 'tts_job_1',
            text: 'TTS: This is the first response',
            status: JobStatus.todo,
            createdAt: DateTime.now().subtract(Duration(minutes: 3)),
            metadata: {'voice_input_id': 'voice_1', 'type': 'tts'},
          ),
          Job(
            id: 'tts_job_2',
            text: 'TTS: This is the second response',
            status: JobStatus.todo,
            createdAt: DateTime.now().subtract(Duration(minutes: 2)),
            metadata: {'voice_input_id': 'voice_2', 'type': 'tts'},
          ),
          Job(
            id: 'tts_job_3',
            text: 'TTS: This is the third response',
            status: JobStatus.running,
            createdAt: DateTime.now().subtract(Duration(minutes: 1)),
            metadata: {'voice_input_id': 'voice_3', 'type': 'tts'},
          ),
        ];

        for (final job in ttsJobs) {
          await jobRepo.create(job);
        }

        // Get TTS queue (pending jobs)
        final pendingJobs = await jobRepo.findByStatus(JobStatus.todo);
        final ttsQueue = pendingJobs.where((job) => 
          job.metadata?['type'] == 'tts'
        ).toList();

        expect(ttsQueue, hasLength(2));
        expect(ttsQueue.map((j) => j.id), containsAll(['tts_job_1', 'tts_job_2']));

        // Get currently processing job
        final runningJobs = await jobRepo.findByStatus(JobStatus.running);
        final currentTTSJob = runningJobs.where((job) => 
          job.metadata?['type'] == 'tts'
        ).firstOrNull;

        expect(currentTTSJob, isNotNull);
        expect(currentTTSJob!.id, equals('tts_job_3'));
      });

      test('should manage audio cache for TTS outputs', () async {
        // Create multiple audio chunks for caching test
        final audioChunks = [
          AudioChunk(
            id: 'audio_1',
            sessionId: 'session_1',
            jobId: 'tts_job_1',
            chunkIndex: 0,
            type: AudioChunkType.output,
            localPath: '/temp/tts1.mp3',
            timestamp: DateTime.now().subtract(Duration(hours: 2)),
            duration: Duration(seconds: 3),
            metadata: {'size_bytes': 1024, 'is_cached': true},
          ),
          AudioChunk(
            id: 'audio_2',
            sessionId: 'session_1',
            jobId: 'tts_job_2',
            chunkIndex: 0,
            type: AudioChunkType.output,
            localPath: '/temp/tts2.mp3',
            timestamp: DateTime.now().subtract(Duration(hours: 1)),
            duration: Duration(seconds: 2),
            metadata: {'size_bytes': 512, 'is_cached': true},
          ),
          AudioChunk(
            id: 'audio_3',
            sessionId: 'session_1',
            jobId: 'tts_job_3',
            chunkIndex: 0,
            type: AudioChunkType.output,
            localPath: '/temp/tts3.mp3',
            timestamp: DateTime.now().subtract(Duration(minutes: 30)),
            duration: Duration(seconds: 4),
            metadata: {'size_bytes': 2048, 'is_cached': false},
          ),
        ];

        for (final chunk in audioChunks) {
          await audioRepo.create(chunk);
        }

        // Get cached audio statistics
        final stats = await audioRepo.getAudioStats();
        expect(stats.totalChunks, equals(3));
        expect(stats.cachedChunks, equals(2));
        expect(stats.totalSize, equals(3584)); // 1024 + 512 + 2048

        final cacheSize = await audioRepo.getTotalCacheSize();
        expect(cacheSize, equals(1536)); // 1024 + 512 (only cached)

        // Test cache cleanup
        await audioRepo.clearCache(keepRecent: true);

        // Check that recent audio is kept
        final audio3 = await audioRepo.findById('audio_3');
        expect(audio3, isNotNull);

        // Check that old cached audio is cleared
        final audio1 = await audioRepo.findById('audio_1');
        expect(audio1!.metadata?['is_cached'], equals(false));
      });
    });

    group('Cross-Service Data Flow', () {
      test('should handle complete voice-to-audio pipeline', () async {
        // 1. Create session
        final session = await sessionRepo.createSession('user_1', 'token_123');
        
        // 2. Create voice input (user speaks)
        final voiceInput = VoiceInput(
          id: 'voice_1',
          sessionId: session.id,
          status: VoiceInputStatus.recording,
          timestamp: DateTime.now(),
        );
        await voiceRepo.create(voiceInput);

        // 3. Update voice status through processing pipeline
        await voiceRepo.updateStatus('voice_1', VoiceInputStatus.processing);
        await voiceRepo.updateTranscription('voice_1', 'What is the weather?', 0.92);
        await voiceRepo.updateResponse('voice_1', 'The weather is sunny today.');

        // 4. Create TTS job
        final ttsJob = Job(
          id: 'tts_job_1',
          text: 'TTS: The weather is sunny today.',
          status: JobStatus.todo,
          createdAt: DateTime.now(),
          metadata: {
            'voice_input_id': 'voice_1',
            'session_id': session.id,
            'type': 'tts',
          },
        );
        await jobRepo.create(ttsJob);

        // 5. Process TTS job
        await jobRepo.updateStatus('tts_job_1', JobStatus.running);
        
        // 6. Create audio output
        final audioOutput = AudioChunk(
          id: 'audio_1',
          sessionId: session.id,
          jobId: 'tts_job_1',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/temp/weather_response.mp3',
          timestamp: DateTime.now(),
          duration: Duration(seconds: 3),
          metadata: {
            'voice_input_id': 'voice_1',
            'text': 'The weather is sunny today.',
            'size_bytes': 1024,
            'is_cached': true,
          },
        );
        await audioRepo.create(audioOutput);

        // 7. Complete TTS job
        await jobRepo.updateResult('tts_job_1', 'TTS audio generated successfully');

        // 8. Update session activity
        await sessionRepo.updateActivity(session.id);

        // Verify complete pipeline
        final finalVoice = await voiceRepo.findById('voice_1');
        expect(finalVoice!.status, equals(VoiceInputStatus.completed));
        expect(finalVoice.transcription, equals('What is the weather?'));
        expect(finalVoice.response, equals('The weather is sunny today.'));

        final finalJob = await jobRepo.findById('tts_job_1');
        expect(finalJob!.status, equals(JobStatus.completed));
        expect(finalJob.result, equals('TTS audio generated successfully'));

        final finalAudio = await audioRepo.findById('audio_1');
        expect(finalAudio!.metadata?['voice_input_id'], equals('voice_1'));
        expect(finalAudio.type, equals(AudioChunkType.output));

        final finalSession = await sessionRepo.findById(session.id);
        expect(finalSession!.lastActivityAt, isNotNull);
      });

      test('should handle error propagation across services', () async {
        // Create session and voice input
        final session = await sessionRepo.createSession('user_1', 'token_123');
        final voiceInput = VoiceInput(
          id: 'voice_1',
          sessionId: session.id,
          status: VoiceInputStatus.processing,
          timestamp: DateTime.now(),
          transcription: 'Test error handling',
        );
        await voiceRepo.create(voiceInput);

        // Create TTS job
        final ttsJob = Job(
          id: 'tts_job_1',
          text: 'TTS: Test error handling',
          status: JobStatus.running,
          createdAt: DateTime.now(),
          metadata: {
            'voice_input_id': 'voice_1',
            'session_id': session.id,
            'type': 'tts',
          },
        );
        await jobRepo.create(ttsJob);

        // Simulate TTS error
        await jobRepo.updateError('tts_job_1', 'TTS service unavailable');

        // Update voice input to reflect error
        await voiceRepo.updateStatus('voice_1', VoiceInputStatus.failed);

        // Verify error handling
        final failedJob = await jobRepo.findById('tts_job_1');
        expect(failedJob!.status, equals(JobStatus.dead));
        expect(failedJob.error, equals('TTS service unavailable'));

        final failedVoice = await voiceRepo.findById('voice_1');
        expect(failedVoice!.status, equals(VoiceInputStatus.failed));

        // Check that no audio chunk was created
        final audioChunks = await audioRepo.findByJobId('tts_job_1');
        expect(audioChunks, isEmpty);
      });

      test('should handle concurrent operations across services', () async {
        final session = await sessionRepo.createSession('user_1', 'token_123');
        
        // Create multiple concurrent voice inputs
        final futures = <Future>[];
        
        for (int i = 1; i <= 5; i++) {
          futures.add(() async {
            final voiceInput = VoiceInput(
              id: 'voice_$i',
              sessionId: session.id,
              status: VoiceInputStatus.recording,
              timestamp: DateTime.now(),
            );
            await voiceRepo.create(voiceInput);
            
            final job = Job(
              id: 'job_$i',
              text: 'Concurrent job $i',
              status: JobStatus.todo,
              createdAt: DateTime.now(),
              metadata: {'voice_input_id': 'voice_$i'},
            );
            await jobRepo.create(job);
            
            await voiceRepo.updateStatus('voice_$i', VoiceInputStatus.completed);
            await jobRepo.updateStatus('job_$i', JobStatus.completed);
          }());
        }
        
        // Wait for all operations to complete
        await Future.wait(futures);
        
        // Verify all operations completed successfully
        final voices = await voiceRepo.findBySession(session.id);
        expect(voices, hasLength(5));
        expect(voices.every((v) => v.status == VoiceInputStatus.completed), isTrue);
        
        final jobs = await jobRepo.findBySession(session.id);
        expect(jobs, hasLength(5));
        expect(jobs.every((j) => j.status == JobStatus.completed), isTrue);
      });
    });

    group('Performance and Load Testing', () {
      test('should handle high-volume data operations', () async {
        final stopwatch = Stopwatch()..start();
        
        // Create session
        final session = await sessionRepo.createSession('user_1', 'token_123');
        
        // Create large number of voice inputs
        for (int i = 1; i <= 100; i++) {
          final voiceInput = VoiceInput(
            id: 'voice_$i',
            sessionId: session.id,
            status: VoiceInputStatus.completed,
            timestamp: DateTime.now().subtract(Duration(minutes: i)),
            transcription: 'Voice input $i',
            response: 'Response $i',
          );
          await voiceRepo.create(voiceInput);
        }
        
        stopwatch.stop();
        final creationTime = stopwatch.elapsed;
        
        // Performance assertions
        expect(creationTime.inSeconds, lessThan(10)); // Should complete in under 10 seconds
        
        // Test pagination performance
        stopwatch.reset();
        stopwatch.start();
        
        final page1 = await voiceRepo.findPaginated(page: 0, size: 20);
        final page2 = await voiceRepo.findPaginated(page: 1, size: 20);
        final page3 = await voiceRepo.findPaginated(page: 2, size: 20);
        
        stopwatch.stop();
        final queryTime = stopwatch.elapsed;
        
        expect(queryTime.inMilliseconds, lessThan(1000)); // Should complete in under 1 second
        expect(page1.items, hasLength(20));
        expect(page2.items, hasLength(20));
        expect(page3.items, hasLength(20));
        
        // Test search performance
        stopwatch.reset();
        stopwatch.start();
        
        final searchResults = await voiceRepo.search('Voice input', page: 0, size: 50);
        
        stopwatch.stop();
        final searchTime = stopwatch.elapsed;
        
        expect(searchTime.inMilliseconds, lessThan(500)); // Should complete in under 500ms
        expect(searchResults.totalCount, equals(100));
      });

      test('should handle cache performance under load', () async {
        final stopwatch = Stopwatch()..start();
        
        // Cache large number of items
        for (int i = 1; i <= 1000; i++) {
          await cache.put('item_$i', {
            'id': i,
            'data': 'test data $i',
            'timestamp': DateTime.now().toIso8601String(),
          });
        }
        
        stopwatch.stop();
        final cacheWriteTime = stopwatch.elapsed;
        
        expect(cacheWriteTime.inSeconds, lessThan(5)); // Should complete in under 5 seconds
        
        // Test cache read performance
        stopwatch.reset();
        stopwatch.start();
        
        for (int i = 1; i <= 100; i++) {
          final item = await cache.get('item_$i');
          expect(item, isNotNull);
        }
        
        stopwatch.stop();
        final cacheReadTime = stopwatch.elapsed;
        
        expect(cacheReadTime.inMilliseconds, lessThan(1000)); // Should complete in under 1 second
      });
    });
  });
}