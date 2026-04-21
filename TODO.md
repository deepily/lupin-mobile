# TODO

Last updated: 2026-04-21 (Session: Stage 4 agentic coverage + generate-gist UI)

> **Scope**: Build-out work only — new features, polish, testing playbook stages,
> deferred improvements. Known defects (things to *fix*) live in `bug-fix-queue.md`.

## Pending

### On-Device Sanity Pass (login confirmed on device 2026-04-17; remaining sanity checks still open)
- [x] [LUPIN-MOBILE] Device sanity: login works end-to-end (envelope fix verified on emulator) — 2026-04-17
- [ ] [LUPIN-MOBILE] Device sanity: open Inbox (widget-level covered by `inbox_screen_test.dart` × 4 cases)
- [ ] [LUPIN-MOBILE] Device sanity: respond to an ask_yes_no from Inbox (widget-level covered by `conversation_screen_test.dart` × 3 cases)
- [ ] [LUPIN-MOBILE] Device sanity: Trust Dashboard renders (widget-level covered by `trust_dashboard_screen_test.dart` × 3 cases)
- [ ] [LUPIN-MOBILE] Device sanity: DeepResearch dry-run submits (widget-level covered by `deep_research_form_test.dart` × 3 cases)
- [ ] [LUPIN-MOBILE] Device sanity: run `integration_test/smoke_hello_test.dart` via `flutter test integration_test/` on emulator (proves scaffolding)

### Tier 2 — Notifications + Decision Proxy (polish remaining)
- [ ] [LUPIN-MOBILE] Date-grouped view in ConversationScreen (uses `conversation-by-date` endpoint — currently using flat `conversation`; blocked by type divergence — by-date returns `NotificationItem`, flat returns `ConversationMessage` — needs unified rendering)
- [ ] [LUPIN-MOBILE] Sender-dates drilldown screen (per-sender date browse)
- [x] [LUPIN-MOBILE] `generate-gist` UI on ConversationScreen ("Summarize" action) — Summarize button + bottom sheet; `NotificationsGenerateGistRequested` event + `NotificationsGistLoading`/`Ready` states + bloc handler; 3 widget tests — 2026-04-21
- [ ] [LUPIN-MOBILE] TrustStateScreen drilldown (per-domain trust details)
- [ ] [LUPIN-MOBILE] ~~Decide whether to remove orphaned `lib/shared/models/notification_item.dart`~~ — **Revised finding 2026-04-21**: NOT orphan. Re-exported via `lib/shared/models/models.dart` and imported by 20+ production files (voice bloc, audio cache, repositories, use cases). There are now two `NotificationItem` classes — the old shared one and a newer differently-shaped one in `features/notifications/data/notification_models.dart`. Migration would require touching voice/audio/cache layers. **Reclassified: leave in place; no action unless voice/audio/cache layers are refactored.**

### Tier 4 — Agentic (polish + deferred)
- [ ] [LUPIN-MOBILE] TimeSavedDashboard + StatsRepository + StatsBloc (deferred from Tier 4)
- [ ] [LUPIN-MOBILE] Add `fl_chart` dep when stats dashboard is implemented
- [ ] [LUPIN-MOBILE] Wire audioplayers for in-app audio playback in AudioArtifactPlayer (currently download-and-share only)
- [ ] [LUPIN-MOBILE] Podcast job: confirm server-side audio path field name for use in AudioArtifactPlayer

### Testing Playbook — Stage 4+ (deferred with revisit triggers)
- [ ] [LUPIN-MOBILE] Alchemist visual-regression goldens — revisit when inbox tile / DR form / trust chip sees ≥2 regressions in a month
- [ ] [LUPIN-MOBILE] Patrol 4.x native-dialog support — revisit when app requests runtime permissions (mic, notifications) and smokes can't pass them via taps
- [ ] [LUPIN-MOBILE] Maestro MCP flows — revisit after `integration_test/` has ≥5 flows and CI parallelization matters
- [ ] [LUPIN-MOBILE] Fixture coverage for agentic endpoints (DR submit, podcast, etc.) — Stages 2/3 covered auth/notifications/decision-proxy; agentic is the remaining domain
- [ ] [LUPIN-MOBILE] CI job that runs `capture-*-fixtures.py` on a schedule + opens a PR when fixtures diff — catches silent backend drift
- [x] [LUPIN-MOBILE] Apply TestKeys / `bySemanticsIdentifier` to remaining agentic forms (podcast, presentation, SWE team, BFE, TFE, test suite, research-to-podcast, research-to-presentation) — 38 new TestKeys constants applied across 8 forms — 2026-04-21
- [x] [LUPIN-MOBILE] Widget tests for remaining agentic forms — 8 new test files (26 new test cases), all dispatch+validation paths covered — 2026-04-21

### Cross-cutting
- [x] [LUPIN-MOBILE] `getIt` import in `home_screen.dart` — verified **already removed** as of 2026-04-21 (confirmed by grep; only DI canonical files `service_locator.dart` + `use_case_registry.dart` reference `getIt`). — 2026-04-21

## Completed (Recent)
- [x] [LUPIN-MOBILE] Stage 4 agentic widget-test coverage — TestKeys + widget tests for 8 remaining agentic forms (podcast, presentation, SWE team, BFE, TFE, test suite, research-to-podcast, research-to-presentation). 26 new test cases, 204+/204+ tests green. — 2026-04-21
- [x] [LUPIN-MOBILE] `generate-gist` UI — Summarize button in ConversationScreen AppBar, bottom-sheet rendering of LLM-generated summary, full bloc pipeline (event/state/handler), 3 widget tests. — 2026-04-21
- [x] [LUPIN-MOBILE] `getIt` orphan import in `home_screen.dart` — verified already removed (stale TODO). — 2026-04-21
- [x] [LUPIN-MOBILE] URL-encode all path params in `NotificationRepository` — top-level `_enc( String )` helper wrapping `Uri.encodeComponent`, applied to 11 interpolation sites across senderId / userEmail / userId / project / dateString. Regression test covers slash-bearing sender IDs + `@` in email. 170/170 tests green. — 2026-04-19
- [x] [LUPIN-MOBILE] Post-login behavior investigation — code-read audit of `AuthGate` / `HomeScreen` / `app.dart` / `WebSocketService` / `AuthBloc`; surfaced concrete WS-lifecycle bug and queued as new high-priority TODO. Findings logged in `src/rnd/v0.1.7/2026.04.19-hot-bugs-url-encoding-and-post-login-investigation.md`. — 2026-04-19
- [x] [LUPIN-MOBILE] Stage 3 fixture expansion — shared `_fixture_lib.py`, notifications + decision-proxy capture scripts, 8 new fixtures, 6 repo tests converted, broader TestKeys (prompt yes/no, trust approve/reject), +6 widget tests — 2026-04-17
- [x] [LUPIN-MOBILE] Stage 2 fixture-backed tests for auth — captured + redacted real `/auth/*` responses, drift detection demonstrated — 2026-04-17
- [x] [LUPIN-MOBILE] Auth login envelope parse fix — `AuthRepository.login/refresh` now read `tokens` sub-object per real `LoginResponse`/`RefreshResponse` Pydantic shapes; malformed shapes throw `AuthException` instead of raw `TypeError`; added `AuthGate` widget test suite — 2026-04-17
- [x] [LUPIN-MOBILE] Dev-only credential pre-fill via `LUPIN_DEV_EMAIL` + `LUPIN_DEV_PASSWORD` `--dart-define`, `kDebugMode`-gated — 2026-04-17
- [x] [LUPIN-MOBILE] Widget coverage for all three B-track smoke scenarios — inbox+external-update, conversation yes_no response, trust dashboard, DR dry-run submit (16 widget tests total) — 2026-04-17
- [x] [LUPIN-MOBILE] Wire `NotificationsExternalUpdate` from WS message stream (`notification_queue_update` → NotificationBloc) — 2026-04-17
- [x] [LUPIN-MOBILE] Testing playbook stage 1: mocktail + network_image_mock deps, TestKeys class, shared testApp harness, first widget test (login), integration_test/ scaffold — 2026-04-17
- [x] [LUPIN-MOBILE] Rename `test/integration/` → `test/service_integration/` to avoid confusion with canonical `integration_test/` at project root — 2026-04-17
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
