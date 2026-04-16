import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../lib/core/repositories/impl/audio_repository_impl.dart';
import '../../lib/shared/models/models.dart';

void main() {
  group('AudioRepository Tests', () {
    late AudioRepositoryImpl repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repository = AudioRepositoryImpl();
    });

    tearDown(() {
      repository.dispose();
    });

    group('Basic CRUD Operations', () {
      test('should create and retrieve audio chunk', () async {
        final audioChunk = AudioChunk(
          id: 'audio_1',
          sessionId: 'session_1',
          jobId: 'job_1',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/path/to/audio.mp3',
          timestamp: DateTime.now(),
          duration: Duration(seconds: 3),
          metadata: {'size_bytes': 1024, 'sample_rate': 44100},
        );

        final createdChunk = await repository.create(audioChunk);
        expect(createdChunk.id, equals('audio_1'));
        expect(createdChunk.sessionId, equals('session_1'));
        expect(createdChunk.type, equals(AudioChunkType.output));

        final retrievedChunk = await repository.findById('audio_1');
        expect(retrievedChunk, isNotNull);
        expect(retrievedChunk!.localPath, equals('/path/to/audio.mp3'));
        expect(retrievedChunk.duration, equals(Duration(seconds: 3)));
        expect(retrievedChunk.metadata?['size_bytes'], equals(1024));
      });

      test('should update audio chunk', () async {
        final audioChunk = AudioChunk(
          id: 'audio_1',
          sessionId: 'session_1',
          jobId: 'job_1',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/path/to/audio.mp3',
          timestamp: DateTime.now(),
        );

        await repository.create(audioChunk);

        final updatedChunk = audioChunk.copyWith(
          localPath: '/new/path/to/audio.mp3',
          duration: Duration(seconds: 5),
          metadata: {'size_bytes': 2048, 'processed': true},
        );
        
        await repository.update(updatedChunk);

        final retrievedChunk = await repository.findById('audio_1');
        expect(retrievedChunk!.localPath, equals('/new/path/to/audio.mp3'));
        expect(retrievedChunk.duration, equals(Duration(seconds: 5)));
        expect(retrievedChunk.metadata?['processed'], equals(true));
      });

      test('should delete audio chunk', () async {
        final audioChunk = AudioChunk(
          id: 'audio_1',
          sessionId: 'session_1',
          jobId: 'job_1',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/path/to/audio.mp3',
          timestamp: DateTime.now(),
        );

        await repository.create(audioChunk);
        expect(await repository.exists('audio_1'), isTrue);

        await repository.deleteById('audio_1');
        expect(await repository.exists('audio_1'), isFalse);
      });
    });

    group('Audio Chunk Queries', () {
      late List<AudioChunk> testChunks;

      setUp(() async {
        final now = DateTime.now();
        testChunks = [
          AudioChunk(
            id: 'audio_1',
            sessionId: 'session_1',
            jobId: 'job_1',
            chunkIndex: 0,
            type: AudioChunkType.output,
            localPath: '/path/to/output1.mp3',
            timestamp: now.subtract(Duration(hours: 2)),
            duration: Duration(seconds: 3),
            metadata: {'size_bytes': 1024, 'is_cached': true},
          ),
          AudioChunk(
            id: 'audio_2',
            sessionId: 'session_1',
            jobId: 'job_1',
            chunkIndex: 1,
            type: AudioChunkType.output,
            localPath: '/path/to/output2.mp3',
            timestamp: now.subtract(Duration(hours: 1)),
            duration: Duration(seconds: 2),
            metadata: {'size_bytes': 512, 'is_cached': false},
          ),
          AudioChunk(
            id: 'audio_3',
            sessionId: 'session_2',
            jobId: 'job_2',
            chunkIndex: 0,
            type: AudioChunkType.input,
            localPath: '/path/to/input1.mp3',
            timestamp: now.subtract(Duration(minutes: 30)),
            duration: Duration(seconds: 4),
            metadata: {'size_bytes': 2048, 'is_cached': true},
          ),
          AudioChunk(
            id: 'audio_4',
            sessionId: 'session_1',
            jobId: 'job_3',
            chunkIndex: 0,
            type: AudioChunkType.output,
            localPath: '/path/to/output3.mp3',
            timestamp: now.subtract(Duration(minutes: 15)),
            duration: Duration(seconds: 1),
            metadata: {'size_bytes': 256, 'is_cached': true},
          ),
        ];

        for (final chunk in testChunks) {
          await repository.create(chunk);
        }
      });

      test('should find audio chunks by session', () async {
        final session1Chunks = await repository.findBySession('session_1');
        expect(session1Chunks, hasLength(3));
        expect(session1Chunks.map((c) => c.id), containsAll(['audio_1', 'audio_2', 'audio_4']));

        final session2Chunks = await repository.findBySession('session_2');
        expect(session2Chunks, hasLength(1));
        expect(session2Chunks.first.id, equals('audio_3'));
      });

      test('should find audio chunks by job ID', () async {
        final job1Chunks = await repository.findByJobId('job_1');
        expect(job1Chunks, hasLength(2));
        expect(job1Chunks.map((c) => c.id), containsAll(['audio_1', 'audio_2']));

        final job2Chunks = await repository.findByJobId('job_2');
        expect(job2Chunks, hasLength(1));
        expect(job2Chunks.first.id, equals('audio_3'));
      });

      test('should find audio chunks by type', () async {
        final outputChunks = await repository.findByType(AudioChunkType.output);
        expect(outputChunks, hasLength(3));
        expect(outputChunks.map((c) => c.id), containsAll(['audio_1', 'audio_2', 'audio_4']));

        final inputChunks = await repository.findByType(AudioChunkType.input);
        expect(inputChunks, hasLength(1));
        expect(inputChunks.first.id, equals('audio_3'));
      });

      test('should find audio chunks by time range', () async {
        final now = DateTime.now();
        final start = now.subtract(Duration(hours: 1, minutes: 30));
        final end = now.subtract(Duration(minutes: 10));

        final chunksInRange = await repository.findByTimeRange(start, end);
        expect(chunksInRange, hasLength(2));
        expect(chunksInRange.map((c) => c.id), containsAll(['audio_2', 'audio_3']));
      });

      test('should get recent audio chunks', () async {
        final recentChunks = await repository.getRecentAudio('session_1');
        expect(recentChunks, hasLength(3));
        // Should be sorted by timestamp (newest first)
        expect(recentChunks.first.id, equals('audio_4'));
        expect(recentChunks.last.id, equals('audio_1'));

        final limitedChunks = await repository.getRecentAudio('session_1', limit: 2);
        expect(limitedChunks, hasLength(2));
        expect(limitedChunks.first.id, equals('audio_4'));
        expect(limitedChunks.last.id, equals('audio_2'));
      });

      test('should get cached audio chunks', () async {
        final cachedChunks = await repository.getCachedAudio();
        expect(cachedChunks, hasLength(3));
        expect(cachedChunks.map((c) => c.id), containsAll(['audio_1', 'audio_3', 'audio_4']));
      });
    });

    group('Audio Chunk State Management', () {
      test('should update playback state', () async {
        final audioChunk = AudioChunk(
          id: 'audio_1',
          sessionId: 'session_1',
          jobId: 'job_1',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/path/to/audio.mp3',
          timestamp: DateTime.now(),
        );

        await repository.create(audioChunk);

        final updatedChunk = await repository.updatePlaybackState('audio_1', true);
        expect(updatedChunk.metadata?['is_playing'], equals(true));
        expect(updatedChunk.metadata?['last_played'], isNotNull);

        final stoppedChunk = await repository.updatePlaybackState('audio_1', false);
        expect(stoppedChunk.metadata?['is_playing'], equals(false));
      });

      test('should update cache status', () async {
        final audioChunk = AudioChunk(
          id: 'audio_1',
          sessionId: 'session_1',
          jobId: 'job_1',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/path/to/audio.mp3',
          timestamp: DateTime.now(),
        );

        await repository.create(audioChunk);

        await repository.updateCacheStatus('audio_1', true, '/cached/path/audio.mp3');
        
        final cachedChunk = await repository.findById('audio_1');
        expect(cachedChunk!.localPath, equals('/cached/path/audio.mp3'));
        expect(cachedChunk.metadata?['is_cached'], equals(true));
        expect(cachedChunk.metadata?['cached_at'], isNotNull);

        await repository.updateCacheStatus('audio_1', false, null);
        
        final uncachedChunk = await repository.findById('audio_1');
        expect(uncachedChunk!.localPath, isNull);
        expect(uncachedChunk.metadata?['is_cached'], equals(false));
      });
    });

    group('Audio Statistics', () {
      test('should get audio statistics', () async {
        final now = DateTime.now();
        final chunks = [
          AudioChunk(
            id: 'audio_1',
            sessionId: 'session_1',
            jobId: 'job_1',
            chunkIndex: 0,
            type: AudioChunkType.output,
            localPath: '/path/to/audio1.mp3',
            timestamp: now,
            duration: Duration(seconds: 3),
            metadata: {'size_bytes': 1024, 'is_cached': true},
          ),
          AudioChunk(
            id: 'audio_2',
            sessionId: 'session_1',
            jobId: 'job_1',
            chunkIndex: 1,
            type: AudioChunkType.output,
            localPath: '/path/to/audio2.mp3',
            timestamp: now,
            duration: Duration(seconds: 2),
            metadata: {'size_bytes': 512, 'is_cached': false},
          ),
          AudioChunk(
            id: 'audio_3',
            sessionId: 'session_2',
            jobId: 'job_2',
            chunkIndex: 0,
            type: AudioChunkType.input,
            localPath: '/path/to/input.mp3',
            timestamp: now,
            duration: Duration(seconds: 4),
            metadata: {'size_bytes': 2048, 'is_cached': true},
          ),
        ];

        for (final chunk in chunks) {
          await repository.create(chunk);
        }

        final stats = await repository.getAudioStats();
        expect(stats.totalChunks, equals(3));
        expect(stats.cachedChunks, equals(2));
        expect(stats.totalSize, equals(3584)); // 1024 + 512 + 2048
        expect(stats.totalDuration, equals(Duration(seconds: 9)));
        expect(stats.inputChunks, equals(1));
        expect(stats.outputChunks, equals(2));
        expect(stats.lastActivity, isNotNull);

        // Test session-specific stats
        final sessionStats = await repository.getAudioStats(sessionId: 'session_1');
        expect(sessionStats.totalChunks, equals(2));
        expect(sessionStats.cachedChunks, equals(1));
        expect(sessionStats.totalSize, equals(1536)); // 1024 + 512
      });

      test('should get total cache size', () async {
        final chunks = [
          AudioChunk(
            id: 'audio_1',
            sessionId: 'session_1',
            jobId: 'job_1',
            chunkIndex: 0,
            type: AudioChunkType.output,
            localPath: '/path/to/audio1.mp3',
            timestamp: DateTime.now(),
            metadata: {'size_bytes': 1024, 'is_cached': true},
          ),
          AudioChunk(
            id: 'audio_2',
            sessionId: 'session_1',
            jobId: 'job_1',
            chunkIndex: 1,
            type: AudioChunkType.output,
            localPath: '/path/to/audio2.mp3',
            timestamp: DateTime.now(),
            metadata: {'size_bytes': 512, 'is_cached': false},
          ),
          AudioChunk(
            id: 'audio_3',
            sessionId: 'session_1',
            jobId: 'job_2',
            chunkIndex: 0,
            type: AudioChunkType.input,
            localPath: '/path/to/input.mp3',
            timestamp: DateTime.now(),
            metadata: {'size_bytes': 2048, 'is_cached': true},
          ),
        ];

        for (final chunk in chunks) {
          await repository.create(chunk);
        }

        final totalCacheSize = await repository.getTotalCacheSize();
        expect(totalCacheSize, equals(3072)); // 1024 + 2048 (only cached chunks)
      });
    });

    group('Audio Cache Management', () {
      test('should clear cache keeping recent items', () async {
        final now = DateTime.now();
        final chunks = [
          AudioChunk(
            id: 'audio_1',
            sessionId: 'session_1',
            jobId: 'job_1',
            chunkIndex: 0,
            type: AudioChunkType.output,
            localPath: '/path/to/audio1.mp3',
            timestamp: now.subtract(Duration(hours: 2)),
            metadata: {'is_cached': true},
          ),
          AudioChunk(
            id: 'audio_2',
            sessionId: 'session_1',
            jobId: 'job_1',
            chunkIndex: 1,
            type: AudioChunkType.output,
            localPath: '/path/to/audio2.mp3',
            timestamp: now.subtract(Duration(minutes: 30)),
            metadata: {'is_cached': true},
          ),
        ];

        for (final chunk in chunks) {
          await repository.create(chunk);
        }

        await repository.clearCache(keepRecent: true);

        final chunk1 = await repository.findById('audio_1');
        final chunk2 = await repository.findById('audio_2');

        expect(chunk1!.metadata?['is_cached'], equals(false));
        expect(chunk2!.metadata?['is_cached'], equals(true)); // Recent, should be kept
      });

      test('should clear all cache', () async {
        final chunks = [
          AudioChunk(
            id: 'audio_1',
            sessionId: 'session_1',
            jobId: 'job_1',
            chunkIndex: 0,
            type: AudioChunkType.output,
            localPath: '/path/to/audio1.mp3',
            timestamp: DateTime.now(),
            metadata: {'is_cached': true},
          ),
          AudioChunk(
            id: 'audio_2',
            sessionId: 'session_1',
            jobId: 'job_1',
            chunkIndex: 1,
            type: AudioChunkType.output,
            localPath: '/path/to/audio2.mp3',
            timestamp: DateTime.now(),
            metadata: {'is_cached': true},
          ),
        ];

        for (final chunk in chunks) {
          await repository.create(chunk);
        }

        await repository.clearCache(keepRecent: false);

        final chunk1 = await repository.findById('audio_1');
        final chunk2 = await repository.findById('audio_2');

        expect(chunk1!.metadata?['is_cached'], equals(false));
        expect(chunk2!.metadata?['is_cached'], equals(false));
      });
    });

    group('Audio Cleanup', () {
      test('should cleanup old audio chunks', () async {
        final now = DateTime.now();
        
        // Create old audio chunks
        final oldChunk1 = AudioChunk(
          id: 'old_audio_1',
          sessionId: 'session_1',
          jobId: 'job_1',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/path/to/old1.mp3',
          timestamp: now.subtract(Duration(days: 10)),
        );
        
        final oldChunk2 = AudioChunk(
          id: 'old_audio_2',
          sessionId: 'session_1',
          jobId: 'job_1',
          chunkIndex: 1,
          type: AudioChunkType.output,
          localPath: '/path/to/old2.mp3',
          timestamp: now.subtract(Duration(days: 15)),
        );
        
        // Create recent audio chunk
        final recentChunk = AudioChunk(
          id: 'recent_audio',
          sessionId: 'session_1',
          jobId: 'job_2',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/path/to/recent.mp3',
          timestamp: now.subtract(Duration(hours: 1)),
        );
        
        await repository.create(oldChunk1);
        await repository.create(oldChunk2);
        await repository.create(recentChunk);
        
        expect(await repository.count(), equals(3));
        
        // Cleanup chunks older than 7 days
        await repository.cleanupOldAudio(olderThan: Duration(days: 7));
        
        expect(await repository.count(), equals(1));
        
        final remainingChunk = await repository.findById('recent_audio');
        expect(remainingChunk, isNotNull);
      });
    });

    group('Pagination', () {
      test('should find audio chunks with pagination', () async {
        // Create 12 audio chunks for pagination testing
        for (int i = 1; i <= 12; i++) {
          final chunk = AudioChunk(
            id: 'audio_$i',
            sessionId: 'session_1',
            jobId: 'job_1',
            chunkIndex: i - 1,
            type: AudioChunkType.output,
            localPath: '/path/to/audio$i.mp3',
            timestamp: DateTime.now().subtract(Duration(minutes: i)),
            metadata: {'size_bytes': i * 100},
          );
          await repository.create(chunk);
        }

        // Test first page
        final firstPage = await repository.findPaginated(page: 0, size: 5);
        expect(firstPage.items, hasLength(5));
        expect(firstPage.page, equals(0));
        expect(firstPage.size, equals(5));
        expect(firstPage.totalCount, equals(12));
        expect(firstPage.hasNext, isTrue);
        expect(firstPage.hasPrevious, isFalse);

        // Test second page
        final secondPage = await repository.findPaginated(page: 1, size: 5);
        expect(secondPage.items, hasLength(5));
        expect(secondPage.page, equals(1));
        expect(secondPage.hasNext, isTrue);
        expect(secondPage.hasPrevious, isTrue);

        // Test last page
        final lastPage = await repository.findPaginated(page: 2, size: 5);
        expect(lastPage.items, hasLength(2));
        expect(lastPage.hasNext, isFalse);
        expect(lastPage.hasPrevious, isTrue);
      });

      test('should search audio chunks with pagination', () async {
        // Create audio chunks with searchable content
        for (int i = 1; i <= 8; i++) {
          final chunk = AudioChunk(
            id: 'audio_$i',
            sessionId: i <= 4 ? 'session_1' : 'session_2',
            jobId: 'job_$i',
            chunkIndex: 0,
            type: AudioChunkType.output,
            localPath: '/path/to/audio$i.mp3',
            timestamp: DateTime.now().subtract(Duration(minutes: i)),
          );
          await repository.create(chunk);
        }

        final searchResults = await repository.search(
          'session_1',
          page: 0,
          size: 3,
        );

        expect(searchResults.items, hasLength(3));
        expect(searchResults.totalCount, equals(4));
        expect(searchResults.hasNext, isTrue);
      });
    });

    group('Real-time Updates', () {
      test('should stream audio chunk updates', () async {
        final streamEvents = <List<AudioChunk>>[];
        final subscription = repository.watchAll().listen((chunks) {
          streamEvents.add(chunks);
        });

        // Create an audio chunk
        final chunk = AudioChunk(
          id: 'audio_1',
          sessionId: 'session_1',
          jobId: 'job_1',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/path/to/audio.mp3',
          timestamp: DateTime.now(),
        );

        await repository.create(chunk);

        // Update the chunk
        await repository.updatePlaybackState('audio_1', true);

        // Delete the chunk
        await repository.deleteById('audio_1');

        // Wait for stream updates
        await Future.delayed(Duration(milliseconds: 100));

        expect(streamEvents, hasLength(3));
        expect(streamEvents[0], hasLength(1));
        expect(streamEvents[1], hasLength(1));
        expect(streamEvents[2], hasLength(0));

        await subscription.cancel();
      });

      test('should watch specific audio chunk by ID', () async {
        final chunkUpdates = <AudioChunk?>[];
        
        // Create initial chunk
        final chunk = AudioChunk(
          id: 'audio_1',
          sessionId: 'session_1',
          jobId: 'job_1',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/path/to/audio.mp3',
          timestamp: DateTime.now(),
        );
        await repository.create(chunk);

        final subscription = repository.watchById('audio_1').listen((chunk) {
          chunkUpdates.add(chunk);
        });

        // Update chunk
        await repository.updatePlaybackState('audio_1', true);

        // Delete chunk
        await repository.deleteById('audio_1');

        // Wait for stream updates
        await Future.delayed(Duration(milliseconds: 100));

        expect(chunkUpdates, hasLength(3));
        expect(chunkUpdates[0]?.id, equals('audio_1'));
        expect(chunkUpdates[1]?.metadata?['is_playing'], equals(true));
        expect(chunkUpdates[2], isNull);

        await subscription.cancel();
      });
    });

    group('Error Handling', () {
      test('should handle operations on non-existent audio chunks', () async {
        expect(
          () => repository.updatePlaybackState('nonexistent', true),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('AudioChunk with id nonexistent not found'),
          )),
        );

        expect(
          () => repository.updateCacheStatus('nonexistent', true, '/path'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('AudioChunk with id nonexistent not found'),
          )),
        );
      });
    });
  });
}