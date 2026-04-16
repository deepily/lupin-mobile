import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:mockito/mockito.dart';
import 'package:lupin_mobile/features/voice/domain/voice_bloc.dart';
import 'package:lupin_mobile/features/voice/domain/voice_event.dart';
import 'package:lupin_mobile/features/voice/domain/voice_state.dart';
import 'package:lupin_mobile/services/network/http_service.dart';
import 'package:lupin_mobile/services/tts/tts_service.dart';
import 'package:lupin_mobile/core/repositories/voice_repository.dart';
import 'package:lupin_mobile/core/repositories/session_repository.dart';
import 'package:lupin_mobile/shared/models/models.dart';

// Mock classes
class MockTtsService extends Mock implements TtsService {}
class MockVoiceRepository extends Mock implements VoiceRepository {}
class MockSessionRepository extends Mock implements SessionRepository {}

void main() {
  group('VoiceBloc', () {
    late HttpService httpService;
    late VoiceBloc voiceBloc;

    setUp(() {
      httpService = HttpService(Dio());
      // Create mock dependencies
      final mockTtsService = MockTtsService();
      final mockVoiceRepository = MockVoiceRepository();
      final mockSessionRepository = MockSessionRepository();
      
      voiceBloc = VoiceBloc(
        ttsService: mockTtsService,
        voiceRepository: mockVoiceRepository,
        sessionRepository: mockSessionRepository,
      );
    });

    tearDown(() {
      voiceBloc.close();
    });

    test('initial state is VoiceInitial', () {
      expect(voiceBloc.state, equals(VoiceInitial()));
    });

    group('VoicePermissionRequested', () {
      blocTest<VoiceBloc, VoiceState>(
        'emits VoiceIdle when permission is granted',
        build: () => voiceBloc,
        act: (bloc) => bloc.add(VoicePermissionRequested()),
        expect: () => [
          const VoiceIdle(hasPermission: true),
        ],
      );
    });

    group('VoiceRecordingStarted', () {
      blocTest<VoiceBloc, VoiceState>(
        'emits VoiceRecording when recording starts',
        build: () => voiceBloc,
        act: (bloc) => bloc.add(VoiceRecordingStarted(sessionId: 'session-1')),
        expect: () => [
          isA<VoiceRecording>(),
        ],
        verify: (bloc) {
          final state = bloc.state as VoiceRecording;
          expect(state.voiceInput.sessionId, equals('session-1'));
          expect(state.voiceInput.status, equals(VoiceInputStatus.recording));
        },
      );
    });

    group('VoiceRecordingStopped', () {
      blocTest<VoiceBloc, VoiceState>(
        'emits VoiceProcessing then VoiceTranscribed when recording stops',
        build: () => voiceBloc,
        act: (bloc) async {
          bloc.add(VoiceRecordingStarted(sessionId: 'session-1'));
          await Future.delayed(Duration(milliseconds: 150));
          bloc.add(VoiceRecordingStopped());
        },
        wait: Duration(seconds: 2),
        expect: () => [
          isA<VoiceRecording>(),
          isA<VoiceProcessing>(),
          isA<VoiceTranscribed>(),
        ],
        verify: (bloc) {
          final state = bloc.state as VoiceTranscribed;
          expect(state.transcription, isNotEmpty);
          expect(state.confidence, greaterThan(0.0));
        },
      );
    });

    group('VoiceRecordingCancelled', () {
      blocTest<VoiceBloc, VoiceState>(
        'emits VoiceIdle when recording is cancelled',
        build: () => voiceBloc,
        act: (bloc) async {
          bloc.add(VoiceRecordingStarted(sessionId: 'session-1'));
          await Future.delayed(Duration(milliseconds: 100));
          bloc.add(VoiceRecordingCancelled());
        },
        expect: () => [
          isA<VoiceRecording>(),
          const VoiceIdle(hasPermission: true),
        ],
      );
    });

    group('VoiceTextEdited', () {
      blocTest<VoiceBloc, VoiceState>(
        'emits VoiceEditing when text is edited',
        build: () => voiceBloc,
        act: (bloc) => bloc.add(VoiceTextEdited(text: 'Edited text')),
        expect: () => [
          isA<VoiceEditing>(),
        ],
        verify: (bloc) {
          final state = bloc.state as VoiceEditing;
          expect(state.text, equals('Edited text'));
        },
      );
    });

    group('VoiceInputSubmitted', () {
      blocTest<VoiceBloc, VoiceState>(
        'emits VoiceSubmitting, VoiceSubmitted, then VoiceIdle',
        build: () => voiceBloc,
        act: (bloc) => bloc.add(VoiceInputSubmitted(
          text: 'Test question',
          sessionId: 'session-1',
        )),
        wait: Duration(seconds: 3),
        expect: () => [
          isA<VoiceSubmitting>(),
          isA<VoiceSubmitted>(),
          const VoiceIdle(hasPermission: true),
        ],
        verify: (bloc) {
          // Verify the final state is VoiceIdle
          expect(bloc.state, isA<VoiceIdle>());
        },
      );
    });

    group('VoiceInputCleared', () {
      blocTest<VoiceBloc, VoiceState>(
        'emits VoiceIdle when input is cleared',
        build: () => voiceBloc,
        act: (bloc) => bloc.add(VoiceInputCleared()),
        expect: () => [
          const VoiceIdle(hasPermission: true),
        ],
      );
    });

    group('VoiceSettingsUpdated', () {
      blocTest<VoiceBloc, VoiceState>(
        'updates settings in VoiceIdle state',
        build: () => voiceBloc,
        act: (bloc) async {
          bloc.add(VoicePermissionRequested());
          await Future.delayed(Duration(milliseconds: 100));
          bloc.add(VoiceSettingsUpdated(settings: {'volume': 0.8}));
        },
        expect: () => [
          const VoiceIdle(hasPermission: true),
          const VoiceIdle(hasPermission: true, settings: {'volume': 0.8}),
        ],
      );
    });
  });
}