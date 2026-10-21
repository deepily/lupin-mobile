---
capability: finished-tasks-pane
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.finished_tasks.data.finished_tasks_models.FinishedTaskEvent@8ec51a0033
  - lupin-mobile:lib.features.finished_tasks.data.finished_tasks_models.FinishedStatusFace@45f8b80ddf
  - lupin-mobile:lib.features.finished_tasks.data.finished_tasks_models.clampWindowDays@7162f42a40
  - lupin-mobile:lib.features.finished_tasks.data.finished_tasks_models.windowSinceIso@977b0890bd
  - lupin-mobile:lib.features.finished_tasks.data.finished_tasks_models.relativeAge@4be5002b01
  - lupin-mobile:lib.features.finished_tasks.data.finished_tasks_models.actorPersona@52beaea8b6
  - lupin-mobile:lib.features.finished_tasks.data.finished_tasks_models.transitionTarget@e4287c3edf
  - lupin-mobile:lib.features.finished_tasks.data.finished_tasks_models.toggleShownStatus@5125b93dba
  - lupin-mobile:lib.features.finished_tasks.data.finished_tasks_repository.FinishedFetchResult@dd83d28e70
  - lupin-mobile:lib.features.finished_tasks.data.finished_tasks_repository.FinishedTasksApiException@0f772e61d6
  - lupin-mobile:lib.features.finished_tasks.domain.finished_tasks_bloc.FinishedTasksBloc@dabbe60bd8
  - lupin-mobile:lib.features.finished_tasks.domain.finished_tasks_event.FinishedTasksEvent@3241d59648
  - lupin-mobile:lib.features.finished_tasks.domain.finished_tasks_event.FinishedTasksRequested@f96ae9ba3f
  - lupin-mobile:lib.features.finished_tasks.domain.finished_tasks_event.FinishedTasksWindowPreviewed@2ebe2e9f9b
  - lupin-mobile:lib.features.finished_tasks.domain.finished_tasks_event.FinishedTasksWindowChanged@b5c478b540
  - lupin-mobile:lib.features.finished_tasks.domain.finished_tasks_event.FinishedTasksStatusToggled@e7f50d227a
  - lupin-mobile:lib.features.finished_tasks.domain.finished_tasks_event.FinishedTasksPolled@cfdfcd937d
  - lupin-mobile:lib.features.finished_tasks.domain.finished_tasks_state.FinishedTasksState@5d0743edf1
  - lupin-mobile:lib.features.finished_tasks.domain.finished_tasks_state.FinishedTasksInitial@c103f07640
  - lupin-mobile:lib.features.finished_tasks.domain.finished_tasks_state.FinishedTasksLoading@f7a1785bda
  - lupin-mobile:lib.features.finished_tasks.domain.finished_tasks_state.FinishedTasksLoaded@d381b6f20c
  - lupin-mobile:lib.features.finished_tasks.domain.finished_tasks_state.FinishedTasksError@2762875801
  - lupin-mobile:lib.features.finished_tasks.presentation.finished_tasks_screen.FinishedTasksScreen@7865412f05
  - lupin-mobile:lib.features.finished_tasks.presentation.finished_tasks_screen.FinishedTaskRow@982178ee40
---
# Finished tasks pane

The event model, window helpers, bloc and screen of the pane described on [[task-board-panes]]. `FinishedTasksScreen` lists `task_events` in `FinishedTaskRow`, a four-cell row with the status glyph inside the When cell, never the shared `TaskRow`.

## What it does
- `FinishedTaskEvent` is one wire row. `status` is the right side of `transition`, from `transitionTarget`, which gives `""` for a missing or odd transition. `FinishedStatusFace` is a status's glyph, label and description.
- `clampWindowDays` keeps the window in 1 to 14 and returns 1 for a value it cannot parse. `windowSinceIso` turns days into the API's `since` instant. `relativeAge` prints `7m`, `3h20m` or `2d`, clamps a future time to `0m` and prints an em dash for null.
- `actorPersona` strips a trailing session id from the actor. `toggleShownStatus` keeps the order of the three statuses and ignores turning off the last lit one.
- `FinishedFetchResult` keeps a failed status absent, so empty and unknown stay different. `FinishedTasksApiException` carries the server's `detail` text.
- `FinishedTasksRequested` and `FinishedTasksWindowChanged` emit `FinishedTasksLoading`. `FinishedTasksWindowPreviewed` and `FinishedTasksStatusToggled` fetch nothing. `FinishedTasksPolled` is silent once rows are showing.
- `FinishedTasksLoaded` is partial when some statuses failed; `FinishedTasksError` means every status failed.
