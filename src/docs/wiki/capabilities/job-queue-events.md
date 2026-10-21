---
capability: job-queue-events
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.queue.domain.queue_event.QueueEvent@0b967e92b2
  - lupin-mobile:lib.features.queue.domain.queue_event.QueueLoadSnapshot@33e8c9c034
  - lupin-mobile:lib.features.queue.domain.queue_event.QueueLoadHistory@87fbc22adf
  - lupin-mobile:lib.features.queue.domain.queue_event.QueueLoadInteractions@e945015a8b
  - lupin-mobile:lib.features.queue.domain.queue_event.QueueExternalUpdate@838273ad00
  - lupin-mobile:lib.features.queue.domain.queue_event.QueueSubmitJob@f65a1cde86
  - lupin-mobile:lib.features.queue.domain.queue_event.QueueSubmitAgenticJob@4cd9bb3a40
  - lupin-mobile:lib.features.queue.domain.queue_event.QueueCancelJob@29b770c6dd
  - lupin-mobile:lib.features.queue.domain.queue_event.QueuePauseJob@fee5e4a544
  - lupin-mobile:lib.features.queue.domain.queue_event.QueueResumeJob@95830f1236
  - lupin-mobile:lib.features.queue.domain.queue_event.QueueDeleteJob@efb3727000
  - lupin-mobile:lib.features.queue.domain.queue_event.QueueRetryJob@5b4557573a
  - lupin-mobile:lib.features.queue.domain.queue_event.QueueResumeFromCheckpoint@09f6d4ffb6
  - lupin-mobile:lib.features.queue.domain.queue_event.QueueInjectMessage@01ace3e784
---
# Job queue events

The inputs `QueueBloc` accepts, all subclasses of `QueueEvent`. The bloc is on [[job-queue-client]]; the requests they carry are on [[job-queue-models]] and the outputs on [[job-queue-states]].

## What it does
- `QueueLoadSnapshot` takes a queue name: `todo`, `run`, `done` or `dead`. `QueueLoadHistory` takes status and job-type filters and a page that defaults to the first 20. `QueueLoadInteractions` takes one job id.
- `QueueExternalUpdate` is sent when the WebSocket reports a queue change. The bloc refreshes only while a snapshot is showing, and prefers the queue it last loaded over the one named.
- `QueueSubmitJob` carries an `AskRequest` and `QueueSubmitAgenticJob` a `PushAgenticRequest`.
- `QueueCancelJob`, `QueuePauseJob` and `QueueResumeJob` take a job id. Pause and resume apply to the todo queue.
- `QueueDeleteJob` takes the queue name and the job id.
- `QueueRetryJob` carries the question text, because the server no longer retries. It re-asks through `/api/v2/ask`.
- `QueueResumeFromCheckpoint` takes the job's id hash and starts a new job.
- `QueueInjectMessage` sends text into a running job; priority defaults to `normal`.

## Don't
- Don't expect `QueueDeleteJob` to leave `QueueActionComplete` as the last state. It emits `QueueActionComplete`, then re-fetches the active queue and emits `QueueSnapshotLoaded`; the re-fetch is skipped when no queue snapshot was loaded.
- Don't expect the server to retry a job. `QueueRetryJob` asks again with the question text it is given.
