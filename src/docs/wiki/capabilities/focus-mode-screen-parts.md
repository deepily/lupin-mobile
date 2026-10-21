---
capability: focus-mode-screen-parts
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_bloc.sessionHashOf@f156650a94
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_bloc.senderWithSessionHash@5fdde6e00e
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_state.FocusHydration@e102ede055
  - lupin-mobile:lib.features.focus_mode.domain.focus_chat_state.FocusBand@2e29315d80
  - lupin-mobile:lib.features.focus_mode.presentation.focus_mode_screen.focusDrawerSurfaces@9363e09ed0
  - lupin-mobile:lib.features.focus_mode.presentation.focus_mode_screen.muteRosterLoader@8b8ee5e5d2
  - lupin-mobile:lib.features.focus_mode.presentation.focus_mode_screen.pushPauseRepository@394c4a37ab
  - lupin-mobile:lib.features.focus_mode.presentation.focus_mode_screen.heartbeatPokeRepository@5878128462
  - lupin-mobile:lib.features.focus_mode.presentation.focus_mode_screen.focusDrawerTools@ac128250c8
  - lupin-mobile:lib.features.focus_mode.presentation.focus_mode_screen.FocusDrawerSurface@1b099a6314
  - lupin-mobile:lib.features.focus_mode.presentation.speech_silenced_banner.SilencerHome@447b63cdb3
  - lupin-mobile:lib.features.focus_mode.presentation.speech_silenced_banner.SpeechSilencer@6b33459e34
  - lupin-mobile:lib.shared.widgets.tts_pause_control.TtsPausedBanner@ecfc85e90e
---
# Focus mode screen parts

The helper functions, enums and widgets around the focus screen, beyond the pane and rail on [[focus-mode-chat]]. The events are on [[focus-chat-events]].

## What it does
- `sessionHashOf` returns the 8 hex characters after the last `#` of a sender id, or null. `senderWithSessionHash` returns the first sender in an order with that hash. Two ids with one hash are the same session.
- `FocusHydration` is idle, loading, ready or error. `FocusBand` is live (last hour), history (last 24 hours) or stale, which leaves the rail.
- `focusDrawerSurfaces` lists the drawer's screens as data: Agentic Jobs, Claude Code, Broadcast, Fleet Status, Finished Tasks, Task List and Holding Area. Broadcast takes the app-root bloc by value; the four polling panes build their bloc inside the route.
- `focusDrawerTools` lists Notifications, Settings and the stop-list entry, which is disabled when no stop list is registered. `FocusDrawerSurface` is one row: icon, title, builder and an enabled flag.
- `muteRosterLoader` returns null when nobody is signed in or no notification repository is registered, which hides the Add button. `pushPauseRepository` and `heartbeatPokeRepository` return null when unregistered, which hides their sections.
- `SpeechSilencer` is one whole-phone reason for silence. `SilencerHome` says where its switch lives: notifications, settings, or here. A tap opens that screen, and `here` has no tap target.
- `TtsPausedBanner` shows the held state and a live queue count. It claims no source for the pause, only an optional reason line the screen supplies.

## Don't
- Don't add per-sender mutes or the stop-list as silencers. They silence some messages, not the phone.
- Don't change one door of a screen without the other. The drawer and the Home grid must open the same screen.
