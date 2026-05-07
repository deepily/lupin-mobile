// Phase 2 — Voice/persona bloc-dispatch test cases (2.4.1–2.4.4).
//
// Locks the persona-map mutation contract on `NotificationBloc`:
//   2.4.1 — assigned event populates `personasBySender` for that senderId
//   2.4.2 — released event clears the entry
//   2.4.3 — borrowed=true persona survives across unrelated state changes
//   2.4.4 — released for unknown sender is idempotent (no emit)
//
// Per Pass 1 finding F3 (applied 2026-05-06), assertions use `predicate(...)`
// against `state.personaFor(senderId)` exactly as the plan specifies.
//
// Sister doc: src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/01-implementation.md §3

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/features/notifications/data/voice_persona.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_event.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_state.dart';

import '../_helpers/stub_dio.dart';

const _adam = VoicePersona(
  name        : "Adam",
  voiceId     : "pNInz6obpgDQGcFmaJgB",
  icon        : "🌑",
  color       : "#3F51B5",
  borrowed    : false,
  displayName : "Adam",
);

const _bellaBorrowed = VoicePersona(
  name     : "Bella",
  voiceId  : "EXAVITQu4vr4xnSDxMaL",
  borrowed : true,
);

NotificationsInboxLoaded _seedInbox( {
  Map<String, VoicePersona> personasBySender = const {},
} ) =>
    NotificationsInboxLoaded(
      senders          : const [],
      userEmail        : "u@x.y",
      personasBySender : personasBySender,
    );

void main() {
  group( "NotificationBloc — voice-persona dispatch (Phase 2)", () {
    late StubAdapter             adapter;
    late NotificationRepository  repo;

    setUp( () {
      adapter = StubAdapter();
      repo    = NotificationRepository( makeDio( adapter ) );
    } );

    blocTest<NotificationBloc, NotificationState>(
      "2.4.1 — assigned event populates personasBySender for senderId",
      build  : () => NotificationBloc( repo ),
      seed   : () => _seedInbox(),
      act    : ( b ) => b.add(
        const NotificationsVoicePersonaAssigned(
          senderId : "s-1",
          persona  : _adam,
        ),
      ),
      expect : () => [
        predicate<NotificationsInboxLoaded>(
          ( s ) => s.personaFor( "s-1" ) == _adam,
          'state.personaFor("s-1") == _adam after assigned event',
        ),
      ],
    );

    blocTest<NotificationBloc, NotificationState>(
      "2.4.2 — released event clears personasBySender entry",
      build  : () => NotificationBloc( repo ),
      seed   : () => _seedInbox(),
      act    : ( b ) async {
        b.add( const NotificationsVoicePersonaAssigned(
          senderId : "s-1",
          persona  : _adam,
        ) );
        await Future.delayed( const Duration( milliseconds: 30 ) );
        b.add( const NotificationsVoicePersonaReleased(
          senderId    : "s-1",
          personaName : "Adam",
        ) );
      },
      wait   : const Duration( milliseconds: 100 ),
      expect : () => [
        predicate<NotificationsInboxLoaded>(
          ( s ) => s.personaFor( "s-1" ) == _adam,
          "post-assign: persona present",
        ),
        predicate<NotificationsInboxLoaded>(
          ( s ) => s.personaFor( "s-1" ) == null,
          "post-release: persona cleared",
        ),
      ],
    );

    blocTest<NotificationBloc, NotificationState>(
      "2.4.3 — borrowed=true persona survives unrelated state-change",
      build  : () => NotificationBloc( repo ),
      seed   : () => _seedInbox(),
      setUp  : () {
        // The LoadInbox act-step refetches sendersVisible. Stub it so the
        // refetch succeeds and emits a fresh NotificationsInboxLoaded that
        // should still carry the borrowed=true persona snapshot.
        adapter.handlers[ "GET /api/notifications/senders-visible/u%40x.y" ] =
            ( _ ) => jsonBody( [
                  {
                    "sender_id"     : "s-2",
                    "last_activity" : "2026-04-28T20:33:42Z",
                    "count"         : 7,
                    "new_count"     : 2,
                  },
                ] );
      },
      act    : ( b ) async {
        b.add( const NotificationsVoicePersonaAssigned(
          senderId : "s-1",
          persona  : _bellaBorrowed,
        ) );
        await Future.delayed( const Duration( milliseconds: 30 ) );
        // Unrelated state-change: re-load the inbox. Persona snapshot must
        // survive on the freshly-emitted InboxLoaded.
        b.add( const NotificationsLoadInbox( userEmail: "u@x.y" ) );
      },
      wait   : const Duration( milliseconds: 200 ),
      expect : () => [
        predicate<NotificationsInboxLoaded>(
          ( s ) => s.personaFor( "s-1" )?.borrowed == true,
          "post-assign: borrowed=true visible on persona snapshot",
        ),
        isA<NotificationsLoading>(),
        predicate<NotificationsInboxLoaded>(
          ( s ) =>
              s.personaFor( "s-1" )?.borrowed == true &&
              s.personaFor( "s-1" )?.voiceId == _bellaBorrowed.voiceId,
          "post-reload: borrowed=true Bella STILL on snapshot (survived state change)",
        ),
      ],
    );

    blocTest<NotificationBloc, NotificationState>(
      "2.4.4 — released for unknown sender is idempotent (no emit)",
      build  : () => NotificationBloc( repo ),
      seed   : () => _seedInbox(),
      act    : ( b ) => b.add( const NotificationsVoicePersonaReleased(
        senderId    : "unknown-sender-id",
        personaName : "Nobody",
      ) ),
      // Per Pass 1 F3: expect: [] — no state-change emit, no error.
      expect : () => const <NotificationState>[],
    );
  } );
}
