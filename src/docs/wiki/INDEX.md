# Capability index

One line per capability: `[[slug]]`, what it covers, the folders it spans. Every slug below gets a page under `wiki/capabilities/`. Paths are under `lib/`.

Rick approved the names. Drafted from the symbol index of `lupin-mobile` at generation `399b92b103` (2,609 public symbols).

## Core and platform

- [[app-bootstrap-and-di]] — start-up order, the service locator, the root widget and the build stamp. `main.dart`, `app.dart`, `core/app_initialization.dart`, `core/di`, `core/build_info.dart`
- [[settings-store]] — typed settings definitions, validation, quick presets and change events. `core/settings`
- [[local-caches]] — the generic, network and audio caches, their policy and eviction, and key-value storage. `core/cache`, `core/storage`
- [[local-caches-events]] — the events `CacheManager` emits on each put, hit, miss, removal and cleanup. `core/cache/cache_manager.dart`
- [[network-cache-events]] — the events `NetworkCache` emits per cached HTTP response. `core/cache/network_cache.dart`
- [[audio-cache-events]] — the events `AudioCache` emits per cached utterance. `core/cache/audio_cache.dart`
- [[offline-queue]] — queueing requests while offline and replaying them when the network returns. `core/cache/offline_manager.dart`, `services/network/network_connectivity_service.dart`
- [[error-handling-and-recovery]] — typed app errors, recovery strategies and the global error handler. `core/error_handling`
- [[logging-and-redaction]] — the leveled logger, its console, file and remote sinks, and secret redaction. `core/logging`
- [[http-client]] — the HTTP layer, its cached variant and the auth interceptor. `services/network`, `services/auth/auth_interceptor.dart`
- [[app-lifecycle]] — foreground and background state and the connection strategy that follows it. `services/lifecycle`, `features/auth/presentation/ws_lifecycle_listener.dart`
- [[test-keys-and-fixtures]] — stable widget keys shared by the app and its tests. `core/testing`
- [[theme-and-shared-widgets]] — themes, constants, the dashed border painter and the build footer. `core/constants`, `shared/painters`, `core/build_info_footer.dart`

## Auth

- [[mobile-auth]] — login, token refresh, session persistence, the auth gate and the auth bloc. `services/auth`, `features/auth`
- [[mobile-auth-events-and-states]] — the auth bloc's input events, its two quiet states, and the user role and status enums. `features/auth/domain`, `shared/models/user.dart`
- [[biometric-and-credential-store]] — biometric unlock and the secure credential vault. `services/auth`, `features/auth/presentation`
- [[server-context]] — which server the app talks to and the toggle that switches it. `services/auth/server_context_service.dart`, `features/settings/presentation`

## Realtime, push and voice

- [[ws-connection]] — the WebSocket client, reconnect coordination and the resume cursor. `services/websocket`
- [[fcm-push-wake]] — Firebase wake-ups, the token source, the wake chain and notification taps. `services/push`
- [[fcm-wake-background-helpers]] — the helpers the background isolate runs during a wake: credentials, token exchange, fetch, notification id and details. `services/push/fcm_bootstrap.dart`
- [[notification-audio-playback]] — deciding whether a notification is spoken, playing it, and the unplayed order. `services/notification_audio`, `services/push`
- [[tts-streaming]] — speech intent, the orchestrator, the streaming player and preview truncation. `services/tts`
- [[tts-audio-chunk-model]] — the audio chunk record and its type and status enums. `shared/models/audio_chunk.dart`
- [[asr-dictation]] — microphone capture, speech to text, dictation splicing and the microphone permission. `services/asr`, `services/permissions`, `shared/widgets`
- [[round-trip-probe]] — measuring the voice round trip with a probe WAV. `services/diagnostics`, `features/settings/presentation`
- [[notification-filtering]] — the stop list, progress-group collapse, muting a sender and the filter settings. `services/notification_filter`, `features/notifications/presentation`
- [[notification-permission]] — the operating system notification permission prompts. `services/permissions`

## Notifications, conversations and decisions

- [[notification-inbox]] — the inbox, conversations by sender and date, and the repository, bloc and models behind them. `features/notifications`, `shared/models`
  - [[notification-wire-models]] — The notification, sender, date and gist response models and the ask-ending enum. `features/notifications`, `shared/models`
  - [[notification-bloc-events]] — The events the notification bloc accepts, from inbox load to gist request. `features/notifications`, `shared/models`
  - [[notification-bloc-states]] — The states the notification bloc emits, loaded views, gist and response states. `features/notifications`, `shared/models`
- [[interactive-prompts]] — the yes or no, multiple-choice, open-ended and multi-question answer sheets. `features/notifications/presentation`, `shared/widgets`
- [[voice-personas]] — persona identity, the badge, labels and the speakerphone snapshot. `features/notifications/data`, `core/text`
- [[quick-ask]] — a one-shot voice or text question to the server. `features/quick_ask`, `services/quick_ask`
  - [[quick-ask-events-and-state]] — The quick ask bloc's events, phases and block reasons. `features/quick_ask`, `services/quick_ask`
- [[decision-proxy-client]] — the trust dashboard and trust state screens. `features/decision_proxy`
  - [[decision-proxy-models]] — Trust modes, status, decision and trust-state models. `features/decision_proxy`
  - [[decision-proxy-events-and-states]] — The decision proxy bloc's events and states. `features/decision_proxy`
- [[broadcast-pane]] — the operator broadcasts list and the acknowledgements. `features/broadcast`
  - [[broadcast-bloc-and-models]] — Broadcast events, states and the ack models not covered by the parent. `features/broadcast`

## Queue, tasks and fleet

- [[job-queue-client]] — job models and lifecycle, the queue dashboard, job detail and the submit sheet. `features/queue`, `shared/models`
  - [[job-queue-models]] — Queue request and response models and the shared Job vocabulary. `features/queue`, `shared/models`
  - [[job-queue-events]] — The queue bloc's events: loads, submits and job actions. `features/queue`, `shared/models`
  - [[job-queue-states]] — The queue bloc's states: snapshot, history, submit and action results. `features/queue`, `shared/models`
- [[agentic-job-forms]] — the nine submit forms and their request models, behind one bloc. `features/agentic`
  - [[agentic-requests-and-forms]] — The nine request models, nine form widgets and the bloc's events and states. `features/agentic`
- [[task-board-panes]] — the task list, the holding area, finished tasks and the new-ticket sheet. `features/task_list`, `features/holding_area`, `features/finished_tasks`
  - [[finished-tasks-pane]] — Finished-task models, repository, bloc and screen. `features/task_list`, `features/holding_area`, `features/finished_tasks`
  - [[holding-area-pane]] — Holding-area models, repository, bloc, pane and filer header. `features/task_list`, `features/holding_area`, `features/finished_tasks`
  - [[task-list-data]] — The task list model, lookup, new-ticket model and repository. `features/task_list`, `features/holding_area`, `features/finished_tasks`
  - [[task-list-bloc-and-widgets]] — The task list bloc, its sheet and headers. `features/task_list`, `features/holding_area`, `features/finished_tasks`
- [[task-row-and-verbs]] — the shared task row, schema-driven field controls, verbs and the write repository. `features/fleet`
  - [[task-verbs-and-write-repository]] — The verb table, the row and schema models, write repository and reason sheet. `features/fleet`
- [[pane-polling-and-visibility]] — mixins that poll a pane only while it is visible. `features/fleet/domain`, `features/fleet/presentation`
- [[fleet-status]] — fleet rows, watchables, the cap dial and the status screen. `features/fleet_status`
  - [[fleet-status-models-and-bloc]] — Fleet row and watchable models, repository and bloc events. `features/fleet_status`
- [[heartbeat-and-push-switches]] — the settings sections for the heartbeat poke and the push pause. `features/settings`

## Sessions, docs and artifacts

- [[claude-code-sessions]] — listing and dispatching Claude Code seats from the phone. `features/claude_code`
- [[focus-mode-chat]] — the per-session chat pane, session rail, filter bar and TTS queue sheet. `features/focus_mode`, `shared/widgets`
  - [[focus-chat-events]] — The focus chat bloc's events, from selection to ask expiry. `features/focus_mode`, `shared/widgets`
  - [[focus-mode-screen-parts]] — The focus screen's drawer data, repositories, silencer types, pause banner and state. `features/focus_mode`, `shared/widgets`
- [[live-transcript]] — streaming another seat's transcript as a backlog plus live frames. `features/transcript`
  - [[transcript-stream-events-and-frames]] — The transcript bloc's events and the remaining frame models. `features/transcript`
- [[doc-viewer-client]] — opening repo documents by path, the split panel, link taps and upload. `features/docs`
  - [[doc-links-models-and-upload]] — Link helpers, content models and upload helpers. `features/docs`
  - [[doc-directory-panel-and-sheets]] — The directory view, roots panel, panel placement and upload sheet. `features/docs`
- [[artifact-viewers]] — the markdown report, slide deck and audio artifact viewers and the io file fetch. `features/artifacts`, `services/artifacts`
