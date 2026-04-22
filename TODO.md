# TODO

Last updated: 2026-04-21 (Session: TTS orchestrator — ElevenLabs primary + flutter_tts fallback)

---

## ⭐ NEXT SESSION — START HERE: On-device verification of TTS + notification-audio pipelines

All code for agent-narration TTS is written and unit-test-green (237/237).
**None of it has run on a real device yet.** The next session's primary
job is laptop + emulator validation of:

1. **Notification audio (shipped in commit `180a4ba`, 2026-04-21)** —
   dings and `flutter_tts` speech for high/urgent notifications. Never
   verified on device.
2. **Agent-narration TTS (shipped as Phase 1–5 this session, uncommitted)** —
   `StreamingTtsPlayer` + `TtsOrchestrator`. Never run on device.

### Why this is required before further work

Both pipelines touch platform audio (`flutter_local_notifications`,
`flutter_tts`, `audioplayers`), native Android channels (`lupin_medium`/
`lupin_high`/`lupin_urgent`), and real backend WS audio streaming. Unit
tests exercise the logic in isolation but can't exercise:
- Actual audio playback quality
- ElevenLabs voice arrival timing + PCM → WAV wrap correctness
- Audio-focus interaction between the OS notification channel sound and
  `audioplayers` concurrent playback
- Android channel registration on first cold install
- Priority-appropriate sound selection at real OS level

### Environment prerequisites (user's laptop)

- Android SDK + `adb` — present on user's laptop per memory rule; NOT on this dev server
- Flutter toolchain (`./flutter.sh` works here too but emulator requires Android SDK)
- Live Lupin backend reachable at `http://10.0.2.2:7999` (emulator host-loopback) — verify `POST /api/notify` works from laptop
- Valid ElevenLabs API key configured on backend
- Lupin-mobile sources synced via `rsync` (per dev-server/laptop split convention)

### Build & deploy

```bash
# On laptop (after pulling latest via rsync):
cd /path/to/lupin-mobile
./src/scripts/build-and-deploy-lupin-mobile.sh   # per memory: this is the right entry point
# or fall back to raw:
./flutter.sh pub get
./flutter.sh build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### Verification scenarios (in emulator, with Lupin backend live)

**Dings** (tests notification_audio_service.dart):
1. Trigger a `priority=medium` notification via `POST /api/notify` → expect single medium ding
2. Trigger `priority=high` → expect high ding
3. Trigger `priority=urgent` → expect urgent alert-tone ding
4. Trigger with `suppress_ding=true` → expect silence

**Speech — ElevenLabs primary path** (tests streaming_tts_player.dart + tts_orchestrator.dart):
5. Trigger `priority=high` (with user pref `speakOnHigh=true`, the default) → expect ding then ElevenLabs voice speaking the title + message, ~300ms gap
6. Trigger `priority=urgent` while priority=high is still speaking → expect urgent to preempt, stop the high utterance, and play the urgent message
7. Fire two `priority=high` notifications rapidly → expect FIFO: first plays fully, then second plays (no overlap)

**Speech — flutter_tts fallback path** (tests quota-exceeded branch):
8. Inject a fake `tts_error` event with `error_code="quota_exceeded"` while a high utterance is in flight (either via backend stub OR by pointing at an exhausted ElevenLabs account for the duration of the test) → expect current utterance to re-speak via on-device `flutter_tts`, and subsequent notifications in the next 5 minutes to also route through `flutter_tts` without hitting ElevenLabs
9. After 5 minutes elapse, fire another `priority=high` → expect ElevenLabs to be tried again

**Settings integration**:
10. Open Settings → toggle `master mute` on → fire urgent → expect total silence (no ding, no speech)
11. Toggle `speakOnHigh=false` → fire high → expect ding but no speech

### Expected gotchas / things to watch for

- **Channel sound may not play on first install** — Android sometimes delays channel-sound activation until after the app is relaunched. If first-run urgent ding uses the default OS sound instead of `lupin_urgent.mp3`, uninstall + reinstall.
- **Audio focus conflict** — when `audioplayers` (ElevenLabs path) starts playing, Android's OS may duck or stop the concurrent notification-channel ding. The 300ms gap pattern is meant to prevent this but might not be enough on all devices. If the ding gets cut short, consider either (a) increasing the gap, or (b) routing both sounds through `audioplayers` (abandoning the channel-sound approach).
- **ElevenLabs first-byte latency** — web client target is 300ms; mobile may see similar or worse on cellular. If noticeable, log the `audio_streaming_status` loading→streaming transition timing to quantify.
- **PCM→WAV wrap correctness** — verify the WAV header is readable by `audioplayers` on Android. If playback crashes or plays as noise, the `_wrapPcm24kAsWav` helper in `streaming_tts_player.dart` is the first place to look. Sample rate is 24000 Hz, 16-bit mono per ElevenLabs spec.
- **Session ID mismatch** — the orchestrator reads `WebSocketService.sessionId` at speak-time. If WS isn't connected (user just opened app, hasn't authenticated), the orchestrator correctly falls back to `flutter_tts`. Verify this early-startup scenario.

### Reference files (read these first)

- Plan doc: `src/rnd/v0.1.7/2026.04.21-agent-narration-tts-plan.md` — full architecture + phase breakdown + Phase 1 course-correction rationale
- Notification audio plan: `src/rnd/v0.1.7/2026.04.21-notification-audio-on-receipt-plan.md`
- FCM deferral rationale: `src/rnd/v0.1.7/2026.04.21-fcm-apns-push-considerations.md`
- New code to scan: `lib/services/tts/streaming_tts_player.dart`, `lib/services/tts/tts_orchestrator.dart`
- Modified code: `lib/services/notification_audio/notification_audio_service.dart` (speech auto-branch removed), `lib/features/notifications/domain/notification_bloc.dart` (orchestrator injected), `lib/app.dart` (audio_streaming_* routing), `lib/core/di/service_locator.dart`

### If device testing finds a regression

Roll-forward preferred over roll-back: the new TTS code is gated by WS
connection + user prefs, so it fails soft (falls back to flutter_tts or
silent). Identify the regression, patch in a focused PR, re-run unit
tests, re-verify on device.

---

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

### Agent-narration TTS (new 2026-04-21)
- [x] [LUPIN-MOBILE] Phase 0 — Plan serialized to `src/rnd/v0.1.7/2026.04.21-agent-narration-tts-plan.md` — 2026-04-21
- [x] [LUPIN-MOBILE] Phase 1 — Built slim `StreamingTtsPlayer` (abandoned the legacy `EnhancedTTSService` revival; 2.7K lines of parallel WS infra would have been pulled in for no marginal benefit). Reuses live `WebSocketService` + `Dio`. Renamed binary-frame wrapper type to `audio_streaming_chunk`. — 2026-04-21
- [x] [LUPIN-MOBILE] Phase 2 — `TtsOrchestrator`: FIFO queue + priority gate + urgent preempt + quota fallback (5min window) — 2026-04-21
- [x] [LUPIN-MOBILE] Phase 3 — Removed auto-priority `flutter_tts` branch from `NotificationAudioService`; exposed `flutterTtsSpeak()` + `stopFallbackSpeech()` as orchestrator fallback helpers. Wired `TtsOrchestrator` into `NotificationBloc._onExternalUpdate`. — 2026-04-21
- [x] [LUPIN-MOBILE] Phase 4 — 11 new orchestrator tests + 1 new bloc→tts test + rewrote notification_audio_service_test.dart for split responsibilities. — 2026-04-21
- [ ] [LUPIN-MOBILE] On-device verify TTS: live ElevenLabs audio plays in the emulator (user's laptop); injected `quota_exceeded` falls back to `flutter_tts` cleanly.
- [ ] [LUPIN-MOBILE] Future: ElevenLabs voice/config customization per agent/context (currently uses backend defaults only)
- [ ] [LUPIN-MOBILE] Future: Cancel/replay UI for in-flight narration

### Notification audio-on-receipt (new 2026-04-21)
- [x] [LUPIN-MOBILE] Phase 0 — Web client cross-check (low/medium/high/urgent policy aligned) + 3 MP3 assets copied from `src/fastapi_app/static/audio/` into `android/app/src/main/res/raw/lupin_{medium,high,urgent}.mp3`. Plan: `src/rnd/v0.1.7/2026.04.21-notification-audio-on-receipt-plan.md` — 2026-04-21
- [x] [LUPIN-MOBILE] Phase 1 — `flutter_local_notifications` dep + `POST_NOTIFICATIONS` perm + 3 Android channels + `NotificationAudioService` + `NotificationPreferences` + `NotificationsExternalUpdate` extended with `NotificationItem` + `app.dart` parses payload + `NotificationBloc._onExternalUpdate` triggers audio — 2026-04-21
- [x] [LUPIN-MOBILE] Phase 2 — `flutter_tts` dep + `speak()` method; 300ms delay ding→TTS; dispatch from `_maybePlayAudio` on high/urgent — 2026-04-21
- [x] [LUPIN-MOBILE] Phase 3 — `NotificationAudioSettingsScreen` with 6 toggles; gear-icon entry from `home_screen.dart` AppBar — 2026-04-21
- [x] [LUPIN-MOBILE] Phase 4 — Unit tests (prefs defaults+persistence; service priority-filter/suppress/mute/speech) + widget test (settings screen toggles) + blocTest extension (urgent item triggers audio) — 2026-04-21
- [x] [LUPIN-MOBILE] ~~Cross-repo: file backend FCM/APNs integration item in parent Lupin `bug-fix-queue.md`~~ — **PULLED 2026-04-21** per user decision; full investigation and defer rationale captured in `src/rnd/v0.1.7/2026.04.21-fcm-apns-push-considerations.md`. Parent Lupin queue no longer carries this as an action item.
- [ ] [LUPIN-MOBILE] ~~Phase 5 — Background FCM handler~~ — **DEFERRED INDEFINITELY** per 2026-04-21 decision. Conditions for revisiting documented in R&D doc section 7. Mobile implementation notes remain in `2026.04.21-notification-audio-on-receipt-plan.md` Phase 5 (still accurate when triggered — switch to silent-relay variant per R&D recommendation).
- [ ] [LUPIN-MOBILE] On-device verify: urgent notification plays correct MP3 + speaks message (laptop + emulator; user to run)

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
