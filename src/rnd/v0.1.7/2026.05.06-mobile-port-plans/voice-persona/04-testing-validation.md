# Testing & Validation — Voice/Persona Mobile Port

**Status**: Draft — pending plan-review (Pass 2 Adversarial verifies every step's `EXECUTOR` tag)
**Last Updated**: 2026-05-06

---

## Related Documentation

- **[Index](00-index.md)** — master navigation
- **[Working Contract](00-working-contract.md)** — test-layer enumeration; user involvement gate
- **[Decisions](03-decisions.md)** — Q1–Q6 FROZEN
- **[Implementation](01-implementation.md)** — phase-by-phase task breakdown

---

## 1. Test Layer Matrix (per `00-working-contract.md`)

| Layer | Venue | Who Runs | When |
|---|---|---|---|
| 1 — `./flutter.sh test test/unit/` | Local (any host with Flutter SDK) | EXECUTOR: AI | After every Phase task that touches `lib/` |
| 1 — `./flutter.sh test test/widget/` | Local | EXECUTOR: AI | After every Phase 3 task; smoke after every other phase |
| 1 — `./flutter.sh test test/service_integration/` | Local | EXECUTOR: AI | After every Phase that touches a `Repository`-shaped class |
| 1 — `./flutter.sh test` (full) | Local | EXECUTOR: AI | At Phase-close for every phase |
| 2 — Android emulator + adb | User's laptop | EXECUTOR: HUMAN — laptop + Android SDK access required | At Phase 5 close, via existing TTS runbook (per `Q6`) |

---

## 2. Per-Phase Test Cases

### Phase 1 — Data Model

| # | Test | Layer | Executor | Asserts |
|---|---|---|---|---|
| 1.1 | `voice_persona_test.dart` — fromJson round-trip | 1 unit | AI | `VoicePersona.fromJson(serverShape).toJson() == serverShape` for normal + borrowed personas |
| 1.2 | `voice_persona_test.dart` — equality keyed on voiceId | 1 unit | AI | Two `VoicePersona` instances with same `voiceId` are `==`; different `voiceId` are `!=` |
| 1.3 | `notification_models_test.dart` — NotificationItem with persona | 1 unit | AI | `NotificationItem.fromJson` reads `voice_persona` field; preserves `null` when field absent |
| 1.4 | Fixture-backed test | 1 service_integration | AI | Uses fixture `test/_fixtures/notifications/notification-with-persona.json` (created in Phase 1 Task 1.4); verifies `NotificationRepository.fetch()` round-trips the `voice_persona` field without loss; confirms persona-absent fixture variant still parses correctly (no regression). Per Pass 1 finding F7 |

### Phase 2 — WS Event Dispatch (depends on Phase 0)

| # | Test | Layer | Executor | Asserts |
|---|---|---|---|---|
| 2.1 (matches Task 2.4.1) | `notification_bloc_test.dart` — assigned event | 1 unit (bloc) | AI | `blocTest` with `expect: [predicate((state) => state.personaFor(senderId) == persona)]` after `NotificationsVoicePersonaAssigned(senderId, persona)`. Per Pass 1 finding F3 |
| 2.2 (matches Task 2.4.2) | `notification_bloc_test.dart` — released event | 1 unit (bloc) | AI | `blocTest` with `expect: [predicate((state) => state.personaFor(senderId) == null)]` after `NotificationsVoicePersonaReleased(senderId, name)`. Per Pass 1 finding F3 |
| 2.3 (matches Task 2.4.3) | `notification_bloc_test.dart` — borrowed survives state transitions | 1 unit (bloc) | AI | After an unrelated state-change event, `state.personaFor(senderId) == persona && persona.borrowed == true` retained. Per Pass 1 finding F3 |
| 2.4 (matches Task 2.4.4) | `notification_bloc_test.dart` — release-unknown idempotent | 1 unit (bloc) | AI | Released event for sender with no current persona — `expect: []` (no state-change emit, no error). Per Pass 1 finding F3 |
| 2.5 | Phase 0 regression | 1 unit | AI | Phase 0's dispatch regression test still green; verifies inner-type discriminator works for `voice_persona_assigned` |

### Phase 3 — UI Badge

| # | Test | Layer | Executor | Asserts |
|---|---|---|---|---|
| 3.1 | `persona_badge_test.dart` — present + colored | 1 widget | AI | Badge widget tree contains a `Container` with `BoxDecoration.color == persona.color`; finder via `TestKeys.personaBadge` |
| 3.2 | `persona_badge_test.dart` — absent | 1 widget | AI | When parent passes `persona == null`, no widget is found at `TestKeys.personaBadge` |
| 3.3 | `persona_badge_test.dart` — borrowed dashed border | 1 widget | AI | When `persona.borrowed == true`, a `CustomPaint` with `DashedBorderPainter` is in the tree |
| 3.4 | `persona_badge_test.dart` — light + dark mode contrast + emoji-failure resilience | 1 widget | AI | Widget renders in both `ThemeMode.light` and `ThemeMode.dark`; basic luminance assertion (badge bg vs surface bg differ by ≥ 0.2). **Parameterized variant** (per Pass 1 finding F9): render with `persona.icon = '\u{1FAFF}'` (deliberately-broken codepoint) — assert no error, badge background color still renders, child text renders empty/substitute without crash |
| 3.5 | `conversation_screen_test.dart` — header reads bloc-cached persona | 1 widget | AI | Header shows badge keyed by current `senderId` from `personasBySender` |
| 3.6 | Final acceptance — light + dark visual review | 2 emulator | EXECUTOR: HUMAN (subjective UX) | User confirms badge color contrast and emoji rendering meets taste in both theme modes |

### Phase 4 — TTS Routing

| # | Test | Layer | Executor | Asserts |
|---|---|---|---|---|
| 4.1 | `streaming_tts_player_test.dart` — voiceId present in body | 1 unit | AI | `speak(text, voiceId: 'pNInz6obpgDQGcFmaJgB')` produces POST body containing `"voice_id": "pNInz6obpgDQGcFmaJgB"` |
| 4.2 | `streaming_tts_player_test.dart` — voiceId omitted when null | 1 unit | AI | `speak(text)` (no voiceId) produces POST body with no `voice_id` key |
| 4.3 | `streaming_tts_player_test.dart` — borrowed unchanged | 1 unit | AI | `borrowed=true` persona produces same body shape as `borrowed=false` (server treats them identically) |
| 4.4 | `tts_orchestrator_test.dart` — persona piped from notification | 1 unit | AI | When notification arrives with `voicePersona`, orchestrator calls `speak()` with that `voiceId` |
| 4.5 | `tts_orchestrator_test.dart` — quota fallback omits voiceId | 1 unit | AI | Test setup (per Pass 1 finding F11): instantiate `TtsOrchestrator` with a `MockFlutterTtsAdapter` (mocktail). Inject a `TtsErrorEvent(error_code: 'quota_exceeded')` via the orchestrator's `handleWsEvent` hook (the same hook real WS events flow through). Assert `verifyNever(() => mockFlutterTts.speak(any(), voiceId: any(named: 'voiceId')))` — fallback path is hit, voiceId never passed. Per `Q4` |

### Phase 5 — Docs + Verify

| # | Test | Layer | Executor | Asserts |
|---|---|---|---|---|
| 5.1 | Full suite | 1 unit + widget + service_integration | AI | `./flutter.sh test` returns `273 + N green / 0 failed`; N ≈ 14 across phases 1-4 |
| 5.2 | Quarantined regression check | 1 unit | AI | `test/legacy_quarantine/` count unchanged from baseline (no quarantined tests silently reactivated) |
| 5.3 | TTS runbook on-device | 2 emulator | EXECUTOR: HUMAN — laptop + Android SDK access required | User runs `<mobile>/src/rnd/v0.1.7/2026.04.24-on-device-tts-verify-runbook.md` end-to-end; confirms scenarios 5, 6, 7 (the ElevenLabs primary path) speak with the assigned per-session voice rather than Sam |

---

## 3. Convergence Criteria (full-milestone close)

This milestone is COMPLETE when ALL of the following are true:

- [ ] EXECUTOR: AI — `./flutter.sh test` → `273 + N green / 0 failed`
- [ ] EXECUTOR: AI — `pubspec.yaml` unchanged (no new dependencies introduced — REUSE pre-pass should confirm)
- [ ] EXECUTOR: AI — `git diff --stat` shows only files in §8 of `01-implementation.md`; no scope creep
- [ ] EXECUTOR: AI — `<mobile>/TODO.md` and `<mobile>/history.md` reflect milestone completion
- [ ] EXECUTOR: AI — All 6 phases' execution-log rows in `01-implementation.md` populated with test counts + commit hash
- [ ] EXECUTOR: HUMAN (subjective UX) — Badge contrast acceptance review (Phase 3 test 3.6)
- [ ] EXECUTOR: HUMAN — laptop + Android SDK access required — TTS runbook on-device confirmation (Phase 5 test 5.3)

Per `00-working-contract.md` user-involvement gate, these are the **only** human-required steps in the entire milestone. All other tests are AI-executable.

---

## 4. Test Count Forecast

Starting baseline: **273 tests green** (post-`0d54c763`, 2026-04-24).

Phase-by-phase additions:

| Phase | New tests | Cumulative |
|---|---|---|
| 1 — Data model | ~4 (1.1, 1.2, 1.3, 1.4) | 277 |
| 2 — WS dispatch | ~5 (2.1-2.5) | 282 |
| 3 — UI badge | ~5 (3.1-3.5; 3.6 is HUMAN) | 287 |
| 4 — TTS routing | ~5 (4.1-4.5) | 292 |
| 5 — docs + verify | 0 (full-suite verification only) | 292 |

**Total expected end state**: ~292 tests green (up from 273; +19 net). Adjust if REUSE pre-pass collapses/expands any test.

---

## 5. Test Failure Triage (AI-executable per the working contract)

If any Layer-1 test fails:

1. AI captures full failure output (stdout + stderr from `./flutter.sh test`)
2. AI determines root cause without asking the user (project memory: "automate smokes before recommending on-device manual testing")
3. AI proposes the fix in the next phase progress note + applies it (NOT requiring user approval per the contract — code-touching is AI-executable)
4. AI re-runs the full suite to confirm green
5. AI logs the failure-triage cycle in the phase's progress note for transparency

If a failure is **not** locally reproducible (e.g., flake suspected):
- AI runs the test 3× to confirm flakiness
- If consistently flaky, AI either fixes the underlying race OR documents a `// FLAKY:` annotation with explanation, but does NOT skip silently
- "Test is flaky, ignore" without justification is a Pass 2 Adversarial violation

If a failure is in legacy_quarantine (drift-broken pre-existing tests):
- Per project memory `feedback_legacy_test_quarantine.md`, drift-broken quarantined tests are NOT regressions
- Document the count remains unchanged (test 5.2)
