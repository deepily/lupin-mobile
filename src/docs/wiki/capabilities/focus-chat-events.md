---
capability: focus-chat-events
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusPromptContext@6be1bb6c35
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusChatEvent@d602f5acf5
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusInboundNotification@8b4e1fabe9
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusSpeakAnywayRequested@5ce51a8f6c
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusAskExpired@9b2be9345e
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusAskResponded@c7107da960
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusSenderSelected@a52295f2cf
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusMessageRevealRequested@8de69fecc5
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusRevealConsumed@0c7564a35c
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusColdStartRequested@242f9aaa55
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusRosterRefreshRequested@b79911a5a7
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusPersonaUpdated@7e25af10f5
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusFilterChanged@08428b3e8d
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusSenderScopeChanged@cbb4aa2fa4
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusActivityTick@4058c7283d
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusSenderExited@94d8eb3397
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_event.FocusRespondRequested@610214bb54
---
# Focus chat events

The inputs `FocusChatBloc` accepts, all subclasses of `FocusChatEvent`. The bloc, rail and pane are on [[focus-mode-chat]].

## What it does
- `FocusInboundNotification` upserts the sender, appends to its window and enqueues speech. `FocusSpeakAnywayRequested` carries only a notification id; the bloc hands back its own suppression record.
- `FocusAskExpired` retires a question the server answered with its default. `FocusAskResponded` retires one someone else answered, which is not an error.
- `FocusSenderSelected` focuses a sender, zeroes its unread count and backfills if needed. `FocusMessageRevealRequested` does the same for a notification tap, with the target and the email in one event. `FocusRevealConsumed` clears the target once the pane has scrolled.
- `FocusColdStartRequested` builds the one-time activity snapshot when the sender list is empty, and merges on a reconnect. `FocusRosterRefreshRequested` re-reads the roster and live seats.
- `FocusPersonaUpdated` sets a sender's persona, or clears it when null. `FocusSenderExited` hides the sender in Live and History still shows it.
- `FocusFilterChanged` and `FocusSenderScopeChanged` set the rail's lenses. `FocusActivityTick` re-evaluates recency bands and fetches nothing.
- `FocusRespondRequested` is the one answer shape, with a text and an optional `FocusPromptContext`. A voice reply omits the context and the bloc looks up the sender's pending prompt.
- `FocusPromptContext` holds the notification id and prompt type: `yes_no`, `open_ended` or `multiple_choice`.

## Don't
- Don't send a batch open-ended answer through `FocusRespondRequested`. Its text is a single string, and those asks go to the legacy sheet.
- Don't split a notification tap into a select plus a reveal. One event keeps the two halves from interleaving.
