---
capability: focus-mode-chat
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_bloc.FocusChatBloc@17bc0e83aa
  - lupin-mobile:lib.features.focus_mode.presentation.focus_chat_pane.FocusChatPane@b33abec535
  - lupin-mobile:lib.features.focus_mode.presentation.session_rail.SessionRail@377d91286e
  - lupin-mobile:lib.features.focus_mode.presentation.focus_filter_bar.FocusFilterBar@318b049ba0
  - lupin-mobile:lib.features.focus_mode.presentation.focus_mode_screen.FocusModeScreen@866460b42e
  - lupin-mobile:lib.features.focus_mode.presentation.speech_silenced_banner.SpeechSilencedBanner@e0bddd863e
  - lupin-mobile:lib.features.focus_mode.presentation.tts_fraction_bar.TtsFractionBar@8e7fa95e53
  - lupin-mobile:lib.features.focus_mode.presentation.tts_queue_sheet.TtsQueueSheet@db6d38ccb3
  - lupin-mobile:lib.shared.widgets.tts_pause_control.TtsPauseToggle@deeeaf37a9
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_state.FocusFilter@83effe6d51
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_state.FocusSenderScope@89c1a31fab
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_state.FocusChatState@8799c1afc4
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_state.FocusMessage@b5d90cb0bb
---
# Focus mode chat

The phone's main screen: a rail of sessions beside the focused session's conversation, plus the controls that decide what is spoken. Lupin's `websocket-events` page covers the frames it reads. See [[notification-inbox]], [[tts-streaming]] and [[asr-dictation]].

## What it does
- `FocusChatBloc` keeps senders in establishment order, the last 7 messages per sender, unread counts and the focused sender. It is separate from the older notification bloc.
- It is the only speech dispatcher here. Every inbound notification goes to `TtsOrchestrator.enqueueAlways`, and the stop-list decides what is dropped.
- A stop-list match is not stored, counted unread or spoken. A muted question is stored with its rule named, and `FocusSpeakAnywayRequested` speaks it.
- The rail is built once from `senders-visible` and never re-sorts. A reconnect merges and keeps positions. Only a user tap or a notification tap moves focus.
- `FocusRespondRequested` answers an open ask. With none open it sends a direct message through `POST /api/notify`, not `/api/dm/send`. An unsent answer is resent on reconnect.
- `FocusFilter` is Live or 24h and `FocusSenderScope` is Personas or All. They change what the rail shows, never what is stored.
- `FocusChatPane` shows the focused window newest first. A progress group collapses to one row, but an open ask never does.
- `SpeechSilencedBanner` names whole-phone silencers and opens the screen that holds each switch. `TtsFractionBar` sets how much of each message is spoken. `TtsQueueSheet` shows the queue.
- `TtsPauseToggle` holds and resumes speech. A hold queues speech and mutes nothing. `DocSplitHost` lets a tapped link open beside the chat; see [[doc-viewer-client]].

## Don't
- Don't add a second speech dispatcher, and don't re-sort the rail on refresh.
- Don't use `/api/dm/send` for a phone reply. It frames the phone as a peer session nobody can answer.

## Invariants
- Unread is 0 for the focused sender. A window never holds more than 7 messages and a merge dedupes by notification id.
