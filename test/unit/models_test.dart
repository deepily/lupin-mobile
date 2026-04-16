import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/shared/models/models.dart';

void main() {
  group('Models Tests', () {
    group('Job Model', () {
      test('should create Job instance correctly', () {
        final job = Job(
          id: 'test-job-1',
          text: 'Test job description',
          status: JobStatus.todo,
          createdAt: DateTime.now(),
        );

        expect(job.id, equals('test-job-1'));
        expect(job.text, equals('Test job description'));
        expect(job.status, equals(JobStatus.todo));
        expect(job.createdAt, isA<DateTime>());
      });

      test('should serialize to/from JSON correctly', () {
        final now = DateTime.now();
        final job = Job(
          id: 'test-job-1',
          text: 'Test job description',
          status: JobStatus.running,
          createdAt: now,
          updatedAt: now,
        );

        final json = job.toJson();
        final recreatedJob = Job.fromJson(json);

        expect(recreatedJob.id, equals(job.id));
        expect(recreatedJob.text, equals(job.text));
        expect(recreatedJob.status, equals(job.status));
        expect(recreatedJob.createdAt, equals(job.createdAt));
      });
    });

    group('User Model', () {
      test('should create User instance correctly', () {
        final user = User(
          id: 'user-1',
          email: 'test@example.com',
          displayName: 'Test User',
          role: UserRole.user,
          status: UserStatus.active,
          createdAt: DateTime.now(),
        );

        expect(user.id, equals('user-1'));
        expect(user.email, equals('test@example.com'));
        expect(user.displayName, equals('Test User'));
        expect(user.role, equals(UserRole.user));
        expect(user.status, equals(UserStatus.active));
      });
    });

    group('VoiceInput Model', () {
      test('should create VoiceInput instance correctly', () {
        final voiceInput = VoiceInput(
          id: 'voice-1',
          sessionId: 'session-1',
          status: VoiceInputStatus.recording,
          startedAt: DateTime.now(),
        );

        expect(voiceInput.id, equals('voice-1'));
        expect(voiceInput.sessionId, equals('session-1'));
        expect(voiceInput.status, equals(VoiceInputStatus.recording));
        expect(voiceInput.isProcessing, isTrue);
      });

      test('should detect processing status correctly', () {
        final recordingInput = VoiceInput(
          id: 'voice-1',
          sessionId: 'session-1',
          status: VoiceInputStatus.recording,
          startedAt: DateTime.now(),
        );

        final completedInput = VoiceInput(
          id: 'voice-2',
          sessionId: 'session-1',
          status: VoiceInputStatus.completed,
          startedAt: DateTime.now(),
        );

        expect(recordingInput.isProcessing, isTrue);
        expect(completedInput.isProcessing, isFalse);
        expect(completedInput.isCompleted, isTrue);
      });
    });

    group('AudioChunk Model', () {
      test('should create AudioChunk instance correctly', () {
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        final audioChunk = AudioChunk(
          id: 'chunk-1',
          type: AudioChunkType.tts,
          data: data,
          timestamp: DateTime.now(),
          sequenceNumber: 0,
          totalChunks: 5,
        );

        expect(audioChunk.id, equals('chunk-1'));
        expect(audioChunk.type, equals(AudioChunkType.tts));
        expect(audioChunk.data, equals(data));
        expect(audioChunk.sequenceNumber, equals(0));
        expect(audioChunk.totalChunks, equals(5));
        expect(audioChunk.isFirstChunk, isTrue);
        expect(audioChunk.isLastChunk, isFalse);
      });

      test('should detect last chunk correctly', () {
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        final lastChunk = AudioChunk(
          id: 'chunk-5',
          type: AudioChunkType.tts,
          data: data,
          timestamp: DateTime.now(),
          sequenceNumber: 4,
          totalChunks: 5,
        );

        expect(lastChunk.isLastChunk, isTrue);
        expect(lastChunk.isFirstChunk, isFalse);
      });
    });

    group('Session Model', () {
      test('should create Session instance correctly', () {
        final session = Session(
          id: 'session-1',
          userId: 'user-1',
          token: 'mock-token',
          status: SessionStatus.active,
          createdAt: DateTime.now(),
        );

        expect(session.id, equals('session-1'));
        expect(session.userId, equals('user-1'));
        expect(session.token, equals('mock-token'));
        expect(session.status, equals(SessionStatus.active));
        expect(session.isActive, isTrue);
      });

      test('should detect expired session correctly', () {
        final expiredSession = Session(
          id: 'session-1',
          userId: 'user-1',
          token: 'mock-token',
          status: SessionStatus.active,
          createdAt: DateTime.now().subtract(Duration(hours: 2)),
          expiresAt: DateTime.now().subtract(Duration(hours: 1)),
        );

        expect(expiredSession.isExpired, isTrue);
        expect(expiredSession.isActive, isFalse);
      });
    });
  });
}