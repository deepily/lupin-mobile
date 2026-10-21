---
capability: broadcast-bloc-and-models
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.broadcast.data.broadcast_models.ActiveSession@b84e917aee
  - lupin-mobile:lib.features.broadcast.data.broadcast_models.ActiveSessionRoster@8e74c65157
  - lupin-mobile:lib.features.broadcast.data.broadcast_models.BroadcastSendResult@cb311adec1
  - lupin-mobile:lib.features.broadcast.data.broadcast_models.BroadcastHistory@30db766e39
  - lupin-mobile:lib.features.broadcast.domain.broadcast_bloc.BroadcastEvent@96f8d3dce6
  - lupin-mobile:lib.features.broadcast.domain.broadcast_bloc.BroadcastRosterRequested@f7eecd20d2
  - lupin-mobile:lib.features.broadcast.domain.broadcast_bloc.BroadcastBodyChanged@0b86d77024
  - lupin-mobile:lib.features.broadcast.domain.broadcast_bloc.BroadcastMicToggled@252580aca8
  - lupin-mobile:lib.features.broadcast.domain.broadcast_bloc.BroadcastSendConfirmed@a5a73eb8a3
  - lupin-mobile:lib.features.broadcast.domain.broadcast_bloc.BroadcastAckReceived@db1b9634d1
  - lupin-mobile:lib.features.broadcast.domain.broadcast_bloc.BroadcastListeningInterrupted@73558b87bb
  - lupin-mobile:lib.features.broadcast.domain.broadcast_bloc.BroadcastAcksReconcileRequested@7f59b50038
  - lupin-mobile:lib.features.broadcast.domain.broadcast_bloc.BroadcastHistoryRequested@208418f17d
  - lupin-mobile:lib.features.broadcast.domain.broadcast_bloc.MicState@ec78b4db1f
  - lupin-mobile:lib.features.broadcast.domain.broadcast_bloc.BroadcastState@2278c71312
---
# Broadcast bloc and models

The events, state and send and roster models of `BroadcastBloc`, beyond the ack classes on [[broadcast-pane]].

## What it does
- `ActiveSession` here keeps the persona as three string fields and its `label` is the persona name, else the session id. The class of the same name in [[notification-wire-models]] builds a `VoicePersona` instead.
- `ActiveSessionRoster` treats an empty or malformed `sessions` list as an empty roster, not an error. `BroadcastSendResult` carries recipients, `failedRecipients`, `filteredOut` and a status. `noActiveSessions` is true when the status is `no-active-sessions`.
- `BroadcastHistory` keeps `disabled` apart from an empty `entries`, so a server kill switch reads differently from a quiet fleet.
- `BroadcastRosterRequested`, `BroadcastBodyChanged`, `BroadcastMicToggled`, `BroadcastSendConfirmed` and `BroadcastHistoryRequested` are the compose-side events. The pane confirms before it dispatches the send.
- `BroadcastAckReceived` folds one ack. `BroadcastListeningInterrupted` fetches nothing; `BroadcastAcksReconcileRequested` reads the saved acks for the broadcast on screen.
- `MicState` is idle, listening or transcribing. A mic toggle with no voice capture sets `micError`.
- `BroadcastState.canSend` needs a body, a live session and no send in flight, and `disabledReason` is null exactly then.
- A failed history read changes nothing; compose is not disturbed.

## Don't
- Don't treat status `queued` as delivered. Check `failedRecipients`.
- Don't count `inactive` as an interruption. `startListeningWatch` ignores it and fires on paused, hidden and detached.
