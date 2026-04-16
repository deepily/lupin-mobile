import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/decision_proxy/data/decision_proxy_models.dart';
import 'package:lupin_mobile/features/decision_proxy/data/decision_proxy_repository.dart';
import 'package:lupin_mobile/features/decision_proxy/domain/decision_proxy_bloc.dart';
import 'package:lupin_mobile/features/decision_proxy/domain/decision_proxy_event.dart';
import 'package:lupin_mobile/features/decision_proxy/domain/decision_proxy_state.dart';

import '../_helpers/stub_dio.dart';

void main() {
  group("DecisionProxyBloc", () {
    late StubAdapter adapter;
    late DecisionProxyRepository repo;

    setUp(() {
      adapter = StubAdapter();
      repo = DecisionProxyRepository(makeDio(adapter));
    });

    blocTest<DecisionProxyBloc, DecisionProxyState>(
      "LoadDashboard fetches mode + pending + batch",
      setUp: () {
        adapter.handlers["GET /api/proxy/mode"] = (_) => jsonBody({
          "status": "success", "ini_mode": "shadow", "running_mode": null,
          "effective": "shadow", "has_running_job": false,
        });
        adapter.handlers["GET /api/proxy/pending/u@x.y"] = (_) => jsonBody({
          "status": "success",
          "decisions": [{
            "id": "d-1", "domain": "swe", "category": "code_review",
            "question": "?", "action": "act", "confidence": 0.9,
            "trust_level": 3, "reason": "", "ratification_state": "pending",
            "data_origin": "organic",
          }],
          "summary": {
            "total_pending": 1, "by_category": {"code_review": 1},
            "by_trust_level": {"L3": 1}, "oldest_pending": null,
          },
        });
        adapter.handlers["GET /api/proxy/batch-id"] = (_) => jsonBody({
          "status": "success", "batch_id": "pr-aaaaaaaa-1",
        });
      },
      build  : () => DecisionProxyBloc(repo),
      act    : (b) => b.add(const DecisionProxyLoadDashboard("u@x.y")),
      expect : () => [
        isA<DecisionProxyLoading>(),
        isA<DecisionProxyDashboardLoaded>()
          .having((s) => s.mode.effective,        "mode",     TrustMode.shadow)
          .having((s) => s.pending.length,         "pending",  1)
          .having((s) => s.summary.totalPending,   "summary",  1)
          .having((s) => s.batch?.batchId,         "batch",    "pr-aaaaaaaa-1"),
      ],
    );

    blocTest<DecisionProxyBloc, DecisionProxyState>(
      "Ratify reloads dashboard",
      setUp: () {
        var pendingHits = 0;
        adapter.handlers["POST /api/proxy/ratify/d-1"] = (_) => jsonBody({
          "status": "success", "decision_id": "d-1",
          "ratification_state": "approved", "ratified_by": "u@x.y",
          "feedback": "ok", "domain": "swe", "category": "code_review",
        });
        adapter.handlers["GET /api/proxy/mode"] = (_) => jsonBody({
          "status": "success", "ini_mode": "active",
          "running_mode": null, "effective": "active",
          "has_running_job": false,
        });
        adapter.handlers["GET /api/proxy/pending/u@x.y"] = (_) {
          pendingHits++;
          return jsonBody({
            "status": "success",
            "decisions": [],
            "summary": {
              "total_pending": 0, "by_category": {}, "by_trust_level": {},
              "oldest_pending": null,
            },
          });
        };
        adapter.handlers["GET /api/proxy/batch-id"] = (_) => jsonBody({
          "status": "success", "batch_id": "pr-bbbbbbbb-1",
        });
      },
      build  : () => DecisionProxyBloc(repo),
      act    : (b) => b.add(const DecisionProxyRatify(
        decisionId: "d-1", userEmail: "u@x.y", approved: true, feedback: "ok",
      )),
      wait   : const Duration(milliseconds: 200),
      verify : (b) {
        expect(b.state, isA<DecisionProxyDashboardLoaded>());
      },
    );

    blocTest<DecisionProxyBloc, DecisionProxyState>(
      "API error emits DecisionProxyError",
      setUp: () {
        adapter.handlers["GET /api/proxy/mode"] = (_) =>
          jsonBody({"detail": "down"}, status: 503);
      },
      build  : () => DecisionProxyBloc(repo),
      act    : (b) => b.add(const DecisionProxyLoadDashboard("u@x.y")),
      expect : () => [
        isA<DecisionProxyLoading>(),
        isA<DecisionProxyError>().having((s) => s.message, "message", "down"),
      ],
    );
  });
}
