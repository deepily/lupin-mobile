---
capability: job-queue-models
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.queue.data.queue_models.AskRequest@e2ba002564
  - lupin-mobile:lib.features.queue.data.queue_models.SubmitRequest@4d05f9e90a
  - lupin-mobile:lib.features.queue.data.queue_models.PushJobResponse@7785d29ae1
  - lupin-mobile:lib.features.queue.data.queue_models.ResumeRequest@3bfe8e011b
  - lupin-mobile:lib.features.queue.data.queue_models.SpokenAskTranscript@c61cd51f80
  - lupin-mobile:lib.features.queue.data.queue_models.SpokenAskResult@9289f71aed
  - lupin-mobile:lib.features.queue.data.queue_models.JobSummary@609f8ae101
  - lupin-mobile:lib.features.queue.data.queue_models.QueueResponse@8711950407
  - lupin-mobile:lib.features.queue.data.queue_models.JobHistoryEntry@a2f50e164f
  - lupin-mobile:lib.features.queue.data.queue_models.JobHistoryPage@35b6507f08
  - lupin-mobile:lib.features.queue.data.queue_models.JobInteraction@36399d47ce
  - lupin-mobile:lib.features.queue.data.queue_models.JobInteractionsResponse@e101b99012
  - lupin-mobile:lib.features.queue.data.queue_models.MessageDeliveredResponse@1909d60774
  - lupin-mobile:lib.features.queue.data.queue_models.ResumeCheckpointResponse@1d194b1844
  - lupin-mobile:lib.shared.models.job.JobStatus@bb58ee0bda
---
# Job queue models

The request and response classes for the queue and v2 flow doors, plus the local `JobStatus` enum. The repository, bloc and screens are on [[job-queue-client]]; the events and states are on [[job-queue-events]] and [[job-queue-states]].

## What it does
- `AskRequest` is the body for `POST /api/v2/ask`; speech and interaction default to on. `SubmitRequest` names a routing command and its arguments, and writes `scheduled_at` and `monopolize` at the top level only when set.
- `ResumeRequest` carries `pending_id`, the answer and `websocket_id`. Without the socket id the answer is not spoken.
- `PushJobResponse.fromAsk` adapts a v2 reply to the old queue-and-poll shape and leaves `userId` empty. `fromJson` requires `status`, `websocket_id` and `user_id`.
- `SpokenAskTranscript` is not terminal. `SpokenAskResult` wraps an `AskResponse`, is terminal, and compares by the response's fields.
- `JobSummary` is one queue entry. Fields such as `responseText` and `reportPath` are set only on done or dead jobs. `QueueResponse.fromJson` reads the list from the `{queue}_jobs_metadata` key.
- `JobHistoryEntry` and `JobHistoryPage` hold history rows with `limit` 20 and `offset` 0 by default. `JobInteraction` and `JobInteractionsResponse` hold a job's notification trail.
- `MessageDeliveredResponse` answers an injected message. `ResumeCheckpointResponse` names the new and original job ids and the phase resumed from.
- `JobStatus` is todo, running, completed or dead. It is a local vocabulary and `Job.fromJson` turns an unknown name into todo.

## Don't
- Don't map `JobStatus` to `JobLane` by name. Two of four names differ.
- Don't expect `needs_input` to carry a `pending_id`; only a parked ask does.
