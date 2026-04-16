import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/decision_proxy/data/decision_proxy_models.dart';
import 'package:lupin_mobile/features/decision_proxy/data/decision_proxy_repository.dart';

import '../_helpers/stub_dio.dart';

void main() {
  group("DecisionProxyRepository", () {
    late StubAdapter adapter;
    late DecisionProxyRepository repo;

    setUp(() {
      adapter = StubAdapter();
      repo = DecisionProxyRepository(makeDio(adapter));
    });

    test("getMode parses TrustModeStatus", () async {
      adapter.handlers["GET /api/proxy/mode"] = (_) => jsonBody({
        "status": "success", "ini_mode": "shadow", "running_mode": null,
        "effective": "shadow", "has_running_job": false,
      });
      final m = await repo.getMode();
      expect(m.iniMode,       TrustMode.shadow);
      expect(m.hasRunningJob, isFalse);
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

    test("pending forwards filters and parses summary", () async {
      adapter.handlers["GET /api/proxy/pending/u@x.y"] = (opts) {
        expect(opts.queryParameters["domain"],   "swe");
        expect(opts.queryParameters["category"], "code_review");
        expect(opts.queryParameters["limit"],    25);
        return jsonBody({
          "status": "success",
          "decisions": [{
            "id": "d-1", "domain": "swe", "category": "code_review",
            "question": "?", "action": "act", "confidence": 0.9,
            "trust_level": 3, "reason": "", "ratification_state": "pending",
            "data_origin": "organic",
          }],
          "summary": {
            "total_pending": 1,
            "by_category": {"code_review": 1},
            "by_trust_level": {"L3": 1},
            "oldest_pending": "2026-04-15T09:00:00Z",
          },
        });
      };
      final r = await repo.pending(
        "u@x.y", domain: "swe", category: "code_review", limit: 25,
      );
      expect(r.decisions.single.id,        "d-1");
      expect(r.summary.totalPending,        1);
      expect(r.summary.byCategory["code_review"], 1);
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

    test("acknowledge parses retired + new batch", () async {
      adapter.handlers["POST /api/proxy/acknowledge"] = (_) => jsonBody({
        "status": "success",
        "retired_batch": "pr-aaaaaaaa-1",
        "new_batch":     "pr-aaaaaaaa-2",
      });
      final r = await repo.acknowledge();
      expect(r.retiredBatch, "pr-aaaaaaaa-1");
      expect(r.newBatch,     "pr-aaaaaaaa-2");
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

    test("trustState passes optional domain filter", () async {
      adapter.handlers["GET /api/proxy/trust/u@x.y"] = (opts) {
        expect(opts.queryParameters["domain"], "swe");
        return jsonBody({
          "status": "success", "user_email": "u@x.y",
          "trust_states": [{
            "id": "ts-1", "domain": "swe", "category": "code_review",
            "trust_level": 2, "total_decisions": 10,
            "successful_decisions": 8, "rejected_decisions": 2,
            "circuit_breaker_state": null,
            "created_at": "2026-04-01T00:00:00Z",
            "updated_at": "2026-04-15T00:00:00Z",
          }],
        });
      };
      final r = await repo.trustState("u@x.y", domain: "swe");
      expect(r.trustStates.single.trustLevel, 2);
      expect(r.trustStates.single.circuitBreakerState, isNull);
    });
  });
}
