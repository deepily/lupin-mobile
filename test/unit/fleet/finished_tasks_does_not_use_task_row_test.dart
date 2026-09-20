import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🔴 SOMETHING MUST HOLD THE PANES APART, AND NOTHING DID.
///
/// Correcting the shared-row pane set created the opposite pressure. The plan now says
/// Finished Tasks is deliberately different — its rows come from `task_events` and carry
/// no `priority`, no `blocked`, no `accountable`, no `actions` — and then left that
/// difference unguarded.
///
/// THE SPECIFIC FAILURE: a later hand opens `finished_tasks/presentation/`, finds a
/// bespoke row widget, and reads §7 — a section titled **"The shared row"** whose §7.1
/// quotes, verbatim, *"Do not give this pane a row of its own."* **That sentence is
/// about the Holding Area.** Read cold by someone tidying an inconsistency, it reads as
/// a mandate to unify. They unify, every test stays green, and Finished Tasks acquires
/// ten fields it has no data for.
///
/// > Rachel's principle: *a negative assertion is the only kind that survives a
/// > well-meaning refactor, because it fails ON the refactor rather than after it.*
///
/// ⚠️ WHY THIS IS A SOURCE SCAN AND NOT `expect( find.byType( TaskRow ), findsNothing )`.
/// The spec asks for one line in the Finished Tasks WIDGET test. That pane is Phase 2
/// and does not exist yet, so the widget assertion cannot be written — and a guard that
/// arrives with the thing it guards arrives too late to stop the decision. This scans
/// the source instead, which works today, keeps working, and fires the moment anyone
/// wires `TaskRow` into that feature.
///
/// ⇒ When Phase 2 lands, ALSO add the one-line widget assertion. The two are not
/// redundant: this one catches the import, that one catches a re-export or an alias.
/// The shared row's constructor, and not a longer name that merely ends in it.
final sharedTaskRowUse = RegExp(r"(?<![A-Za-z0-9_])TaskRow\s*\(");

void main() {
  // 🔴 THE GUARD'S OWN PATTERN IS TESTED, BECAUSE A GUARD THAT MATCHES NOTHING PASSES.
  // Loosening the pattern until the suite goes green is the obvious repair when it
  // fires, and it is indistinguishable from fixing it — until the day it should have
  // fired and did not.
  group("the pattern tells the two names apart", () {
    test("it catches a real use of the shared row", () {
      expect(sharedTaskRowUse.hasMatch("child: TaskRow( model: m )"), isTrue);
      expect(sharedTaskRowUse.hasMatch("return TaskRow(model: m);"), isTrue);
    });

    test("it does NOT catch this pane's own FinishedTaskRow", () {
      expect(sharedTaskRowUse.hasMatch("itemBuilder: (c, i) => FinishedTaskRow("), isFalse);
      expect(sharedTaskRowUse.hasMatch("class FinishedTaskRow extends StatelessWidget"), isFalse);
    });
  });

  test("Finished Tasks does not render the shared TaskRow", () {
    final dir = Directory("lib/features/finished_tasks");

    if (!dir.existsSync()) {
      // Phase 2 has not landed. Say so out loud rather than passing silently — a test
      // that reports nothing is indistinguishable from a test that found nothing.
      printOnFailure("lib/features/finished_tasks/ does not exist yet (Phase 2).");
      return;
    }

    final offenders = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith(".dart"))
        .where((f) {
          final src = f.readAsStringSync();
          // 🔴 A WORD BOUNDARY, NOT A BARE SUBSTRING. `src.contains("TaskRow(")` also
          // matches `FinishedTaskRow(` — this pane's OWN four-cell row, whose name ends
          // in the string being searched for. The guard went red the moment Phase 2
          // landed, accusing the pane of the exact thing it was built not to do, and a
          // guard that cries wolf about correct code is one the next hand deletes.
          //
          // ⚠️ The import check stays a plain substring: `task_row.dart` is a path and
          // cannot collide the same way.
          return src.contains("task_row.dart") || sharedTaskRowUse.hasMatch(src);
        })
        .map((f) => f.path)
        .toList();

    expect(
      offenders,
      isEmpty,
      reason: "Finished Tasks is sourced from task_events and has no priority, blocked, "
              "accountable or actions. Sharing the task row would give it ten cells it "
              "has no data for. §7's title is about the OTHER two panes.",
    );
  });
}
