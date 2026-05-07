# Implementation — Voice/Persona Mobile Port

**Status**: Draft — pending plan-review
**Last Updated**: 2026-05-06

---

## Related Documentation

- **[Index](00-index.md)** — master navigation
- **[Working Contract](00-working-contract.md)** — rules of engagement; user involvement gates
- **[Decisions](03-decisions.md)** — Q1–Q6 FROZEN 2026-05-06
- **[Testing & Validation](04-testing-validation.md)** — full EXECUTOR-tagged test matrix
- **[Phase 0 prerequisite](../00-phase-0-dispatch-audit.md)** — WS dispatch audit; blocks this milestone

---

## 1. Background — Server-side facts

These are LOCKED. No design exposure on the mobile side. See parent design at `<parent-lupin>/src/rnd/v0.1.7/2026.04.28-per-session-voice-personas/01-design.md` for full rationale.

### 1.1 Bridge schema (per CC session)

```json
"voice_persona": {
  "name"        : "Adam",
  "voice_id"    : "pNInz6obpgDQGcFmaJgB",
  "icon"        : "🌑",
  "color"       : "#3F51B5",
  "borrowed"    : false,
  "assigned_at" : "2026-04-28T20:33:42Z",
  "display_name": "Adam"
}
```

`borrowed=true` means the 6-voice pool was exhausted at allocation time and a deterministic-hash fallback was assigned. Mobile renders this as a dashed-border badge variant per `Q2`.

### 1.2 Endpoints (mobile is a CONSUMER, not a caller)

Mobile does NOT call these — the SessionStart hook on the dev server handles them. Listed only for reference.

| Verb | Path | Purpose |
|---|---|---|
| POST | `/api/cosa-voice/voice-persona/{sid}/allocate` | Server-only — atomic claim |
| POST | `/api/cosa-voice/voice-persona/{sid}/release`  | Server-only — clear bridge |
| GET  | `/api/cosa-voice/voice-persona/sample`          | Dev tools / debug |

### 1.3 WS events (mobile MUST handle)

Both ride **inside** `notification_queue_update` envelopes (per the 2026-04-29 WS-event-cleanup migration). Phase 0 (`../00-phase-0-dispatch-audit.md`) must have landed first so the inner-type discriminator dispatches correctly.

| Inner `notification.type` | Payload (`notification.voice_persona`) | When |
|---|---|---|
| `voice_persona_assigned` | full persona dict (§1.1 shape) | At SessionStart for each new CC session; also after `/clear` re-assignment |
| `voice_persona_released` | `{ name, released: true }`           | At SessionEnd |

A re-assignment after `/clear` arrives as: **first** a `voice_persona_assigned` for the new persona, **then** a separate `task`-type notification with `Voice re-assigned: X → Y`. Mobile only handles the first; the second renders as an ordinary notification.

**Server ordering guarantee** (per Pass 1 finding F6, applied 2026-05-06): server-side `voice_persona.py:202-211` (the `voice_persona_assigned` push) and `:222-232` (the announcement push) issue the two `notification_queue.push_notification()` calls sequentially in that order. Mobile receives them in the same order via the WS envelope sequence.

**Mobile resilience to ordering deviations** (defensive, in case server changes):
- Only `voice_persona_assigned` arrives (no announcement): handled normally — state map updated, persona used for next TTS. The announcement is purely informational; its absence is not an error.
- Only the announcement arrives without prior `voice_persona_assigned`: log a warning (`[VOICE-PERSONA] announcement received without prior assignment`); render the notification as ordinary `task` — no state-map change.
- Reverse order: persona-assigned event still updates state correctly; announcement renders ordinarily. No special ordering logic required mobile-side.

### 1.4 Notification stamping

Server stamps `voice_persona` onto **every outbound notification** for that session, sourced from the bridge file (parent §4.3). Mobile reads the persona straight from the notification payload — **no separate persona cache** (per `Q1`). Falls back to no-persona when absent (server then falls back to Sam, today's behavior).

---

## 2. Phase 1 — Data Model

**Status**: ✅ COMPLETE 2026-05-06 (session a756441c continuation, post-Phase-0)
**Goal**: Mirror server's persona shape in Dart; extend `NotificationItem` with persona field; ensure fixtures cover both presence + absence.
**Test delta**: 276 → 290 (+14 net new) across 3 test files — meets the §4 forecast for Phase 1.

### Tasks (sequential — Task 1.3 depends on 1.1; Task 1.4 depends on 1.3; Task 1.5 depends on 1.1, 1.2, 1.3)

- [x] **Task 1.1** — EXECUTOR: AI — Create `lib/features/notifications/data/voice_persona.dart`. Required fields: `name`, `voiceId`, `icon`, `color`, `borrowed`, `assignedAt`, `displayName`. `fromJson` is **liberal** per `Q7` (FROZEN at REUSE 2026-05-06) — no enum validation, accepts any string field. **Null-defense contract** (per Pass 1 finding F1, applied 2026-05-06): malformed or missing fields default to `null`; consumers (Phase 3 widgets, Phase 4 TTS dispatch) MUST null-check before use; throw nothing — degrade gracefully to no-persona behavior so server-stamp absence cleanly flows to Sam fallback per `Q3`. — File created 87 lines; library doc-comment cross-references parent design + voice-persona milestone docs; null-defense honored via `_asStr` helper that returns null on type mismatch.
- [x] **Task 1.2** (depends on 1.1) — EXECUTOR: AI — Override `==` and `hashCode` on `VoicePersona` keyed on `voiceId`. — implemented in same file; comment notes acceptable collision (same-voiceId different-session compares equal; bloc state map keys on senderId, not persona identity).
- [x] **Task 1.3** (depends on 1.1) — EXECUTOR: AI — Extend `lib/features/notifications/data/notification_models.dart` `NotificationItem` with `VoicePersona? voicePersona` field; update `fromJson` to read `voice_persona` from envelope; preserve null when absent. — added field + constructor param + `fromJson` reader (liberal: handles map/null/missing); also re-exported `VoicePersona` from `notification_models.dart` for convenience.
- [x] **Task 1.4** (depends on 1.3) — EXECUTOR: AI — Add fixture variant `test/fixtures/notifications/notification-with-persona.json`; update an existing fixture to confirm persona-absent path still works. — fixture created (canonical Adam allocation, borrowed=false); plan's `test/_fixtures/...` path was a typo — actual project layout uses `test/fixtures/` (per `_helpers/fixture_loader.dart:9`). Persona-absent path covered by reusing existing `list_response.json` fixture in regression test.
- [x] **Task 1.5** (depends on 1.1, 1.2, 1.3) — EXECUTOR: AI — Run unit tests. — `./flutter.sh test test/unit/notifications/voice_persona_test.dart`: 9/9 pass. `./flutter.sh test test/unit/notifications/`: 42/42 pass (was 27 before this phase; +15 = 9 + 4 model + 2 repo). Full baseline-tracked suite (`test/unit/ test/widget/ test/service_integration/`): 290/290 pass.

### Risks (Phase 1)

- **REUSE risk** — there may already be a `lib/shared/models/` persona-shaped class from earlier work; the REUSE pre-pass catches this before code is written.
- **Equality semantics** — keying equality on `voiceId` means two same-voice-different-session personas compare equal. Acceptable for our usage (we look up persona-by-session via `senderId`, not by persona identity), but worth a comment.

### Files Modified / Created in Phase 1

- New: `lib/features/notifications/data/voice_persona.dart`
- New: `test/unit/features/notifications/data/voice_persona_test.dart`
- New: `test/_fixtures/notifications/notification-with-persona.json`
- Modified: `lib/features/notifications/data/notification_models.dart` (add `voicePersona` field)

---

## 3. Phase 2 — WS Event Dispatch

**Status**: ✅ COMPLETE 2026-05-06 (session a756441c continuation, post-checkpoint `fd8fc18`)
**Depends on**: Phase 0 (`../00-phase-0-dispatch-audit.md`) — inner-type dispatch table must already route by `notification.type` discriminator. ✅ landed in checkpoint `fd8fc18`.
**Test delta**: 290 → 294 (+4 net new) — all 4 Pass-1-F3 assertion-shape blocTests in a new `notification_bloc_persona_test.dart`.

### Tasks

- [x] EXECUTOR: AI — Add bloc events to `lib/features/notifications/domain/notification_event.dart`:
  - `NotificationsVoicePersonaAssigned(senderId, persona)` — props: senderId + persona.voiceId
  - `NotificationsVoicePersonaReleased(senderId, personaName)` — props: senderId + personaName
- [x] EXECUTOR: AI — Extend `notification_state.dart` loaded states with `Map<String, VoicePersona> personasBySender` plus helper `VoicePersona? personaFor(String senderId)`. Per `Q1`, this map is for **header rendering only**, not for TTS dispatch. — implemented via `PersonaSnapshotMixin` shared by all 4 loaded states (`InboxLoaded`, `ConversationLoaded`, `SenderDatesLoaded`, `ConversationByDateLoaded`); each state has `personasBySender` field defaulting to const `{}`; `personaFor(senderId)` is a default mixin method.
- [x] EXECUTOR: AI — Inside `notification_bloc.dart` `_onExternalUpdate`, pivot on inner `notification.type`. Route persona-assigned → emit state with persona keyed in; persona-released → emit state with key removed. Other inner types fall through to existing logic. — added 2 explicit cases (`voice_persona_assigned`, `voice_persona_released`) before the default-branch logger; both mutate `_personasBySender`; the existing `_refreshCurrent` emit picks up the snapshot. Bloc instance field `_personasBySender` + helper `_personasSnapshot()` (defensive `Map.unmodifiable` copy) added; threaded through 7 loaded-state emit sites (4 LoadX handlers + 3 `_refreshCurrent` cases). New private helper `_emitCurrentSnapshot(emit)` for the dedicated event handlers (test path).
- [x] EXECUTOR: AI — `blocTest` cases (with explicit assertion shapes per Pass 1 finding F3, applied 2026-05-06):
  - [x] **2.4.1** — assigned event arrives → `predicate<NotificationsInboxLoaded>((s) => s.personaFor("s-1") == _adam)` ✅
  - [x] **2.4.2** — released event arrives → `predicate<...>((s) => s.personaFor("s-1") == null)` after assigned-then-released sequence ✅
  - [x] **2.4.3** — borrowed=true survives → after `LoadInbox` re-emit, `s.personaFor("s-1")?.borrowed == true && voiceId == _bellaBorrowed.voiceId` ✅
  - [x] **2.4.4** — released for unknown sender is idempotent → `expect: const <NotificationState>[]` (no emit) ✅
- [x] EXECUTOR: AI — Run `./flutter.sh test test/unit/notifications/notification_bloc_persona_test.dart` — 4/4 pass. Full baseline-tracked: 290 → 294 ✅. Phase 0 regression test (`notification_bloc_dispatch_test.dart`) still green — its `voice_persona_assigned` test case still asserts no audio/TTS calls; the new explicit case branch doesn't fire audio/TTS (only mutates the persona map), so the assertion still holds.

### Risks (Phase 2)

- **Phase 0 hasn't landed yet** — if dispatch table doesn't route inner-type, this phase produces dead code. **HARD BLOCKER** until Phase 0 closes.
- **State map churn** — emitting a new map for every persona-assigned could trigger over-rebuild in `BlocBuilder`s. Mitigation: use `BlocBuilder.buildWhen` filter to only rebuild when the local sender's persona changes.

### Files Modified / Created in Phase 2

- Modified: `lib/features/notifications/domain/notification_event.dart` (+2 events)
- Modified: `lib/features/notifications/domain/notification_state.dart` (+map + helper)
- Modified: `lib/features/notifications/domain/notification_bloc.dart` (+inner-type pivot, +2 handlers)
- New tests: `test/unit/features/notifications/domain/notification_bloc_test.dart` extensions

---

## 4. Phase 3 — UI Badge

**Status**: PLANNED

### Tasks

- [ ] EXECUTOR: AI — Create `lib/features/notifications/presentation/persona_badge.dart` as a `StatelessWidget` **wrapping `CircleAvatar`** (per REUSE pre-pass `extend-existing` finding — see `00-index.md` "Prior art referenced"; sibling pattern at `inbox_screen.dart:~186`). Emoji from `persona.icon` rendered as the avatar child; background color from `persona.color`; long-press shows `displayName` tooltip; dashed-border variant when `borrowed=true` via a `CustomPaint` overlay using the new `DashedBorderPainter` (per `Q2`).
- [ ] EXECUTOR: AI — Create `lib/shared/painters/dashed_border_painter.dart` — a `CustomPainter` subclass drawing a dashed stroke around its boundary `Rect`. Per `Q9` (FROZEN at REUSE pre-pass — confirmed genuinely-new; no existing `CustomPainter` subclass and no dashed-border package in `pubspec.yaml`).
- [ ] EXECUTOR: AI — Add `TestKeys` constants to `lib/core/testing/test_keys.dart` for badge + dashed variant.
- [ ] EXECUTOR: AI — Wire badge into 3 surfaces (per `Q5`, badge only — exact paths per Pass 1 finding F2, applied 2026-05-06):
  - `_NotificationItemCard` in `lib/features/notifications/presentation/conversation_by_date_screen.dart` — read persona directly from the `NotificationItem` (per `Q1`)
  - `ConversationScreen` header in `lib/features/notifications/presentation/conversation_screen.dart` — read from bloc-cached `personasBySender` keyed on `senderId`
  - Inbox sender tile in `lib/features/notifications/presentation/inbox_screen.dart` (CircleAvatar at `:~186` per REUSE pre-pass) — same pattern as conversation header
- [ ] EXECUTOR: AI — Widget tests: persona present → badge renders with correct color (verified by finder + key); persona absent → no badge in tree; borrowed variant → dashed border verified.
- [ ] EXECUTOR: AI — Run `./flutter.sh test test/widget/notifications/persona_badge_test.dart` — assert all 3 widget tests pass.
- [ ] EXECUTOR: HUMAN (subjective UX) — Final acceptance review: confirm badge color/contrast in light + dark mode meets visual taste. Per `00-working-contract.md` user-involvement gate item 3.

### Risks (Phase 3)

- **Color contrast in dark mode** — server's persona colors are vibrant (`#E91E63` pink, `#FFA000` amber) and may have low contrast on dark surface backgrounds. Mitigation: use `Color.computeLuminance()` to dim the badge background or boost border contrast in dark theme; widget test parameterizes both themes.
- **Emoji rendering** — Android emoji rendering varies by API level + manufacturer skin. Mitigation: stick to common emoji from the 6-voice pool (🌸🦉🕊️🌑⚡🪨), all of which render reliably on API 24+. **Failure-mode contract** (per Pass 1 finding F9, applied 2026-05-06): badge always renders with the persona color background regardless of emoji success. Emoji is rendered as the `CircleAvatar` child via `Text(persona.icon, …)`. If emoji renders as tofu/empty/substituted, the badge still presents the persona color (the primary disambiguator). No crash. No fallback to letter substitution (`persona.name[0]`) — color-only is acceptable degradation.

### Files Modified / Created in Phase 3

- New: `lib/features/notifications/presentation/persona_badge.dart`
- New (conditional, REUSE-dependent): `lib/shared/painters/dashed_border_painter.dart`
- New: `test/widget/notifications/persona_badge_test.dart`
- Modified: `lib/features/notifications/presentation/conversation_by_date_screen.dart` (badge in `_NotificationItemCard`)
- Modified: `lib/features/notifications/presentation/conversation_screen.dart` (badge in header)
- Modified: `lib/features/notifications/presentation/inbox_screen.dart` (badge in sender tile)
- Modified: `lib/core/testing/test_keys.dart`

---

## 5. Phase 4 — TTS Routing

**Status**: PLANNED

### Tasks

- [ ] EXECUTOR: AI — **REUSE-AS-IS verified** at 2026-05-06: `StreamingTtsPlayer.speak()` already has the `String? voiceId` parameter (`streaming_tts_player.dart:130`) and the body wiring at `:141` already uses `if (voiceId != null) body['voice_id'] = voiceId`. Per REUSE pre-pass — see `00-index.md` "Prior art referenced". Phase 4 Task 4.1 collapses to **verification + comment**: add a code comment at `:130` flagging this parameter as the documented persona pipe-through path; confirm via test that body shape matches `Q3` spec.
- [ ] EXECUTOR: AI — Add a code comment in the fallback path of `tts_orchestrator.dart` explicitly stating that `voiceId` is intentionally NOT piped through to the `flutter_tts` fallback (different voice space). Per `Q4`. The comment exists to prevent a future maintainer from "fixing" this; Pass 2 Adversarial would otherwise flag the missing test coverage that this comment forestalls.
- [ ] EXECUTOR: AI — Wire orchestrator → `notification.voicePersona?.voiceId`. `tts_orchestrator.dart` reads the persona straight off the notification (per `Q1`) and passes through to the **already-wired** `streamingTtsPlayer.speak(text, voiceId: ...)`.
- [ ] EXECUTOR: AI — TTS unit tests covering existing-but-untested behavior + new orchestrator pipe-through: body includes `voice_id` when persona present; body omits `voice_id` when persona absent; `borrowed=true` does not change the call site; orchestrator calls `speak()` with `voiceId` from notification.voicePersona.
- [ ] EXECUTOR: AI — Run `./flutter.sh test test/unit/services/tts/` — assert all new tests pass plus existing 10 regression tests stay green.

### Risks (Phase 4)

- **Absent-persona fallback path** — server-side fallback to Sam is what we depend on (existing behavior, unchanged). If a future server change rejects persona-less requests, mobile would break silently. Mitigation: integration test fixture covering the absent-persona case.
- ~~**Body-key bug carry-over**~~ — REUSE pre-pass confirmed `streaming_tts_player.dart:141` already uses `voice_id` as the body key. No carry-over risk; this risk is **retired** at 2026-05-06 REUSE pre-pass.

### Files Modified / Created in Phase 4

- Modified: `lib/services/tts/streaming_tts_player.dart` — **comment + verify only** (parameter already wired per REUSE pre-pass)
- Modified: `lib/services/tts/tts_orchestrator.dart` (+pipe `notification.voicePersona?.voiceId` + intentional-omit comment in fallback)
- Modified (or extended): `test/unit/services/tts/streaming_tts_player_test.dart` (+ tests for the existing-but-uncovered `voiceId` parameter + new orchestrator pipe-through)

---

## 6. Phase 5 — Documentation + Verify

**Status**: PLANNED

### Tasks

- [ ] EXECUTOR: AI — Update `<mobile>/TODO.md` (per Pass 1 finding F4, applied 2026-05-06): (a) mark each of the 12 implementation tasks enumerated in §2-§6 of this doc as `[x]`; (b) add a single 'Completed (Recent)' entry referencing this milestone's commit hash; (c) leave all other open items unchanged. **Do NOT do a wider TODO sweep** — out of scope for this milestone.
- [ ] EXECUTOR: AI — Update `<mobile>/history.md`: append a session-end entry per the standard template.
- [ ] EXECUTOR: AI — Run `./flutter.sh test` — assert full suite is `273 + N green / 0 failed` where N is the count of new tests added across phases 1-4 (~10).
- [ ] EXECUTOR: AI — Verify no quarantined tests reactivated (per `<global>~/.claude/CLAUDE.md` legacy quarantine rule).
- [ ] EXECUTOR: HUMAN — laptop + Android SDK access required — Run existing TTS verify runbook at `<mobile>/src/rnd/v0.1.7/2026.04.24-on-device-tts-verify-runbook.md` scenarios 5-7 (ElevenLabs primary path; no new on-device step per `Q6`). **Additional assertion for this milestone** (per Pass 1 finding F5, applied 2026-05-06): confirm voice timbre matches session's allocated persona — e.g., if `get_session_info()` shows Adam allocated, voice heard should be deep male (not Sam's neutral default). Record the persona name + perceived voice character in the session's progress note.

### Phase 5 closure criterion

Phase 5 closes when:
1. Test count is `273 + N green / 0 failed` (AI evidence: test output)
2. `TODO.md` and `history.md` reflect completion (AI evidence: file diff)
3. User has run the existing TTS runbook on emulator and confirmed per-session voice (HUMAN evidence: user note in this doc's Progress Notes)

Per `00-working-contract.md`, items 1+2 are AI-executable; item 3 is the only HUMAN-required step in Phase 5.

---

## 7. Out of Scope

- **On-device TTS verification as a new dedicated step** — bucketed with existing runbook per `Q6`.
- **Persona-color theming of inbox/conversation backgrounds, AppBar, bubble gradients** — out per `Q5` (badge only).
- **Persona reassignment after `/clear` UX** — already handled implicitly (the announcement notification renders normally).
- **Per-agent / per-context persona override** — parent's TODO. Defer.
- **Direct calls to `/api/cosa-voice/voice-persona/{sid}/allocate` or `/release`** — server-side concern; mobile is purely a consumer.

---

## 8. Files Inventory (Phase-Cross-Reference Summary)

### New (across all phases)
- `lib/features/notifications/data/voice_persona.dart`
- `lib/features/notifications/presentation/persona_badge.dart`
- `lib/shared/painters/dashed_border_painter.dart` (conditional on REUSE pre-pass result)
- `test/unit/features/notifications/data/voice_persona_test.dart`
- `test/widget/notifications/persona_badge_test.dart`
- `test/_fixtures/notifications/notification-with-persona.json`

### Modified
- `lib/features/notifications/data/notification_models.dart`
- `lib/features/notifications/domain/notification_event.dart`
- `lib/features/notifications/domain/notification_state.dart`
- `lib/features/notifications/domain/notification_bloc.dart`
- `lib/features/notifications/presentation/conversation_by_date_screen.dart`
- `lib/features/notifications/presentation/conversation_screen.dart`
- `lib/features/notifications/presentation/inbox_screen.dart`
- `lib/services/tts/streaming_tts_player.dart`
- `lib/services/tts/tts_orchestrator.dart`
- `lib/core/testing/test_keys.dart`
- `<mobile>/TODO.md`, `<mobile>/history.md`
- (extended) `test/unit/features/notifications/domain/notification_bloc_test.dart`
- (extended) `test/unit/services/tts/streaming_tts_player_test.dart`

---

## 9. Execution Log

*Populated during execution.*

| Phase | Status | Date | Test count delta | Commit-hash placeholder | Progress note |
|---|---|---|---|---|---|
| 0 (prereq) | ✅ complete | 2026-05-06 | 273 → 276 (+3) | fd8fc18 (checkpoint, session a756441c continuation) | Verdict 🟡 partial drift confirmed live; `_onExternalUpdate` extended with `switch (n.type)` + default-branch logger. New file `test/unit/notifications/notification_bloc_dispatch_test.dart`. See `../00-phase-0-dispatch-audit.md`. |
| 1 — data model | ✅ complete | 2026-05-06 | 276 → 290 (+14) | fd8fc18 (checkpoint, session a756441c continuation) | New: `voice_persona.dart` (87 lines, liberal fromJson + null-defense + `==`/`hashCode` on `voiceId`); `voice_persona_test.dart` (9 tests); fixture `notification-with-persona.json`. Modified: `notification_models.dart` (+`voicePersona` field); `notification_models_test.dart` (+4 tests covering present/absent/null/borrowed); `notification_repository_test.dart` (+2 fixture-backed round-trip tests). |
| 2 — WS dispatch | ✅ complete | 2026-05-06 | 290 → 294 (+4) | uncommitted (post-checkpoint `fd8fc18`) | New events `NotificationsVoicePersonaAssigned`/`Released`; `PersonaSnapshotMixin` on 4 loaded states; `_personasBySender` instance field on bloc + `_personasSnapshot()` defensive-copy helper threaded through 7 emit sites. `_onExternalUpdate` switch now has explicit voice-persona cases before the default-branch logger. New file `notification_bloc_persona_test.dart` with 4 Pass-1-F3 assertion-shape blocTests. |
| 3 — UI badge | ⏳ pending | | | | |
| 4 — TTS routing | ⏳ pending | | | | |
| 5 — docs + verify | ⏳ pending | | | | |
