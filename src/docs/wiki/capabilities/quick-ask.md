---
capability: quick-ask
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_bloc.QuickAskBloc@ab0d9a861b
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_state.QuickAskState@7aef85f553
  - lupin-mobile:lib.features.quick_ask.data.quick_ask_models.QuickAskEntry@ca1cc55b97
  - lupin-mobile:lib.features.quick_ask.data.quick_ask_models.QuickAskSource@e340c6e1b2
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_state.QuickAskInterview@1dabcf4bba
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_state.QuickAskPrompt@8e6e208321
  - lupin-mobile:lib.services.quick_ask.quick_ask_preferences.QuickAskPreferences@521d092cc4
  - lupin-mobile:lib.features.quick_ask.presentation.quick_ask_screen.QuickAskScreen@32c1de85b1
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskConnectionChanged@b2e64c032f
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskEntryDismissed@8e8a0d98bc
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskEvent@fd3d3913c7
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskInterviewAnswered@b2a1074931
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskNotificationReceived@ce655cf04e
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskPromptAnswered@62a0e92cff
---
# Quick ask

Quick ask is the one-shot question screen: tap, speak, tap again, send, read the answer. `QuickAskBloc` runs the capture and follows the job. It is separate from the queue bloc, whose single slot a refresh would wipe. See [[job-queue-client]] and [[asr-dictation]].

## What it does
- Record is a tap toggle. Release transcribes into `draftTranscript` for review, and nothing leaves the phone until `QuickAskDraftSent`. `QuickAskPreferences` can switch to send immediately.
- One question is live at a time. `blockReason` checks a live job, an open prompt or interview, a closed WebSocket and a capture in flight, in that order.
- The bloc branches on response `status`. `done` has no job to follow and `parked` opens an interview. `expired`, `rejected` and `needs_input` each become a failed card.
- A job is followed through `job_state_transition` frames. A frame applies only if its lifecycle rank is higher or it is terminal, so duplicates do nothing.
- A watchdog probes the queue at 45, 90 and 180 seconds. Three misses spanning over 120 seconds set `lost`.
- `QuickAskInterview` keeps one `pending_id` across turns and answers through the resume route. `QuickAskPrompt` is a `response_requested` notification and answers through the notify response route; see [[interactive-prompts]].

## Don't
- Don't rename `QuickAskPreferences.keySendImmediately`. The stored choice would silently reset.
- Don't hold only a prompt's id. Hold the whole prompt, or the record button blocks on a question nobody saw.
- Don't poll the job-history route. It answers 404 for a plain question.

## Invariants
- A stale spoken result that names a job is cancelled. A stale one without a job is dropped.
- `QuickAskBloc` is an app-root singleton, and `FocusChatBloc` asks `isQuickAskJob` before speaking.
