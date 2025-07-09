import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../lib/core/repositories/impl/voice_repository_impl.dart';
import '../../lib/shared/models/models.dart';

void main() {
  group('VoiceRepository Tests', () {
    late VoiceRepositoryImpl repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repository = VoiceRepositoryImpl();
    });

    tearDown(() {
      repository.dispose();
    });

    group('Basic CRUD Operations', () {
      test('should create and retrieve voice input', () async {
        final voiceInput = VoiceInput(
          id: 'voice_1',
          sessionId: 'session_1',
          status: VoiceInputStatus.recording,
          timestamp: DateTime.now(),
          duration: Duration(seconds: 5),
          transcription: 'Hello world',
          confidence: 0.95,
        );

        final createdVoice = await repository.create(voiceInput);
        expect(createdVoice.id, equals('voice_1'));
        expect(createdVoice.sessionId, equals('session_1'));
        expect(createdVoice.transcription, equals('Hello world'));

        final retrievedVoice = await repository.findById('voice_1');
        expect(retrievedVoice, isNotNull);
        expect(retrievedVoice!.transcription, equals('Hello world'));
        expect(retrievedVoice.confidence, equals(0.95));
      });

      test('should update voice input', () async {
        final voiceInput = VoiceInput(
          id: 'voice_1',
          sessionId: 'session_1',
          status: VoiceInputStatus.recording,
          timestamp: DateTime.now(),
        );

        await repository.create(voiceInput);

        final updatedVoice = voiceInput.copyWith(
          status: VoiceInputStatus.completed,
          transcription: 'Updated transcription',
          confidence: 0.88,
        );
        
        await repository.update(updatedVoice);

        final retrievedVoice = await repository.findById('voice_1');
        expect(retrievedVoice!.status, equals(VoiceInputStatus.completed));
        expect(retrievedVoice.transcription, equals('Updated transcription'));
        expect(retrievedVoice.confidence, equals(0.88));
      });

      test('should delete voice input', () async {
        final voiceInput = VoiceInput(
          id: 'voice_1',
          sessionId: 'session_1',
          status: VoiceInputStatus.recording,
          timestamp: DateTime.now(),
        );

        await repository.create(voiceInput);
        expect(await repository.exists('voice_1'), isTrue);

        await repository.deleteById('voice_1');
        expect(await repository.exists('voice_1'), isFalse);
      });
    });

    group('Voice Input Status Management', () {
      test('should update voice input status', () async {
        final voiceInput = VoiceInput(
          id: 'voice_1',
          sessionId: 'session_1',
          status: VoiceInputStatus.recording,
          timestamp: DateTime.now(),
        );

        await repository.create(voiceInput);

        final updatedVoice = await repository.updateStatus('voice_1', VoiceInputStatus.processing);
        expect(updatedVoice.status, equals(VoiceInputStatus.processing));

        final retrievedVoice = await repository.findById('voice_1');
        expect(retrievedVoice!.status, equals(VoiceInputStatus.processing));
      });

      test('should update transcription', () async {
        final voiceInput = VoiceInput(
          id: 'voice_1',
          sessionId: 'session_1',
          status: VoiceInputStatus.processing,
          timestamp: DateTime.now(),
        );

        await repository.create(voiceInput);

        final updatedVoice = await repository.updateTranscription(
          'voice_1',
          'This is a test transcription',
          0.92,
        );
        
        expect(updatedVoice.transcription, equals('This is a test transcription'));
        expect(updatedVoice.status, equals(VoiceInputStatus.transcribed));
        expect(updatedVoice.metadata?['confidence'], equals(0.92));
      });

      test('should update response', () async {
        final voiceInput = VoiceInput(
          id: 'voice_1',
          sessionId: 'session_1',
          status: VoiceInputStatus.transcribed,
          timestamp: DateTime.now(),
          transcription: 'Hello',
        );

        await repository.create(voiceInput);

        final updatedVoice = await repository.updateResponse(
          'voice_1',
          'Hello there! How can I help you?',
        );
        
        expect(updatedVoice.response, equals('Hello there! How can I help you?'));
        expect(updatedVoice.status, equals(VoiceInputStatus.completed));
      });
    });

    group('Voice Input Queries', () {
      late List<VoiceInput> testVoices;

      setUp(() async {
        final now = DateTime.now();
        testVoices = [
          VoiceInput(
            id: 'voice_1',
            sessionId: 'session_1',
            status: VoiceInputStatus.completed,
            timestamp: now.subtract(Duration(hours: 2)),
            duration: Duration(seconds: 3),
            transcription: 'Hello world',
            confidence: 0.95,
            response: 'Hello! How can I help you?',
          ),
          VoiceInput(
            id: 'voice_2',
            sessionId: 'session_1',
            status: VoiceInputStatus.recording,
            timestamp: now.subtract(Duration(hours: 1)),
            duration: Duration(seconds: 2),
          ),
          VoiceInput(
            id: 'voice_3',
            sessionId: 'session_2',
            status: VoiceInputStatus.completed,
            timestamp: now.subtract(Duration(minutes: 30)),
            duration: Duration(seconds: 4),
            transcription: 'What is the weather like?',
            confidence: 0.88,
            response: 'The weather is sunny today.',
          ),
          VoiceInput(
            id: 'voice_4',
            sessionId: 'session_1',
            status: VoiceInputStatus.failed,
            timestamp: now.subtract(Duration(minutes: 15)),
            duration: Duration(seconds: 1),
          ),
        ];

        for (final voice in testVoices) {
          await repository.create(voice);
        }
      });

      test('should find voice inputs by session', () async {
        final session1Voices = await repository.findBySession('session_1');
        expect(session1Voices, hasLength(3));
        expect(session1Voices.map((v) => v.id), containsAll(['voice_1', 'voice_2', 'voice_4']));

        final session2Voices = await repository.findBySession('session_2');
        expect(session2Voices, hasLength(1));
        expect(session2Voices.first.id, equals('voice_3'));
      });

      test('should find voice inputs by status', () async {
        final completedVoices = await repository.findByStatus(VoiceInputStatus.completed);
        expect(completedVoices, hasLength(2));
        expect(completedVoices.map((v) => v.id), containsAll(['voice_1', 'voice_3']));

        final recordingVoices = await repository.findByStatus(VoiceInputStatus.recording);
        expect(recordingVoices, hasLength(1));
        expect(recordingVoices.first.id, equals('voice_2'));

        final failedVoices = await repository.findByStatus(VoiceInputStatus.failed);
        expect(failedVoices, hasLength(1));
        expect(failedVoices.first.id, equals('voice_4'));
      });

      test('should find voice inputs by time range', () async {
        final now = DateTime.now();
        final start = now.subtract(Duration(hours: 1, minutes: 30));
        final end = now.subtract(Duration(minutes: 10));

        final voicesInRange = await repository.findByTimeRange(start, end);
        expect(voicesInRange, hasLength(2));
        expect(voicesInRange.map((v) => v.id), containsAll(['voice_2', 'voice_3']));
      });

      test('should find voice inputs by transcription search', () async {
        final helloResults = await repository.findByTranscriptionSearch('Hello');
        expect(helloResults, hasLength(1));
        expect(helloResults.first.id, equals('voice_1'));

        final weatherResults = await repository.findByTranscriptionSearch('weather');
        expect(weatherResults, hasLength(1));
        expect(weatherResults.first.id, equals('voice_3'));

        final responseResults = await repository.findByTranscriptionSearch('sunny');
        expect(responseResults, hasLength(1));
        expect(responseResults.first.id, equals('voice_3'));
      });

      test('should get active voice inputs', () async {
        final activeVoices = await repository.getActiveVoiceInputs();
        expect(activeVoices, hasLength(1));
        expect(activeVoices.first.id, equals('voice_2'));
        expect(activeVoices.first.isProcessing, isTrue);
      });

      test('should get recent voice inputs', () async {
        final recentVoices = await repository.getRecentVoiceInputs('session_1');
        expect(recentVoices, hasLength(3));
        // Should be sorted by timestamp (newest first)
        expect(recentVoices.first.id, equals('voice_4'));
        expect(recentVoices.last.id, equals('voice_1'));

        final limitedVoices = await repository.getRecentVoiceInputs('session_1', limit: 2);
        expect(limitedVoices, hasLength(2));
        expect(limitedVoices.first.id, equals('voice_4'));
        expect(limitedVoices.last.id, equals('voice_2'));
      });

      test('should get incomplete voice inputs', () async {
        final incompleteVoices = await repository.findIncompleteInputs();
        expect(incompleteVoices, hasLength(1));
        expect(incompleteVoices.first.id, equals('voice_2'));
        expect(incompleteVoices.first.status, equals(VoiceInputStatus.recording));
      });
    });

    group('Voice Input Statistics', () {
      test('should get voice statistics', () async {
        final now = DateTime.now();
        final voices = [
          VoiceInput(
            id: 'voice_1',
            sessionId: 'session_1',
            status: VoiceInputStatus.completed,
            timestamp: now,
            duration: Duration(seconds: 3),
            transcription: 'Hello',
            confidence: 0.95,
          ),
          VoiceInput(
            id: 'voice_2',
            sessionId: 'session_1',
            status: VoiceInputStatus.completed,
            timestamp: now,
            duration: Duration(seconds: 2),
            transcription: 'World',
            confidence: 0.88,
          ),
          VoiceInput(
            id: 'voice_3',
            sessionId: 'session_2',
            status: VoiceInputStatus.failed,
            timestamp: now,
            duration: Duration(seconds: 1),
          ),
        ];

        for (final voice in voices) {
          await repository.create(voice);
        }

        final stats = await repository.getVoiceStats();
        expect(stats.totalInputs, equals(3));
        expect(stats.completedInputs, equals(2));
        expect(stats.failedInputs, equals(1));
        expect(stats.averageConfidence, equals(0.85)); // Mock value
        expect(stats.averageProcessingTime, equals(Duration(seconds: 3))); // Mock value
        expect(stats.successRate, equals(2.0 / 3.0));

        // Test session-specific stats
        final sessionStats = await repository.getVoiceStats(sessionId: 'session_1');
        expect(sessionStats.totalInputs, equals(2));
        expect(sessionStats.completedInputs, equals(2));
        expect(sessionStats.failedInputs, equals(0));
      });

      test('should get average confidence', () async {
        final voices = [
          VoiceInput(
            id: 'voice_1',
            sessionId: 'session_1',
            status: VoiceInputStatus.completed,
            timestamp: DateTime.now(),
            metadata: {'confidence': 0.95},
          ),
          VoiceInput(
            id: 'voice_2',
            sessionId: 'session_1',
            status: VoiceInputStatus.completed,
            timestamp: DateTime.now(),
            metadata: {'confidence': 0.85},
          ),
          VoiceInput(
            id: 'voice_3',
            sessionId: 'session_2',
            status: VoiceInputStatus.completed,
            timestamp: DateTime.now(),
            metadata: {'confidence': 0.90},
          ),
        ];

        for (final voice in voices) {
          await repository.create(voice);
        }

        final overallConfidence = await repository.getAverageConfidence();
        expect(overallConfidence, equals(0.9));

        final sessionConfidence = await repository.getAverageConfidence(sessionId: 'session_1');
        expect(sessionConfidence, equals(0.9));
      });

      test('should get common transcriptions', () async {
        final voices = [
          VoiceInput(
            id: 'voice_1',
            sessionId: 'session_1',
            status: VoiceInputStatus.completed,
            timestamp: DateTime.now(),
            transcription: 'Hello world',
          ),
          VoiceInput(
            id: 'voice_2',
            sessionId: 'session_1',
            status: VoiceInputStatus.completed,
            timestamp: DateTime.now(),
            transcription: 'Hello world',
          ),
          VoiceInput(
            id: 'voice_3',
            sessionId: 'session_1',
            status: VoiceInputStatus.completed,
            timestamp: DateTime.now(),
            transcription: 'How are you?',
          ),
        ];

        for (final voice in voices) {
          await repository.create(voice);
        }

        final commonTranscriptions = await repository.getCommonTranscriptions(limit: 2);
        expect(commonTranscriptions, hasLength(2));
        expect(commonTranscriptions.first, equals('Hello world'));
        expect(commonTranscriptions.last, equals('How are you?'));
      });
    });

    group('Audio Data Management', () {
      test('should save and retrieve audio data', () async {
        final voiceInput = VoiceInput(
          id: 'voice_1',
          sessionId: 'session_1',
          status: VoiceInputStatus.recording,
          timestamp: DateTime.now(),
        );

        await repository.create(voiceInput);

        final audioData = [1, 2, 3, 4, 5];
        final updatedVoice = await repository.saveAudioData('voice_1', audioData);
        
        expect(updatedVoice.metadata?['audio_data'], equals(audioData));
        expect(updatedVoice.metadata?['audio_saved_at'], isNotNull);

        final retrievedAudioData = await repository.getAudioData('voice_1');
        expect(retrievedAudioData, equals(audioData));
      });

      test('should delete audio data', () async {
        final voiceInput = VoiceInput(
          id: 'voice_1',
          sessionId: 'session_1',
          status: VoiceInputStatus.recording,
          timestamp: DateTime.now(),
          metadata: {'audio_data': [1, 2, 3, 4, 5]},
        );

        await repository.create(voiceInput);

        await repository.deleteAudioData('voice_1');

        final updatedVoice = await repository.findById('voice_1');
        expect(updatedVoice!.metadata?['audio_data'], isNull);
        expect(updatedVoice.metadata?['audio_deleted_at'], isNotNull);

        final audioData = await repository.getAudioData('voice_1');
        expect(audioData, isNull);
      });
    });

    group('Voice Input Cleanup', () {
      test('should cleanup old voice inputs', () async {
        final now = DateTime.now();
        
        // Create old voice inputs
        final oldVoice1 = VoiceInput(
          id: 'old_voice_1',
          sessionId: 'session_1',
          status: VoiceInputStatus.completed,
          timestamp: now.subtract(Duration(days: 35)),
        );
        
        final oldVoice2 = VoiceInput(
          id: 'old_voice_2',
          sessionId: 'session_1',
          status: VoiceInputStatus.completed,
          timestamp: now.subtract(Duration(days: 40)),
        );
        
        // Create recent voice input
        final recentVoice = VoiceInput(
          id: 'recent_voice',
          sessionId: 'session_1',
          status: VoiceInputStatus.completed,
          timestamp: now.subtract(Duration(days: 1)),
        );
        
        await repository.create(oldVoice1);
        await repository.create(oldVoice2);
        await repository.create(recentVoice);
        
        expect(await repository.count(), equals(3));
        
        // Cleanup voices older than 30 days
        final cleanedCount = await repository.cleanupOldInputs(olderThan: Duration(days: 30));
        expect(cleanedCount, equals(2));
        expect(await repository.count(), equals(1));
        
        final remainingVoice = await repository.findById('recent_voice');
        expect(remainingVoice, isNotNull);
      });
    });

    group('Pagination', () {
      test('should find voice inputs with pagination', () async {
        // Create 15 voice inputs for pagination testing
        for (int i = 1; i <= 15; i++) {
          final voice = VoiceInput(
            id: 'voice_$i',
            sessionId: 'session_1',
            status: VoiceInputStatus.completed,
            timestamp: DateTime.now().subtract(Duration(minutes: i)),
            transcription: 'Voice input $i',
          );
          await repository.create(voice);
        }

        // Test first page
        final firstPage = await repository.findPaginated(page: 0, size: 5);
        expect(firstPage.items, hasLength(5));
        expect(firstPage.page, equals(0));
        expect(firstPage.size, equals(5));
        expect(firstPage.totalCount, equals(15));
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
        expect(lastPage.items, hasLength(5));
        expect(lastPage.hasNext, isFalse);
        expect(lastPage.hasPrevious, isTrue);
      });

      test('should search voice inputs with pagination', () async {
        // Create voice inputs with searchable text
        for (int i = 1; i <= 10; i++) {
          final voice = VoiceInput(
            id: 'voice_$i',
            sessionId: 'session_1',
            status: VoiceInputStatus.completed,
            timestamp: DateTime.now().subtract(Duration(minutes: i)),
            transcription: i <= 5 ? 'Important message $i' : 'Regular message $i',
          );
          await repository.create(voice);
        }

        final searchResults = await repository.search(
          'Important',
          page: 0,
          size: 3,
        );

        expect(searchResults.items, hasLength(3));
        expect(searchResults.totalCount, equals(5));
        expect(searchResults.hasNext, isTrue);
      });
    });

    group('Real-time Updates', () {
      test('should stream voice input updates', () async {
        final streamEvents = <List<VoiceInput>>[];
        final subscription = repository.watchAll().listen((voices) {
          streamEvents.add(voices);
        });

        // Create a voice input
        final voice = VoiceInput(
          id: 'voice_1',
          sessionId: 'session_1',
          status: VoiceInputStatus.recording,
          timestamp: DateTime.now(),
        );

        await repository.create(voice);

        // Update the voice input
        await repository.updateStatus('voice_1', VoiceInputStatus.completed);

        // Delete the voice input
        await repository.deleteById('voice_1');

        // Wait for stream updates
        await Future.delayed(Duration(milliseconds: 100));

        expect(streamEvents, hasLength(3));
        expect(streamEvents[0], hasLength(1));
        expect(streamEvents[1], hasLength(1));
        expect(streamEvents[2], hasLength(0));

        await subscription.cancel();
      });

      test('should watch specific voice input by ID', () async {
        final voiceUpdates = <VoiceInput?>[];
        
        // Create initial voice input
        final voice = VoiceInput(
          id: 'voice_1',
          sessionId: 'session_1',
          status: VoiceInputStatus.recording,
          timestamp: DateTime.now(),
        );
        await repository.create(voice);

        final subscription = repository.watchById('voice_1').listen((voice) {
          voiceUpdates.add(voice);
        });

        // Update voice input
        await repository.updateStatus('voice_1', VoiceInputStatus.completed);

        // Delete voice input
        await repository.deleteById('voice_1');

        // Wait for stream updates
        await Future.delayed(Duration(milliseconds: 100));

        expect(voiceUpdates, hasLength(3));
        expect(voiceUpdates[0]?.status, equals(VoiceInputStatus.recording));
        expect(voiceUpdates[1]?.status, equals(VoiceInputStatus.completed));
        expect(voiceUpdates[2], isNull);

        await subscription.cancel();
      });
    });

    group('Error Handling', () {
      test('should handle operations on non-existent voice inputs', () async {
        expect(
          () => repository.updateStatus('nonexistent', VoiceInputStatus.completed),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('VoiceInput with id nonexistent not found'),
          )),
        );

        expect(
          () => repository.updateTranscription('nonexistent', 'text', 0.9),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('VoiceInput with id nonexistent not found'),
          )),
        );

        expect(
          () => repository.updateResponse('nonexistent', 'response'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('VoiceInput with id nonexistent not found'),
          )),
        );
      });

      test('should handle missing audio data gracefully', () async {
        final audioData = await repository.getAudioData('nonexistent');
        expect(audioData, isNull);
      });
    });
  });
}