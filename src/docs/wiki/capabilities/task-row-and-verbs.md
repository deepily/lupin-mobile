---
capability: task-row-and-verbs
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.fleet.data.task_row_model.TaskRowModel@aaa437a2dc
  - lupin-mobile:lib.features.fleet.data.task_row_schema.RowSchema@66acde2589
  - lupin-mobile:lib.features.fleet.presentation.task_row.TaskRow@334cfcf37e
  - lupin-mobile:lib.features.fleet.presentation.task_field_controls.TaskFieldControls@56faff02e3
  - lupin-mobile:lib.features.fleet.data.task_write_repository.TaskVerb@cb97457a54
  - lupin-mobile:lib.features.fleet.data.task_write_repository.TaskWriteRepository@d0b9918e32
  - lupin-mobile:lib.features.fleet.data.task_write_repository.TaskAwaitingApprovalException@f77ef8deb4
  - lupin-mobile:lib.features.fleet.domain.unsent_write.UnsentWrite@0b2cd7cedd
  - lupin-mobile:lib.features.fleet.data.task_verbs.VerbNeeds@6224e46647
  - lupin-mobile:lib.features.fleet.data.task_verbs.buildTaskVerb@dfdc85f530
  - lupin-mobile:lib.features.fleet.data.task_verbs.verbLegality@8eaaec35ca
  - lupin-mobile:lib.features.fleet.domain.unsent_write.retryUnsentWrites@1eb083c904
---
# Task row and verbs

The row widget, the seven status verbs and the write repository that Task List and Holding Area share. Finished Tasks does not use them.

## What it does
- `TaskRowModel` maps one `/api/tasks` row onto the cells of `RowSchema`. A terse pull drops `detail`, so those fields arrive null.
- `RowSchema` fixes three lines of cells in render order. Line 1 is the title alone, so it does not truncate at 360 dp.
- `TaskRow` takes no pane parameter, so both panes render identical cells. `VerbReasonSheet` shares that rule, and `TaskFieldControls` edits priority and owner.
- `kTaskVerbs` lists park, drop, demote, wont_fix, fixed, unpark and approve, in that order. `VerbNeeds` says which need a reason, a date or an arm-then-confirm step.
- `verbLegality( status )` returns all seven verbs, each enabled or disabled with a reason. A terminal row disables every verb.
- `buildTaskVerb` makes the payload. Park sends `park_reason`, others `reason`. Unpark sends an explicit null `next_chase_ts`. Fixed sends the `operator (mobile)` receipt.
- `TaskWriteRepository` has two doors. `patchFields` PATCHes priority or owner and cannot send status. `transition` POSTs a verb to `/api/tasks/{id}/transition`.
- Every write carries `authority: user_direct` and an `actor` of the signed-in email plus `(mobile)`.

## Don't
- Don't treat a 202 as success. `transition` throws `TaskAwaitingApprovalException`, because retrying files a second ticket.
- Don't add a pane flag to `TaskRow`. Drift should need a constructor change.
- Don't keep a second status list. `verbLegality` imports `isOpenStatus` from [[task-board-panes]].

## Invariants
- Only a transport failure becomes an `UnsentWrite`. A 4xx rolls back and shows the server's words.
- `retryUnsentWrites` tries each write once per restored connection and never throws.
- Nothing is stored durably, so unsent writes die with the session.
