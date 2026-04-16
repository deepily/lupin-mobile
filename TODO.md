# TODO

Last updated: 2026-04-16 (Session: Legacy test triage + baseline green)

## Pending

### On-Device Verification (still pending)
- [ ] [LUPIN-MOBILE] On-device smoke: launch app → log in → open Inbox → respond to a `cosa-voice` `ask_yes_no` end-to-end
- [ ] [LUPIN-MOBILE] On-device smoke: open Trust Dashboard → verify mode shows + decisions list rendered
- [ ] [LUPIN-MOBILE] Decide whether to commit Tier 1 + Tier 2 as one bundle or two separate commits

### Tier 2 — Notifications + Decision Proxy (mostly complete, polish remaining)
- [ ] [LUPIN-MOBILE] Wire `NotificationsExternalUpdate` event from WS message stream (event types: `notification_queue_update`)
- [ ] [LUPIN-MOBILE] Date-grouped view in ConversationScreen (uses `conversation-by-date` endpoint — currently using flat `conversation`)
- [ ] [LUPIN-MOBILE] Sender-dates drilldown screen (per-sender date browse)
- [ ] [LUPIN-MOBILE] `generate-gist` UI on ConversationScreen ("Summarize" action)
- [ ] [LUPIN-MOBILE] TrustStateScreen drilldown (per-domain trust details)
- [ ] [LUPIN-MOBILE] Decide whether to remove orphaned `lib/shared/models/notification_item.dart`

### Tier 3 — Queue/CJ Flow + Interactive Claude Code (planned, ready to start)
- [ ] [LUPIN-MOBILE] Build `lib/features/queue/data/queue_models.dart` + `queue_repository.dart` (14 endpoints)
- [ ] [LUPIN-MOBILE] Build `lib/features/claude_code/data/claude_code_models.dart` + `claude_code_repository.dart` (5+1 endpoints)
- [ ] [LUPIN-MOBILE] Verify exact response shapes for `/api/get-queue/*`, `/api/jobs/{id}/*`, `/api/claude-code/*` against router source (analogous to Tier 2's openapi+router trace)
- [ ] [LUPIN-MOBILE] QueueBloc + QueueDashboardScreen + JobDetailScreen
- [ ] [LUPIN-MOBILE] ClaudeCodeBloc + ChatScreen + DispatchSheet
- [ ] [LUPIN-MOBILE] WS subscription for `claude_code_*` events (verify event names exist in app_constants.dart)
- [ ] [LUPIN-MOBILE] Unit tests for Tier 3 data + BLoC layer

### Tier 4 — Agentic Job UIs (planned, blocked on Tier 3)
- [ ] [LUPIN-MOBILE] Build per-job-type request/response models (deep_research, podcast, presentation, swe_team, bug_fix_expediter, test_suite, chained_*)
- [ ] [LUPIN-MOBILE] AgenticHubScreen + per-job submission forms
- [ ] [LUPIN-MOBILE] `IoFileService` for artifact streaming (`/api/io/file`)
- [ ] [LUPIN-MOBILE] AudioArtifactPlayer (reuse `audioplayers`), MarkdownReportViewer (new dep `flutter_markdown`), SlideDeckViewer (new dep `open_file` or `share_plus`)
- [ ] [LUPIN-MOBILE] TimeSavedDashboard + StatsRepository
- [ ] [LUPIN-MOBILE] Add `flutter_markdown`, `open_file`/`share_plus`, optionally `fl_chart` to pubspec
- [ ] [LUPIN-MOBILE] Unit tests for Tier 4 data layer

### Cross-cutting
- [ ] [LUPIN-MOBILE] Decide whether/when to PR `2025.07.07-wip-mobile-phased-implementation` → `main`
- [ ] [LUPIN-MOBILE] Resolve pre-existing `getIt` import in `home_screen.dart` (orphan from old wiring)

## Completed (Recent)
- [x] [LUPIN-MOBILE] `flutter pub get` + `flutter test test/unit/` — 63/63 pass — 2026-04-16
- [x] [LUPIN-MOBILE] Legacy test triage: 21 quarantined, 6 confirmed green, 1 fixed — 2026-04-16
- [x] [LUPIN-MOBILE] Decide whether to commit Tier 1 + Tier 2 as one bundle or two — deferred to next session — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 2 data layer: models + repos for notifications + decision proxy — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 2 BLoC layer: NotificationBloc + DecisionProxyBloc — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 2 UI: InboxScreen, ConversationScreen, InteractivePromptSheet, TrustDashboardScreen — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 2 unit + BLoC tests (6 test files, 30+ cases) — 2026-04-16
- [x] [LUPIN-MOBILE] DI wiring (service_locator + app.dart MultiBlocProvider + home AppBar entry points) — 2026-04-16
- [x] [LUPIN-MOBILE] Expand Tier 2 plan stub into full active plan doc — 2026-04-16
- [x] [LUPIN-MOBILE] Expand Tier 3 plan stub (queue + Claude Code) — 2026-04-16
- [x] [LUPIN-MOBILE] Expand Tier 4 plan stub (agentic UIs + artifacts + stats) — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 1 auth + biometric + WS persistence + Dev/Test toggle (full implementation) — 2026-04-15
- [x] [LUPIN-MOBILE] Tier 1 unit tests (4 files, 16 cases) — 2026-04-15
- [x] [LUPIN-MOBILE] Audit Lupin v0.1.6 backend (113 endpoints, 24 router groups) — 2026-04-15
- [x] [LUPIN-MOBILE] Map mobile REST + WebSocket coverage (~5%) — 2026-04-15
- [x] [LUPIN-MOBILE] Create `src/rnd/v0.1.6-migration/` with master audit — 2026-04-15
- [x] [LUPIN-MOBILE] Install planning-is-prompting (all 13 groups, 30 slash commands) — 2026-04-15
