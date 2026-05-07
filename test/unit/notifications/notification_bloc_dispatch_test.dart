// Phase 0 — WS dispatch audit regression test (2026-05-06).
//
// Locks the inner-`notification.type` discriminator pivot in
// `NotificationBloc._onExternalUpdate`. Without this test, a future migration
// could silently drop new event types that ride inside the
// `notification_queue_update` envelope.
//
// Sister doc: src/rnd/v0.1.7/2026.05.06-mobile-port-plans/00-phase-0-dispatch-audit.md
//
// Pattern mirrors the mocktail tests at the bottom of `notification_bloc_test.dart`
// (the `_MockAudioService` / `_MockTtsOrchestrator` block).

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_event.dart';
import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:mocktail/mocktail.dart';

import '../_helpers/stub_dio.dart';

class _MockAudioService extends Mock implements NotificationAudioService {}
class _MockTtsOrchestrator extends Mock implements TtsOrchestrator {}

NotificationItem _makeItem( {
  required String type,
  String  priority = "urgent",
  String  id       = "n-test",
  String  message  = "body",
  String? title    = "title",
} ) {
  return NotificationItem(
    id                     : id,
    message                : message,
    title                  : title,
    type                   : type,
    priority               : priority,
    timestamp              : DateTime( 2026, 5, 6 ),
    played                 : false,
    playCount              : 0,
    responseRequested      : false,
    suppressDing           : false,
    displayQualifierWidget : false,
  );
}

void main() {
  group( "NotificationBloc — inner-type dispatch (Phase 0)", () {
    late StubAdapter             adapter;
    late NotificationRepository  repo;
    late _MockAudioService       audio;
    late _MockTtsOrchestrator    tts;

    setUp( () {
      adapter = StubAdapter();
      repo    = NotificationRepository( makeDio( adapter ) );
      audio   = _MockAudioService();
      tts     = _MockTtsOrchestrator();
      when( () => audio.handleIncoming(
        priority     : any( named: "priority" ),
        message      : any( named: "message" ),
        title        : any( named: "title" ),
        suppressDing : any( named: "suppressDing" ),
      ) ).thenAnswer( ( _ ) async {} );
      when( () => tts.enqueueIfSpeakable(
        priority : any( named: "priority" ),
        message  : any( named: "message" ),
        title    : any( named: "title" ),
      ) ).thenReturn( null );
    } );

    test(
      "type='voice_persona_assigned' (future feature event) hits default branch — "
      "no audio, no TTS, no crash",
      () async {
        final bloc = NotificationBloc( repo, audio: audio, tts: tts );

        bloc.add( NotificationsExternalUpdate(
          notification: _makeItem( type: "voice_persona_assigned" ),
        ) );
        await Future.delayed( const Duration( milliseconds: 50 ) );

        verifyNever( () => audio.handleIncoming(
          priority     : any( named: "priority" ),
          message      : any( named: "message" ),
          title        : any( named: "title" ),
          suppressDing : any( named: "suppressDing" ),
        ) );
        verifyNever( () => tts.enqueueIfSpeakable(
          priority : any( named: "priority" ),
          message  : any( named: "message" ),
          title    : any( named: "title" ),
        ) );

        await bloc.close();
      },
    );

    test(
      "type='some_unknown_type' (graceful-degradation safety net) hits default branch — "
      "no audio, no TTS, no crash",
      () async {
        final bloc = NotificationBloc( repo, audio: audio, tts: tts );

        bloc.add( NotificationsExternalUpdate(
          notification: _makeItem( type: "some_unknown_type" ),
        ) );
        await Future.delayed( const Duration( milliseconds: 50 ) );

        verifyNever( () => audio.handleIncoming(
          priority     : any( named: "priority" ),
          message      : any( named: "message" ),
          title        : any( named: "title" ),
          suppressDing : any( named: "suppressDing" ),
        ) );
        verifyNever( () => tts.enqueueIfSpeakable(
          priority : any( named: "priority" ),
          message  : any( named: "message" ),
          title    : any( named: "title" ),
        ) );

        await bloc.close();
      },
    );

    test(
      "type='alert' (whitelisted existing type) regresses to existing path — "
      "audio AND TTS called",
      () async {
        final bloc = NotificationBloc( repo, audio: audio, tts: tts );

        bloc.add( NotificationsExternalUpdate(
          notification: _makeItem(
            type     : "alert",
            priority : "urgent",
            message  : "Prod is down.",
            title    : "CRIT",
          ),
        ) );
        await Future.delayed( const Duration( milliseconds: 50 ) );

        verify( () => audio.handleIncoming(
          priority     : "urgent",
          message      : "Prod is down.",
          title        : "CRIT",
          suppressDing : false,
        ) ).called( 1 );
        verify( () => tts.enqueueIfSpeakable(
          priority : "urgent",
          message  : "Prod is down.",
          title    : "CRIT",
        ) ).called( 1 );

        await bloc.close();
      },
    );
  } );
}
