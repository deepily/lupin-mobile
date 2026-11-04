---
capability: job-queue-client
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.queue.data.queue_repository.QueueRepository@3dce1bc787
  - lupin-mobile:lib.features.queue.data.queue_models.QueueApiException@e4ad48ef87
  - lupin-mobile:lib.features.queue.data.queue_models.AskResponse@1cf3669566
  - lupin-mobile:lib.features.queue.data.queue_models.SpokenAskEvent@06445f7c78
  - lupin-mobile:lib.features.queue.domain.queue_bloc.QueueBloc@ed187d06e7
  - lupin-mobile:lib.features.queue.domain.job_lifecycle.JobLifecycleState@8fb2eee51e
  - lupin-mobile:lib.features.queue.domain.job_lifecycle.JobLane@409134c5fd
  - lupin-mobile:lib.features.queue.presentation.queue_dashboard_screen.QueueDashboardScreen@7b7f742140
  - lupin-mobile:lib.features.queue.presentation.job_detail_screen.JobDetailScreen@44cb0a1c77
  - lupin-mobile:lib.features.queue.presentation.submit_job_sheet.SubmitJobSheet@9cd80c768b
  - lupin-mobile:lib.shared.models.job.Job@859b5b3783
  - lupin-mobile:lib.features.queue.data.queue_models.PushAgenticRequest@0b8370c5a7
  - lupin-mobile:lib.features.queue.data.queue_models.SpokenAskCutOff@21c935fe01
  - lupin-mobile:lib.features.queue.data.queue_models.SpokenAskFailed@a73b39e33b
---
# Job queue client

The phone's view of lupin's job queue: a four-tab dashboard, a job detail screen, a submit sheet and the job state vocabulary. The server half is lupin's `cj-flow-queue` page. Detail pages: [[job-queue-models]], [[job-queue-events]], [[job-queue-states]].

## What it does
- `QueueRepository` wraps the queue and v2 flow doors: ask, spoken ask, submit, resume, listings, history, interactions, and cancel, pause, resume, delete, inject and retry.
- `ask`, `askSpoken` and `resume` wait 240 seconds because the server may hold for a near-match confirm. Other calls keep the shared client's 30 seconds.
- `askSpoken` returns a stream of `SpokenAskEvent`s and never throws. A transcript comes first, then one result, failure or cut-off. A cut-off means the ask still runs on the server.
- `AskResponse.isParked` means answer through `resume`; `isNeedsInput` means the server is telling, not asking. Dropping `websocket_id` on a resume silences later spoken answers.
- `QueueBloc` holds one state slot. `QueueExternalUpdate` refreshes silently, only while a snapshot shows, and a failed refresh keeps the last good state.
- `JobLifecycleState` has ten values mirroring the server. Its lane maps each to a `JobLane`: `stalled` is in `todo`, `interrupted` in `dead`. `parse` returns null for an unknown name.
- `Job` in `shared/models/job.dart` is a separate local vocabulary; only a test imports it.

## Don't
- Don't use `/api/push` for a question. It answers 410.
- Don't build the tab list by hand. Take it from `JobLane.values`.
- Don't give `QueueBloc` the quick-ask jobs; see [[quick-ask]].

## Invariants
- No screen dispatches `QueueLoadHistory`, `QueueDeleteJob`, `QueueRetryJob` or `QueueResumeFromCheckpoint`. The bloc supports them. The forms are in [[agentic-job-forms]].
