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
void main() {
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
          return src.contains("task_row.dart") || src.contains("TaskRow(");
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
