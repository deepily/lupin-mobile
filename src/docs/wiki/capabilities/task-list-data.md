---
capability: task-list-data
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.task_list.data.new_ticket.NewTicketFields@97d01bbc15
  - lupin-mobile:lib.features.task_list.data.new_ticket.NewTicketBuild@7e81b6b627
  - lupin-mobile:lib.features.task_list.data.new_ticket.newTicketDetailFrom@ae64b416ac
  - lupin-mobile:lib.features.task_list.data.new_ticket.NewTicketState@49c3fa9140
  - lupin-mobile:lib.features.task_list.data.new_ticket.NewTicketOutcome@96a7aef944
  - lupin-mobile:lib.features.task_list.data.new_ticket.describeNewTicketResult@f491b0ded3
  - lupin-mobile:lib.features.task_list.data.new_ticket.newTicketAssigneeOptions@b0ec20fd40
  - lupin-mobile:lib.features.task_list.data.new_ticket.NewTicketResponse@2ee466640c
  - lupin-mobile:lib.features.task_list.data.task_list_model.statusRank@7f2f86ae04
  - lupin-mobile:lib.features.task_list.data.task_list_model.priorityRank@9e40c571ff
  - lupin-mobile:lib.features.task_list.data.task_list_model.isOpenStatus@e2f67c459b
  - lupin-mobile:lib.features.task_list.data.task_list_model.TaskGroup@23055c41e9
  - lupin-mobile:lib.features.task_list.data.task_list_model.TaskListModel@4277bb0ea3
  - lupin-mobile:lib.features.task_list.data.task_list_model.isParkActive@26a6efbc51
  - lupin-mobile:lib.features.task_list.data.task_list_model.taskListCountLabel@7a5a0df0a8
  - lupin-mobile:lib.features.task_list.data.task_list_model.compareByUrgency@b43d48b5c3
  - lupin-mobile:lib.features.task_list.data.task_list_repository.TaskListPage@4dd75af5c4
  - lupin-mobile:lib.features.task_list.data.task_list_repository.TaskListFetchException@e50156a09a
  - lupin-mobile:lib.features.task_list.data.task_lookup.TaskRefKind@0fd354d6eb
  - lupin-mobile:lib.features.task_list.data.task_lookup.TaskRef@f22afde98c
  - lupin-mobile:lib.features.task_list.data.task_lookup.taskLookupPath@0f4ef03fbe
  - lupin-mobile:lib.features.task_list.data.task_lookup.TaskLookupException@5e7fc62996
  - lupin-mobile:lib.features.task_list.data.task_lookup.describeLookupFailure@03f0485f1f
---
# Task list data

The grouping model, the New Ticket rules and the lookup helpers behind the Task List on [[task-board-panes]].

## What it does
- `statusRank` and `priorityRank` give sort keys: an unknown status ranks 7, between open and terminal work, and a missing or non-`P<n>` priority ranks 99. `isOpenStatus` counts a missing status as open. `compareByUrgency` sorts by priority, then status, then title ignoring case.
- `TaskGroup` is one owner's rows, labelled `Name (n)`, with a null owner for Unassigned. `TaskListModel` holds the groups and the open-row total.
- `isParkActive` is true only for a `parked` row whose chase time is still ahead. `taskListCountLabel` prints `Live: n`, or `Live · Parked · Total` when a park is active.
- `TaskListPage` carries `truncated`, `total`, `hasMore` and `warnings` beside the rows. `TaskListFetchException` wraps a failed fetch.
- `NewTicketFields` holds the form. `NewTicketBuild` holds either a payload or an error, never both. It refuses a blank title and an unknown priority or type.
- `describeNewTicketResult` words a POST by status: 2xx with `petition` is `petition`, other 2xx is `created`, then 401, 403, 422, 0 for nothing answered, else `failed`. `newTicketDetailFrom` reads the server's `detail`, a list of `msg` fields or plain text. `NewTicketResponse` holds the status and body.
- `newTicketAssigneeOptions` merges name lists once, sorted. `TaskRef` is a classified id: full, prefix of 4 or more hex characters, or invalid. `taskLookupPath` gives null for invalid text. `TaskLookupException` feeds `describeLookupFailure`: 404 names the typed text and 422 passes the server's detail.
