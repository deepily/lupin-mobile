import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';

import '../../_helpers/fixture_loader.dart';
import '../_helpers/stub_dio.dart';

void main() {
  group("NotificationRepository", () {
    late StubAdapter adapter;
    late NotificationRepository repo;

    setUp(() {
      adapter = StubAdapter();
      repo = NotificationRepository(makeDio(adapter));
    });

    test("notify forwards every set query param", () async {
      adapter.handlers["POST /api/notify"] = (opts) {
        expect(opts.queryParameters["message"],     "hello");
        expect(opts.queryParameters["target_user"], "ricardo");
        expect(opts.queryParameters["priority"],    "high");
        expect(opts.queryParameters.containsKey("response_type"), isFalse);
        return jsonBody({
          "status"            : "queued",
          "message"           : "ok",
          "target_user"       : "ricardo",
          "target_system_id"  : "tsi-1",
          "connection_count"  : 1,
        });
      };
      final r = await repo.notify(const NotifyRequest(
        message: "hello", targetUser: "ricardo", priority: "high",
      ));
      expect(r.status,         "queued");
      expect(r.targetSystemId, "tsi-1");
    });

    test("list parses notification envelope", () async {
      adapter.handlers["GET /api/notifications/u-1"] = (opts) {
        expect(opts.queryParameters["include_played"], false);
        expect(opts.queryParameters["limit"],          25);
        return jsonBody({
          "status": "success", "user_id": "u-1",
          "notification_count": 1, "include_played": false, "limit": 25,
          "timestamp": "2026-04-15T12:00:00Z",
          "notifications": [{
            "id": "n-1", "message": "x", "type": "task", "priority": "low",
            "timestamp": "2026-04-15T11:00:00Z", "played": false, "play_count": 0,
            "response_requested": false, "suppress_ding": false,
            "display_qualifier_widget": false,
          }],
        });
      };
      final r = await repo.list("u-1", limit: 25);
      expect(r.notifications.single.id, "n-1");
    });

    test("conversation parses fixture of real ConversationMessage[] shape", () async {
      // Fixture captured via src/scripts/capture-notifications-fixtures.py
      // — 5 redacted messages from the real /api/notifications/conversation/...
      // `@` percent-encodes to `%40` under Uri.encodeComponent.
      adapter.handlers["GET /api/notifications/conversation/s-1/u%40x.y"] =
        (_) => jsonBodyFromFixture("notifications/conversation.json");
      final list = await repo.conversation("s-1", "u@x.y", hours: 24);
      expect(list, isNotEmpty);
      expect(list.first.id, startsWith("msg-fixture-"));
      expect(list.first.senderId, "sender-fixture-0");
      // Every captured message has a `type` and `priority` — parser must
      // accept the real backend's values, not just the ones we made up.
      expect(list.every((m) => m.type.isNotEmpty),     isTrue);
      expect(list.every((m) => m.priority.isNotEmpty), isTrue);
    });

    test("conversationByDate parses fixture of real date-keyed map", () async {
      adapter.handlers["GET /api/notifications/conversation-by-date/s/u"] =
        (_) => jsonBodyFromFixture("notifications/conversation_by_date.json");
      final m = await repo.conversationByDate("s", "u");
      // At least one recent date with at least one message per the capture caps.
      expect(m.keys,  isNotEmpty);
      final firstDateMessages = m.values.first;
      expect(firstDateMessages, isNotEmpty);
      // All message IDs match the redaction pattern.
      for (final msgs in m.values) {
        for (final item in msgs) {
          expect(item.id, startsWith("msg-fixture-"));
        }
      }
    });

    test("respond posts json body and parses ack", () async {
      adapter.handlers["POST /api/notify/response"] = (opts) {
        expect(opts.data, isA<Map>());
        expect((opts.data as Map)["notification_id"], "n-1");
        expect((opts.data as Map)["response_value"],  "yes");
        return jsonBody({
          "status": "success",
          "message": "Response saved",
          "notification_id": "n-1",
          "response_value": "yes",
          "timestamp": "2026-04-15T12:00:00Z",
          "time_display": "12:00 UTC",
          "date_display": "2026-04-15",
        });
      };
      final ack = await repo.respond(const NotificationResponsePayload(
        notificationId: "n-1", responseValue: "yes",
      ));
      expect(ack.status,        "success");
      expect(ack.responseValue, "yes");
    });

    test("conversation URL-encodes senderId with `/` and userEmail with `@`", () async {
      // Regression for the pre-fix bug where raw path interpolation caused
      // FastAPI to split `peer-queue-watch/abc-def` into two segments.
      adapter.handlers[
        "GET /api/notifications/conversation/peer-queue-watch%2Fabc-def/u%40x.y"
      ] = (_) => jsonBody( const [] );
      final list = await repo.conversation(
        "peer-queue-watch/abc-def", "u@x.y", hours: 24,
      );
      expect( list, isEmpty );
      // Also verify the captured request used the encoded path, not raw.
      final req = adapter.captured.single;
      expect( req.path, contains( "peer-queue-watch%2Fabc-def" ) );
      expect( req.path, contains( "u%40x.y" ) );
      expect( req.path, isNot( contains( "peer-queue-watch/abc-def/u@x.y" ) ) );
    });

    test("404 maps to NotificationApiException", () async {
      adapter.handlers["GET /api/notifications/none/next"] = (_) =>
        jsonBody({"detail": "not found"}, status: 404);
      await expectLater(
        repo.next("none"),
        throwsA(isA<NotificationApiException>()
          .having((e) => e.statusCode, "statusCode", 404)
          .having((e) => e.message,    "message",    "not found")),
      );
    });

    test("bulkDelete parses deleted_count", () async {
      adapter.handlers["DELETE /api/notifications/bulk/u%40x.y"] = (opts) {
        expect(opts.queryParameters["hours"],            48);
        expect(opts.queryParameters["exclude_own_jobs"], true);
        return jsonBody({
          "status": "success", "user_email": "u@x.y",
          "hours_filter": 48, "exclude_own_jobs": true, "deleted_count": 12,
        });
      };
      final r = await repo.bulkDelete("u@x.y", hours: 48, excludeOwnJobs: true);
      expect(r.deletedCount, 12);
    });
  });
}
