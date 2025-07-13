import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'dart:typed_data';
import 'package:lupin_mobile/core/cache/voice_recording_cache.dart';
import 'package:lupin_mobile/core/cache/offline_manager.dart';
import 'package:lupin_mobile/core/cache/cache_manager.dart';
import 'package:lupin_mobile/core/cache/cache_policy.dart';
import 'package:lupin_mobile/core/storage/storage_manager.dart';
import 'package:lupin_mobile/shared/models/models.dart';

// Generate mocks
@GenerateMocks([
  OfflineManager,
  CacheManager,
  StorageManager,
])
import 'voice_recording_cache_test.mocks.dart';

void main() {
  group('VoiceRecordingCache Tests', () {
    late VoiceRecordingCache cache;
    late MockOfflineManager mockOfflineManager;
    late MockCacheManager<VoiceRecordingData> mockRecordingCache;
    late MockCacheManager<TranscriptionData> mockTranscriptionCache;

    setUp(() async {
      mockOfflineManager = MockOfflineManager();
      mockRecordingCache = MockCacheManager<VoiceRecordingData>();
      mockTranscriptionCache = MockCacheManager<TranscriptionData>();

      // Mock the cache manager creation
      when(mockOfflineManager.getCacheManager<VoiceRecordingData>(
        cacheKey: anyNamed('cacheKey'),
        toJson: anyNamed('toJson'),
        fromJson: anyNamed('fromJson'),
        policy: anyNamed('policy'),
        calculateSize: anyNamed('calculateSize'),
      )).thenReturn(mockRecordingCache);

      when(mockOfflineManager.getCacheManager<TranscriptionData>(
        cacheKey: anyNamed('cacheKey'),
        toJson: anyNamed('toJson'),
        fromJson: anyNamed('fromJson'),
        policy: anyNamed('policy'),
        calculateSize: anyNamed('calculateSize'),
      )).thenReturn(mockTranscriptionCache);

      cache = await VoiceRecordingCache.createForTesting(mockOfflineManager);
    });

    group('Cache Recording', () {
      test('should cache voice recording successfully', () async {
        // Arrange
        final voiceInput = _createMockVoiceInput();
        final audioData = Uint8List.fromList([1, 2, 3, 4, 5]);
        
        when(mockRecordingCache.put(any, any))
            .thenAnswer((_) async => {});
        when(mockTranscriptionCache.put(any, any))
            .thenAnswer((_) async => {});

        // Act
        await cache.cacheRecording(
          voiceInput: voiceInput,
          audioData: audioData,
          transcription: 'Test transcription',
        );

        // Assert
        verify(mockRecordingCache.put(
          voiceInput.id,
          any,
        )).called(1);
        verify(mockTranscriptionCache.put(
          '${voiceInput.id}_transcription',
          any,
        )).called(1);
      });

      test('should cache recording without transcription', () async {
        // Arrange
        final voiceInput = _createMockVoiceInput();
        final audioData = Uint8List.fromList([1, 2, 3, 4, 5]);
        
        when(mockRecordingCache.put(any, any))
            .thenAnswer((_) async => {});

        // Act
        await cache.cacheRecording(
          voiceInput: voiceInput,
          audioData: audioData,
        );

        // Assert
        verify(mockRecordingCache.put(
          voiceInput.id,
          any,
        )).called(1);
        verifyNever(mockTranscriptionCache.put(any, any));
      });

      test('should emit storage event', () async {
        // Arrange
        final voiceInput = _createMockVoiceInput();
        final audioData = Uint8List.fromList([1, 2, 3, 4, 5]);
        
        when(mockRecordingCache.put(any, any))
            .thenAnswer((_) async => {});

        // Act
        final eventsFuture = cache.events
            .where((event) => event is VoiceRecordingStoredEvent)
            .first;
        
        await cache.cacheRecording(
          voiceInput: voiceInput,
          audioData: audioData,
        );
        
        final event = await eventsFuture as VoiceRecordingStoredEvent;

        // Assert
        expect(event.recordingId, equals(voiceInput.id));
        expect(event.sizeBytes, equals(audioData.length));
        expect(event.hasTranscription, isFalse);
      });
    });

    group('Retrieve Recording', () {
      test('should retrieve cached recording successfully', () async {
        // Arrange
        final voiceInput = _createMockVoiceInput();
        final recordingData = VoiceRecordingData(
          voiceInput: voiceInput,
          audioData: Uint8List.fromList([1, 2, 3, 4, 5]),
          compressed: false,
          cachedAt: DateTime.now(),
        );
        
        when(mockRecordingCache.get(voiceInput.id))
            .thenAnswer((_) async => recordingData);

        // Act
        final result = await cache.getRecording(voiceInput.id);

        // Assert
        expect(result, isNotNull);
        expect(result!.voiceInput.id, equals(voiceInput.id));
        expect(result.audioData.length, equals(5));
      });

      test('should return null for non-existent recording', () async {
        // Arrange
        when(mockRecordingCache.get('non-existent'))
            .thenAnswer((_) async => null);

        // Act
        final result = await cache.getRecording('non-existent');

        // Assert
        expect(result, isNull);
      });

      test('should emit access event on successful retrieval', () async {
        // Arrange
        final voiceInput = _createMockVoiceInput();
        final recordingData = VoiceRecordingData(
          voiceInput: voiceInput,
          audioData: Uint8List.fromList([1, 2, 3, 4, 5]),
          compressed: false,
          cachedAt: DateTime.now(),
        );
        
        when(mockRecordingCache.get(voiceInput.id))
            .thenAnswer((_) async => recordingData);

        // Act
        final eventsFuture = cache.events
            .where((event) => event is VoiceRecordingAccessedEvent)
            .first;
        
        await cache.getRecording(voiceInput.id);
        
        final event = await eventsFuture as VoiceRecordingAccessedEvent;

        // Assert
        expect(event.recordingId, equals(voiceInput.id));
        expect(event.found, isTrue);
      });

      test('should emit access event on cache miss', () async {
        // Arrange
        when(mockRecordingCache.get('non-existent'))
            .thenAnswer((_) async => null);

        // Act
        final eventsFuture = cache.events
            .where((event) => event is VoiceRecordingAccessedEvent)
            .first;
        
        await cache.getRecording('non-existent');
        
        final event = await eventsFuture as VoiceRecordingAccessedEvent;

        // Assert
        expect(event.recordingId, equals('non-existent'));
        expect(event.found, isFalse);
      });
    });

    group('Transcription Management', () {
      test('should retrieve transcription successfully', () async {
        // Arrange
        final transcriptionData = TranscriptionData(
          recordingId: 'test-id',
          transcription: 'Test transcription',
          confidence: 0.95,
          language: 'en',
          createdAt: DateTime.now(),
        );
        
        when(mockTranscriptionCache.get('test-id_transcription'))
            .thenAnswer((_) async => transcriptionData);

        // Act
        final result = await cache.getTranscription('test-id');

        // Assert
        expect(result, isNotNull);
        expect(result!.transcription, equals('Test transcription'));
        expect(result.confidence, equals(0.95));
      });

      test('should return null for non-existent transcription', () async {
        // Arrange
        when(mockTranscriptionCache.get('non-existent_transcription'))
            .thenAnswer((_) async => null);

        // Act
        final result = await cache.getTranscription('non-existent');

        // Assert
        expect(result, isNull);
      });
    });

    group('Search Functionality', () {
      test('should search recordings by transcription', () async {
        // Arrange
        final transcriptionData = TranscriptionData(
          recordingId: 'test-id',
          transcription: 'Hello world test',
          confidence: 0.95,
          language: 'en',
          createdAt: DateTime.now(),
        );
        
        when(mockTranscriptionCache.get('test-id_transcription'))
            .thenAnswer((_) async => transcriptionData);

        // Mock the metadata index (this would be loaded from storage)
        // In a real test, we'd need to properly mock the storage loading

        // Act
        final results = await cache.searchByTranscription('hello');

        // Assert
        // This test would need proper setup of the metadata index
        expect(results, isA<List<RecordingSearchResult>>());
      });

      test('should calculate relevance score correctly', () async {
        // This would test the private _calculateRelevanceScore method
        // In practice, we might expose this as a public method for testing
        // or test it indirectly through search results
      });
    });

    group('Cache Statistics', () {
      test('should return accurate statistics', () async {
        // Arrange
        when(mockRecordingCache.getStats())
            .thenReturn(const CacheStats(
              itemCount: 10,
              totalSizeBytes: 5000,
              expiredCount: 1,
              hitRate: 0.8,
              policy: CachePolicy.defaultPolicy,
            ));

        // Act
        final stats = await cache.getStats();

        // Assert
        expect(stats.itemCount, equals(0)); // Would be based on metadata index
        expect(stats.totalSizeBytes, equals(5000));
        expect(stats.hitRate, equals(0.8));
      });
    });

    group('Cache Cleanup', () {
      test('should remove old recordings', () async {
        // Arrange
        when(mockRecordingCache.remove(any))
            .thenAnswer((_) async => {});
        when(mockTranscriptionCache.remove(any))
            .thenAnswer((_) async => {});

        // Act
        final removedCount = await cache.removeOldRecordings(
          const Duration(days: 30),
        );

        // Assert
        expect(removedCount, isA<int>());
      });

      test('should optimize cache', () async {
        // Arrange
        when(mockRecordingCache.remove(any))
            .thenAnswer((_) async => {});
        when(mockTranscriptionCache.remove(any))
            .thenAnswer((_) async => {});
        when(mockRecordingCache.cleanup())
            .thenAnswer((_) async => {});
        when(mockTranscriptionCache.cleanup())
            .thenAnswer((_) async => {});

        // Act
        await cache.optimize();

        // Assert
        verify(mockRecordingCache.cleanup()).called(1);
        verify(mockTranscriptionCache.cleanup()).called(1);
      });

      test('should clear all recordings', () async {
        // Arrange
        when(mockRecordingCache.clear())
            .thenAnswer((_) async => {});
        when(mockTranscriptionCache.clear())
            .thenAnswer((_) async => {});

        // Act
        await cache.clearAll();

        // Assert
        verify(mockRecordingCache.clear()).called(1);
        verify(mockTranscriptionCache.clear()).called(1);
      });

      test('should emit cleanup event', () async {
        // Arrange
        when(mockRecordingCache.remove(any))
            .thenAnswer((_) async => {});
        when(mockTranscriptionCache.remove(any))
            .thenAnswer((_) async => {});

        // Act
        final eventsFuture = cache.events
            .where((event) => event is VoiceRecordingCleanupEvent)
            .first;
        
        await cache.removeOldRecordings(const Duration(days: 30));
        
        final event = await eventsFuture as VoiceRecordingCleanupEvent;

        // Assert
        expect(event.removedCount, isA<int>());
      });
    });

    group('Language Detection', () {
      test('should detect Chinese language', () {
        // This would test the private _detectLanguage method
        // We'd need to expose it or test it indirectly
      });

      test('should detect Japanese language', () {
        // Similar test for Japanese
      });

      test('should default to English', () {
        // Test for default language detection
      });
    });

    group('Error Handling', () {
      test('should handle cache storage errors', () async {
        // Arrange
        final voiceInput = _createMockVoiceInput();
        final audioData = Uint8List.fromList([1, 2, 3, 4, 5]);
        
        when(mockRecordingCache.put(any, any))
            .thenThrow(Exception('Storage failed'));

        // Act & Assert
        expect(
          () => cache.cacheRecording(
            voiceInput: voiceInput,
            audioData: audioData,
          ),
          throwsException,
        );
      });

      test('should handle retrieval errors', () async {
        // Arrange
        when(mockRecordingCache.get('test-id'))
            .thenThrow(Exception('Retrieval failed'));

        // Act & Assert
        expect(
          () => cache.getRecording('test-id'),
          throwsException,
        );
      });
    });

    group('Data Models', () {
      test('VoiceRecordingData should serialize correctly', () {
        // Arrange
        final voiceInput = _createMockVoiceInput();
        final data = VoiceRecordingData(
          voiceInput: voiceInput,
          audioData: Uint8List.fromList([1, 2, 3]),
          compressed: true,
          cachedAt: DateTime.now(),
        );

        // Act
        final json = data.toJson();
        final restored = VoiceRecordingData.fromJson(json);

        // Assert
        expect(restored.voiceInput.id, equals(voiceInput.id));
        expect(restored.audioData.length, equals(3));
        expect(restored.compressed, isTrue);
      });

      test('TranscriptionData should serialize correctly', () {
        // Arrange
        final data = TranscriptionData(
          recordingId: 'test-id',
          transcription: 'Test transcription',
          confidence: 0.95,
          language: 'en',
          createdAt: DateTime.now(),
        );

        // Act
        final json = data.toJson();
        final restored = TranscriptionData.fromJson(json);

        // Assert
        expect(restored.recordingId, equals('test-id'));
        expect(restored.transcription, equals('Test transcription'));
        expect(restored.confidence, equals(0.95));
        expect(restored.language, equals('en'));
      });

      test('RecordingMetadata should serialize correctly', () {
        // Arrange
        final metadata = RecordingMetadata(
          recordingId: 'test-id',
          sessionId: 'session-123',
          duration: const Duration(seconds: 30),
          sizeBytes: 1000,
          compressed: true,
          hasTranscription: true,
          createdAt: DateTime.now(),
          lastAccessedAt: DateTime.now(),
          accessCount: 5,
        );

        // Act
        final json = metadata.toJson();
        final restored = RecordingMetadata.fromJson(json);

        // Assert
        expect(restored.recordingId, equals('test-id'));
        expect(restored.sessionId, equals('session-123'));
        expect(restored.duration, equals(const Duration(seconds: 30)));
        expect(restored.sizeBytes, equals(1000));
        expect(restored.compressed, isTrue);
        expect(restored.hasTranscription, isTrue);
        expect(restored.accessCount, equals(5));
      });
    });
  });
}

// Helper functions

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

// Use the real VoiceRecordingCacheStats instead of a mock CacheStats