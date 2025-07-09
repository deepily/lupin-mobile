import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../lib/services/network/websocket_service.dart';
import '../../lib/core/repositories/impl/session_repository_impl.dart';
import '../../lib/core/repositories/impl/job_repository_impl.dart';
import '../../lib/core/repositories/impl/voice_repository_impl.dart';
import '../../lib/core/repositories/impl/audio_repository_impl.dart';
import '../../lib/shared/models/models.dart';

void main() {
  group('WebSocket Integration Tests', () {
    late WebSocketService webSocketService;
    late SessionRepositoryImpl sessionRepo;
    late JobRepositoryImpl jobRepo;
    late VoiceRepositoryImpl voiceRepo;
    late AudioRepositoryImpl audioRepo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      
      webSocketService = WebSocketService();
      sessionRepo = SessionRepositoryImpl();
      jobRepo = JobRepositoryImpl();
      voiceRepo = VoiceRepositoryImpl();
      audioRepo = AudioRepositoryImpl();
    });

    tearDown(() async {
      await webSocketService.disconnect();
      sessionRepo.dispose();
      jobRepo.dispose();
      voiceRepo.dispose();
      audioRepo.dispose();
    });

    group('Real-time Voice Processing', () {
      test('should handle voice input lifecycle via WebSocket', () async {
        final voiceEvents = <Map<String, dynamic>>[];
        
        // Create session
        final session = await sessionRepo.createSession('user_1', 'token_123');
        
        // Create voice input
        final voiceInput = VoiceInput(
          id: 'voice_1',
          sessionId: session.id,
          status: VoiceInputStatus.recording,
          timestamp: DateTime.now(),
        );
        await voiceRepo.create(voiceInput);

        // Simulate WebSocket events for voice processing
        final mockWebSocketEvents = [
          {
            'type': 'voice_status_update',
            'voice_id': 'voice_1',
            'status': 'processing',
            'timestamp': DateTime.now().toIso8601String(),
          },
          {
            'type': 'voice_transcription_update',
            'voice_id': 'voice_1',
            'transcription': 'Hello, how are you?',
            'confidence': 0.94,
            'timestamp': DateTime.now().toIso8601String(),
          },
          {
            'type': 'voice_response_update',
            'voice_id': 'voice_1',
            'response': 'Hello! I am doing well, thank you for asking.',
            'timestamp': DateTime.now().toIso8601String(),
          },
        ];

        // Process mock WebSocket events
        for (final event in mockWebSocketEvents) {
          voiceEvents.add(event);
          
          switch (event['type']) {
            case 'voice_status_update':
              final status = _parseVoiceStatus(event['status']);
              await voiceRepo.updateStatus(event['voice_id'], status);
              break;
            case 'voice_transcription_update':
              await voiceRepo.updateTranscription(
                event['voice_id'],
                event['transcription'],
                event['confidence'],
              );
              break;
            case 'voice_response_update':
              await voiceRepo.updateResponse(
                event['voice_id'],
                event['response'],
              );
              break;
          }
        }

        // Verify voice input progression
        final finalVoice = await voiceRepo.findById('voice_1');
        expect(finalVoice!.status, equals(VoiceInputStatus.completed));
        expect(finalVoice.transcription, equals('Hello, how are you?'));
        expect(finalVoice.response, equals('Hello! I am doing well, thank you for asking.'));
        expect(voiceEvents, hasLength(3));
      });

      test('should handle voice input streaming updates', () async {
        final streamUpdates = <VoiceInput>[];
        
        // Create voice input
        final voiceInput = VoiceInput(
          id: 'voice_stream_1',
          sessionId: 'session_1',
          status: VoiceInputStatus.recording,
          timestamp: DateTime.now(),
        );
        await voiceRepo.create(voiceInput);

        // Subscribe to voice updates
        final subscription = voiceRepo.watchById('voice_stream_1').listen((voice) {
          if (voice != null) streamUpdates.add(voice);
        });

        // Simulate real-time WebSocket updates
        await Future.delayed(Duration(milliseconds: 10));
        await voiceRepo.updateStatus('voice_stream_1', VoiceInputStatus.processing);
        
        await Future.delayed(Duration(milliseconds: 10));
        await voiceRepo.updateTranscription('voice_stream_1', 'What is', 0.8);
        
        await Future.delayed(Duration(milliseconds: 10));
        await voiceRepo.updateTranscription('voice_stream_1', 'What is the weather', 0.9);
        
        await Future.delayed(Duration(milliseconds: 10));
        await voiceRepo.updateTranscription('voice_stream_1', 'What is the weather today?', 0.95);
        
        await Future.delayed(Duration(milliseconds: 10));
        await voiceRepo.updateResponse('voice_stream_1', 'The weather is sunny today!');

        // Wait for all updates to propagate
        await Future.delayed(Duration(milliseconds: 100));

        expect(streamUpdates.length, greaterThanOrEqualTo(5));
        expect(streamUpdates.last.transcription, equals('What is the weather today?'));
        expect(streamUpdates.last.response, equals('The weather is sunny today!'));
        expect(streamUpdates.last.status, equals(VoiceInputStatus.completed));

        await subscription.cancel();
      });
    });

    group('Job Queue Management', () {
      test('should handle job queue updates via WebSocket', () async {
        final jobUpdates = <Job>[];
        
        // Create multiple jobs
        final jobs = [
          Job(
            id: 'job_1',
            text: 'Process voice input',
            status: JobStatus.todo,
            createdAt: DateTime.now().subtract(Duration(minutes: 3)),
          ),
          Job(
            id: 'job_2',
            text: 'Generate TTS audio',
            status: JobStatus.todo,
            createdAt: DateTime.now().subtract(Duration(minutes: 2)),
          ),
          Job(
            id: 'job_3',
            text: 'Send notification',
            status: JobStatus.todo,
            createdAt: DateTime.now().subtract(Duration(minutes: 1)),
          ),
        ];

        for (final job in jobs) {
          await jobRepo.create(job);
        }

        // Watch all job updates
        final subscription = jobRepo.watchAll().listen((jobs) {
          jobUpdates.addAll(jobs);
        });

        // Simulate WebSocket job processing events
        await jobRepo.updateStatus('job_1', JobStatus.running);
        await Future.delayed(Duration(milliseconds: 50));
        
        await jobRepo.updateResult('job_1', 'Voice processing completed');
        await Future.delayed(Duration(milliseconds: 50));
        
        await jobRepo.updateStatus('job_2', JobStatus.running);
        await Future.delayed(Duration(milliseconds: 50));
        
        await jobRepo.updateResult('job_2', 'TTS audio generated');
        await Future.delayed(Duration(milliseconds: 50));

        // Verify job progression
        final job1 = await jobRepo.findById('job_1');
        final job2 = await jobRepo.findById('job_2');
        final job3 = await jobRepo.findById('job_3');

        expect(job1!.status, equals(JobStatus.completed));
        expect(job2!.status, equals(JobStatus.completed));
        expect(job3!.status, equals(JobStatus.todo)); // Still pending

        await subscription.cancel();
      });

      test('should handle job priority updates', () async {
        // Create jobs with different priorities
        final jobs = [
          Job(
            id: 'low_priority',
            text: 'Low priority task',
            status: JobStatus.todo,
            createdAt: DateTime.now(),
            metadata: {'priority': 'low'},
          ),
          Job(
            id: 'high_priority',
            text: 'High priority task',
            status: JobStatus.todo,
            createdAt: DateTime.now(),
            metadata: {'priority': 'high'},
          ),
          Job(
            id: 'urgent_priority',
            text: 'Urgent task',
            status: JobStatus.todo,
            createdAt: DateTime.now(),
            metadata: {'priority': 'urgent'},
          ),
        ];

        for (final job in jobs) {
          await jobRepo.create(job);
        }

        // Simulate WebSocket priority queue processing
        final urgentJobs = await jobRepo.findByPriority('urgent');
        final highJobs = await jobRepo.findByPriority('high');
        final lowJobs = await jobRepo.findByPriority('low');

        expect(urgentJobs, hasLength(1));
        expect(highJobs, hasLength(1));
        expect(lowJobs, hasLength(1));

        // Process urgent first
        await jobRepo.updateStatus('urgent_priority', JobStatus.running);
        await jobRepo.updateResult('urgent_priority', 'Urgent task completed');

        // Then high priority
        await jobRepo.updateStatus('high_priority', JobStatus.running);
        await jobRepo.updateResult('high_priority', 'High priority task completed');

        // Verify processing order
        final completedJobs = await jobRepo.findByStatus(JobStatus.completed);
        expect(completedJobs, hasLength(2));
        expect(completedJobs.map((j) => j.id), containsAll(['urgent_priority', 'high_priority']));

        final pendingJobs = await jobRepo.findByStatus(JobStatus.todo);
        expect(pendingJobs, hasLength(1));
        expect(pendingJobs.first.id, equals('low_priority'));
      });
    });

    group('Audio Streaming', () {
      test('should handle real-time audio chunk updates', () async {
        final audioUpdates = <AudioChunk>[];
        
        // Create audio chunk for streaming
        final audioChunk = AudioChunk(
          id: 'stream_audio_1',
          sessionId: 'session_1',
          jobId: 'tts_job_1',
          chunkIndex: 0,
          type: AudioChunkType.output,
          localPath: '/temp/streaming.mp3',
          timestamp: DateTime.now(),
        );
        await audioRepo.create(audioChunk);

        // Watch audio updates
        final subscription = audioRepo.watchById('stream_audio_1').listen((chunk) {
          if (chunk != null) audioUpdates.add(chunk);
        });

        // Simulate WebSocket audio streaming events
        await audioRepo.updatePlaybackState('stream_audio_1', true);
        await Future.delayed(Duration(milliseconds: 50));
        
        await audioRepo.updateCacheStatus('stream_audio_1', true, '/cached/streaming.mp3');
        await Future.delayed(Duration(milliseconds: 50));
        
        await audioRepo.updatePlaybackState('stream_audio_1', false);
        await Future.delayed(Duration(milliseconds: 50));

        expect(audioUpdates.length, greaterThanOrEqualTo(3));
        expect(audioUpdates.last.metadata?['is_playing'], equals(false));
        expect(audioUpdates.last.metadata?['is_cached'], equals(true));

        await subscription.cancel();
      });

      test('should handle multiple concurrent audio streams', () async {
        final streamStatuses = <String, bool>{};
        
        // Create multiple audio chunks
        final audioChunks = [
          AudioChunk(
            id: 'audio_stream_1',
            sessionId: 'session_1',
            jobId: 'job_1',
            chunkIndex: 0,
            type: AudioChunkType.output,
            localPath: '/temp/stream1.mp3',
            timestamp: DateTime.now(),
          ),
          AudioChunk(
            id: 'audio_stream_2',
            sessionId: 'session_1',
            jobId: 'job_2',
            chunkIndex: 0,
            type: AudioChunkType.output,
            localPath: '/temp/stream2.mp3',
            timestamp: DateTime.now(),
          ),
          AudioChunk(
            id: 'audio_stream_3',
            sessionId: 'session_2',
            jobId: 'job_3',
            chunkIndex: 0,
            type: AudioChunkType.output,
            localPath: '/temp/stream3.mp3',
            timestamp: DateTime.now(),
          ),
        ];

        for (final chunk in audioChunks) {
          await audioRepo.create(chunk);
        }

        // Start multiple streams concurrently
        final futures = audioChunks.map((chunk) async {
          await audioRepo.updatePlaybackState(chunk.id, true);
          streamStatuses[chunk.id] = true;
          
          // Simulate streaming duration
          await Future.delayed(Duration(milliseconds: 100));
          
          await audioRepo.updatePlaybackState(chunk.id, false);
          streamStatuses[chunk.id] = false;
        });

        await Future.wait(futures);

        // Verify all streams completed
        expect(streamStatuses.length, equals(3));
        expect(streamStatuses.values.every((playing) => !playing), isTrue);

        // Check final states
        for (final chunk in audioChunks) {
          final updatedChunk = await audioRepo.findById(chunk.id);
          expect(updatedChunk!.metadata?['is_playing'], equals(false));
        }
      });
    });

    group('Session Management', () {
      test('should handle session state updates via WebSocket', () async {
        final sessionUpdates = <Session>[];
        
        // Create session
        final session = await sessionRepo.createSession(
          'user_1',
          'token_123',
          expiresIn: Duration(hours: 24),
        );

        // Watch session updates
        final subscription = sessionRepo.watchById(session.id).listen((session) {
          if (session != null) sessionUpdates.add(session);
        });

        // Simulate WebSocket session activity updates
        await sessionRepo.updateActivity(session.id);
        await Future.delayed(Duration(milliseconds: 50));
        
        await sessionRepo.extendSession(session.id, Duration(hours: 2));
        await Future.delayed(Duration(milliseconds: 50));
        
        await sessionRepo.updateActivity(session.id);
        await Future.delayed(Duration(milliseconds: 50));

        expect(sessionUpdates.length, greaterThanOrEqualTo(3));
        expect(sessionUpdates.last.lastActivityAt, isNotNull);

        await subscription.cancel();
      });

      test('should handle multi-user session management', () async {
        // Create sessions for multiple users
        final user1Session1 = await sessionRepo.createSession('user_1', 'token_1');
        final user1Session2 = await sessionRepo.createSession('user_1', 'token_2');
        final user2Session1 = await sessionRepo.createSession('user_2', 'token_3');

        // Simulate WebSocket user activity
        await sessionRepo.updateActivity(user1Session1.id);
        await sessionRepo.updateActivity(user2Session1.id);

        // Terminate all sessions for user_1
        await sessionRepo.terminateAllUserSessions('user_1');

        // Verify session states
        final user1Sessions = await sessionRepo.findByUser('user_1');
        final user2Sessions = await sessionRepo.findByUser('user_2');

        expect(user1Sessions.every((s) => s.status == SessionStatus.terminated), isTrue);
        expect(user2Sessions.every((s) => s.status == SessionStatus.active), isTrue);
      });
    });

    group('Error Handling and Recovery', () {
      test('should handle WebSocket connection failures', () async {
        // Create data that would be affected by connection loss
        final voiceInput = VoiceInput(
          id: 'voice_error_1',
          sessionId: 'session_1',
          status: VoiceInputStatus.processing,
          timestamp: DateTime.now(),
        );
        await voiceRepo.create(voiceInput);

        final job = Job(
          id: 'job_error_1',
          text: 'Process voice input',
          status: JobStatus.running,
          createdAt: DateTime.now(),
        );
        await jobRepo.create(job);

        // Simulate connection failure and recovery
        // Note: In real implementation, this would involve actual WebSocket reconnection logic
        
        // Mark operations as failed due to connection loss
        await voiceRepo.updateStatus('voice_error_1', VoiceInputStatus.failed);
        await jobRepo.updateError('job_error_1', 'WebSocket connection lost');

        // Verify error states
        final failedVoice = await voiceRepo.findById('voice_error_1');
        final failedJob = await jobRepo.findById('job_error_1');

        expect(failedVoice!.status, equals(VoiceInputStatus.failed));
        expect(failedJob!.status, equals(JobStatus.dead));
        expect(failedJob.error, equals('WebSocket connection lost'));

        // Simulate recovery by requeuing
        await jobRepo.requeueJob('job_error_1');
        await voiceRepo.updateStatus('voice_error_1', VoiceInputStatus.recording);

        final recoveredJob = await jobRepo.findById('job_error_1');
        final recoveredVoice = await voiceRepo.findById('voice_error_1');

        expect(recoveredJob!.status, equals(JobStatus.todo));
        expect(recoveredVoice!.status, equals(VoiceInputStatus.recording));
      });

      test('should handle partial data synchronization', () async {
        // Create related data that might get out of sync
        final session = await sessionRepo.createSession('user_1', 'token_123');
        
        final voiceInput = VoiceInput(
          id: 'voice_sync_1',
          sessionId: session.id,
          status: VoiceInputStatus.transcribed,
          timestamp: DateTime.now(),
          transcription: 'Hello world',
        );
        await voiceRepo.create(voiceInput);

        final job = Job(
          id: 'job_sync_1',
          text: 'TTS: Hello world response',
          status: JobStatus.running,
          createdAt: DateTime.now(),
          metadata: {'voice_input_id': 'voice_sync_1'},
        );
        await jobRepo.create(job);

        // Simulate partial update (job completes but voice doesn't get response)
        await jobRepo.updateResult('job_sync_1', 'TTS audio generated');

        // Check for data inconsistency
        final completedJob = await jobRepo.findById('job_sync_1');
        final incompleteVoice = await voiceRepo.findById('voice_sync_1');

        expect(completedJob!.status, equals(JobStatus.completed));
        expect(incompleteVoice!.response, isNull); // Missing response

        // Simulate synchronization fix
        await voiceRepo.updateResponse('voice_sync_1', 'Hello! How can I help you?');

        final synchronizedVoice = await voiceRepo.findById('voice_sync_1');
        expect(synchronizedVoice!.status, equals(VoiceInputStatus.completed));
        expect(synchronizedVoice.response, equals('Hello! How can I help you?'));
      });
    });
  });
}

VoiceInputStatus _parseVoiceStatus(String status) {
  switch (status) {
    case 'recording':
      return VoiceInputStatus.recording;
    case 'processing':
      return VoiceInputStatus.processing;
    case 'transcribed':
      return VoiceInputStatus.transcribed;
    case 'completed':
      return VoiceInputStatus.completed;
    case 'failed':
      return VoiceInputStatus.failed;
    default:
      return VoiceInputStatus.recording;
  }
}