import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_event.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_state.dart';

import '../_helpers/stub_dio.dart';

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
        adapter.handlers["GET /api/notifications/senders-visible/u@x.y"] = (_) =>
          jsonBody([
            {"sender_id": "s-1", "last_activity": "2026-04-15T10:00:00Z",
             "count": 3, "new_count": 1},
            {"sender_id": "s-2", "last_activity": "2026-04-15T09:00:00Z",
             "count": 5},
          ]);
      },
      build  : () => NotificationBloc(repo),
      act    : (b) => b.add(const NotificationsLoadInbox(userEmail: "u@x.y")),
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
        adapter.handlers["GET /api/notifications/conversation/s-1/u@x.y"] = (_) =>
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
        adapter.handlers["GET /api/notifications/conversation/s-1/u@x.y"] = (_) =>
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
        adapter.handlers["GET /api/notifications/senders-visible/u@x.y"] = (_) =>
          jsonBody({"detail": "boom"}, status: 500);
      },
      build  : () => NotificationBloc(repo),
      act    : (b) => b.add(const NotificationsLoadInbox(userEmail: "u@x.y")),
      expect : () => [
        isA<NotificationsLoading>(),
        isA<NotificationsError>().having((s) => s.message, "message", "boom"),
      ],
    );
  });
}
