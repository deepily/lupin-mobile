---
capability: quick-ask-events-and-state
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.quick_ask.data.quick_ask_models.stateForQueue@8f5dfccde0
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskRecordPressed@b4e1c5cde6
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskRecordReleased@f3d832951b
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskRecordCancelled@f2230b0ef6
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskDraftSent@ac8fe14c34
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskDraftCleared@942c3bfb4c
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskTransitionReceived@5445ef2c5c
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskInterviewCancelled@9ceef47d83
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskErrorDismissed@78b4433303
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskWatchdogFired@b2c6efb8ae
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskSpokenEventArrived@affe563314
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskSendModeChanged@9ba6aa5e65
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_event.QuickAskPromptDismissed@1ea82c519d
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_state.QuickAskPhase@65ab68df73
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_state.QuickAskBlockReason@cffd3383a4
  - lupin-mobile:lib.features.quick_ask.domain.quick_ask_state.QuickAskBlockReasonText@8da64bd400
---
# Quick ask events and state

The events `QuickAskBloc` accepts, the capture phases and the reasons the record button is blocked. The bloc, state and screen are in [[quick-ask]].

## What it does
- `QuickAskRecordPressed` starts a capture and `QuickAskRecordReleased` stops it and holds the transcript. `QuickAskRecordCancelled` discards any transcription in flight.
- `QuickAskDraftSent` is the only path from a held transcript to the server. `QuickAskDraftCleared` throws the draft away.
- `QuickAskTransitionReceived` carries a raw `job_state_transition` frame. `QuickAskNotificationReceived` is completion evidence when its job id matches, and resets the watchdog when it asks for a response.
- `QuickAskEntryDismissed` removes a card and cancels its job server-side when still running; a null `jobId` means a question not yet tied to a job.
- `QuickAskPromptDismissed` posts the prompt's default answer, so the blocked ask stops waiting.
- `QuickAskSpokenEventArrived` and `QuickAskWatchdogFired` are internal; only the bloc adds them. A spoken event whose epoch is stale is cancelled if it names a job, else dropped.
- `QuickAskPhase` is idle, recording, transcribing, review, submitting or waiting.
- `QuickAskBlockReason` is liveJobInFlight, unansweredPrompt, socketDisconnected or captureInFlight. `QuickAskBlockReasonText.message` gives the sentence the button shows.
- `stateForQueue` maps `done` to completed, `dead` to failed, `run` to running and anything else to queued.

## Don't
- Don't treat `QuickAskRecordPressed` as a finger-down event. The button is a tap toggle and the name is older than that.
- Don't add a new `QuickAskEvent` outside its file; the class is sealed.
