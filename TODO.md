# TODO

Last updated: 2026-04-16 (Session: Tier 4 Complete — Agentic Job UIs)

## Pending

### On-Device Verification (still pending)
- [ ] [LUPIN-MOBILE] On-device smoke: launch app → log in → open Inbox → respond to a `cosa-voice` `ask_yes_no` end-to-end
- [ ] [LUPIN-MOBILE] On-device smoke: open Trust Dashboard → verify mode shows + decisions list rendered
- [ ] [LUPIN-MOBILE] On-device smoke: submit a dry-run DeepResearch job → verify it lands in JobDetailScreen

### Tier 2 — Notifications + Decision Proxy (polish remaining)
- [ ] [LUPIN-MOBILE] Wire `NotificationsExternalUpdate` event from WS message stream (event type: `notification_queue_update` — confirm vs backend)
- [ ] [LUPIN-MOBILE] Date-grouped view in ConversationScreen (uses `conversation-by-date` endpoint — currently using flat `conversation`)
- [ ] [LUPIN-MOBILE] Sender-dates drilldown screen (per-sender date browse)
- [ ] [LUPIN-MOBILE] `generate-gist` UI on ConversationScreen ("Summarize" action)
- [ ] [LUPIN-MOBILE] TrustStateScreen drilldown (per-domain trust details)
- [ ] [LUPIN-MOBILE] Decide whether to remove orphaned `lib/shared/models/notification_item.dart`

### Tier 4 — Agentic (polish + deferred)
- [ ] [LUPIN-MOBILE] TimeSavedDashboard + StatsRepository + StatsBloc (deferred from Tier 4)
- [ ] [LUPIN-MOBILE] Add `fl_chart` dep when stats dashboard is implemented
- [ ] [LUPIN-MOBILE] Wire audioplayers for in-app audio playback in AudioArtifactPlayer (currently download-and-share only)
- [ ] [LUPIN-MOBILE] Podcast job: confirm server-side audio path field name for use in AudioArtifactPlayer

### Cross-cutting
- [ ] [LUPIN-MOBILE] PR `2026.04.15-resync-with-lupin-v0.1.6` → `main` after on-device validation
- [ ] [LUPIN-MOBILE] Resolve pre-existing `getIt` import in `home_screen.dart` (orphan from old wiring)

## Completed (Recent)
- [x] [LUPIN-MOBILE] Tier 4 all 6 phases: models, repository, IoFileService, AgenticSubmissionBloc, 9 forms, 3 artifact viewers, JobDetailScreen artifact/dead actions — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 4 unit tests: 40 new cases (models/repo/bloc), 140/140 total — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 4 planning docs serialized to src/rnd/v0.1.6-migration/ — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 3 queue data layer: queue_models.dart + queue_repository.dart (14 endpoints) — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 3 Claude Code data layer: claude_code_models.dart + claude_code_repository.dart (6 endpoints) — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 3 BLoC layer: QueueBloc + ClaudeCodeBloc — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 3 UI: QueueDashboardScreen, JobDetailScreen, SubmitJobSheet, ChatScreen, SessionListScreen, DispatchSheet — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 3 WS integration: app.dart bridging claude_code_message/state_change → ClaudeCodeBloc; queue_*_update → QueueBloc — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 3 DI wiring: QueueRepository, ClaudeCodeRepository, QueueBloc, ClaudeCodeBloc in service_locator + app.dart MultiBlocProvider — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 3 unit tests: 37 new cases across 6 files (100/100 total) — 2026-04-16
- [x] [LUPIN-MOBILE] Legacy test triage: 21 quarantined, 6 confirmed green, 1 fixed — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 2 data layer: models + repos for notifications + decision proxy — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 2 BLoC layer: NotificationBloc + DecisionProxyBloc — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 2 UI: InboxScreen, ConversationScreen, InteractivePromptSheet, TrustDashboardScreen — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 2 unit + BLoC tests (6 test files, 30+ cases) — 2026-04-16
- [x] [LUPIN-MOBILE] DI wiring (service_locator + app.dart MultiBlocProvider + home AppBar entry points) — 2026-04-16
- [x] [LUPIN-MOBILE] Expand Tier 2/3/4 plan stubs into full plans — 2026-04-16
- [x] [LUPIN-MOBILE] Tier 1 auth + biometric + WS persistence + Dev/Test toggle — 2026-04-15
- [x] [LUPIN-MOBILE] Audit Lupin v0.1.6 backend (113 endpoints) + map mobile coverage — 2026-04-15
- [x] [LUPIN-MOBILE] Install planning-is-prompting (all 13 groups, 30 slash commands) — 2026-04-15

---

*Completed items older than 7 days can be removed or archived.*
