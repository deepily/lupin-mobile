---
capability: job-queue-states
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.queue.domain.queue_state.QueueState@705b7ba4a1
  - lupin-mobile:lib.features.queue.domain.queue_state.QueueInitial@08ddd39a23
  - lupin-mobile:lib.features.queue.domain.queue_state.QueueLoading@d722527672
  - lupin-mobile:lib.features.queue.domain.queue_state.QueueSnapshotLoaded@83529ee580
  - lupin-mobile:lib.features.queue.domain.queue_state.QueueHistoryLoaded@0027b88c0e
  - lupin-mobile:lib.features.queue.domain.queue_state.QueueInteractionsLoaded@871c7a5806
  - lupin-mobile:lib.features.queue.domain.queue_state.QueueSubmitting@73e98c8f9a
  - lupin-mobile:lib.features.queue.domain.queue_state.QueueSubmitted@65b6e52137
  - lupin-mobile:lib.features.queue.domain.queue_state.QueueAnswered@a1f69208bb
  - lupin-mobile:lib.features.queue.domain.queue_state.QueueActionComplete@702079032e
  - lupin-mobile:lib.features.queue.domain.queue_state.QueueError@8f2ece844d
---
# Job queue states

The states `QueueBloc` emits, all subclasses of `QueueState`. The bloc is on [[job-queue-client]]; the payload classes are on [[job-queue-models]] and the inputs on [[job-queue-events]].

## What it does
- `QueueInitial` means nothing has loaded. `QueueLoading` covers a snapshot, history or interactions load. `QueueError` carries one message.
- `QueueSnapshotLoaded` holds a `QueueResponse`, `QueueHistoryLoaded` a `JobHistoryPage` and `QueueInteractionsLoaded` a `JobInteractionsResponse`.
- `QueueSubmitting` covers both submit paths. `QueueAnswered` holds the `AskResponse` of a synchronous ask, which has nothing to poll. `QueueSubmitted` holds the `PushJobResponse` of an agentic submit.
- `QueueActionComplete` holds a confirmation: `Cancel requested`, `Job paused`, `Job resumed`, `Job deleted`, `Message delivered`, a retry summary or the phase resumed from.
- Every `QueueApiException` in a handler becomes `QueueError` with its message.

## Don't
- Don't rely on equality to see changed content. A snapshot state compares by queue name and job count. A history state compares by total and offset, and an interactions state by job id and count.
- Don't expect a list screen to stay on `QueueSnapshotLoaded` after a job action. The bloc holds one state slot, so `QueueActionComplete` replaces it.
