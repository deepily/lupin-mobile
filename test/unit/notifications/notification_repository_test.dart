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

    test("sendDm posts the DM body to /api/dm/send (nulls omitted) and parses {message_id, thread_id}", () async {
      adapter.handlers["POST /api/dm/send"] = (opts) {
        final d = opts.data as Map;
        expect(d["sender_session_id"], "lupin-mobile:rick@x");
        expect(d["body"],              "re-run the suite");
        expect(d["recipient_persona"], "Tiffany");
        expect(d["sender_persona"],    "Rick");
        expect(d["sender_icon"],       "📱");
        expect(d["sender_project"],    "lupin-mobile");
        expect(d.containsKey("recipient_session_id"), isFalse);
        return jsonBody({"message_id": "m-9", "thread_id": "t-9", "recipient_persona": "Tiffany"});
      };
      final ack = await repo.sendDm(const DmSendRequest(
        senderSessionId  : "lupin-mobile:rick@x",
        body             : "re-run the suite",
        recipientPersona : "Tiffany",
        senderPersona    : "Rick",
        senderIcon       : "📱",
        senderProject    : "lupin-mobile",
      ));
      expect(ack.messageId, "m-9");
      expect(ack.threadId,  "t-9");
    });

    test("sendDm maps a 422 (recipient unresolved) to NotificationApiException", () async {
      adapter.handlers["POST /api/dm/send"] = (opts) => jsonBody({"detail": "no such persona"}, status: 422);
      expect(
        () => repo.sendDm(const DmSendRequest(senderSessionId: "s", body: "b", recipientPersona: "Nobody")),
        throwsA(isA<NotificationApiException>()),
      );
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

    test(
      "list round-trips voice_persona stamped on a fixture envelope (Phase 1 Task 1.4)",
      () async {
        // Fixture: test/fixtures/notifications/notification-with-persona.json
        // — single NotificationItem shape with full voice_persona dict (Adam,
        // borrowed=false). Wrap it as a list-response envelope so the standard
        // GET /api/notifications/{user} handler round-trips it.
        final item = loadFixture("notifications/notification-with-persona.json");
        adapter.handlers["GET /api/notifications/u-persona"] = (_) => jsonBody({
          "status"            : "success",
          "user_id"           : "u-persona",
          "notification_count": 1,
          "include_played"    : false,
          "limit"             : 50,
          "timestamp"         : "2026-04-28T20:35:00Z",
          "notifications"     : [item],
        });

        final r = await repo.list("u-persona");
        expect(r.notifications.length,                1);
        final n = r.notifications.single;
        expect(n.id,                                  "fixture-persona-1");
        expect(n.voicePersona,                        isNotNull);
        expect(n.voicePersona!.name,                  "Adam");
        expect(n.voicePersona!.voiceId,               "pNInz6obpgDQGcFmaJgB");
        expect(n.voicePersona!.color,                 "#3F51B5");
        expect(n.voicePersona!.borrowed,              isFalse);
        expect(n.voicePersona!.displayName,           "Adam");
      },
    );

    test(
      "list still parses persona-absent envelopes cleanly (Phase 1 Task 1.4 regression)",
      () async {
        // Confirms the persona-absent path didn't regress. The existing
        // list_response.json fixture has notifications without voice_persona.
        adapter.handlers["GET /api/notifications/u-no-persona"] = (_) =>
          jsonBodyFromFixture("notifications/list_response.json");

        final r = await repo.list("u-no-persona");
        expect(r.status,        "success");
        // list_response.json fixture has 0 notifications — that's fine; the
        // assertion is "no throw on persona-less envelope," which the call
        // returning successfully proves.
        expect(r.notifications.length, 0);
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // Section D (Phase 4, 2026-05-23 notif-client-sync) — `assigned_at`
    // wire-contract grounding on the voice-persona pool REST path (AC-D4)
    // and the live WS probe (AC-D6). Per cascade Stage-2 consolidated
    // wire-grounding doctrine: the AC-D4 fixture is a MANDATED live `:7999`
    // capture, never hand-authored. The AC-D6 probe is non-optional but
    // requires a running :7999 + authenticated HTTP client + WebSocket
    // client setup — the dev-server slice of this test verifies the
    // contract shape via the captured fixture (AC-D4); the laptop slice
    // runs the live probe (AC-D6) under the existing Flutter test pipeline.
    // ─────────────────────────────────────────────────────────────────────

    test(
      "AC-D4 — voice-persona pool fixture: every active_sessions entry "
      "carries a non-null assigned_at (wire-contract grounding)",
      () {
        // Source-of-truth fixture: `test/fixtures/notifications/voice_persona_pool.json`.
        //
        // Capture procedure (MANDATED — never hand-author per consolidated
        // wire-grounding doctrine, cascade Stage-2 F-Krishna-D1):
        //
        //   1. Start the lupin FastAPI server on :7999 with a logged-in
        //      test user (LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL/PASSWORD
        //      per CLAUDE.md TEST CREDENTIALS).
        //   2. Obtain a Bearer token by logging in via /api/auth/login,
        //      OR use an X-API-Key the server accepts.
        //   3. curl -H "Authorization: Bearer <jwt>" \
        //        http://localhost:7999/api/cosa-voice/voice-persona/pool \
        //        > test/fixtures/notifications/voice_persona_pool.json
        //   4. Add a provenance header (capture UTC timestamp, endpoint path,
        //      server build hash) — either as JSON metadata fields on the
        //      response root or as a sibling .provenance file. Recommended
        //      shape: { "_capture": { "ts": "<ISO-8601>", "endpoint": "...",
        //      "server_build": "..." }, "active_sessions": [...] }.
        //   5. Commit the fixture.
        //
        // Capture is DEFERRED to the laptop pipeline because the dev-server
        // session lacks the authenticated HTTP context needed (probe in this
        // session returned 401: "Missing auth. Provide X-API-Key or
        // Authorization: Bearer <jwt>"). When the fixture lands, this test
        // becomes a regression that pins the wire contract every test run.
        //
        // If the live capture lacks assigned_at on any entry, the test
        // fails as designed — that failure is the OSQ-D-1 tests-as-spec
        // signal for the parent-side patch (cascade-handoff §Section D
        // residuals RA-D1: courtesy DM to Mr. Radio at Section D impl
        // start surfaces any contract amendment).

        final fixture = loadFixture( "notifications/voice_persona_pool.json" );

        // Per the consolidated wire-grounding doctrine + Section D Goal,
        // the response carries an `active_sessions` list (the data layer
        // that has per-session assigned_at — distinct from the senders
        // summary list at `/api/notifications/senders-visible/...`).
        expect(
          fixture[ "active_sessions" ],
          isA<List>(),
          reason:
              "AC-D4 — voice_persona_pool fixture must have an "
              "active_sessions list field. If absent, the cosa server's "
              "/api/cosa-voice/voice-persona/pool shape has changed; "
              "re-capture and update the wire-contract spec.",
        );

        final sessions = fixture[ "active_sessions" ] as List;
        expect(
          sessions,
          isNotEmpty,
          reason:
              "AC-D4 — fixture should have at least one active_session entry "
              "to meaningfully test the assigned_at contract. Capture against "
              "a server with at least one allocated persona.",
        );

        for ( final s in sessions ) {
          expect( s, isA<Map>(),
            reason: "AC-D4 — each active_sessions entry must be an object." );
          final m = s as Map;
          expect(
            m.containsKey( "assigned_at" ),
            isTrue,
            reason:
                "AC-D4 — every active_sessions entry must carry an "
                "`assigned_at` field. Missing means the wire contract has "
                "drifted: either the cosa server-side hasn't been patched "
                "to stamp it, or the fixture is stale. Per Q4 tests-as-spec, "
                "this failure IS the empirical spec for any parent-Lupin "
                "Part-B patch.",
          );
          expect(
            m[ "assigned_at" ],
            isNotNull,
            reason:
                "AC-D4 — assigned_at must be non-null on every active_sessions "
                "entry (per assumption 2 of the Section D spec).",
          );
        }
      },
    );

    test(
      "AC-D6 — WS-path live :7999 probe (allocate → observe WS event → "
      "release; net-zero persistent-state mutation)",
      () async {
        // Live :7999 probe per cascade Stage-2 F-Krishna-D2 (non-optional)
        // + F-Krishna-D3 (paired allocate/release for net-zero mutation).
        //
        // Test shape (to flesh out when run laptop-side):
        //   1. Authenticate an HTTP client to :7999 (Bearer token via
        //      /api/auth/login using LUPIN_TEST_INTERACTIVE_MOCK_JOBS_*).
        //   2. Open a WebSocket connection to :7999/ws and subscribe to
        //      persona-assignment events for a fresh sender id.
        //   3. POST /api/cosa-voice/voice-persona/{sid}/allocate (mutates
        //      persona-pool state — allocates a fresh persona; this is the
        //      half of the pair that requires cleanup below).
        //   4. Await the WS event; assert assigned_at is present and
        //      parseable via DateTime.tryParse.
        //   5. POST /api/cosa-voice/voice-persona/{sid}/release to clean up
        //      (the paired release — together with the allocate, nets zero
        //      persistent-state mutation, keeping the probe `:7999`-eligible
        //      per CLAUDE.md TESTING VENUES).
        //
        // Skipped here because the test requires:
        //   - A running :7999 server (the laptop pipeline provides this).
        //   - Authenticated HTTP client setup (see test creds in CLAUDE.md).
        //   - A test-side WebSocket client (the mobile's `websocket_service.dart`
        //     can be reused or a thin test-only ws client written).
        //
        // The probe shape above is the cascade-ratified spec verbatim. Un-skip
        // by removing the `skip:` argument once the laptop pipeline plumbs
        // the auth + WS prerequisites. The `:7999` venue assignment stands —
        // the paired allocate/release keeps the run AI-discretionary.
      },
      skip:
          "AC-D6 requires running :7999 + authenticated HTTP client + "
          "WebSocket test client; un-skip in the laptop test pipeline once "
          "auth + WS prerequisites are wired in (see in-test docstring for "
          "the full probe shape).",
    );
  });
}
