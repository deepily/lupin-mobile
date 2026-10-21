---
capability: task-list-bloc-and-widgets
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.task_list.domain.task_list_bloc.TaskListEvent@eb84b1c276
  - lupin-mobile:lib.features.task_list.domain.task_list_bloc.TaskListRefreshRequested@7ce0b077c4
  - lupin-mobile:lib.features.task_list.domain.task_list_bloc.TaskListGroupToggled@3bb9c3d258
  - lupin-mobile:lib.features.task_list.domain.task_list_bloc.TaskListVerbPressed@0614604055
  - lupin-mobile:lib.features.task_list.domain.task_list_bloc.TaskListUnsentRetryRequested@c3d4aa5365
  - lupin-mobile:lib.features.task_list.domain.task_list_bloc.TaskListRosterRequested@46ebe24bfe
  - lupin-mobile:lib.features.task_list.domain.task_list_bloc.TaskListFieldChanged@f97e6cd653
  - lupin-mobile:lib.features.task_list.domain.task_list_bloc.TaskListState@be934beaf9
  - lupin-mobile:lib.features.task_list.presentation.new_ticket_sheet.showNewTicketSheet@9159f42fd6
  - lupin-mobile:lib.features.task_list.presentation.new_ticket_sheet.NewTicketSheet@07cfe47fcb
  - lupin-mobile:lib.features.task_list.presentation.task_group_header.TaskGroupHeader@11ea036cf4
  - lupin-mobile:lib.features.task_list.presentation.task_list_header.TaskListHeader@842eb0d084
  - lupin-mobile:lib.features.task_list.presentation.task_list_header.lookupStatusSentence@c968a0dab1
  - lupin-mobile:lib.features.task_list.presentation.task_list_pane.TaskListPane@dfde0f3079
---
# Task list bloc and widgets

The events, state and widgets of the Task List pane on [[task-board-panes]]. The grouping and ticket rules are on [[task-list-data]]; rows and verbs are on [[task-row-and-verbs]].

## What it does
- `TaskListRefreshRequested` is a poll, a pull or a resume. `TaskListVerbPressed` goes through the transition door and `TaskListFieldChanged` through the field door.
- `TaskListUnsentRetryRequested` resends writes the network dropped and is separate from refresh, so a pull never writes. `TaskListRosterRequested` reads the live fleet for the reassign choices.
- `TaskListGroupToggled` carries the owner name, or `Unassigned`, not the label with the count.
- `TaskListState` keeps the collapsed groups, unsent writes and reassign targets across refreshes. An empty reassign list is a valid state.
- `lookupTask` and `createTicket` are plain methods on the bloc, not events. The lookup answer never enters board state. A refresh follows only a `created` outcome.
- `TaskListHeader` holds the count headline, the New task button and the lookup box. The lookup state lives in the header. `lookupStatusSentence` names where a looked-up row is: holding area, parked, finished or `Status: <status>`.
- `showNewTicketSheet` completes with the `created` outcome, or null when dismissed. Any other outcome keeps `NewTicketSheet` open with its sentence showing.
- `TaskGroupHeader` shows one owner's name and count, and announces collapsed state and count to a screen reader.
- `TaskListPane` flattens groups and rows into one list, skipping rows of collapsed groups.

## Don't
- Don't register `TaskListBloc` at the app root. It is route-scoped so its poll timer stops with the pane.
- Don't offer verbs on a lookup result. It renders a bare `TaskRow`.
