---
capability: task-board-panes
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.task_list.domain.task_list_bloc.TaskListBloc@fcca9ec095
  - lupin-mobile:lib.features.task_list.data.task_list_repository.TaskListRepository@a33ff907f3
  - lupin-mobile:lib.features.task_list.data.task_list_model.groupTasksByOwner@49cd5fd98e
  - lupin-mobile:lib.features.task_list.data.task_lookup.classifyTaskRef@394868e28f
  - lupin-mobile:lib.features.task_list.data.new_ticket.buildNewTicketPayload@6bacdf8cab
  - lupin-mobile:lib.features.holding_area.domain.holding_area_bloc.HoldingAreaBloc@675d0af19a
  - lupin-mobile:lib.features.holding_area.data.holding_area_repository.HoldingAreaRepository@527d4118d4
  - lupin-mobile:lib.features.holding_area.data.holding_area_models.groupByFiler@c15ba1e7f3
  - lupin-mobile:lib.features.finished_tasks.data.finished_tasks_repository.FinishedTasksRepository@5e6d074c32
  - lupin-mobile:lib.features.finished_tasks.data.finished_tasks_models.mergeShownEvents@2f04486755
---
# Task board panes

Three panes show the task store: Task List, Holding Area and Finished Tasks. The first two share the row in [[task-row-and-verbs]]. Each pane has a bloc and a repository, and polls only while visible. Detail pages: [[finished-tasks-pane]], [[holding-area-pane]], [[task-list-data]], [[task-list-bloc-and-widgets]].

## Task List
- `TaskListRepository.fetch` pulls 500 terse rows with `hide_parked=false` and `char_budget=0`. A page that is truncated or has more rows shows a banner.
- `groupTasksByOwner` drops terminal rows and groups by `owner_persona`, not the accountable manager. Unassigned comes last. Rows sort priority first, then status, then title.
- The headline reads `Live: n`, plus `Parked: p · Total: t` when a park is active. A park counts only until its chase time passes.
- Lookup uses `classifyTaskRef` and then `GET /api/tasks/<ref>`. The `id_prefix` query would hide held rows. Four hex characters is the minimum.
- `buildNewTicketPayload` builds the New Ticket card's body: P2, approved, type `task`, epic `epic:unassigned`. A 2xx with a `petition` field is its own outcome, because the row sits at P1 in the holding area.

## Holding Area
- `HoldingAreaRepository.fetch` asks for `status=not_approved`. `groupByFiler` makes one folded group per persona, with an "Unattributed" group last.
- Approve-all asks for confirmation. Won't-fix-all asks for one reason, applied to every row, and refuses a blank one.
- `HoldingAreaBloc` runs a batch one row at a time and reports "n of m rows did not move". It does not use `Future.wait`.

## Finished Tasks
- `FinishedTasksRepository` reads `/api/tasks/events`, one call per terminal status, because `updated_ts` moves on every write. One failed status leaves a partial result.
- The window is 1 to 14 days, default 1. Only `done` is lit by default. `mergeShownEvents` sorts newest first, with the event id as tiebreak.
- A poll tick emits no loading state and keeps the rows on a failure. The pane does not use `TaskRow`.

## Don't
- Don't fold Holding Area batch controls into `TaskRow`; they live in the group header.
- Don't move `TaskListPage` casually. Holding Area imports it from the Task List.
