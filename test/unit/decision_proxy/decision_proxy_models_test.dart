import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/decision_proxy/data/decision_proxy_models.dart';

void main() {
  group("trustModeFromString / toString", () {
    test("known values round-trip", () {
      for (final s in const ["disabled", "shadow", "suggest", "active"]) {
        expect(trustModeToString(trustModeFromString(s)), s);
      }
    });
    test("unknown value", () {
      expect(trustModeFromString("nope"),    TrustMode.unknown);
      expect(trustModeFromString(null),      TrustMode.unknown);
    });
  });

  group("ProxyDecision.fromJson", () {
    test("parses full record", () {
      final d = ProxyDecision.fromJson({
        "id"                 : "d-1",
        "notification_id"    : "n-1",
        "domain"             : "swe",
        "category"           : "code_review",
        "question"           : "Approve?",
        "sender_id"          : "claude.code@x",
        "action"             : "act",
        "decision_value"     : true,
        "confidence"         : 0.9,
        "trust_level"        : 3,
        "reason"             : "high confidence",
        "ratification_state" : "pending",
        "data_origin"        : "organic",
        "created_at"         : "2026-04-15T12:00:00Z",
      });
      expect(d.id,                "d-1");
      expect(d.confidence,        0.9);
      expect(d.trustLevel,        3);
      expect(d.ratificationState, "pending");
    });

    test("defaults", () {
      final d = ProxyDecision.fromJson({
        "id": "d-2", "domain": "swe", "category": "x",
        "question": "?", "action": "shadow",
        "reason": "", "data_origin": "organic",
      });
      expect(d.confidence,        0.0);
      expect(d.trustLevel,        1);
      expect(d.ratificationState, "pending");
    });
  });

  group("PendingSummary.fromJson", () {
    test("parses category + trust maps", () {
      final s = PendingSummary.fromJson({
        "total_pending": 5,
        "by_category"  : {"testing": 3, "refactor": 2},
        "by_trust_level": {"L1": 4, "L2": 1},
        "oldest_pending": "2026-04-15T10:00:00Z",
      });
      expect(s.totalPending,       5);
      expect(s.byCategory["testing"], 3);
      expect(s.byTrustLevel["L1"],    4);
      expect(s.oldestPending!.hour,   10);
    });

    test("missing maps default to empty", () {
      final s = PendingSummary.fromJson({"total_pending": 0});
      expect(s.byCategory,    isEmpty);
      expect(s.byTrustLevel,  isEmpty);
      expect(s.oldestPending, isNull);
    });
  });

  group("TrustModeStatus.fromJson", () {
    test("parses ini + running + effective", () {
      final m = TrustModeStatus.fromJson({
        "status": "success",
        "ini_mode": "shadow",
        "running_mode": "active",
        "effective": "active",
        "has_running_job": true,
      });
      expect(m.iniMode,       TrustMode.shadow);
      expect(m.runningMode,   TrustMode.active);
      expect(m.effective,     TrustMode.active);
      expect(m.hasRunningJob, isTrue);
    });

    test("null running_mode preserved", () {
      final m = TrustModeStatus.fromJson({
        "status": "success", "ini_mode": "disabled",
        "running_mode": null, "effective": "disabled",
        "has_running_job": false,
      });
      expect(m.runningMode, isNull);
    });
  });

  group("TrustModeUpdateRequest.toJson", () {
    test("default domain swe", () {
      final body = const TrustModeUpdateRequest(mode: TrustMode.active).toJson();
      expect(body["mode"],   "active");
      expect(body["domain"], "swe");
    });
  });
}
