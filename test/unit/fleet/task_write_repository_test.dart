import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';

import '../_helpers/stub_dio.dart';

void main() {
  late StubAdapter adapter;
  late TaskWriteRepository repo;

  setUp(() {
    adapter = StubAdapter();
    repo    = TaskWriteRepository(makeDio(adapter));
  });

  group("the 202 trap", () {
    // 🔴 §10 test 5, and §4.5 calls it "the single most dangerous omission".
    //
    // POST …/transition can answer 202 with {"status":"awaiting_human_approval"} — a 2xx.
    // Dio throws only on a non-2xx, so without this branch the answer arrives
    // indistinguishable from a real approval and the pane paints the row approved.
    // HoldingAreaStore.ts:316-319: "A false FACT, not a false red."
    test("a 202 awaiting_human_approval does NOT resolve as success", () async {
      adapter.handlers["POST /api/tasks/t1/transition"] = (_) => jsonBody(
        {"status": "awaiting_human_approval", "ticket_id": "tk-9"}, status: 202,
      );

      await expectLater(
        repo.transition(id: "t1", verb: TaskVerb.approve()),
        throwsA(isA<TaskAwaitingApprovalException>()
            .having((e) => e.ticketId, "ticketId", "tk-9")),
      );
    });

    // ⚠️ TEST THE `status` FIELD, NEVER A SUBSTRING. A row whose own reason text mentions
    // the marker is an ORDINARY SUCCESS; a payload-wide match would call it pending
    // (HoldingAreaStore.ts:75-78). This is the test that tells the two implementations
    // apart — a substring check passes the test above and fails this one.
    test("the marker inside a reason string is an ordinary success", () async {
      adapter.handlers["POST /api/tasks/t2/transition"] = (_) => jsonBody({
        "status": "ok",
        "reason": "demoted because it was awaiting_human_approval for a week",
      });

      await repo.transition(id: "t2", verb: TaskVerb.approve());   // must not throw
    });

    test("an ordinary 200 resolves", () async {
      adapter.handlers["POST /api/tasks/t3/transition"] = (_) => jsonBody({"status": "ok"});
      await repo.transition(id: "t3", verb: TaskVerb.approve());
    });
  });

  group("id encoding", () {
    // TaskListStore.ts:275-280 — a raw and an encoded id are byte-identical until the id
    // carries / ? or #, at which point the request silently lands on a DIFFERENT ROUTE.
    // That store shipped without it once. The spec says to drive it with this exact id.
    const nasty = "a/b?c#d";

    test("the transition door encodes the id", () async {
      final path = "/api/tasks/${TaskWriteRepository.encodeId(nasty)}/transition";
      adapter.handlers["POST $path"] = (_) => jsonBody({"status": "ok"});

      await repo.transition(id: nasty, verb: TaskVerb.approve());

      expect(adapter.captured.single.path, contains("a%2Fb%3Fc%23d"));
      expect(adapter.captured.single.path, isNot(contains("a/b?c#d")));
    });

    test("the field door encodes the id", () async {
      final path = "/api/tasks/${TaskWriteRepository.encodeId(nasty)}";
      adapter.handlers["PATCH $path"] = (_) => jsonBody({"status": "ok"});

      await repo.patchFields(id: nasty, priority: "P1");

      expect(adapter.captured.single.path, contains("a%2Fb%3Fc%23d"));
    });
  });

  group("two doors, not interchangeable", () {
    // ⇒ APPROVE IS A STATUS CHANGE. A builder implementing it as PATCH {status:"queued"}
    // gets a field door silently ignoring an unknown key — a Holding Area that looks
    // wired and changes nothing. patchFields takes two named parameters and no map, so
    // that mistake cannot be expressed; this pins the intent.
    test("the field door sends only the two addressable keys, never status", () async {
      adapter.handlers["PATCH /api/tasks/t1"] = (opts) {
        final body = opts.data as Map;
        expect(body.containsKey("status"), isFalse);
        expect(body["priority"],      "P2");
        expect(body["owner_persona"], "sam");
        return jsonBody({"status": "ok"});
      };
      await repo.patchFields(id: "t1", priority: "P2", ownerPersona: "sam");
    });

    test("an omitted field is not sent, so it cannot clobber", () async {
      adapter.handlers["PATCH /api/tasks/t1"] = (opts) {
        expect((opts.data as Map).containsKey("owner_persona"), isFalse);
        return jsonBody({"status": "ok"});
      };
      await repo.patchFields(id: "t1", priority: "P2");
    });

    test("changing nothing is a caller bug, not a round-trip", () {
      expect(() => repo.patchFields(id: "t1"), throwsArgumentError);
    });
  });

  group("provenance", () {
    // authority "user_direct" IS NOT DECORATION — the store's audit trail keys
    // provenance off it, and anything weaker makes an operator's decision read as
    // automation (HoldingAreaStore.ts:302-305).
    test("both doors carry authority: user_direct", () async {
      adapter.handlers["POST /api/tasks/t1/transition"] = (opts) {
        expect((opts.data as Map)["authority"], "user_direct");
        return jsonBody({"status": "ok"});
      };
      adapter.handlers["PATCH /api/tasks/t1"] = (opts) {
        expect((opts.data as Map)["authority"], "user_direct");
        return jsonBody({"status": "ok"});
      };

      await repo.transition(id: "t1", verb: TaskVerb.approve());
      await repo.patchFields(id: "t1", priority: "P1");
    });
  });

  group("the seven verbs — the four things no summary carries", () {
    // 1. park sends park_reason, NOT reason. One verb out of five uses a different key
    //    for the same text box (taskVerbs.ts:301).
    test("park sends park_reason, not reason", () {
      final v = TaskVerb.park(parkReason: "waiting on Rick");
      expect(v.payload["park_reason"], "waiting on Rick");
      expect(v.payload.containsKey("reason"), isFalse);
      expect(v.payload["to_status"], "parked");
    });

    // 2. unpark sends an EXPLICIT null. Omitting the key is a different request and only
    //    one of them clears (taskVerbs.ts:304-313). Rick ruled this — row 03d3bf78 — a
    //    surviving chase date re-chases him about a row already back on his board.
    test("unpark sends an explicit null next_chase_ts, not an omitted key", () {
      final v = TaskVerb.unpark();
      expect(v.payload.containsKey("next_chase_ts"), isTrue);
      expect(v.payload["next_chase_ts"], isNull);
    });

    // 3. fixed is refused without a receipt (taskVerbs.ts:315-319). The multiplexer
    //    shipped this exact bug once (709128d4) and every Fixed press was refused.
    test("fixed carries a receipt and sends no reason", () {
      final v = TaskVerb.fixed(operatorAttestation: "Rick says so");
      expect((v.payload["receipt_refs"] as Map)["operator_attestation"], "Rick says so");
      expect(v.payload.containsKey("reason"), isFalse);
      expect(v.payload["to_status"], "done");
    });

    test("approve is a status change with to_status queued", () {
      expect(TaskVerb.approve().payload["to_status"], "queued");
    });

    test("terminal verbs are marked so the row can arm them", () {
      expect(TaskVerb.wontFix(reason: "no").terminal, isTrue);
      expect(TaskVerb.fixed(operatorAttestation: "x").terminal, isTrue);
      expect(TaskVerb.approve().terminal, isFalse);
      expect(TaskVerb.park(parkReason: "x").terminal, isFalse);
    });

    // 4. Five verbs share one reason box and must not share one complaint —
    //    "'A reason is required' is true of four of them and teaches none of them"
    //    (taskVerbs.ts:160-165).
    test("each reason-taking verb gets its own prompt", () {
      final prompts = ["park", "demote", "drop", "wont_fix"]
          .map(TaskVerb.reasonPrompt)
          .toList();
      expect(prompts.toSet().length, 4, reason: "one prompt for all of them teaches none");
    });
  });
}
