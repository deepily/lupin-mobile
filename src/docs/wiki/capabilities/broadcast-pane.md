---
capability: broadcast-pane
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.broadcast.data.broadcast_repository.BroadcastRepository@b9eae2854e
  - lupin-mobile:lib.features.broadcast.data.broadcast_repository.BroadcastException@8cf3a599b1
  - lupin-mobile:lib.features.broadcast.data.broadcast_repository.BroadcastRateLimited@a7c4715009
  - lupin-mobile:lib.features.broadcast.domain.broadcast_bloc.BroadcastBloc@611ce7185c
  - lupin-mobile:lib.features.broadcast.data.broadcast_models.BroadcastAck@e3d5ba4247
  - lupin-mobile:lib.features.broadcast.data.broadcast_models.AckAggregate@63626b654a
  - lupin-mobile:lib.features.broadcast.data.broadcast_models.AckConfidence@a175f04209
  - lupin-mobile:lib.features.broadcast.data.broadcast_models.AckOutcome@2c99a15f58
  - lupin-mobile:lib.features.broadcast.presentation.broadcast_pane.BroadcastPane@e8224d0ba4
---
# Broadcast pane

The operator pane that sends one message to every live seat and tallies acknowledgements. The server side is lupin's `commons-and-dm` page.

## What it does
- `BroadcastRepository` has four doors: active sessions, send, a five-entry history and a saved-acks read. None is polled.
- `send` always sends `require_ack` and `include_originator`. A 429 becomes `BroadcastRateLimited`; other failures become `BroadcastException`.
- `BroadcastBloc` composes, takes mic input by appending, and sends. Send needs a body, a live session and no send in flight.
- A failed send keeps the body. A success clears it and starts an `AckAggregate` sized by the server's recipient count.
- `BroadcastAck.fromNotification` reads a socket frame, where every field is in `payload`. `fromSavedAck` reads the saved row, where the status key is `ack_status`.
- `AckAggregate.fold` is idempotent per session. `outcome` is `AckOutcome.complete`, `partial` or `expired`; `expired` needs a known send time and the five-minute `ackWindow`.
- `startListeningWatch` marks the tally interrupted when the app pauses or the socket drops, and reconciles on return.
- `BroadcastPane` sends only after a confirm dialog and renders other seats' words as plain text.

## Don't
- Don't poll, and don't read ack content from `message`. It is always empty.
- Don't read "n of m acked" after a resume as seats ignoring the operator. The recovered tally appends a read-back note.
- Don't recover acks through `/api/notifications/undelivered`. It skips acks already handed to a socket.

## Invariants
- `AckConfidence` (`observed`, `interrupted`, `recovered`) is never improved by folding, only by a successful `reconciled` read. A failed read leaves it interrupted.
- A chip types an `@Persona` mention; every broadcast still goes to every live seat.
- `BroadcastBloc` is a singleton provided at the app root, so a screen change keeps the tally.

## When not to use it
- Direct messages are not here. See [[ws-connection]] for the socket that carries acks.
