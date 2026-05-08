# TODO

Last updated: 2026-05-07 (this session continued: Phase 3 + Phase 4 + Phase 5 ALL LANDED — voice-persona milestone is CODE-COMPLETE; 308 baseline tests green; +35 across Phases 0-4; HUMAN gate (laptop+emulator runbook vp1-vp7) is the only outstanding step. **NEW R&D dropped 2026-05-07** proposing Patrol-based automation of most of vp1-vp7 — see breadcrumb below before running the runbook manually.)

---

## 🍞 BREADCRUMB — read this first on resume (2026-05-07)

**Before starting the vp1-vp7 runbook, revisit it in light of**:

- **R&D doc**: `src/rnd/v0.1.7/2026.05.07-automating-rendering-and-behaviors-on-android-emulator.md` (1079 lines, dropped 2026-05-07)
  - Title: "Lupin Voice-Persona Validation Runbook — Three-Domain Split"
  - Premise: Flutter rasterises into a single `SurfaceView`/`FlutterView` canvas, so vanilla `uiautomator`/Espresso can't see the widget tree. **Patrol** bridges this — Dart-side test driver via `integration_test` + `PatrolJUnitRunner` instrumentation — exposing Flutter's element tree to native test process while still allowing native affordances (system dialogs, dark-mode toggle) via `$.native`.
  - Three deliverables proposed:
    1. **Splitter prompt** — Claude Code prompt (`prompts/split_runbook.md`) that splits the existing `2026.04.24-on-device-tts-verify-runbook.md` §vp1-vp7 into three domain files: `automated_patrol.md` / `human_perception.md` / `metadata_signoff.md`.
    2. **Patrol bootstrap + automated tests** — full pubspec/Gradle/instrumentation-runner config + `integration_test/` files for **vp1-vp4 + vp6-infra + vp7-infra**.
    3. **Single-file Python CLI** (`tools/qa/human_signoff.py`) for the residual human-perception gates: **vp5, vp6-timbre, vp7-audible**.

**What this changes about the runbook plan**:

| Gate | Currently HUMAN | Per R&D | Net effect |
|---|---|---|---|
| vp1 inbox badge | manual visual | Patrol widget identity | automatable |
| vp2 conversation header | manual visual | Patrol widget size + colour eq | automatable |
| vp3 by-date item | manual visual | Patrol widget size + sibling layout | automatable |
| vp4 borrowed dashed | manual visual | Patrol conditional overlay | automatable |
| vp5 light/dark contrast | manual visual | **stays HUMAN** | residual |
| vp6 voice_id present | manual audible | Patrol logcat WS-envelope `voice_id` ∈ persona table; not Sam | automatable (infra) |
| vp6 timbre match | manual audible | **stays HUMAN** (perceptual) | residual |
| vp7 fallback engine | manual audible | Patrol logcat `flutter_tts` engine path + 5-min window | automatable (infra) |
| vp7 robotic cadence | manual audible | **stays HUMAN** (perceptual) | residual |

So instead of 7 manual gates, the runbook could collapse to ~3 HUMAN gates (vp5, vp6-timbre, vp7-audible) + an automated Patrol suite covering everything else.

**Decision points to consider on resume**:

1. **Adopt the R&D plan or run the runbook manually as-currently-written?** Tradeoff: Patrol bootstrap is non-trivial (pubspec deps, AndroidX instrumentation, JUnitRunner config) but durable — every future on-device milestone benefits. Manual run is one-time cost but recurs each milestone.
2. **If adopting**: which deliverable order? D1 (splitter prompt) is cheap and just rearranges docs; D2 (Patrol bootstrap) is the heavy lift; D3 (Python CLI) is single-file. Probably D1 → D3 → D2.
3. **If adopting**: file the manual `vp1-vp7` runbook section I added 2026-05-07 as the "fallback runbook" — the Patrol suite + Python CLI become the primary path, and the manual section stays as backup for environments where Patrol can't run.
4. **If skipping for now**: file an explicit defer item with revisit-trigger (e.g., "revisit when a 2nd milestone needs on-device verification"). Don't lose the R&D — it's a substantial design proposal.

**Why this matters**: per the auto-memory `feedback_automate_over_manual_tests` rule, I should default to automating. The R&D presents a credible path to do that for ~⅔ of the gates I just told you to run by hand. Worth at least a 30-minute design conversation before committing to the manual run.

---

## ⭐ NEXT SESSION — START HERE: voice-persona milestone HUMAN gate (laptop+emulator runbook execution)

**Voice-persona milestone is CODE-COMPLETE** as of 2026-05-07. All 6 phases AI-executable work has landed. The only remaining step is the HUMAN runbook execution on a real device — single laptop+emulator session running `src/rnd/v0.1.7/2026.04.24-on-device-tts-verify-runbook.md` §"Voice-persona milestone gate" steps vp1-vp7 (5 visual + 2 audible). Sign-off in the runbook closes the milestone.

**⚠️ But see the breadcrumb above** — review the new R&D doc on automating most of these gates before committing to the manual run.

### Order of operations

1. **Phase 0 — WS dispatch audit + regression test** ✅ DONE 2026-05-06 (session `a756441c` continuation)
   - Plan: `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/00-phase-0-dispatch-audit.md` — §5 checkboxes all marked complete; §6 success criteria all met; §10 audit findings populated
   - Verdict realized: 🟡 PARTIAL DRIFT (matches REUSE pre-confirm)
   - Code change: `notification_bloc.dart:146-185` `_onExternalUpdate` extended with `switch (n.type)` — whitelisted types route to existing audio+TTS path; default branch logs unknown types
   - New test: `test/unit/notifications/notification_bloc_dispatch_test.dart` (3 tests, all green)
   - Test impact: 273 → 276 baseline (+3); 44 quarantined unchanged

2. **Voice-persona Phase 1 — Data model** ✅ DONE 2026-05-06 (session `a756441c` continuation)
   - New `lib/features/notifications/data/voice_persona.dart` — liberal `fromJson` per Q7, null-defense per F1, equality keyed on `voiceId`
   - Modified `notification_models.dart` — `NotificationItem.voicePersona` field + `fromJson` reader (handles missing/null/object); re-exports `VoicePersona`
   - Fixture `test/fixtures/notifications/notification-with-persona.json` (canonical Adam allocation)
   - 14 new tests: voice_persona_test.dart (9), notification_models_test.dart (+3 net new), notification_repository_test.dart (+2 fixture-backed round-trip)
   - Test impact: 276 → 290 baseline; 44 quarantined unchanged

3. **Voice-persona Phase 2 — WS event dispatch** ✅ DONE 2026-05-06 (session `a756441c` post-checkpoint)
   - 2 new bloc events (`NotificationsVoicePersonaAssigned`/`Released`)
   - `PersonaSnapshotMixin` on 4 loaded states; `personaFor(senderId)` accessor
   - `_personasBySender` bloc instance field + `_personasSnapshot()` defensive copy threaded through 7 emit sites
   - `_onExternalUpdate` switch extended with explicit voice-persona cases (default-branch logger preserved)
   - 4 new blocTests (Pass-1-F3 assertion shapes): assigned, released, borrowed-survives, release-unknown idempotent
   - Test impact: 290 → 294 baseline; 44 quarantined unchanged

4. **Voice-persona Phase 3 — UI badge** ✅ DONE 2026-05-07 (this session)
   - New `lib/shared/painters/dashed_border_painter.dart` (60-line `CustomPainter` per Q9)
   - New `lib/features/notifications/presentation/persona_badge.dart` (StatelessWidget wrapping `CircleAvatar`, hex-color parser with theme-primary fallback, F9 failure-mode contract — color always renders even when emoji glyph fails, 28px header / 24px in-card sizing)
   - Extended `test_keys.dart` with `personaBadgePrefix` + `personaBadgeDashedPrefix`
   - Wired into 3 surfaces:
     - `_SenderTile` (inbox) — parent passes `state.personaFor(senderId)` to tile; PersonaBadge in `leading:` slot when persona present, falls back to existing CircleAvatar
     - `ConversationScreen` AppBar — `BlocSelector<NotificationBloc, NotificationState, VoicePersona?>` reading `state.personaFor(widget.senderId)` (state guarded by `is PersonaSnapshotMixin`); 28px badge + senderId text via Row
     - `_NotificationItemCard` (conversation_by_date) — reads `item.voicePersona` directly per Q1; 24px badge inline next to priority chip
   - 8 new widget tests: 6 in new `persona_badge_test.dart` (3.1 present+colored / 3.2 absent / 3.3 borrowed dashed / 3.4a light+dark / 3.4b broken-emoji codepoint resilience / malformed-color defensive); +2 in `conversation_screen_test.dart` (3.5 header reads bloc-cached / header omits when empty)
   - Test impact: 294 → 302 baseline; 44 quarantined unchanged
   - **Pending HUMAN final acceptance**: badge color/contrast review in light + dark mode (gated on laptop+emulator per `feedback_dev_server_laptop_split` — bucket with TTS on-device verification at Phase 5 close)

5. **Voice-persona Phase 4 — TTS routing (collapsed verify+comment)** ✅ DONE 2026-05-07 (this session)
   - 13-line dartdoc on `streaming_tts_player.dart:speak()` flagging `voiceId` as persona pipe-through (Q3); absent-→-Sam server contract documented
   - 11-line "intentional omit" comment block inside `tts_orchestrator.dart:_speakViaFallback` (Q4 — different voice space)
   - Wired `enqueueIfSpeakable.voiceId` → `_Utterance.voiceId` → `_player.speak(voiceId:)`
   - `NotificationBloc._onExternalUpdate` passes `voiceId: n.voicePersona?.voiceId` at the `enqueueIfSpeakable` call site
   - 6 new tests: 3 in `streaming_tts_player_test.dart` (4.1 voiceId in body / 4.2 omitted when null / 4.3 borrowed body shape unchanged); 3 in `tts_orchestrator_test.dart` (4.4 persona piped from notification / 4.4b null voiceId defensive / 4.5 quota fallback omits voiceId per Q4+F11)
   - Test impact: 302 → 308 baseline (+6; plan estimated +5, the +1 is 4.4b defensive); 44 quarantined unchanged

6. **Voice-persona Phase 5 — Docs + on-device verify** ✅ AI complete 2026-05-07 (this session); ⏳ HUMAN gate pending
   - All 5 AI tasks complete: TODO.md (this entry) + `00-index.md` Current Status to milestone code-complete + `01-implementation.md` §9 Phase 5 row populated + history.md session-end entry + 308 ✅ baseline confirmed + 44 ❌ quarantine unchanged + on-device runbook extended
   - Runbook extension: 7 new acceptance steps (vp1-vp7) bundling BOTH outstanding HUMAN gates per user direction 2026-05-07
     - vp1-vp5: Phase 3 visual gates (inbox / conversation header / by-date item / borrowed dashed / light+dark contrast)
     - vp6-vp7: Phase 4 audible gates (persona timbre vs Sam / quota fallback uses device flutter_tts per Q4)
     - Persona timbre cheat sheet for the 6-voice pool inline
   - Test impact: 308 ✅ baseline confirmed (unchanged from Phase 4 close — Phase 5 is doc-only); 44 ❌ quarantine drift baseline unchanged
   - **HUMAN gate** (single laptop+emulator session): execute `src/rnd/v0.1.7/2026.04.24-on-device-tts-verify-runbook.md` §"Voice-persona milestone gate" steps vp1-vp7; sign off in the runbook's progress log; that closes the milestone

### Earlier next-session task — still pending, now bucketed

- On-device verification of TTS + notification-audio pipelines (from session `0d54c763`) — bucketed into voice-persona Phase 5 per `Q6` (existing TTS runbook is the verification artifact). Will execute when voice-persona Phase 5 closes.

1. **Notification audio (shipped in commit `180a4ba`, 2026-04-21)** —
   dings and `flutter_tts` speech for high/urgent notifications. Never
   verified on device.
2. **Agent-narration TTS (shipped as Phase 1–5 on 2026-04-21 +
   overlap fix 2026-04-24)** — `StreamingTtsPlayer` + `TtsOrchestrator`.
   Never run on device. Scenario #7 (FIFO rapid-fire) is the regression
   test for the 2026-04-24 overlap fix — MUST pass or the fix regressed.

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

### ⚡ First thing next session — hygiene-commit follow-ups (from 2026-04-23 gitignore cleanup, commit `edaec79`)
- [ ] [LUPIN-MOBILE] Run `flutter pub get` sanity check — confirm the newly-untracked `.dart_tool/` regenerates cleanly on next build; catches any surprise from the un-track. Low risk since disk copies are intact, but worth a deliberate verification pass.
- [ ] [LUPIN-MOBILE] Decide whether to add a `history.md` one-liner for commit `edaec79` — the chore is fully documented in the commit message itself; decision is: keep history.md for feature/bug work only, or backfill a one-liner for this cleanup.
- [ ] [LUPIN-MOBILE] Decide whether to purge `build_runner.dart-3.8.0.snapshot` (~26MB binary) from git history — requires `git filter-repo` + force-push; permanently reduces clone size but rewrites history. Only worth it if the repo is mirrored/cloned frequently.
- [ ] [LUPIN-MOBILE] Audit parent Lupin + other sub-repos (cosa, lupin-plugin-firefox) for the same gitignore gaps — consistency pass; may not apply since those aren't Flutter projects, but .claude-session.md / __pycache__ gaps might recur elsewhere. (Out of scope for lupin-mobile repo; would need to be done in each repo's own context.)

### On-Device Sanity Pass (login confirmed on device 2026-04-17; remaining sanity checks still open)
- [x] [LUPIN-MOBILE] Device sanity: login works end-to-end (envelope fix verified on emulator) — 2026-04-17
- [ ] [LUPIN-MOBILE] Device sanity: open Inbox (widget-level covered by `inbox_screen_test.dart` × 4 cases)
- [ ] [LUPIN-MOBILE] Device sanity: respond to an ask_yes_no from Inbox (widget-level covered by `conversation_screen_test.dart` × 3 cases)
- [ ] [LUPIN-MOBILE] Device sanity: Trust Dashboard renders (widget-level covered by `trust_dashboard_screen_test.dart` × 3 cases)
- [ ] [LUPIN-MOBILE] Device sanity: DeepResearch dry-run submits (widget-level covered by `deep_research_form_test.dart` × 3 cases)
- [ ] [LUPIN-MOBILE] Device sanity: run `integration_test/smoke_hello_test.dart` via `flutter test integration_test/` on emulator (proves scaffolding)

### Tier 2 — Notifications + Decision Proxy (polish remaining)
- [x] [LUPIN-MOBILE] Date-grouped `ConversationByDateScreen` (Option A: separate `_NotificationItemCard` for `NotificationItem` field set; sectioned by date desc; reachable via calendar AppBar action → `SenderDatesScreen` → date tile tap; 6 widget tests + 1 bloc test). — 2026-04-22
- [x] [LUPIN-MOBILE] Sender-dates drilldown — `SenderDatesScreen` with calendar tile list, `newCount` badge; 5 widget tests + 1 bloc test; calendar AppBar action on `ConversationScreen`. — 2026-04-22
- [x] [LUPIN-MOBILE] `generate-gist` UI on ConversationScreen ("Summarize" action) — Summarize button + bottom sheet; `NotificationsGenerateGistRequested` event + `NotificationsGistLoading`/`Ready` states + bloc handler; 3 widget tests — 2026-04-21
- [x] [LUPIN-MOBILE] `TrustStateScreen` drilldown — per-domain grouped trust-state list with circuit-breaker badge, "View trust details" action on `TrustDashboardScreen`; reuses existing `DecisionProxyLoadTrust` event/state/handler (no new bloc plumbing); 5 widget tests. — 2026-04-22
- [ ] [LUPIN-MOBILE] ~~Decide whether to remove orphaned `lib/shared/models/notification_item.dart`~~ — **Revised finding 2026-04-21**: NOT orphan. Re-exported via `lib/shared/models/models.dart` and imported by 20+ production files (voice bloc, audio cache, repositories, use cases). There are now two `NotificationItem` classes — the old shared one and a newer differently-shaped one in `features/notifications/data/notification_models.dart`. Migration would require touching voice/audio/cache layers. **Reclassified: leave in place; no action unless voice/audio/cache layers are refactored.**

### Agent-narration TTS (new 2026-04-21)
- [x] [LUPIN-MOBILE] Phase 0 — Plan serialized to `src/rnd/v0.1.7/2026.04.21-agent-narration-tts-plan.md` — 2026-04-21
- [x] [LUPIN-MOBILE] Phase 1 — Built slim `StreamingTtsPlayer` (abandoned the legacy `EnhancedTTSService` revival; 2.7K lines of parallel WS infra would have been pulled in for no marginal benefit). Reuses live `WebSocketService` + `Dio`. Renamed binary-frame wrapper type to `audio_streaming_chunk`. — 2026-04-21
- [x] [LUPIN-MOBILE] Phase 2 — `TtsOrchestrator`: FIFO queue + priority gate + urgent preempt + quota fallback (5min window) — 2026-04-21
- [x] [LUPIN-MOBILE] Phase 3 — Removed auto-priority `flutter_tts` branch from `NotificationAudioService`; exposed `flutterTtsSpeak()` + `stopFallbackSpeech()` as orchestrator fallback helpers. Wired `TtsOrchestrator` into `NotificationBloc._onExternalUpdate`. — 2026-04-21
- [x] [LUPIN-MOBILE] Phase 4 — 11 new orchestrator tests + 1 new bloc→tts test + rewrote notification_audio_service_test.dart for split responsibilities. — 2026-04-21
- [x] [LUPIN-MOBILE] Overlap bug fix + `StreamingTtsAudioPlayer` test seam — `TtsCompleteEvent` now gated on `AudioPlayer.onPlayerComplete`, completer + identity guard so `stop()` doesn't emit a stray complete. 8 new regression tests + 2 flag-coverage tests. Unit count 177 → 187. — 2026-04-24 session `0d54c763`
- [x] [LUPIN-MOBILE] Quota-simulation hook — `LUPIN_DEV_SIMULATE_TTS_ERROR` dart-define for scenario #8 (mobile injects `debug_simulate_error=true`, backend emits `tts_error`). — 2026-04-24 session `0d54c763`
- [x] [LUPIN-MOBILE] Scenario-firing script — `src/scripts/fire-tts-scenarios.py` (12 scenarios, Python/`requests`, dry-run + single-scenario modes, auto-rapid-fire for FIFO test). — 2026-04-24 session `0d54c763`
- [x] [LUPIN-MOBILE] On-device verify runbook — `src/rnd/v0.1.7/2026.04.24-on-device-tts-verify-runbook.md` (copy-paste-ready for laptop). — 2026-04-24 session `0d54c763`
- [ ] [LUPIN-MOBILE] On-device verify TTS: live ElevenLabs audio plays in the emulator (user's laptop); injected `quota_exceeded` falls back to `flutter_tts` cleanly. **Scenario #7 is the regression test for the 2026-04-24 overlap fix.**
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
- [scope decision 2026-04-22] **TimeSavedDashboard + StatsRepository + StatsBloc + `fl_chart`** — deferred indefinitely per user; not in any current slate. Re-add only on explicit request.
- [x] [LUPIN-MOBILE] **Phase 4a**: Wire `audioplayers` for in-app audio playback in `AudioArtifactPlayer` — UI rebuilt around `AudioPlayer` + `DeviceFileSource`; extracted `AudioPlaybackController` interface for testability; calls `TtsOrchestrator.stopAll()` before play; preserved Share as overflow action; 7 widget tests (download, play, pause/resume, stop, share, empty-path). Plan: `src/rnd/v0.1.7/2026.04.22-tier-2-and-4-polish-plan.md`. — 2026-04-22
- [ ] [LUPIN-MOBILE] On-device verify Phase 4a — load a podcast/research-podcast artifact (or any MP3 path until Phase 4b backend fix lands), test play/pause/stop/share + audio-focus interaction with TTS narration. Bucket with the existing TTS on-device verification.
- [ ] [LUPIN-MOBILE] **Phase 4b (deferred, blocked on cross-repo)**: switch `JobDetailScreen` for `pg-*`/`rp-*` jobs to use real `audioPath` field — blocked on parent Lupin exposing `artifacts['audio_path']` in queue metadata. See `bug-fix-queue.md` Cross-Repo entry.

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
- [x] [LUPIN-MOBILE] TTS overlap bug fix + on-device verify prep (session `0d54c763`): `StreamingTtsAudioPlayer` test seam + playback-gated `TtsCompleteEvent` + `LUPIN_DEV_SIMULATE_TTS_ERROR` dart-define + 10 new regression/flag tests + `fire-tts-scenarios.py` script + runbook. 263→273 green. Runbook: `src/rnd/v0.1.7/2026.04.24-on-device-tts-verify-runbook.md`. — 2026-04-24
- [x] [LUPIN-MOBILE] Tier 2 + Tier 4 polish slate (session `40aa03d3`): TrustStateScreen drilldown + SenderDatesScreen + ConversationByDateScreen + AudioArtifactPlayer in-app playback rebuild. 4 phases, 22 widget tests + 2 bloc tests, 237→263 green. Plan: `src/rnd/v0.1.7/2026.04.22-tier-2-and-4-polish-plan.md`. — 2026-04-22
- [x] [LUPIN-MOBILE] Cross-repo bug filed: parent Lupin `routers/queues.py:456,523` omits `artifacts['audio_path']` mapping for `pg-*`/`rp-*` jobs. Blocks Phase 4b. — 2026-04-22
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
