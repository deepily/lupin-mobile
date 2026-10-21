---
capability: task-verbs-and-write-repository
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.fleet.data.task_row_model.TaskBlocker@742a411c40
  - lupin-mobile:lib.features.fleet.data.task_row_schema.RowCell@7cd69e4b62
  - lupin-mobile:lib.features.fleet.data.task_verbs.verbNeeds@e201685d21
  - lupin-mobile:lib.features.fleet.data.task_verbs.verbLabel@9ed5e5cc58
  - lupin-mobile:lib.features.fleet.data.task_verbs.verbReasonComplaint@57d16e07f4
  - lupin-mobile:lib.features.fleet.data.task_verbs.verbDateComplaint@c96b086228
  - lupin-mobile:lib.features.fleet.data.task_verbs.VerbLegality@60af1cd419
  - lupin-mobile:lib.features.fleet.data.task_write_repository.TaskWriteException@cd282700b1
  - lupin-mobile:lib.features.fleet.presentation.pane_host_screen.PaneHostScreen@1f6963acab
  - lupin-mobile:lib.features.fleet.presentation.verb_reason_sheet.VerbReasonSheet@3c88febfb5
  - lupin-mobile:lib.features.fleet.presentation.verb_reason_sheet.showVerbReasonSheet@eba61e6e99
---
# Task verbs and the write repository

The verb table, small row models, write error and shared sheet behind [[task-row-and-verbs]].

## What it does
- `verbNeeds` returns a verb's obligations, or null for an unknown verb, `""` or null. `verbLabel` returns the verb itself when unknown.
- Four verbs need a reason: park, drop, demote and wont_fix. Park and demote also need a date, labelled `Chase me again on` and `Triage this by`. The terminal verbs are wont_fix and fixed. Fixed needs no reason and still opens the sheet.
- `verbReasonComplaint` has its own sentence for each reason verb and a generic one otherwise. `verbDateComplaint` has two: a park is bounded, and a held row is bounded.
- `VerbLegality` is one verb's standing on one row: enabled or not, its `VerbNeeds`, and why not. Park is enabled only from queued or in_progress, approve only on not_approved, un-park only on parked, and demote on every other open row.
- `TaskBlocker` is a typed `blocked_by` entry of kind `item`, `persona` or `user`; a missing field becomes empty. `RowCell` is a stable test key plus a label.
- `TaskWriteException` carries a message naming the operation and row, and the underlying error. A 202 is the separate `TaskAwaitingApprovalException`.
- `PaneHostScreen` wraps one pane in a Scaffold and builds its bloc from a factory, so the bloc lives and dies with the route.
- `VerbReasonSheet` is a bottom sheet shared by both panes, with no pane parameter. `showVerbReasonSheet` returns the built verb, or null on cancel, and needs a verb whose `needsSheet` is true.

## Don't
- Don't reorder `kTaskVerbs`. `fixed` sits between `wont_fix` and `unpark` to match every other client.
- Don't treat the sheet as the confirm. Terminal verbs arm in the row first.
