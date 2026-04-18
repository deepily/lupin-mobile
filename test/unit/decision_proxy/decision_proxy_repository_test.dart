import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/decision_proxy/data/decision_proxy_models.dart';
import 'package:lupin_mobile/features/decision_proxy/data/decision_proxy_repository.dart';

import '../../_helpers/fixture_loader.dart';
import '../_helpers/stub_dio.dart';

void main() {
  group("DecisionProxyRepository", () {
    late StubAdapter adapter;
    late DecisionProxyRepository repo;

    setUp(() {
      adapter = StubAdapter();
      repo = DecisionProxyRepository(makeDio(adapter));
    });

    test("getMode parses TrustModeStatus from real backend shape", () async {
      // Fixture captured via src/scripts/capture-decision-proxy-fixtures.py.
      adapter.handlers["GET /api/proxy/mode"] =
        (_) => jsonBodyFromFixture("decision_proxy/mode.json");
      final m = await repo.getMode();
      // Whatever the real backend currently returns — capture a property the
      // parser must handle (effective is always a valid TrustMode).
      expect(m.effective,     isA<TrustMode>());
      expect(m.hasRunningJob, isA<bool>());
    });

    test("setMode posts request body and parses queued response", () async {
      adapter.handlers["PUT /api/proxy/mode"] = (opts) {
        expect((opts.data as Map)["mode"],   "active");
        expect((opts.data as Map)["domain"], "swe");
        return jsonBody({
          "status": "queued", "old_mode": "shadow", "new_mode": "active",
          "target": "next_job", "message": "Will apply on next job",
        });
      };
      final r = await repo.setMode(const TrustModeUpdateRequest(
        mode: TrustMode.active,
      ));
      expect(r.status,  "queued");
      expect(r.oldMode, TrustMode.shadow);
      expect(r.newMode, TrustMode.active);
      expect(r.target,  "next_job");
    });

    test("pending forwards filters and parses real fixture envelope", () async {
      adapter.handlers["GET /api/proxy/pending/u@x.y"] = (opts) {
        // Still verify query-param forwarding — fixture only covers the
        // response shape, not the request shape.
        expect(opts.queryParameters["domain"],   "swe");
        expect(opts.queryParameters["category"], "code_review");
        expect(opts.queryParameters["limit"],    25);
        return jsonBodyFromFixture("decision_proxy/pending.json");
      };
      final r = await repo.pending(
        "u@x.y", domain: "swe", category: "code_review", limit: 25,
      );
      expect(r.decisions, isNotEmpty);
      expect(r.decisions.first.id, startsWith("decision-fixture-"));
      // Summary and decision-count must agree (sanity, not capture-specific).
      expect(r.summary.totalPending, greaterThanOrEqualTo(r.decisions.length));
    });

    test("ratify forwards approved + feedback as query", () async {
      adapter.handlers["POST /api/proxy/ratify/d-1"] = (opts) {
        expect(opts.queryParameters["user_email"], "u@x.y");
        expect(opts.queryParameters["approved"],   true);
        expect(opts.queryParameters["feedback"],   "looks good");
        return jsonBody({
          "status": "success", "decision_id": "d-1",
          "ratification_state": "approved", "ratified_by": "u@x.y",
          "ratified_at": "2026-04-15T12:00:00Z", "feedback": "looks good",
          "domain": "swe", "category": "code_review",
        });
      };
      final r = await repo.ratify(
        "d-1", userEmail: "u@x.y", approved: true, feedback: "looks good",
      );
      expect(r.ratificationState, "approved");
      expect(r.feedback,          "looks good");
    });

    test("acknowledge parses retired + new batch from fixture", () async {
      adapter.handlers["POST /api/proxy/acknowledge"] =
        (_) => jsonBodyFromFixture("decision_proxy/acknowledge.json");
      final r = await repo.acknowledge();
      // Both batch IDs should be non-empty "pr-..." strings.
      expect(r.retiredBatch, startsWith("pr-"));
      expect(r.newBatch,     startsWith("pr-"));
      expect(r.retiredBatch, isNot(r.newBatch));
    });

    test("404 maps to DecisionProxyApiException", () async {
      adapter.handlers["DELETE /api/proxy/decision/missing"] = (_) =>
        jsonBody({"detail": "no such decision"}, status: 404);
      await expectLater(
        repo.deleteDecision("missing", userEmail: "u@x.y"),
        throwsA(isA<DecisionProxyApiException>()
          .having((e) => e.statusCode, "statusCode", 404)),
      );
    });

    test("trustState passes optional domain filter + parses envelope", () async {
      adapter.handlers["GET /api/proxy/trust/u@x.y"] = (opts) {
        expect(opts.queryParameters["domain"], "swe");
        return jsonBodyFromFixture("decision_proxy/trust_state.json");
      };
      // Captured fixture may have zero states (fresh test user) — we just
      // verify the envelope parses without throwing.
      final r = await repo.trustState("u@x.y", domain: "swe");
      expect(r.trustStates, isA<List<dynamic>>());
    });
  });
}
