import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet/data/task_row_model.dart';
import 'package:lupin_mobile/features/fleet/data/task_row_schema.dart';

import '../../_helpers/fixture_loader.dart';

/// Rows from a fixture captured off the real `/api/tasks`, never hand-written.
///
/// 🔴 A HAND-WRITTEN ROW CAN ONLY CONFIRM WHAT ITS AUTHOR ALREADY BELIEVED. Twelve cells,
/// most of them independently nullable — a stub would have every field populated, the
/// mapper would pass, and the first real row with an unexpected null would be the thing
/// that found the bug. Re-capture with `src/scripts/capture-tasks-fixtures.py`;
/// `test/fixtures/README.md` records the incident that established the pattern.
List<Map<String, dynamic>> _rows( String fixture ) =>
    (loadFixture("tasks/$fixture")["tasks"] as List).cast<Map<String, dynamic>>();

void main() {
  group("RowSchema", () {
    // §10 tier 1: "one pinning ROW_SCHEMA's field list so a silent reorder goes red".
    //
    // The two task panes are required to be cell-for-cell identical, and the identity
    // guard compares ORDERED key lists. A reorder here would therefore keep both panes
    // matching each other while silently changing what every row looks like — which is
    // exactly the kind of change that should require a deliberate edit to a test.
    test("pins the ordered field list", () {
      expect(RowSchema.keys, [
        "title",
        "id", "class", "status", "priority",
        "blocked", "chase", "accountable", "filer", "project",
        "detail", "actions",
      ]);
    });

    // 🔴 The web packs id/class/status/priority onto line 1. At 360 dp that leaves ~86 dp
    // for the title — about twelve characters — and every title in this fleet shares a
    // "[LUPIN-MOBILE] Phase N:" prefix, so all of them truncate to the SAME string.
    test("line 1 is the title alone, because five fields do not survive 360 dp", () {
      expect(RowSchema.line1.map((c) => c.key), ["title"]);
    });

    // Carrying rowWidth()'s lesson from rowSchema.ts:57-71 — "a stale colspan does not
    // look broken". A hand-written count goes wrong silently the first time a cell is
    // added; this asserts the count is derived from the list rather than typed.
    test("cellCount is derived, not hand-written", () {
      expect(RowSchema.cellCount, RowSchema.all.length);
      expect(RowSchema.cellCount, 12);
    });

    test("every cell key is unique", () {
      expect(RowSchema.keys.toSet().length, RowSchema.keys.length);
    });
  });

  group("TaskRowModel — against captured /api/tasks rows", () {
    test("maps every row of a real FULL page without throwing", () {
      final rows = _rows("task_list_full.json");
      expect(rows, isNotEmpty, reason: "an empty fixture would assert nothing");

      for (final raw in rows) {
        final m = TaskRowModel.fromJson(raw);
        // The cells the full projection always carries.
        expect(m.id,     isNotEmpty);
        expect(m.status, isNotEmpty);
        // Every schema key must be addressable, populated or not.
        for (final key in RowSchema.keys) {
          expect(() => m.cell(key), returnsNormally, reason: "cell($key) threw");
        }
      }
    });

    // ⚠️ THE PANES PULL TERSE ON PURPOSE — ~107 KB against ~2.1 MB for 500 full rows
    // (tasks.py:739). Measured against the captured pages, the terse projection OMITS
    // twelve keys outright, two of which the row renders: `body` (dropped deliberately —
    // it is the multi-KB field that makes rows heavy) and `item_class` (a genuine gap in
    // the projection, tracked lupin-side).
    //
    // They arrive as ABSENT KEYS, not nulls. A pane that threw on its own specified query
    // shape would be a pane that never ran.
    test("a real TERSE row omits detail and class WITHOUT throwing", () {
      final rows = _rows("task_list_terse.json");
      expect(rows, isNotEmpty);

      // The capture proves the premise rather than assuming it.
      expect(rows.first.containsKey("body"),       isFalse);
      expect(rows.first.containsKey("item_class"), isFalse);

      for (final raw in rows) {
        final m = TaskRowModel.fromJson(raw);
        expect(m.cell("detail"), isNull);
        expect(m.cell("class"),  isNull);
        expect(m.cell("id"),     isNotEmpty);
      }
    });

    // 🔴 THE NULLS ARE THE REASON THIS FIXTURE IS CAPTURED AND NOT TYPED. The capture's
    // own null census reported `next_chase_ts`, `park_reason`, `request_state`,
    // `request_move` and `source_qid` null in at least one real row. A stub written by
    // hand would have populated all of them.
    test("real rows carry nulls, and the mapper survives every one", () {
      final rows = _rows("task_list_full.json");
      final withNullChase = rows.where((r) => r["next_chase_ts"] == null);

      expect(withNullChase, isNotEmpty,
          reason: "if no row is null here the fixture has stopped being representative "
                  "— widen the capture rather than weakening the test");

      for (final raw in withNullChase) {
        expect(TaskRowModel.fromJson(raw).cell("chase"), isNull);
      }
    });

    test("the Holding Area's not_approved rows map the same way", () {
      for (final raw in _rows("holding_area.json")) {
        expect(TaskRowModel.fromJson(raw).status, "not_approved");
      }
    });

    // §10 tier 3: an empty `not_approved` result is not an error. The fixture is a real
    // 200 with zero rows, captured from a filter that matches nothing.
    test("an empty result is an empty list, not an error", () {
      final body = loadFixture("tasks/holding_area_empty.json");
      expect(body["tasks"], isEmpty);
      expect(body["total"], 0);
      expect(_rows("holding_area_empty.json").map(TaskRowModel.fromJson), isEmpty);
    });

    // §10 tier 3 again: truncated / total / has_more must be READ, not ignored. Captured
    // live, the terse page reports total 16 against a limit of 8 — so `has_more` is
    // genuinely true here rather than a value I chose.
    test("the envelope carries truncated, total and has_more", () {
      final body = loadFixture("tasks/task_list_terse.json");
      expect(body.containsKey("truncated"), isTrue);
      expect(body.containsKey("total"),     isTrue);
      expect(body.containsKey("has_more"),  isTrue);
      expect(body["has_more"], isTrue, reason: "captured against a page smaller than the "
                                               "matching set, so this is real");
    });

    // next_chase_ts is operator-set and has arrived malformed before. One bad date must
    // not take down a 500-row pane. No captured row is malformed — which is why this one
    // case stays synthetic, and says so.
    test("an unparseable next_chase_ts is null, not a throw", () {
      final real = Map<String, dynamic>.from(_rows("task_list_full.json").first)
        ..["next_chase_ts"] = "not-a-date";
      expect(TaskRowModel.fromJson(real).nextChaseTs, isNull);
    });
  });
}
