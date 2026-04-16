import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'dart:typed_data';
import '../../../lib/services/audio/audio_cache_manager.dart';
import '../../../lib/core/cache/audio_cache.dart';
import '../../../lib/core/cache/voice_recording_cache.dart';
import '../../../lib/core/cache/cache_analytics.dart';
import '../../../lib/core/cache/eviction_manager.dart';
import '../../../lib/core/cache/audio_compression.dart';
import '../../../lib/shared/models/models.dart';

// Generate mocks
@GenerateMocks([
  AudioCache,
  VoiceRecordingCache,
  CacheAnalytics,
  EvictionManager,
  AudioCompression,
])
import 'audio_cache_manager_test.mocks.dart';

void main() {
  group('AudioCacheManager Tests', () {
    late AudioCacheManager cacheManager;
    late MockAudioCache mockAudioCache;
    late MockVoiceRecordingCache mockVoiceRecordingCache;
    late MockCacheAnalytics mockAnalytics;
    late MockEvictionManager mockEvictionManager;
    late MockAudioCompression mockCompression;

    setUp(() {
      mockAudioCache = MockAudioCache();
      mockVoiceRecordingCache = MockVoiceRecordingCache();
      mockAnalytics = MockCacheAnalytics();
      mockEvictionManager = MockEvictionManager();
      mockCompression = MockAudioCompression();

      cacheManager = AudioCacheManager(
        audioCache: mockAudioCache,
        voiceRecordingCache: mockVoiceRecordingCache,
        analytics: mockAnalytics,
        evictionManager: mockEvictionManager,
        compression: mockCompression,
        maxCacheSizeMB: 100,
        enableCompression: true,
        enablePrefetch: true,
        commonPhrases: ['Hello', 'Thank you'],
      );
    });

    group('Initialization', () {
      test('should initialize successfully', () async {
        // Arrange
        when(mockVoiceRecordingCache.initialize())
            .thenAnswer((_) async => {});
        when(mockAnalytics.initialize())
            .thenAnswer((_) async => {});
        when(mockEvictionManager.initialize())
            .thenAnswer((_) async => {});

        // Act
        await cacheManager.initialize();

        // Assert
        verify(mockVoiceRecordingCache.initialize()).called(1);
        verify(mockAnalytics.initialize()).called(1);
        verify(mockEvictionManager.initialize()).called(1);
      });

      test('should emit initialization event', () async {
        // Arrange
        when(mockVoiceRecordingCache.initialize())
            .thenAnswer((_) async => {});
        when(mockAnalytics.initialize())
            .thenAnswer((_) async => {});
        when(mockEvictionManager.initialize())
            .thenAnswer((_) async => {});

        // Act
        final eventsFuture = cacheManager.eventStream.first;
        await cacheManager.initialize();
        final event = await eventsFuture;

        // Assert
        expect(event, isA<AudioCacheInitializedEvent>());
      });

      test('should handle initialization failure', () async {
        // Arrange
        when(mockVoiceRecordingCache.initialize())
            .thenThrow(Exception('Init failed'));

        // Act & Assert
        expect(
          () => cacheManager.initialize(),
          throwsException,
        );
      });
    });

    group('TTS Caching', () {
      test('should cache TTS response successfully', () async {
        // Arrange
        final chunks = [
          _createMockAudioChunk('chunk1', 'Hello'),
          _createMockAudioChunk('chunk2', 'Hello'),
        ];
        
        when(mockCompression.compress(any, format: anyNamed('format')))
            .thenAnswer((invocation) async {
          final data = invocation.positionalArguments[0] as Uint8List;
          return Uint8List.fromList(data.take(data.length ~/ 2).toList());
        });
        
        when(mockAudioCache.cacheAudioForText(any, any, any))
            .thenAnswer((_) async => {});

        // Act
        await cacheManager.cacheTTSResponse(
          text: 'Hello',
          provider: 'openai',
          chunks: chunks,
        );

        // Assert
        verify(mockAudioCache.cacheAudioForText('Hello', 'openai', any))
            .called(1);
        verify(mockAnalytics.recordCacheStore(
          type: 'tts',
          provider: 'openai',
          sizeBytes: any,
          metadata: any,
        )).called(1);
      });

      test('should compress audio chunks when enabled', () async {
        // Arrange
        final chunks = [_createMockAudioChunk('chunk1', 'Hello')];
        
        when(mockCompression.compress(any, format: anyNamed('format')))
            .thenAnswer((invocation) async {
          final data = invocation.positionalArguments[0] as Uint8List;
          return Uint8List.fromList(data.take(data.length ~/ 2).toList());
        });
        
        when(mockAudioCache.cacheAudioForText(any, any, any))
            .thenAnswer((_) async => {});

        // Act
        await cacheManager.cacheTTSResponse(
          text: 'Hello',
          provider: 'openai',
          chunks: chunks,
        );

        // Assert
        verify(mockCompression.compress(
          any,
          format: 'pcm',
        )).called(1);
      });

      test('should retrieve cached TTS response', () async {
        // Arrange
        final chunks = [_createMockAudioChunk('chunk1', 'Hello')];
        
        when(mockAudioCache.getCachedAudioForText('Hello', 'openai'))
            .thenAnswer((_) async => chunks);
        
        when(mockCompression.decompress(any, format: anyNamed('format')))
            .thenAnswer((invocation) async {
          return invocation.positionalArguments[0] as Uint8List;
        });

        // Act
        final result = await cacheManager.getCachedTTSResponse(
          text: 'Hello',
          provider: 'openai',
        );

        // Assert
        expect(result, isNotNull);
        expect(result!.length, equals(1));
        verify(mockAnalytics.recordCacheHit(
          type: 'tts',
          provider: 'openai',
        )).called(1);
      });

      test('should handle cache miss', () async {
        // Arrange
        when(mockAudioCache.getCachedAudioForText('Hello', 'openai'))
            .thenAnswer((_) async => null);

        // Act
        final result = await cacheManager.getCachedTTSResponse(
          text: 'Hello',
          provider: 'openai',
        );

        // Assert
        expect(result, isNull);
        verify(mockAnalytics.recordCacheMiss(
          type: 'tts',
          provider: 'openai',
        )).called(1);
      });
    });

    group('Voice Recording Caching', () {
      test('should cache voice recording successfully', () async {
        // Arrange
        final voiceInput = _createMockVoiceInput();
        final audioData = Uint8List.fromList([1, 2, 3, 4, 5]);
        
        when(mockCompression.compress(any, format: anyNamed('format')))
            .thenAnswer((invocation) async {
          final data = invocation.positionalArguments[0] as Uint8List;
          return Uint8List.fromList(data.take(data.length ~/ 2).toList());
        });
        
        when(mockVoiceRecordingCache.cacheRecording(
          voiceInput: anyNamed('voiceInput'),
          audioData: anyNamed('audioData'),
          transcription: anyNamed('transcription'),
          compressed: anyNamed('compressed'),
        )).thenAnswer((_) async => {});

        // Act
        await cacheManager.cacheVoiceRecording(
          voiceInput: voiceInput,
          audioData: audioData,
          transcription: 'Test transcription',
        );

        // Assert
        verify(mockVoiceRecordingCache.cacheRecording(
          voiceInput: voiceInput,
          audioData: any,
          transcription: 'Test transcription',
          compressed: true,
        )).called(1);
      });

      test('should retrieve cached voice recording', () async {
        // Arrange
        final recordingData = VoiceRecordingData(
          voiceInput: _createMockVoiceInput(),
          audioData: Uint8List.fromList([1, 2, 3, 4, 5]),
          compressed: true,
          cachedAt: DateTime.now(),
        );
        
        when(mockVoiceRecordingCache.getRecording('test-id'))
            .thenAnswer((_) async => recordingData);
        
        when(mockCompression.decompress(any, format: anyNamed('format')))
            .thenAnswer((invocation) async {
          return invocation.positionalArguments[0] as Uint8List;
        });

        // Act
        final result = await cacheManager.getCachedVoiceRecording('test-id');

        // Assert
        expect(result, isNotNull);
        expect(result!.compressed, isFalse);
        verify(mockAnalytics.recordCacheHit(
          type: 'voice_recording',
          provider: 'local',
        )).called(1);
      });
    });

    group('Cache Statistics', () {
      test('should return comprehensive statistics', () async {
        // Arrange
        final audioStats = AudioCacheStats(
          totalChunks: 10,
          totalMetadata: 5,
          totalSizeBytes: 1000,
          providerStats: {'openai': 3, 'elevenlabs': 2},
          chunkHitRate: 0.8,
          metadataHitRate: 0.9,
        );
        
        final voiceStats = VoiceRecordingCacheStats(
          itemCount: 8,
          totalSizeBytes: 2000,
          totalDuration: const Duration(minutes: 5),
          compressedCount: 5,
          transcribedCount: 7,
          averageDuration: const Duration(seconds: 30),
          hitRate: 0.7,
        );
        
        final analyticsData = CacheAnalyticsData(
          periodStart: DateTime.now().subtract(const Duration(days: 1)),
          periodDuration: const Duration(days: 1),
          totalHits: 100,
          totalMisses: 20,
          totalStores: 50,
          totalEvictions: 5,
          totalBytesStored: 5000,
          totalBytesRetrieved: 3000,
          totalCompressionSaved: 1000,
          overallHitRate: 0.83,
          compressionRatio: 0.8,
          providerMetrics: {},
          typeMetrics: {},
          operationLatencies: {},
          recentAccess: [],
        );
        
        when(mockAudioCache.getStats())
            .thenAnswer((_) async => audioStats);
        when(mockVoiceRecordingCache.getStats())
            .thenAnswer((_) async => voiceStats);
        when(mockAnalytics.getAnalytics())
            .thenAnswer((_) async => analyticsData);

        // Act
        final stats = await cacheManager.getStatistics();

        // Assert
        expect(stats.totalSizeMB, closeTo(2.86, 0.1)); // (1000 + 2000) / 1024 / 1024
        expect(stats.ttsItemCount, equals(5));
        expect(stats.voiceRecordingCount, equals(8));
        expect(stats.totalItemCount, equals(13));
        expect(stats.hitRate, equals(0.83));
        expect(stats.compressionRatio, equals(0.8));
      });
    });

    group('Cache Clearing', () {
      test('should clear provider cache', () async {
        // Arrange
        when(mockAudioCache.clearProviderCache('openai'))
            .thenAnswer((_) async => {});

        // Act
        await cacheManager.clearProviderCache('openai');

        // Assert
        verify(mockAudioCache.clearProviderCache('openai')).called(1);
      });

      test('should clear all caches', () async {
        // Arrange
        when(mockAudioCache.clearAll())
            .thenAnswer((_) async => {});
        when(mockVoiceRecordingCache.clearAll())
            .thenAnswer((_) async => {});

        // Act
        await cacheManager.clearAllCaches();

        // Assert
        verify(mockAudioCache.clearAll()).called(1);
        verify(mockVoiceRecordingCache.clearAll()).called(1);
      });
    });

    group('Cache Optimization', () {
      test('should optimize caches successfully', () async {
        // Arrange
        when(mockAudioCache.optimize())
            .thenAnswer((_) async => {});
        when(mockVoiceRecordingCache.optimize())
            .thenAnswer((_) async => {});
        when(mockEvictionManager.runEviction(
          currentSizeBytes: anyNamed('currentSizeBytes'),
          maxSizeBytes: anyNamed('maxSizeBytes'),
        )).thenAnswer((_) async => EvictionResult.success(
          itemsEvicted: 5,
          bytesFreed: 1000,
          strategy: CacheEvictionStrategy.lru,
        ));

        // Act
        await cacheManager.optimizeCaches();

        // Assert
        verify(mockAudioCache.optimize()).called(1);
        verify(mockVoiceRecordingCache.optimize()).called(1);
        verify(mockEvictionManager.runEviction(
          currentSizeBytes: any,
          maxSizeBytes: any,
        )).called(1);
      });

      test('should handle optimization failure', () async {
        // Arrange
        when(mockAudioCache.optimize())
            .thenThrow(Exception('Optimization failed'));

        // Act
        await cacheManager.optimizeCaches();

        // Assert
        // Should emit error event
        verify(mockAudioCache.optimize()).called(1);
      });
    });

    group('Event Handling', () {
      test('should emit TTS cached event', () async {
        // Arrange
        final chunks = [_createMockAudioChunk('chunk1', 'Hello')];
        
        when(mockCompression.compress(any, format: anyNamed('format')))
            .thenAnswer((invocation) async {
          final data = invocation.positionalArguments[0] as Uint8List;
          return Uint8List.fromList(data.take(data.length ~/ 2).toList());
        });
        
        when(mockAudioCache.cacheAudioForText(any, any, any))
            .thenAnswer((_) async => {});

        // Act
        final eventsFuture = cacheManager.eventStream
            .where((event) => event is TTSCachedEvent)
            .first;
        
        await cacheManager.cacheTTSResponse(
          text: 'Hello',
          provider: 'openai',
          chunks: chunks,
        );
        
        final event = await eventsFuture as TTSCachedEvent;

        // Assert
        expect(event.text, equals('Hello'));
        expect(event.provider, equals('openai'));
        expect(event.chunkCount, equals(1));
      });

      test('should emit voice recording cached event', () async {
        // Arrange
        final voiceInput = _createMockVoiceInput();
        final audioData = Uint8List.fromList([1, 2, 3, 4, 5]);
        
        when(mockCompression.compress(any, format: anyNamed('format')))
            .thenAnswer((invocation) async {
          final data = invocation.positionalArguments[0] as Uint8List;
          return Uint8List.fromList(data.take(data.length ~/ 2).toList());
        });
        
        when(mockVoiceRecordingCache.cacheRecording(
          voiceInput: anyNamed('voiceInput'),
          audioData: anyNamed('audioData'),
          transcription: anyNamed('transcription'),
          compressed: anyNamed('compressed'),
        )).thenAnswer((_) async => {});

        // Act
        final eventsFuture = cacheManager.eventStream
            .where((event) => event is VoiceRecordingCachedEvent)
            .first;
        
        await cacheManager.cacheVoiceRecording(
          voiceInput: voiceInput,
          audioData: audioData,
        );
        
        final event = await eventsFuture as VoiceRecordingCachedEvent;

        // Assert
        expect(event.recordingId, equals('test-id'));
        expect(event.duration, equals(const Duration(seconds: 5)));
      });
    });

    group('Error Handling', () {
      test('should handle TTS caching errors', () async {
        // Arrange
        final chunks = [_createMockAudioChunk('chunk1', 'Hello')];
        
        when(mockCompression.compress(any, format: anyNamed('format')))
            .thenThrow(Exception('Compression failed'));

        // Act & Assert
        expect(
          () => cacheManager.cacheTTSResponse(
            text: 'Hello',
            provider: 'openai',
            chunks: chunks,
          ),
          throwsException,
        );
      });

      test('should handle voice recording caching errors', () async {
        // Arrange
        final voiceInput = _createMockVoiceInput();
        final audioData = Uint8List.fromList([1, 2, 3, 4, 5]);
        
        when(mockVoiceRecordingCache.cacheRecording(
          voiceInput: anyNamed('voiceInput'),
          audioData: anyNamed('audioData'),
          transcription: anyNamed('transcription'),
          compressed: anyNamed('compressed'),
        )).thenThrow(Exception('Caching failed'));

        // Act & Assert
        expect(
          () => cacheManager.cacheVoiceRecording(
            voiceInput: voiceInput,
            audioData: audioData,
          ),
          throwsException,
        );
      });

      test('should handle retrieval errors gracefully', () async {
        // Arrange
        when(mockAudioCache.getCachedAudioForText('Hello', 'openai'))
            .thenThrow(Exception('Retrieval failed'));

        // Act
        final result = await cacheManager.getCachedTTSResponse(
          text: 'Hello',
          provider: 'openai',
        );

        // Assert
        expect(result, isNull);
      });
    });
  });
}

// Helper functions

AudioChunk _createMockAudioChunk(String id, String text) {
  return AudioChunk(
    id: id,
    type: AudioChunkType.tts,
    data: Uint8List.fromList([1, 2, 3, 4, 5]),
    text: text,
    timestamp: DateTime.now(),
    metadata: {'size_bytes': 5},
  );
}

VoiceInput _createMockVoiceInput() {
  return VoiceInput(
    id: 'test-id',
    sessionId: 'session-123',
    startedAt: DateTime.now().subtract(const Duration(seconds: 5)),
    completedAt: DateTime.now(),
    duration: const Duration(seconds: 5),
    transcription: 'Test transcription',
    confidence: 0.95,
    audioFormat: AudioFormat.wav,
    sampleRate: 44100,
  );
}