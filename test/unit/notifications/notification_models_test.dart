import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';

void main() {
  group("NotificationItem.fromJson", () {
    test("parses required + optional fields", () {
      final n = NotificationItem.fromJson({
        "id"                       : "n-1",
        "id_hash"                  : "n-1-hash",
        "message"                  : "hello",
        "title"                    : "Hi",
        "type"                     : "task",
        "priority"                 : "high",
        "user_id"                  : "u-1",
        "timestamp"                : "2026-04-15T12:00:00Z",
        "time_display"             : "12:00 UTC",
        "played"                   : false,
        "play_count"               : 0,
        "last_played"              : null,
        "response_requested"       : true,
        "response_type"            : "yes_no",
        "response_default"         : "no",
        "timeout_seconds"          : 60,
        "sender_id"                : "claude.code@x.deepily.ai",
        "abstract"                 : "ctx",
        "suppress_ding"            : false,
        "display_qualifier_widget" : true,
      });
      expect(n.id,                     "n-1");
      expect(n.idHash,                 "n-1-hash");
      expect(n.priority,               "high");
      expect(n.timestamp.isUtc,        isTrue);
      expect(n.responseRequested,      isTrue);
      expect(n.responseType,           "yes_no");
      expect(n.timeoutSeconds,         60);
      expect(n.displayQualifierWidget, isTrue);
      expect(n.abstractText,           "ctx");
    });

    test("defaults for missing fields", () {
      final n = NotificationItem.fromJson({
        "id"        : "n-2",
        "message"   : "x",
        "type"      : "custom",
        "priority"  : "low",
        "timestamp" : "2026-04-15T12:00:00Z",
        "played"    : false,
        "play_count": 0,
        "response_requested"      : false,
        "suppress_ding"           : false,
        "display_qualifier_widget": false,
      });
      expect(n.title,           isNull);
      expect(n.responseType,    isNull);
      expect(n.responseOptions, isNull);
      expect(n.timeoutSeconds,  isNull);
    });
  });

  group("NotificationListResponse.fromJson", () {
    test("parses notification list envelope", () {
      final r = NotificationListResponse.fromJson({
        "status"             : "success",
        "user_id"            : "u-1",
        "notification_count" : 2,
        "include_played"     : false,
        "limit"              : 50,
        "timestamp"          : "2026-04-15T12:00:00Z",
        "notifications": [
          {"id": "a", "message": "1", "type": "task", "priority": "low",
           "timestamp": "2026-04-15T11:00:00Z", "played": false, "play_count": 0,
           "response_requested": false, "suppress_ding": false,
           "display_qualifier_widget": false},
          {"id": "b", "message": "2", "type": "task", "priority": "low",
           "timestamp": "2026-04-15T11:30:00Z", "played": true, "play_count": 1,
           "response_requested": false, "suppress_ding": false,
           "display_qualifier_widget": false},
        ],
      });
      expect(r.status,            "success");
      expect(r.notifications.length, 2);
      expect(r.notifications[1].id,  "b");
    });
  });

  group("ConversationMessage.fromJson", () {
    test("parses delivery state and timestamps", () {
      final m = ConversationMessage.fromJson({
        "id"               : "c-1",
        "sender_id"        : "claude.code@x",
        "message"          : "hi",
        "type"             : "task",
        "priority"         : "low",
        "state"            : "responded",
        "is_hidden"        : false,
        "abstract"         : "",
        "created_at"       : "2026-04-15T10:00:00Z",
        "delivered_at"     : "2026-04-15T10:00:01Z",
        "responded_at"     : "2026-04-15T10:01:00Z",
        "response_requested": true,
        "response_type"    : "yes_no",
        "response_value"   : "yes",
        "timestamp"        : "2026-04-15T10:00:00Z",
        "time_display"     : "10:00 UTC",
      });
      expect(m.state,         "responded");
      expect(m.respondedAt!.minute, 1);
      expect(m.responseValue, "yes");
    });
  });

  group("SenderSummary.fromJson", () {
    test("optional new_count handled", () {
      final s1 = SenderSummary.fromJson({
        "sender_id": "s-1",
        "last_activity": "2026-04-15T10:00:00Z",
        "count": 3,
      });
      expect(s1.newCount, isNull);

      final s2 = SenderSummary.fromJson({
        "sender_id": "s-2",
        "last_activity": "2026-04-15T10:00:00Z",
        "count": 5,
        "new_count": 2,
      });
      expect(s2.newCount, 2);
    });
  });

  group("NotifyRequest.toQuery", () {
    test("only includes set fields", () {
      final q = const NotifyRequest(
        message    : "hi",
        targetUser : "ricardo",
        priority   : "high",
        type       : "task",
      ).toQuery();
      expect(q["message"],     "hi");
      expect(q["target_user"], "ricardo");
      expect(q["priority"],    "high");
      expect(q["type"],        "task");
      expect(q.containsKey("title"),         isFalse);
      expect(q.containsKey("response_type"), isFalse);
    });
  });

  group("ActiveConversationResponse.fromJson", () {
    test("nullable active_sender_id", () {
      final r = ActiveConversationResponse.fromJson({
        "active_sender_id": null,
        "user_email": "x@y.z",
      });
      expect(r.activeSenderId, isNull);
      expect(r.userEmail,      "x@y.z");
    });
  });
}
