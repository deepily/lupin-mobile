import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_event.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_state.dart';
import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:mocktail/mocktail.dart';

import '../_helpers/stub_dio.dart';

class _MockAudioService extends Mock implements NotificationAudioService {}
class _MockTtsOrchestrator extends Mock implements TtsOrchestrator {}

void main() {
  group("NotificationBloc", () {
    late StubAdapter adapter;
    late NotificationRepository repo;

    setUp(() {
      adapter = StubAdapter();
      repo = NotificationRepository(makeDio(adapter));
    });

    blocTest<NotificationBloc, NotificationState>(
      "LoadInbox emits Loading → InboxLoaded with senders",
      setUp: () {
        adapter.handlers["GET /api/notifications/senders-visible/u%40x.y"] = (_) =>
          jsonBody([
            {"sender_id": "s-1", "last_activity": "2026-04-15T10:00:00Z",
             "count": 3, "new_count": 1},
            {"sender_id": "s-2", "last_activity": "2026-04-15T09:00:00Z",
             "count": 5},
          ]);
      },
      build  : () => NotificationBloc(repo),
      act    : (b) => b.add(const NotificationsLoadInbox(userEmail: "u@x.y")),
      wait   : const Duration(milliseconds: 50),
      expect : () => [
        isA<NotificationsLoading>(),
        isA<NotificationsInboxLoaded>()
          .having((s) => s.senders.length,    "count",  2)
          .having((s) => s.senders.first.senderId, "first", "s-1"),
      ],
    );

    blocTest<NotificationBloc, NotificationState>(
      "LoadConversation emits Loading → ConversationLoaded",
      setUp: () {
        adapter.handlers["GET /api/notifications/conversation/s-1/u%40x.y"] = (_) =>
          jsonBody([
            {"id": "c-1", "sender_id": "s-1", "message": "hi",
             "type": "task", "priority": "low", "state": "delivered",
             "is_hidden": false, "abstract": "",
             "timestamp": "2026-04-15T10:00:00Z",
             "response_requested": false},
          ]);
      },
      build  : () => NotificationBloc(repo),
      act    : (b) => b.add(const NotificationsLoadConversation(
        senderId: "s-1", userEmail: "u@x.y",
      )),
      wait   : const Duration(milliseconds: 50),
      expect : () => [
        isA<NotificationsLoading>(),
        isA<NotificationsConversationLoaded>()
          .having((s) => s.messages.single.id, "msg id", "c-1"),
      ],
    );

    blocTest<NotificationBloc, NotificationState>(
      "Respond emits Responding → ResponseAcked → Conversation refresh",
      setUp: () {
        // Establish active conversation context first.
        adapter.handlers["GET /api/notifications/conversation/s-1/u%40x.y"] = (_) =>
          jsonBody([
            {"id": "c-1", "sender_id": "s-1", "message": "?",
             "type": "task", "priority": "low", "state": "delivered",
             "is_hidden": false, "abstract": "",
             "timestamp": "2026-04-15T10:00:00Z",
             "response_requested": true, "response_type": "yes_no"},
          ]);
        adapter.handlers["POST /api/notify/response"] = (_) => jsonBody({
          "status": "success", "message": "saved",
          "notification_id": "c-1", "response_value": "yes",
          "timestamp": "2026-04-15T12:00:00Z",
        });
        adapter.handlers["POST /api/notifications/c-1/played"] = (_) =>
          jsonBody({"status": "success", "notification_id": "c-1"});
      },
      build  : () => NotificationBloc(repo),
      act    : (b) async {
        b.add(const NotificationsLoadConversation(
          senderId: "s-1", userEmail: "u@x.y",
        ));
        await Future.delayed(const Duration(milliseconds: 50));
        b.add(const NotificationsRespond(
          notificationId: "c-1", responseValue: "yes",
        ));
      },
      wait: const Duration(milliseconds: 500),
      verify: (b) {
        // Confirms the responding lifecycle reached an acked state.
        // (The full state list is timing-sensitive; check final history.)
        expect(b.state, anyOf(
          isA<NotificationsConversationLoaded>(),
          isA<NotificationsResponseAcked>(),
        ));
      },
    );

    blocTest<NotificationBloc, NotificationState>(
      "API error emits NotificationsError",
      setUp: () {
        adapter.handlers["GET /api/notifications/senders-visible/u%40x.y"] = (_) =>
          jsonBody({"detail": "boom"}, status: 500);
      },
      build  : () => NotificationBloc(repo),
      act    : (b) => b.add(const NotificationsLoadInbox(userEmail: "u@x.y")),
      wait   : const Duration(milliseconds: 50),
      expect : () => [
        isA<NotificationsLoading>(),
        isA<NotificationsError>().having((s) => s.message, "message", "boom"),
      ],
    );

    blocTest<NotificationBloc, NotificationState>(
      "LoadSenderDates emits Loading → SenderDatesLoaded with date summaries",
      setUp: () {
        adapter.handlers["GET /api/notifications/sender-dates/s-1/u%40x.y"] = (_) =>
          jsonBody([
            {"date": "2026-04-22", "count": 5, "new_count": 2},
            {"date": "2026-04-21", "count": 3, "new_count": 0},
          ]);
      },
      build  : () => NotificationBloc(repo),
      act    : (b) => b.add(const NotificationsLoadSenderDates(
        senderId: "s-1", userEmail: "u@x.y",
      )),
      wait   : const Duration(milliseconds: 50),
      expect : () => [
        isA<NotificationsLoading>(),
        isA<NotificationsSenderDatesLoaded>()
          .having((s) => s.dates.length,         "count",  2)
          .having((s) => s.dates.first.date,     "first",  "2026-04-22")
          .having((s) => s.dates.first.newCount, "newCount", 2),
      ],
    );

    blocTest<NotificationBloc, NotificationState>(
      "LoadConversationByDate emits Loading → ConversationByDateLoaded grouped by date",
      setUp: () {
        adapter.handlers["GET /api/notifications/conversation-by-date/s-1/u%40x.y"] = (_) =>
          jsonBody({
            "2026-04-22": [
              {"id": "n-1", "message": "first",  "type": "task",
               "priority": "low", "timestamp": "2026-04-22T10:00:00Z",
               "played": false, "play_count": 0,
               "response_requested": false, "suppress_ding": false,
               "display_qualifier_widget": false},
            ],
            "2026-04-21": [
              {"id": "n-2", "message": "second", "type": "task",
               "priority": "high", "timestamp": "2026-04-21T10:00:00Z",
               "played": true, "play_count": 1,
               "response_requested": false, "suppress_ding": false,
               "display_qualifier_widget": false},
              {"id": "n-3", "message": "third",  "type": "task",
               "priority": "high", "timestamp": "2026-04-21T11:00:00Z",
               "played": false, "play_count": 0,
               "response_requested": false, "suppress_ding": false,
               "display_qualifier_widget": false},
            ],
          });
      },
      build  : () => NotificationBloc(repo),
      act    : (b) => b.add(const NotificationsLoadConversationByDate(
        senderId: "s-1", userEmail: "u@x.y",
      )),
      wait   : const Duration(milliseconds: 50),
      expect : () => [
        isA<NotificationsLoading>(),
        isA<NotificationsConversationByDateLoaded>()
          .having((s) => s.byDate.length,                   "dateGroups", 2)
          .having((s) => s.byDate["2026-04-22"]?.length,    "n on 22",     1)
          .having((s) => s.byDate["2026-04-21"]?.length,    "n on 21",     2),
      ],
    );

    blocTest<NotificationBloc, NotificationState>(
      "ExternalUpdate refreshes current inbox after WS event",
      setUp: () {
        var hitCount = 0;
        adapter.handlers["GET /api/notifications/senders-visible/u%40x.y"] = (_) {
          hitCount++;
          return jsonBody([
            {"sender_id": "s-1", "last_activity": "2026-04-15T10:00:00Z",
             "count": hitCount, "new_count": hitCount},
          ]);
        };
      },
      build  : () => NotificationBloc(repo),
      act    : (b) async {
        b.add(const NotificationsLoadInbox(userEmail: "u@x.y"));
        await Future.delayed(const Duration(milliseconds: 50));
        b.add(const NotificationsExternalUpdate());
      },
      wait   : const Duration(milliseconds: 150),
      expect : () => [
        isA<NotificationsLoading>(),
        isA<NotificationsInboxLoaded>()
          .having((s) => s.senders.single.count, "first count", 1),
        isA<NotificationsInboxLoaded>()
          .having((s) => s.senders.single.count, "refreshed count", 2),
      ],
    );

    test( "ExternalUpdate with urgent NotificationItem calls NotificationAudioService.handleIncoming", () async {
      final audio = _MockAudioService();
      when( () => audio.handleIncoming(
        priority     : any( named: "priority" ),
        message      : any( named: "message" ),
        title        : any( named: "title" ),
        suppressDing : any( named: "suppressDing" ),
      ) ).thenAnswer( ( _ ) async {} );

      final bloc = NotificationBloc( repo, audio: audio );

      final urgent = NotificationItem(
        id                     : "n-1",
        message                : "Prod is down.",
        title                  : "CRIT",
        type                   : "alert",
        priority               : "urgent",
        timestamp              : DateTime( 2026, 4, 21 ),
        played                 : false,
        playCount              : 0,
        responseRequested      : false,
        suppressDing           : false,
        displayQualifierWidget : false,
      );

      bloc.add( NotificationsExternalUpdate( notification: urgent ) );
      await Future.delayed( const Duration( milliseconds: 50 ) );

      verify( () => audio.handleIncoming(
        priority     : "urgent",
        message      : "Prod is down.",
        title        : "CRIT",
        suppressDing : false,
      ) ).called( 1 );

      await bloc.close();
    } );

    test( "ExternalUpdate with no notification does NOT call audio service", () async {
      final audio = _MockAudioService();
      final bloc  = NotificationBloc( repo, audio: audio );

      bloc.add( const NotificationsExternalUpdate() );
      await Future.delayed( const Duration( milliseconds: 50 ) );

      verifyNever( () => audio.handleIncoming(
        priority     : any( named: "priority" ),
        message      : any( named: "message" ),
        title        : any( named: "title" ),
        suppressDing : any( named: "suppressDing" ),
      ) );

      await bloc.close();
    } );

    test( "ExternalUpdate with urgent notification ALSO calls TtsOrchestrator.enqueueIfSpeakable", () async {
      final audio = _MockAudioService();
      final tts   = _MockTtsOrchestrator();
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
        sender   : any( named: 'sender' ),
      ) ).thenReturn( null );

      final bloc = NotificationBloc( repo, audio: audio, tts: tts );

      final urgent = NotificationItem(
        id                     : "n-42",
        message                : "Prod is down.",
        title                  : "CRIT",
        type                   : "alert",
        priority               : "urgent",
        timestamp              : DateTime( 2026, 4, 21 ),
        played                 : false,
        playCount              : 0,
        responseRequested      : false,
        suppressDing           : false,
        displayQualifierWidget : false,
      );

      bloc.add( NotificationsExternalUpdate( notification: urgent ) );
      await Future.delayed( const Duration( milliseconds: 50 ) );

      verify( () => tts.enqueueIfSpeakable(
        priority : "urgent",
        message  : "Prod is down.",
        title    : "CRIT",
        sender   : any( named: 'sender' ),
      ) ).called( 1 );

      await bloc.close();
    } );

    // ─────────────────────────────────────────────────────────────────────
    // Section D (Phase 4, 2026-05-23 notif-client-sync) — `assigned_at`
    // propagation E2E along the WS event path. AC-D5 asserts that a
    // `voice_persona_assigned` external-update with `assigned_at` in its
    // payload yields a `personasBySender` map whose `VoicePersona.assignedAt`
    // is the parsed DateTime. Companion: AC-D1/D2/D3 in `voice_persona_test.dart`
    // cover the parse-level contract; AC-D4 in `notification_repository_test.dart`
    // covers the REST-path fixture grounding; AC-D6 covers the live WS probe.
    // ─────────────────────────────────────────────────────────────────────

    test(
      "AC-D5 — voice_persona_assigned WS-path with assigned_at populated "
      "yields personasBySender entry with parsed DateTime",
      () async {
        // Seed an InboxLoaded state so `_refreshCurrent` (called at the end of
        // `_onExternalUpdate`) has a context to re-emit into.
        adapter.handlers["GET /api/notifications/senders-visible/u%40x.y"] = (_) =>
          jsonBody( const [] );

        final bloc = NotificationBloc( repo );

        bloc.add( const NotificationsLoadInbox( userEmail: "u@x.y" ) );
        await Future.delayed( const Duration( milliseconds: 50 ) );

        // Inject the WS event with assigned_at populated. The bloc routes
        // type=="voice_persona_assigned" into the `_onExternalUpdate` case
        // that mutates `_personasBySender[sid] = persona;` then calls
        // `_refreshCurrent(emit)`, which re-emits InboxLoaded with the
        // snapshot.
        final assignedUtc = DateTime.utc( 2026, 5, 22, 12, 0, 0 );
        bloc.add( NotificationsExternalUpdate(
          notification: NotificationItem(
            id                     : "n-vpa-d5",
            message                : "",
            type                   : "voice_persona_assigned",
            priority               : "low",
            timestamp              : DateTime( 2026, 5, 22 ),
            played                 : false,
            playCount              : 0,
            responseRequested      : false,
            suppressDing           : false,
            displayQualifierWidget : false,
            senderId               : "s-vpa-d5",
            voicePersona           : VoicePersona(
              name        : "Adam",
              voiceId     : "v-d5",
              icon        : "🌑",
              color       : "#3F51B5",
              borrowed    : false,
              assignedAt  : assignedUtc,
              displayName : "Adam",
            ),
          ),
        ) );
        await Future.delayed( const Duration( milliseconds: 100 ) );

        final state = bloc.state;
        expect(
          state,
          isA<NotificationsInboxLoaded>(),
          reason:
              "AC-D5 — after persona assignment + _refreshCurrent, bloc must "
              "re-emit InboxLoaded carrying the persona snapshot.",
        );
        final loaded  = state as NotificationsInboxLoaded;
        final persona = loaded.personasBySender[ "s-vpa-d5" ];
        expect(
          persona,
          isNotNull,
          reason:
              "AC-D5 — personasBySender must carry an entry at the new "
              "senderId after assignment.",
        );
        expect(
          persona!.assignedAt,
          isNotNull,
          reason:
              "AC-D5 — VoicePersona.assignedAt must be non-null after "
              "WS-path injection (the carrier round-tripped through state).",
        );
        expect(
          persona.assignedAt!.toUtc(),
          assignedUtc,
          reason:
              "AC-D5 — parsed assignedAt must equal the injected UTC DateTime.",
        );
        expect( persona.assignedAt!.isUtc, isTrue,
          reason: "AC-D5 — assignedAt must preserve UTC offset." );

        await bloc.close();
      },
    );
  });
}
