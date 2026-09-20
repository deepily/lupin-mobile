import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet/data/task_row_model.dart';
import 'package:lupin_mobile/features/task_list/data/task_list_model.dart';

import '../../_helpers/fixture_loader.dart';

TaskRowModel _row({
  String id = "t1",
  String title = "a title",
  String status = "queued",
  String? priority = "P2",
  String? owner = "sam",
}) =>
    TaskRowModel(
      id: id, title: title, status: status, priority: priority, ownerPersona: owner,
    );

List<TaskRowModel> _fixtureRows(String name) =>
    (loadFixture("tasks/$name")["tasks"] as List)
        .cast<Map<String, dynamic>>()
        .map(TaskRowModel.fromJson)
        .toList();

void main() {
  group("ordering — PRIORITY FIRST (Rick's ruling, 2026-09-09)", () {
    // 🔴 THE PLAN AND THIS PHASE'S ROW BOTH SAY "status-rank then priority-rank", AND
    // BOTH ARE DESCRIBING THE CODE AS IT WAS BEFORE RICK CORRECTED IT. taskListModel.ts
    // :286-289 records the correction verbatim: "obviously it's going to be priority
    // first, but I also want to make sure that this is implemented for both clients."
    // He had reported seeing a P2 above a P0.
    //
    // This is the test that tells the two rules apart. Under status-first the blocked P1
    // leads; under priority-first the queued P0 does.
    test("a queued P0 outranks a blocked P1", () {
      final rows = [
        _row(id: "blocked-p1", status: "blocked", priority: "P1"),
        _row(id: "queued-p0",  status: "queued",  priority: "P0"),
      ];
      final group = groupTasksByOwner(rows).groups.single;
      expect(group.tasks.map((t) => t.id), ["queued-p0", "blocked-p1"]);
    });

    test("status breaks a priority tie", () {
      final rows = [
        _row(id: "queued",  status: "queued",  priority: "P1"),
        _row(id: "blocked", status: "blocked", priority: "P1"),
      ];
      final group = groupTasksByOwner(rows).groups.single;
      expect(group.tasks.map((t) => t.id), ["blocked", "queued"]);
    });

    test("title breaks a priority-and-status tie, case-insensitively", () {
      final rows = [
        _row(id: "b", title: "beta",  priority: "P1"),
        _row(id: "a", title: "Alpha", priority: "P1"),
      ];
      expect(groupTasksByOwner(rows).groups.single.tasks.map((t) => t.id), ["a", "b"]);
    });

    test("an unknown priority sorts last, not first", () {
      final rows = [
        _row(id: "none", priority: null),
        _row(id: "p3",   priority: "P3"),
      ];
      expect(groupTasksByOwner(rows).groups.single.tasks.map((t) => t.id), ["p3", "none"]);
    });
  });

  group("status ranks", () {
    // ⚠️ wont_fix IS 9, AND ITS ABSENCE WAS A REAL BUG — it fell through to the unknown
    // rank and sorted ABOVE done and dropped, so a closed-as-will-not-do row rendered as
    // more urgent than a finished one.
    test("wont_fix ranks below done, not above it", () {
      expect(statusRank("wont_fix"), greaterThan(statusRank("done")));
    });

    // The gap at 7 is load-bearing: a typo'd status must not hide above blocked work,
    // and must not hide below it either.
    test("an unknown status sits between open and terminal", () {
      expect(statusRank("typo"), greaterThan(statusRank("not_approved")));
      expect(statusRank("typo"), lessThan(statusRank("done")));
    });

    test("parked is open work, ranked below queued and above terminal", () {
      expect(statusRank("parked"), greaterThan(statusRank("queued")));
      expect(statusRank("parked"), lessThan(statusRank("done")));
      expect(isOpenStatus("parked"), isTrue);
    });

    test("not_approved is NOT terminal", () {
      expect(isOpenStatus("not_approved"), isTrue);
    });
  });

  group("terminal rows are FILTERED, not sorted to the bottom", () {
    // 🔴 Rick, correcting the author: "when something gets marked as done it actually
    // literally gets removed from the task list. It is then displayed within the finished
    // list, by order of what's finished." Both web renderers filter before sorting.
    // Sorting them last would leave finished work in a pane meant to hold only what is
    // owed.
    test("done, dropped and wont_fix never reach the pane", () {
      final rows = [
        _row(id: "open",     status: "queued"),
        _row(id: "done",     status: "done"),
        _row(id: "dropped",  status: "dropped"),
        _row(id: "wont_fix", status: "wont_fix"),
      ];
      final model = groupTasksByOwner(rows);
      expect(model.groups.single.tasks.map((t) => t.id), ["open"]);
      expect(model.totalCount, 1, reason: "totalCount counts admitted rows, not input");
    });

    test("a group that is entirely terminal disappears rather than rendering empty", () {
      final model = groupTasksByOwner([_row(id: "d", status: "done")]);
      expect(model.groups, isEmpty);
    });
  });

  group("grouping", () {
    test("groups by owner_persona, NOT accountable_manager", () {
      final rows = [
        const TaskRowModel(
          id: "t1", title: "t", status: "queued",
          ownerPersona: "sam", accountableManager: "tiffany",
        ),
      ];
      expect(groupTasksByOwner(rows).groups.single.ownerPersona, "sam");
    });

    test("groups sort alphabetically and Unassigned is always LAST", () {
      final rows = [
        _row(id: "z", owner: "zoe"),
        _row(id: "u", owner: null),
        _row(id: "a", owner: "aaron"),
        _row(id: "m", owner: "mia"),
      ];
      final groups = groupTasksByOwner(rows).groups;
      expect(groups.map((g) => g.ownerPersona), ["aaron", "mia", "zoe", null]);
      expect(groups.last.isUnassigned, isTrue);
    });

    // Rachel's data pattern #1: two-word personas. A grouping key is a Map key and a
    // sort key, and a space in it must not split or reorder a group.
    test("a two-word persona is ONE group, ordered on its whole name", () {
      final rows = [
        _row(id: "r1", owner: "Mr. Radio"),
        _row(id: "r2", owner: "Mr. Radio"),
        _row(id: "s1", owner: "Sam"),
      ];
      final groups = groupTasksByOwner(rows).groups;
      expect(groups.map((g) => g.ownerPersona), ["Mr. Radio", "Sam"]);
      expect(groups.first.tasks.length, 2);
    });

    // Rachel's data pattern #2: an actor with no session id. Whether the string carries
    // a trailing hash must not create two groups for one persona.
    test("owner strings are grouped exactly, hash or no hash", () {
      final rows = [
        _row(id: "a", owner: "tiffany"),
        _row(id: "b", owner: "tiffany cc9c1f1a"),
      ];
      final groups = groupTasksByOwner(rows).groups;
      expect(groups.length, 2,
          reason: "these are DIFFERENT owner strings — the pane must not silently "
                  "merge them, and if the server is sending both forms that is a "
                  "server-side question, not something to paper over here");
    });

    test("a blank owner is Unassigned, not a group named empty-string", () {
      final rows = [_row(id: "a", owner: "   "), _row(id: "b", owner: null)];
      final groups = groupTasksByOwner(rows).groups;
      expect(groups.single.isUnassigned, isTrue);
      expect(groups.single.tasks.length, 2);
    });

    test("an empty input is an empty model, not a throw", () {
      final model = groupTasksByOwner(const []);
      expect(model.groups, isEmpty);
      expect(model.totalCount, 0);
    });
  });

  group("against real captured rows", () {
    test("a real terse page groups and orders without throwing", () {
      final model = groupTasksByOwner(_fixtureRows("task_list_terse.json"));
      expect(model.groups, isNotEmpty);

      // Unassigned last, if present at all.
      final unassignedAt = model.groups.indexWhere((g) => g.isUnassigned);
      if (unassignedAt != -1) {
        expect(unassignedAt, model.groups.length - 1);
      }

      // Every group's rows are in comparator order.
      for (final g in model.groups) {
        final sorted = [...g.tasks]..sort(compareByUrgency);
        expect(g.tasks.map((t) => t.id), sorted.map((t) => t.id));
      }
    });

    test("the Holding Area's not_approved rows are OPEN and survive the filter", () {
      final model = groupTasksByOwner(_fixtureRows("holding_area.json"));
      expect(model.totalCount, greaterThan(0),
          reason: "not_approved is not terminal — filtering it out would empty the pane");
    });
  });
}
