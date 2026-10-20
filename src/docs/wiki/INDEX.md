# Capability index

One line per capability: `[[slug]]`, what it covers, the folders it spans. Every slug below gets a page under `wiki/capabilities/`. Paths are under `lib/`.

Rick approved the names. Drafted from the symbol index of `lupin-mobile` at generation `399b92b103` (2,609 public symbols).

## Core and platform

- [[app-bootstrap-and-di]] — start-up order, the service locator, the root widget and the build stamp. `main.dart`, `app.dart`, `core/app_initialization.dart`, `core/di`, `core/build_info.dart`
- [[settings-store]] — typed settings definitions, validation, quick presets and change events. `core/settings`
- [[local-caches]] — the generic, network and audio caches, their policy and eviction, and key-value storage. `core/cache`, `core/storage`
- [[offline-queue]] — queueing requests while offline and replaying them when the network returns. `core/cache/offline_manager.dart`, `services/network/network_connectivity_service.dart`
- [[error-handling-and-recovery]] — typed app errors, recovery strategies and the HTTP error interceptor. `core/error_handling`
- [[logging-and-redaction]] — the leveled logger, its console, file and remote sinks, and secret redaction. `core/logging`
- [[http-client]] — the HTTP layer, its cached variant and the auth interceptor. `services/network`, `services/auth/auth_interceptor.dart`
- [[app-lifecycle]] — foreground and background state and the connection strategy that follows it. `services/lifecycle`, `features/auth/presentation/ws_lifecycle_listener.dart`
- [[test-keys-and-fixtures]] — stable widget keys shared by the app and its tests. `core/testing`
- [[theme-and-shared-widgets]] — themes, constants, the dashed border painter and the build footer. `core/constants`, `shared/painters`, `core/build_info_footer.dart`

## Auth

- [[mobile-auth]] — login, token refresh, session persistence, the auth gate and the auth bloc. `services/auth`, `features/auth`
- [[biometric-and-credential-store]] — biometric unlock and the secure credential vault. `services/auth`, `features/auth/presentation`
- [[server-context]] — which server the app talks to and the toggle that switches it. `services/auth/server_context_service.dart`, `features/settings/presentation`

## Realtime, push and voice

- [[ws-connection]] — the WebSocket client, reconnect coordination and the resume cursor. `services/websocket`
- [[fcm-push-wake]] — Firebase wake-ups, the token source, the wake chain and notification taps. `services/push`
- [[notification-audio-playback]] — deciding whether a notification is spoken, playing it, and the unplayed order. `services/notification_audio`, `services/push`
- [[tts-streaming]] — speech intent, the orchestrator, the streaming player and preview truncation. `services/tts`
- [[asr-dictation]] — microphone capture, speech to text, dictation splicing and the microphone permission. `services/asr`, `services/permissions`, `shared/widgets`
- [[round-trip-probe]] — measuring the voice round trip with a probe WAV. `services/diagnostics`, `features/settings/presentation`
- [[notification-filtering]] — the stop list, progress-group collapse, muting a sender and the filter settings. `services/notification_filter`, `features/notifications/presentation`
- [[notification-permission]] — the operating system notification permission prompts. `services/permissions`

## Notifications, conversations and decisions

- [[notification-inbox]] — the inbox, conversations by sender and date, and the repository, bloc and models behind them. `features/notifications`, `shared/models`
- [[interactive-prompts]] — the yes or no, multiple-choice, open-ended and multi-question answer sheets. `features/notifications/presentation`, `shared/widgets`
- [[voice-personas]] — persona identity, the badge, labels and the speakerphone snapshot. `features/notifications/data`, `core/text`
- [[quick-ask]] — a one-shot voice or text question to the server. `features/quick_ask`, `services/quick_ask`
- [[decision-proxy-client]] — the trust dashboard and trust state screens. `features/decision_proxy`
- [[broadcast-pane]] — the operator broadcasts list and the acknowledgements. `features/broadcast`

## Queue, tasks and fleet

- [[job-queue-client]] — job models and lifecycle, the queue dashboard, job detail and the submit sheet. `features/queue`, `shared/models`
- [[agentic-job-forms]] — the nine submit forms and their request models, behind one bloc. `features/agentic`
- [[task-board-panes]] — the task list, the holding area, finished tasks and the new-ticket sheet. `features/task_list`, `features/holding_area`, `features/finished_tasks`
- [[task-row-and-verbs]] — the shared task row, schema-driven field controls, verbs and the write repository. `features/fleet`
- [[pane-polling-and-visibility]] — mixins that poll a pane only while it is visible. `features/fleet/domain`, `features/fleet/presentation`
- [[fleet-status]] — fleet rows, watchables, the cap dial and the status screen. `features/fleet_status`
- [[heartbeat-and-push-switches]] — the settings sections for the heartbeat poke and the push pause. `features/settings`

## Sessions, docs and artifacts

- [[claude-code-sessions]] — listing and dispatching Claude Code seats from the phone. `features/claude_code`
- [[focus-mode-chat]] — the per-session chat pane, session rail, filter bar and TTS queue sheet. `features/focus_mode`, `shared/widgets`
- [[live-transcript]] — streaming another seat's transcript as a backlog plus live frames. `features/transcript`
- [[doc-viewer-client]] — opening repo documents by path, the split panel, link taps and upload. `features/docs`
- [[artifact-viewers]] — the markdown report, slide deck and audio artifact viewers and the io file fetch. `features/artifacts`, `services/artifacts`
