# LUPIN MOBILE - SESSION HISTORY

## 📚 Archived Sessions

Older session entries have been archived for token-limit hygiene. See:
- **[2026-04-15-to-16-history.md](history/2026-04-15-to-16-history.md)** — Tier 1-4 buildout (5 sessions, Apr 15-16, 2026)
- **[2025-07-06-to-08-17-history.md](history/2025-07-06-to-08-17-history.md)** — Initial era (7 sessions, Jul 2025 – Aug 2025; project then dormant for 8 months)

Most recent ~3 weeks (2026-04-17 onward) are retained below.

---


## 2026.05.07 (session-end batch) | Session `c25dbc3e` — Voice-persona milestone CODE-COMPLETE (SESSION-END)

#### Session-End | 2026.05.07 | Voice-persona milestone closed AI-side across Phases 3+4+5; on-device runbook extended with vp1-vp7 + sign-off; APK build unblocked (Gradle desugaring); R&D for Patrol-based runbook automation captured; history.md archived 20.9k → 12.3k tokens (55% reduction across 2 archives)

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`
**Commits this session** (all on `c25dbc3e`):
- `1577e29` — Phase 3 UI badge (PersonaBadge + DashedBorderPainter + 3 wiring sites + 8 widget tests; 294 → 302)
- `a190b4f` — Phase 4 TTS routing (verify+comment per REUSE pre-pass; orchestrator pipe-through; Q3 + Q4 doc; 6 unit tests; 302 → 308)
- `b084549` — Phase 5 AI close + runbook extension (vp1-vp7 + sign-off + 6-voice timbre cheat sheet; tracking-doc closes; 308 ✅ baseline confirmed)
- `<this commit pending>` — Session-end batch (Gradle desugaring fix + R&D drop note + history archive)

### Accomplishments (this session)

1. **Voice-persona milestone reached CODE-COMPLETE** across Phases 3, 4, 5 (full plan-doc-set in `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/`); milestone-close criterion now sits one HUMAN runbook execution away from full closure. Cumulative test delta: **273 → 308 (+35)**; quarantine drift baseline 44 ❌ unchanged throughout.
2. **APK build unblocked** — added `isCoreLibraryDesugaringEnabled = true` to `compileOptions` in `android/app/build.gradle.kts` plus `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")` to a new top-level `dependencies` block. `flutter_local_notifications` 17.2.4 requires desugaring for its `java.time.*` usage on `minSdk 24`. Predates the voice-persona milestone — first surfaced when user attempted the laptop APK build for the runbook.
3. **R&D doc dropped + breadcrumbed** — user added `src/rnd/v0.1.7/2026.05.07-automating-rendering-and-behaviors-on-android-emulator.md` (1079 lines, "Lupin Voice-Persona Validation Runbook — Three-Domain Split"). Proposes Patrol-based automation of vp1-vp4 + vp6-infra + vp7-infra; leaves only vp5 + vp6-timbre + vp7-audible as residual HUMAN gates. Three deliverables: splitter prompt, Patrol bootstrap + tests, single-file Python CLI for residual gates. **Breadcrumb** at top of `TODO.md` flags this as a decision point before running the manual runbook.
4. **History archived** — `history.md` was at 20.9k tokens (83.7%, past CRITICAL ≥19k threshold). Split into 2 archive files leaving 12.3k retained:
   - `history/2025-07-06-to-08-17-history.md` — initial era (7 sessions, Jul-Aug 2025; ~8.7k tokens)
   - `history/2026-04-15-to-16-history.md` — Tier 1-4 buildout (5 sessions, Apr 15-16, 2026; ~3.0k tokens)
   - Retention: 2026-04-17 onward (11 sessions, voice-persona milestone era).
   - Banner added to `history.md` linking back to both archives.

### Files Modified (this session-end batch — final commit)

- `android/app/build.gradle.kts` — Gradle desugaring config (`isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring(...)` dep)
- `TODO.md` — R&D breadcrumb at top of file (Patrol-automation revisit point); milestone close updates
- `history.md` — archive banner + this session-end entry; 12.3k tokens after archive

### Files Created (this session-end batch)

- `history/2025-07-06-to-08-17-history.md` — initial-era archive
- `history/2026-04-15-to-16-history.md` — Tier 1-4 buildout archive
- `src/rnd/v0.1.7/2026.05.07-automating-rendering-and-behaviors-on-android-emulator.md` — user-dropped R&D (Patrol three-domain-split proposal); first-time `git add` to track

### Test Results (cumulative, session-wide)

| Suite | Session start | Phase 3 close | Phase 4 close | Phase 5 close | Δ |
|---|---|---|---|---|---|
| Baseline | 294 ✅ | 302 ✅ | 308 ✅ | 308 ✅ | +14 (this session) |
| `test/legacy_quarantine/` | 44 ❌ | 44 ❌ | 44 ❌ | 44 ❌ | unchanged |

(Phase 5 added zero tests by design — doc-only batch.)

### Key Decisions / Insights (this session)

- **Bundling both HUMAN gates into one runbook section**: per user direction 2026-05-07. Single laptop+emulator pass covers Phase 3 visual badge contrast + Phase 4 TTS persona-voice timbre verification + Q4 fallback verification. Saves a device handoff.
- **R&D file rename caught + corrected**: user dropped the R&D file with a `2025.05.07` prefix; I flagged the year typo; user renamed to `2026.05.07` mid-session. Breadcrumb in `TODO.md` and history references updated to match.
- **History archive deferred from auto-trigger to user decision**: per memory rule `feedback_no_auto_checkpoint`, the CRITICAL-level archive was surfaced via `ask_multiple_choice` rather than auto-executed despite the workflow's "auto-archive on CRITICAL" mandate. User chose archive-now; would have respected defer or skip equally.
- **Two archive files (visual storytelling)**: per workflow guidance "multiple archives per month/period = high-intensity period". The Tier 1-4 buildout was ~5 sessions in 2 days — that intensity is preserved in its own archive rather than absorbed into the broader 2025 archive.

### Out of Scope (HUMAN gate retained)

- **Voice-persona milestone HUMAN gate** — single laptop+emulator session running runbook §"Voice-persona milestone gate" vp1-vp7 + sign-off block. **OR** revisit in light of the Patrol R&D first (TODO breadcrumb decision point). Either way, this is the only step between current state and full milestone closure.

---

## 2026.05.07 (checkpoint, post-Phase-4) | Session `c25dbc3e` — Voice-persona Phase 5 AI close + runbook extension (CHECKPOINT)

#### Checkpoint | 2026.05.07 | Voice-persona milestone CODE-COMPLETE — Phase 5 AI portion landed; on-device runbook extended with vp1-vp7 acceptance steps bundling BOTH outstanding HUMAN gates; baseline 308 ✅ / 0 ❌ confirmed; 44 ❌ quarantine drift baseline unchanged

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`
**Plan slate**: `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/` (unchanged from prior checkpoint `a190b4f`)
**Implementation doc**: `voice-persona/01-implementation.md` (§6 Phase 5 AI task checkboxes all `[x]`; HUMAN runbook task `[ ]` pending; §9 Phase 5 row populated)
**Continues from**: checkpoint `a190b4f` (same session, post-Phase-4 close)

### Accomplishments

1. **Voice-persona Phase 5 — Documentation + Verify (AI portion)** (`voice-persona/01-implementation.md §6`)
   - **Full baseline confirmed**: `./flutter.sh test test/unit/ test/widget/ test/service_integration/` returned `308 ✅ / 0 ❌`. Cumulative delta over the milestone: 273 → 308 (+35 across Phases 0-4). Original Phase 5 §6 task #3 forecast was "+10" — actuals exceeded due to defensive coverage in Phases 1-4.
   - **Quarantine baseline confirmed**: `test/legacy_quarantine/` count is `0 +0 -44` — drift baseline unchanged from session `0d54c763`. No silent reactivations of legacy drift-broken tests. Per `<global>~/.claude/CLAUDE.md` legacy-quarantine rule.
   - **On-device runbook extended** (`src/rnd/v0.1.7/2026.04.24-on-device-tts-verify-runbook.md`): new "Voice-persona milestone gate (added 2026-05-07)" section between "After verify: reporting" and "Related files" — 7 acceptance steps + sign-off block + 6-voice persona timbre cheat sheet:
     - **vp1** Inbox sender tile — colored badge with emoji renders for senders with allocated persona; fallback to legacy first-letter CircleAvatar for senders without persona; long-press tooltip shows `displayName`
     - **vp2** ConversationScreen AppBar — 28px badge + senderId text in Row; persona color matches inbox tile for same sender
     - **vp3** ConversationByDateScreen `_NotificationItemCard` — 24px badge inline directly right of priority chip
     - **vp4** Borrowed-persona dashed border — visible when `borrowed=true`; "skipped — no borrowed persona" if not observable in run
     - **vp5** Light + dark mode contrast — Phase 3 §3.6 HUMAN acceptance gate; F9 failure-mode contract holds (badge always renders persona color even if emoji renders as tofu); subjective sign-off: "distinguishable enough at a glance"
     - **vp6** TTS persona-voice timbre — Phase 4 F5 HUMAN gate; re-fire scenarios s2 + s3 + s5/s5b; voice should match allocated persona (Adam = deep male / Bella = soft female / Domi = confident female / Antoni = mid-male / Rachel = smooth female / Arnold = gravelly male) NOT Sam (neutral fallback). Record persona name + perceived voice character per F5.
     - **vp7** Quota fallback uses device `flutter_tts` — re-fire s8 with `LUPIN_DEV_SIMULATE_TTS_ERROR=true`; Q4 audible verification (different voice space — fallback uses on-device synthesizer voice, NOT any ElevenLabs persona)
     - **Sign-off block**: 4 explicit checkboxes (all visual + audible ticked + persona name/character recorded + date/device/Android/APK-commit recorded)
   - **Tracking-doc closes**:
     - `01-implementation.md §6` — all 5 AI task checkboxes `[x]` with executed-evidence; HUMAN runbook task `[ ]` retained; §9 Phase 5 row populated with `308 ✅ / 0 ❌` baseline + `44 ❌` quarantine + uncommitted-status placeholder.
     - `00-index.md` — Current Status promoted to "🎯 CODE-COMPLETE 2026-05-07"; Progress 6/6 (AI portion) with HUMAN gate noted; Phase Summary table all rows ✅; Recent Updates Phase-5-landed entry.
     - `TODO.md` — header reframed as "milestone CODE-COMPLETE"; NEXT SESSION block now reads "voice-persona milestone HUMAN gate (laptop+emulator runbook execution)"; Phase 5 entry expanded with full task evidence; Phases 4-5 promoted from "next" to "done".
   - **No code changes** in this Phase 5 batch — purely documentation + tracking + runbook extension.

2. **Tracking document updates** (this checkpoint)
   - `voice-persona/01-implementation.md` — §6 task checkboxes [x] for AI items, [ ] retained for HUMAN; §9 Phase 5 row populated
   - `voice-persona/00-index.md` — Current Status to milestone code-complete; Phase Summary 6/6; Recent Updates Phase 5 entry
   - `TODO.md` — milestone code-complete header; HUMAN runbook is sole NEXT-SESSION item
   - `2026.04.24-on-device-tts-verify-runbook.md` — voice-persona section + persona milestone references in Related Files
   - `.claude-session.md` — Phase 5 touched-files block under session `c25dbc3e`
   - `history.md` — this entry

### Files Modified (4)

- `src/rnd/v0.1.7/2026.04.24-on-device-tts-verify-runbook.md` — voice-persona milestone gate section (vp1-vp7 + sign-off + 6-voice cheat sheet); Related Files section extended with persona milestone refs
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/01-implementation.md` — §6 close + §9 Phase 5 row
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/00-index.md` — Current Status, Phase Summary, Recent Updates
- `TODO.md` — milestone close + HUMAN gate as sole NEXT-SESSION item

(No `lib/` or `test/` changes in this batch — Phase 5 is doc-only.)

### Test Results

| Suite | Pre-Phase-5 | Post-Phase-5 | Δ |
|---|---|---|---|
| Baseline (`test/unit/ test/widget/ test/service_integration/`) | 308 ✅ | **308 ✅** | 0 (doc-only) |
| `test/legacy_quarantine/` (drift baseline) | 44 ❌ | **44 ❌** | unchanged ✅ no silent reactivations |

Cumulative milestone close: **273 → 308 (+35)** across Phases 0-4; Phase 5 added zero tests by design (per §6 — Phase 5 is doc + verify only).

### Key Decisions / Insights

- **Bundling both HUMAN gates into a single runbook section**: per user direction 2026-05-07. Without bundling, Phase 3's badge contrast review would have needed its own laptop+emulator session, and Phase 5's TTS persona check would have needed another. The vp1-vp7 batch is structured so a single device handoff covers both — visual checks first (vp1-vp5) since they're the cheap "open the app and look" pass, audible last (vp6-vp7) since they require firing scenarios via `fire-tts-scenarios.py`. Sign-off is one block at the end.
- **Persona timbre cheat sheet inline**: Pass 1 finding F5 required recording "perceived voice character." Without the cheat sheet, the user would have to remember which voice goes with which persona OR look it up server-side mid-test. The 6-voice table inline turns vp6 into a comparison task ("does what I hear match Adam's row?") rather than a recall task. The Sam fallback row at the bottom makes the negative case explicit too.
- **No code changes in Phase 5**: this is the only phase where that holds. The §6 spec was always "docs + verify," which let the milestone close cleanly as a paperwork batch — no risk of regression sneaking in at the close.
- **HUMAN gate as the only open item, not as a TODO inflation**: per F4 ("do NOT do a wider TODO sweep"), the TODO update touches only the voice-persona items. Other open buckets (hygiene follow-ups from `edaec79`, on-device sanity pass items from session `0d54c763`, FCM deferral) are untouched.

### Out of Scope (HUMAN gate retained)

- **HUMAN runbook execution**: single laptop+emulator session running runbook §"Voice-persona milestone gate" vp1-vp7 + sign-off block. Gated on `feedback_dev_server_laptop_split` memory rule — dev server has no Android SDK; build/deploy on laptop. When that lands, the milestone closes fully.

---

## 2026.05.07 (checkpoint, post-Phase-3) | Session `c25dbc3e` — Voice-persona Phase 4 TTS routing (CHECKPOINT)

#### Checkpoint | 2026.05.07 | Voice-persona Phase 4 LANDED — collapsed verify+comment per REUSE pre-pass; orchestrator now pipes `notification.voicePersona?.voiceId` through to `StreamingTtsPlayer.speak()`; 302 → 308 baseline tests green

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`
**Plan slate**: `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/` (unchanged from prior checkpoint `1577e29`)
**Implementation doc**: `voice-persona/01-implementation.md` (§5 Phase 4 task checkboxes all `[x]`; §9 Execution Log Phase 4 row populated)
**Continues from**: checkpoint `1577e29` (same session, post-Phase-3 close)

### Accomplishments

1. **Voice-persona Phase 4 — TTS routing (collapsed verify+comment)** (`voice-persona/01-implementation.md §5`)
   - **`streaming_tts_player.dart` — REUSE-AS-IS verify + dartdoc** (no code change). 13-line dartdoc block above `speak()` documenting `voiceId` as the persona pipe-through path (Q3). Explains the absent-→-Sam server fallback contract; explains why the body-wiring at `:141` deliberately uses `if (voiceId != null)` to OMIT the key (rather than sending `null`) so the server contract is preserved. Cross-referenced to `03-decisions.md` Q3.
   - **`tts_orchestrator.dart` — wiring + Q4 comment**:
     - Added `String? voiceId` parameter to `enqueueIfSpeakable()` with dartdoc explaining the per-session pipe-through and the explicit Q4 carve-out (NOT piped to `flutter_tts` fallback).
     - Added `voiceId` field to private `_Utterance` class.
     - `_dispatchCurrent` now passes `voiceId: utter.voiceId` to `_player.speak()`.
     - 11-line "intentional omit" comment block inside `_speakViaFallback` per Q4: ElevenLabs voice IDs vs `flutter_tts` device voices live in different namespaces; warns future maintainer not to "fix" this. The comment forestalls a Pass 2 Adversarial flag for missing test coverage.
   - **`notification_bloc.dart:191-196`** — `enqueueIfSpeakable` call site now passes `voiceId: n.voicePersona?.voiceId`. The bloc reads persona straight off each notification per Q1; no separate cache.
   - **6 new unit tests**:
     - `streaming_tts_player_test.dart` (+3): 4.1 voiceId in POST body / 4.2 voiceId omitted from body when null per Q3 contract / 4.3 borrowed body shape unchanged (server treats borrowed identically — only `voice_id` is on the wire).
     - `tts_orchestrator_test.dart` (+3): 4.4 persona piped from notification through to `player.speak(voiceId: ...)` / 4.4b null voiceId defensive — orchestrator passes `voiceId: null` cleanly through / 4.5 quota fallback omits voiceId per Q4 + F11 — uses `errorCtrl.add(TtsErrorEvent(errorCode: 'quota_exceeded'))` to enter the 5-min window, then asserts `verify(fallback.flutterTtsSpeak(text))` and `verifyNever(player.speak(voiceId: ...))`.
   - Phase 4 §5 task checkboxes all marked `[x]` with executed-evidence; §9 Execution Log Phase 4 row populated.

2. **Tracking document updates** (this checkpoint)
   - `voice-persona/01-implementation.md` — §5 task checkboxes `[x]` with executed-evidence; §9 Phase 4 row populated
   - `voice-persona/00-index.md` — Current Status (5/6 phases complete; 308 tests; Phase 5 next); Phase Summary table; Recent Updates Phase 4 entry
   - `TODO.md` — Phase 4 marked done; Phase 5 promoted to NEXT SESSION header; both HUMAN gates explicitly bundled into a single laptop+emulator session at Phase 5 close
   - `.claude-session.md` — Phase 4 touched-files block added under session `c25dbc3e`
   - `history.md` — this entry

### Files Modified (8)

- `lib/services/tts/streaming_tts_player.dart` — 13-line dartdoc on `speak()` (Q3 pipe-through documentation; no code change)
- `lib/services/tts/tts_orchestrator.dart` — `enqueueIfSpeakable` + `_Utterance` extended with `voiceId`; `_dispatchCurrent` pipes through to `_player.speak`; 11-line Q4 comment block in `_speakViaFallback`
- `lib/features/notifications/domain/notification_bloc.dart` — call site passes `voiceId: n.voicePersona?.voiceId`
- `test/unit/services/tts/streaming_tts_player_test.dart` — +3 tests (4.1, 4.2, 4.3)
- `test/unit/services/tts/tts_orchestrator_test.dart` — +3 tests (4.4, 4.4b, 4.5)
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/01-implementation.md` — §5 + §9 updates
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/00-index.md` — Current Status, Phase Summary, Recent Updates
- `TODO.md` — Phase 4 done; Phase 5 next-up; HUMAN gates bundled

### Test Results

| Suite | Pre-Phase-4 | Post-Phase-4 | Δ |
|---|---|---|---|
| `test/unit/services/tts/` (focused) | 21 ✅ | 27 ✅ | +6 |
| Baseline (`test/unit/ test/widget/ test/service_integration/`) | 302 ✅ | **308 ✅** | +6 |
| `test/legacy_quarantine/` (drift baseline) | 44 ❌ | 44 ❌ | unchanged |

Plan estimated +5 tests; +1 extra is 4.4b defensive (null voiceId passes through cleanly). All Phase 0/1/2/3 regressions hold.

### Key Decisions / Insights

- **The "verify+comment" interpretation of Phase 4 was load-bearing**: the REUSE pre-pass at 2026-05-06 had already collapsed Phase 4 from "write new" to "verify + comment" because `voiceId` was already shipping. Without the dartdoc block, a future maintainer reading `streaming_tts_player.dart:speak()` would have NO indication that the parameter is the documented persona pipe-through. The 13-line dartdoc is the durable artifact of the REUSE-AS-IS verdict — it's why the line is there *and* why the body wiring is shaped the way it is.
- **Q4 carve-out comment is preventive, not explanatory**: the `_speakViaFallback` comment doesn't document a feature — it documents a deliberate non-feature. Without it, a future maintainer would see "ElevenLabs gets voiceId, flutter_tts doesn't — must be a bug" and "fix" it. The comment names the namespace mismatch and the missing translation table that would be required to do this correctly.
- **Test 4.5 uses error-stream injection over time-mocking**: the natural way to test the quota window is to mock `DateTime.now()` and advance it past `_elevenLabsDisabledUntil`. But `dart:core` time isn't easily mockable here. The cleaner path is to push a `TtsErrorEvent(errorCode: 'quota_exceeded')` into the player's error stream — the orchestrator's `_onElevenLabsError` handler then sets `_elevenLabsDisabledUntil` directly, and the next enqueue routes via fallback. Per Pass 1 finding F11.
- **`_Utterance.voiceId` is nullable + the entire pipe-through honors null**: at every layer (bloc → orchestrator.enqueueIfSpeakable → _Utterance → player.speak → POST body), null means "don't pipe a voice ID; use Sam." Test 4.4b verifies the orchestrator level; test 4.2 verifies the body level. Together they prove the chain doesn't insert a non-null somewhere by mistake.

### Out of Scope (deferred to Phase 5)

- **Phase 5 — Docs + on-device verify** (final phase): updates `00-index.md` Current Status to "milestone complete"; populates `01-implementation.md` §9 Phase 5 row; closes `TODO.md` voice-persona entries; adds a brief `history.md` accomplishment line. Extends the existing on-device TTS runbook with a persona-section that bundles BOTH outstanding HUMAN gates per user direction 2026-05-07: (a) Phase 3 visual badge contrast review in light + dark mode (laptop+emulator) and (b) Phase 4 TTS persona verification (scenarios 5/6/7 speak with assigned per-session voice rather than Sam, Q6). Single laptop+emulator session covers both.

---

## 2026.05.07 (checkpoint) | Session `c25dbc3e` — Voice-persona Phase 3 UI badge (CHECKPOINT)

#### Checkpoint | 2026.05.07 | Voice-persona Phase 3 LANDED — `PersonaBadge` widget + `DashedBorderPainter` + 3 wiring sites + 8 widget tests; 294 → 302 baseline tests green

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`
**Plan slate**: `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/` (unchanged from prior session-end `39e3525`)
**Implementation doc**: `voice-persona/01-implementation.md` (§4 Phase 3 task checkboxes all `[x]` except HUMAN final acceptance gate; §9 Execution Log Phase 3 row populated)
**Continues from**: commit `39e3525` (prior session-end `a756441c` — Phase 2 close)

### Accomplishments

1. **Voice-persona Phase 3 — UI badge** (`voice-persona/01-implementation.md §4`)
   - **`DashedBorderPainter`** in `lib/shared/painters/dashed_border_painter.dart` — 60-line `CustomPainter` per Q9 (FROZEN at REUSE pre-pass; confirmed genuinely-new, no existing `CustomPainter` subclass and no dashed-border package). Uses `Canvas.drawArc` in a stepped loop; configurable `strokeWidth`/`dashLength`/`gapLength`; `shouldRepaint` checks all four params.
   - **`PersonaBadge`** in `lib/features/notifications/presentation/persona_badge.dart` — `StatelessWidget` wrapping `CircleAvatar` per REUSE `extend-existing` finding. Hex-color parser (accepts `#RRGGBB` and `#AARRGGBB`) with theme-primary fallback for malformed input. Foreground color (emoji + dashed border) chosen by `Color.computeLuminance() > 0.5` so contrast holds across dark + light persona backgrounds. **F9 failure-mode contract** enforced: badge always renders with persona color background regardless of emoji glyph success — color is the primary disambiguator, no letter substitution. `Tooltip(triggerMode: longPress)` shows `displayName`. Borrowed variant overlays a `CustomPaint` with `DashedBorderPainter` inside an `IgnorePointer` so taps still hit the avatar. Two diameters in use: 28px (header) and 24px (in-card).
   - **`TestKeys`** extended with `personaBadgePrefix` + `personaBadgeDashedPrefix` (suffixed with `senderId` at use-site).
   - **3 wiring sites** (per Q5 — badge only, no inbox/bubble color sweep):
     - `_SenderTile` in `inbox_screen.dart`: parent `InboxScreen.itemBuilder` passes `persona: state.personaFor(sender.senderId)` to tile; `_SenderTile` renders `PersonaBadge` in `leading:` slot when persona is non-null, falls back to existing `CircleAvatar(senderId[0])` otherwise.
     - `ConversationScreen` AppBar in `conversation_screen.dart`: title wrapped in `BlocSelector<NotificationBloc, NotificationState, VoicePersona?>` reading `state.personaFor(widget.senderId)` (state guarded by `is PersonaSnapshotMixin`); 28px badge + senderId text composed via Row with `MainAxisSize.min` + `Flexible` + ellipsis. Badge omits cleanly when `personasBySender` is empty.
     - `_NotificationItemCard` in `conversation_by_date_screen.dart`: reads `item.voicePersona` directly per Q1 (server-stamped on every notification envelope); 24px badge inline next to the priority chip.
   - **8 new widget tests** — `persona_badge_test.dart` (6: 3.1 present+colored / 3.2 absent / 3.3 borrowed-dashed / 3.4a light+dark / 3.4b broken-emoji codepoint resilience `\u{1FAFF}` / malformed-color defensive); `conversation_screen_test.dart` (+2: 3.5 header reads bloc-cached persona / header omits when `personasBySender` empty).
   - Phase 3 §4 task checkboxes all marked `[x]` except the HUMAN final acceptance review (gated on laptop+emulator deployment per `feedback_dev_server_laptop_split` memory rule). §9 Execution Log Phase 3 row populated with test deltas and uncommitted-status placeholder.

2. **Tracking document updates** (this checkpoint)
   - `voice-persona/01-implementation.md` — §4 task checkboxes `[x]` with executed-evidence; §9 Execution Log Phase 3 row populated
   - `voice-persona/00-index.md` — Current Status (4/6 phases complete; 302 tests); Phase Summary table marked ✅; Recent Updates Phase 3 entry
   - `TODO.md` — Phase 3 marked done; Phase 4 (collapsed verify+comment) promoted to NEXT SESSION header; HUMAN final acceptance review explicitly bucketed with the on-device runbook at Phase 5 close per user direction
   - `.claude-session.md` — new session section for `c25dbc3e` (this session)
   - `history.md` — this entry

### Files Created (3)

- `lib/shared/painters/dashed_border_painter.dart` — `DashedBorderPainter` (60 lines)
- `lib/features/notifications/presentation/persona_badge.dart` — `PersonaBadge` widget
- `test/widget/notifications/persona_badge_test.dart` — 6 widget tests (3.1-3.4 + 2 defensive cases)

### Files Modified (7)

- `lib/core/testing/test_keys.dart` — `personaBadgePrefix` + `personaBadgeDashedPrefix` constants
- `lib/features/notifications/presentation/inbox_screen.dart` — `_SenderTile.persona` param + `leading:` slot wiring
- `lib/features/notifications/presentation/conversation_screen.dart` — AppBar `BlocSelector` + 28px badge composition
- `lib/features/notifications/presentation/conversation_by_date_screen.dart` — `_NotificationItemCard` 24px badge inline next to priority chip
- `test/widget/notifications/conversation_screen_test.dart` — +2 tests (3.5 header reads cached / header omits when empty)
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/01-implementation.md` — §4 + §9 updates
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/00-index.md` — Current Status, Phase Summary, Recent Updates
- `TODO.md` — Phase 3 done; Phase 4 next-up; HUMAN review bucketed at Phase 5

### Test Results

| Suite | Pre-Phase-3 | Post-Phase-3 | Δ |
|---|---|---|---|
| Baseline (`test/unit/ test/widget/ test/service_integration/`) | 294 ✅ | **302 ✅** | +8 |
| `test/legacy_quarantine/` (drift baseline) | 44 ❌ | 44 ❌ | unchanged |

Plan estimated +5 widget tests; +3 extras are defensive coverage (3.4 split into light+dark cell vs broken-emoji cell, plus malformed-color and empty-personasBySender edges).

### Key Decisions / Insights

- **Failure-mode contract over letter substitution**: when emoji rendering fails (broken codepoint, OEM skin missing the glyph), the badge stays color-only rather than falling back to `persona.name[0]`. Color IS the primary disambiguator; adding a letter introduces visual noise on top of color and breaks the "one badge appearance per voice" mental model. Test 3.4b verifies no crash on `\u{1FAFF}`; the avatar still renders with `#FFD600` background.
- **`BlocSelector` over `BlocBuilder` for the AppBar title**: the conversation screen body already uses `BlocConsumer` with `buildWhen` filters; wrapping the AppBar in another `BlocBuilder` would rebuild the whole title on every state change. `BlocSelector` narrows to just the persona for `widget.senderId`, so the title only repaints when that specific persona arrives or changes.
- **Inbox `_SenderTile.persona` passed from parent, not looked up by tile**: keeps `_SenderTile` testable in isolation (no bloc dependency); follows the existing pattern where the tile takes its data via constructor params. Parent `itemBuilder` does the `state.personaFor(senderId)` lookup once per tile.
- **`IgnorePointer` around the dashed-border `CustomPaint`**: without it, the overlay would intercept long-press events and the `Tooltip` (showing `displayName`) wouldn't fire on borrowed personas. Tooltip needs to receive the gesture from the avatar layer underneath.

### Out of Scope (deferred)

- **Phase 3 HUMAN final acceptance review** — visual review of badge color/contrast in light + dark mode on a real Android device. Bucketed with the on-device TTS runbook at Phase 5 close per user direction (2026-05-07). Single laptop+emulator session covers both Phase 3 visual QA and Phase 5 TTS runbook.
- **Phase 4 — TTS routing (collapsed verify+comment)** — next: `voiceId` parameter is already shipping at `streaming_tts_player.dart:130` per REUSE pre-pass; this phase becomes (a) verify wiring, (b) add comment, (c) ensure orchestrator pipes `notification.voicePersona.voiceId` through. 5 unit tests (4.1-4.5).
- **Phase 5 — Docs + on-device verify** — gated on Phase 4. Bundles HUMAN final acceptance for both Phase 3 (badge) + TTS runbook (Phase 5).

---

## 2026.05.06 (session-end batch) | Session `a756441c` — Voice-persona Phase 2 WS event dispatch (SESSION-END)

#### Session-End | 2026.05.06 | Voice-persona Phase 2 LANDED — bloc state now carries `personasBySender` snapshot across all 4 loaded states; 290 → 294 baseline tests green; +4 Pass-1-F3 blocTests

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`
**Plan slate**: `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/` (unchanged from checkpoint `fd8fc18`)
**Implementation doc**: `voice-persona/01-implementation.md` (§3 Phase 2 task checkboxes all `[x]`; §9 Execution Log Phase 2 row populated)
**Continues from**: checkpoint `fd8fc18` (same session, post-/clear; Phases 0 + 1 already committed there)

### Accomplishments

1. **Voice-persona Phase 2 — WS event dispatch** (`voice-persona/01-implementation.md §3`)
   - **2 new bloc events** in `notification_event.dart`:
     - `NotificationsVoicePersonaAssigned(senderId, persona)` — props key on `senderId + persona.voiceId`
     - `NotificationsVoicePersonaReleased(senderId, personaName)` — props key on `senderId + personaName`
     - Both serve dual entry points: real-WS path (via `_onExternalUpdate` switch case) and test/programmatic path (via `bloc.add()`)
   - **`PersonaSnapshotMixin` shared by all 4 loaded states** in `notification_state.dart`:
     - `Map<String, VoicePersona> personasBySender` field (default const `{}`)
     - `VoicePersona? personaFor(String senderId)` accessor
     - Applied to: `NotificationsInboxLoaded`, `NotificationsConversationLoaded`, `NotificationsSenderDatesLoaded`, `NotificationsConversationByDateLoaded`
     - `personasBySender` added to each state's `props` so Equatable detects map mutations
   - **Bloc instance field + threading** in `notification_bloc.dart`:
     - `_personasBySender` mutable map (source of truth across state transitions)
     - `_personasSnapshot()` — `Map.unmodifiable(_personasBySender)` defensive copy at every emit site (prevents leaked mutations into already-emitted states)
     - 2 new event handlers (`_onVoicePersonaAssigned`, `_onVoicePersonaReleased`) with idempotency guard for unknown-sender release
     - `_emitCurrentSnapshot(emit)` helper — re-emits current loaded state with updated map (test-path entry)
     - `_onExternalUpdate` switch extended with explicit `voice_persona_assigned` and `voice_persona_released` cases before the Phase 0 default-branch logger; default branch preserved as canary for genuinely unknown types
     - `personasBySender:` threaded through all 7 emit sites: 4 `_onLoadX` handlers + 3 `_refreshCurrent` cases
   - **4 Pass-1-F3 assertion-shape blocTests** in new file `notification_bloc_persona_test.dart`:
     - **2.4.1** assigned event → `predicate<NotificationsInboxLoaded>((s) => s.personaFor("s-1") == _adam)`
     - **2.4.2** assigned-then-released sequence → 2 emits, second has `personaFor("s-1") == null`
     - **2.4.3** borrowed=true survives — fire `NotificationsLoadInbox` after assigned; persona retained on the freshly-emitted state with `borrowed == true`
     - **2.4.4** released for unknown sender → `expect: const <NotificationState>[]` (no emit; idempotency)

2. **Tracking document updates** (this session-end)
   - `voice-persona/01-implementation.md` — Phase 2 §3 task checkboxes all `[x]` with executed-evidence; §9 Execution Log Phase 2 row populated with commit-hash placeholder
   - `voice-persona/00-index.md` — Current Status (3/6 phases complete; 294 tests); Phase Summary table marked ✅; Recent Updates Phase 2 entry
   - `TODO.md` — Phase 2 marked done; Phase 3 promoted to NEXT SESSION header
   - `.claude-session.md` — Phase 2 touched-files block added (will be updated to status=committed after this session-end commit)
   - `history.md` — this entry (session-end summary above the prior checkpoint entry)

### Files Created (1)

- `test/unit/notifications/notification_bloc_persona_test.dart` — 4 blocTest cases (Phase 2.4.1–2.4.4)

### Files Modified (5)

- `lib/features/notifications/domain/notification_event.dart` — +2 events (Assigned/Released)
- `lib/features/notifications/domain/notification_state.dart` — +`PersonaSnapshotMixin` applied to 4 loaded states; +`personasBySender` field threaded through each
- `lib/features/notifications/domain/notification_bloc.dart` — bloc instance field, snapshot helper, 2 event handlers, `_emitCurrentSnapshot`, `_onExternalUpdate` switch extension, 7 emit-site updates
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/01-implementation.md` — §3 + §9 updates
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/00-index.md` — Current Status, Phase Summary, Recent Updates
- `TODO.md` — Phase 2 done; Phase 3 next-up

### Test Results

| Suite | Pre-Phase-2 (post-checkpoint) | Post-Phase-2 | Δ |
|---|---|---|---|
| `test/unit/notifications/` (focused) | 42 ✅ | 46 ✅ | +4 |
| Baseline (`test/unit/ test/widget/ test/service_integration/`) | 290 ✅ | **294 ✅** | +4 |
| `test/legacy_quarantine/` (drift baseline) | 44 ❌ | 44 ❌ | unchanged |

Cumulative session totals (post-/clear continuation, both commits combined):

| Suite | Session start (post-/clear) | Phase 0 close | Phase 1 close | Phase 2 close (session-end) |
|---|---|---|---|---|
| Baseline | 273 ✅ | 276 ✅ | 290 ✅ | **294 ✅** (+21 cumulative) |

### Key Decisions / Insights

- **`PersonaSnapshotMixin` over per-state field repetition**: shared mixin eliminates 4-way duplication of the `personaFor` accessor; gives every loaded state the same query interface for free. Equatable's `props` still requires per-state listing of `personasBySender`, so the storage isn't fully DRY — but the read-path is.
- **Defensive copy at every emit site**: `_personasSnapshot()` returns `Map.unmodifiable(_personasBySender)`, which COPIES + freezes. Prevents the bloc's mutable map from leaking into emitted states (where a later mutation would silently invalidate the state's snapshot semantics). Single helper centralizes the policy.
- **Two entry points, one mutation site**: WS path (`_onExternalUpdate` switch case) and test path (dedicated event handler) both end up mutating `_personasBySender`. The WS path delegates re-emit to the existing `_refreshCurrent`; the test path uses a separate `_emitCurrentSnapshot` (no fetch). Keeps both flows simple and observable.
- **Idempotency guard on release**: `_onVoicePersonaReleased` returns early if the senderId has no persona — matches Pass-1-F3 test 2.4.4's `expect: []` assertion. Without the guard, `Map.remove()` of an absent key would still trigger `_emitCurrentSnapshot()` and emit a (functionally-identical) state, breaking the no-emit contract.
- **Phase 0 dispatch test still passes after explicit case migration**: the new `voice_persona_assigned` case branch only mutates the persona map; doesn't fire audio/TTS. The Phase 0 test's `verifyNever(audio)` + `verifyNever(tts)` assertions still hold. Confirmed by re-running the Phase 0 file alongside the Phase 2 file in the full baseline run.

### Out of Scope (deferred to next session)

- **Voice-persona Phase 3 — UI badge** (next): new `PersonaBadge` widget wrapping `CircleAvatar`; new `DashedBorderPainter` (Q9 genuinely-new — no existing CustomPainter); 3 wiring sites (`_NotificationItemCard` in `conversation_by_date_screen.dart`, `ConversationScreen` header, inbox sender tile in `inbox_screen.dart`); 5 widget tests; EXECUTOR: HUMAN final acceptance review for badge color/contrast in light + dark mode.
- Voice-persona Phase 4 (TTS routing — collapsed to verify+comment per REUSE pre-pass), Phase 5 (docs + on-device verify) — gated on Phase 3.
- Conversation-mode + session-switcher milestones — separate plans, gated on voice-persona close.

---

## 2026.05.06 (post-/clear continuation) | Session `a756441c` — Phase 0 dispatch audit + voice-persona Phase 1 (CHECKPOINT)

#### Checkpoint | 2026.05.06 | Phase 0 dispatch audit + voice-persona Phase 1 data model both LANDED (273 → 290 baseline tests; +17)

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`
**Plan slate**: `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/` (unchanged from prior commit `e9fa8c9`)
**Implementation doc**: `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/01-implementation.md` (Phase 0 + 1 rows in §9 Execution Log populated)
**Continues from**: commit `e9fa8c9` (same session, post-/clear)

### Accomplishments

1. **Phase 0 — WS dispatch audit + regression test** (`00-phase-0-dispatch-audit.md`)
   - Live audit confirmed REUSE pre-pass verdict: 🟡 PARTIAL DRIFT — outer routing in `app.dart:79-93` correct; `notification_bloc.dart:146-170` `_onExternalUpdate` had no inner-`notification.type` pivot
   - Fix: extended handler with `switch (n.type)` — whitelisted types (`task`/`progress`/`alert`/`custom`/`user_initiated_message`/`session_topic`) route to existing audio + TTS path; default branch logs unknown types as canary for future migrations
   - New file `test/unit/notifications/notification_bloc_dispatch_test.dart` — 3 regression tests (voice_persona_assigned → no audio/TTS; some_unknown_type → graceful degradation; alert → existing path preserved)
   - Audit-doc §10 populated with live findings; §5 EXECUTOR checkboxes marked `[x]` with executed-evidence; §6 success criteria all met; status banner ✅ COMPLETE
   - Test impact: 273 → 276 (+3)

2. **Voice-persona Phase 1 — Data model** (`voice-persona/01-implementation.md §2`)
   - New `lib/features/notifications/data/voice_persona.dart` (87 lines) — liberal `fromJson` per Q7 (no enum validation), null-defense per F1 (missing/malformed fields → null, never throws), equality keyed on `voiceId` per Q3-driven contract, `toJson` round-trip helper
   - Modified `notification_models.dart` — added `VoicePersona? voicePersona` field on `NotificationItem`; `fromJson` now reads `voice_persona` envelope key (handles map/null/missing); re-exports `VoicePersona` for callers
   - New fixture `test/fixtures/notifications/notification-with-persona.json` — canonical Adam allocation (note: actual project layout is `test/fixtures/`, not the plan's `test/_fixtures/` typo; `_helpers/fixture_loader.dart:9` is the source of truth)
   - 14 new tests across 3 files: `voice_persona_test.dart` (9: parse round-trip / borrowed=true / null-defense missing / null-defense malformed / forward-compat / equality 3 cases / toJson round-trip); `notification_models_test.dart` (+3 net new); `notification_repository_test.dart` (+2 fixture-backed round-trip per Phase 1 Task 1.4)
   - Phase 1 §2 task checkboxes marked `[x]` with executed-evidence; §9 Execution Log Phase 0 + Phase 1 rows populated
   - Test impact: 276 → 290 (+14)

3. **Tracking document updates**
   - `01-implementation.md` — Phase 0 + Phase 1 §9 rows populated with test deltas + uncommitted-status
   - `00-index.md` — Current Status (2/6 phases complete; 290 tests); Phase Summary table marked ✅; two new Recent Updates entries
   - `00-phase-0-dispatch-audit.md` — full §10 audit-findings block; §5 + §6 + status banner
   - `TODO.md` — NEXT SESSION block reframed: Phase 0 ✅ done, Phase 1 ✅ done, Phase 2 promoted to header
   - `.claude-session.md` (gitignored) — manifest extended with Phase 0 + Phase 1 file entries

### Files Created (4)

- `lib/features/notifications/data/voice_persona.dart`
- `test/unit/notifications/voice_persona_test.dart`
- `test/unit/notifications/notification_bloc_dispatch_test.dart`
- `test/fixtures/notifications/notification-with-persona.json`

### Files Modified (8)

- `lib/features/notifications/domain/notification_bloc.dart` — `_onExternalUpdate` switch pivot
- `lib/features/notifications/data/notification_models.dart` — `voicePersona` field on `NotificationItem`
- `test/unit/notifications/notification_models_test.dart` — +3 new persona tests
- `test/unit/notifications/notification_repository_test.dart` — +2 fixture-backed round-trip tests
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/00-phase-0-dispatch-audit.md`
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/00-index.md`
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/01-implementation.md`
- `TODO.md`

### Test Results

| Suite | Pre-checkpoint | Post-Phase-0 | Post-Phase-1 |
|---|---|---|---|
| `test/unit/ test/widget/ test/service_integration/` | 273 ✅ | 276 ✅ | **290 ✅** |
| `test/unit/notifications/` (focused) | 27 ✅ | 30 ✅ | **42 ✅** |
| `test/legacy_quarantine/` (drift baseline) | 44 ❌ | 44 ❌ | 44 ❌ unchanged |

Net: +17 tests, zero regressions, zero quarantined-test reactivations.

### Key Decisions / Insights

- **Phase 0 default-branch design**: chose Option A (whitelist-then-default-log) over Option B (default-fallthrough-to-existing) — A's value is the LOG, which is the canary that Phase 0 explicitly exists to install. Future feature ports replace the default branch with explicit cases.
- **Plan path typo caught at execution time**: plan said `test/_fixtures/notifications/...` but the actual project layout is `test/fixtures/` (verified via `_helpers/fixture_loader.dart:9`). Corrected on the fly; documented in the Phase 1 §2 task 1.4 progress note. No design impact.
- **Equality keyed on `voiceId` only**: same-voice-different-session personas compare equal. Documented as acceptable because the bloc state map keys on `senderId`, never on persona identity. Null-voiceId twins also compare equal (benign for "no persona" placeholders).
- **Selective staging**: 2 pre-existing modified files in `src/rnd/v0.1.6-migration/` (from prior session, untouched by this work) excluded per the `.claude-session.md` v2.0 selective-staging rule.
- **No commit between Phase 0 and Phase 1**: ran them back-to-back without intermediate commit, matching the user's "continue" cadence + the no-auto-commit memory rule. This single checkpoint commit captures both at once.

### Out of Scope (deferred to next session)

- **Voice-persona Phase 2 — WS event dispatch** (next): bloc events `NotificationsVoicePersonaAssigned(senderId, persona)` + `NotificationsVoicePersonaReleased(senderId, name)`; bloc state `Map<String, VoicePersona> personasBySender` + `personaFor(senderId)` helper; replace Phase 0 default-branch logger with explicit cases; 4 new blocTest cases. Plan: `voice-persona/01-implementation.md §3`.
- Voice-persona Phase 3 (UI badge), Phase 4 (TTS routing), Phase 5 (docs + on-device verify) — gated on Phase 2.
- Conversation-mode + session-switcher milestones — separate plans, gated on voice-persona close.
- WS reconnect circuit-breaker, `/api/claude-code/dispatch` fossil cleanup, doc-viewer scope=docs deep-link — Tier-1 plumbing, separate slate.

---

## 2026.05.06 | Session `a756441c` — Mobile resync baseline + voice-persona plan-review (CLOSED)

#### Session-End | 2026.05.06 | Plan-review FULLY CLOSED — voice-persona milestone ready to implement (gated on Phase 0)

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`
**Plan slate**: `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/` (4 top-level docs + `voice-persona/` Pattern A subdir of 5 docs)
**Baseline**: `src/rnd/v0.1.7/2026.05.06-resync-baseline-mobile-vs-lupin.md`
**Implementation doc**: `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/01-implementation.md`

### Accomplishments

1. **Mobile-resync baseline** (`2026.05.06-resync-baseline-mobile-vs-lupin.md`)
   - Identified 12-day drift between mobile (last commit `85b0452`, 2026-04-24) and parent Lupin/CoSA (~125 commits since)
   - Themed analysis of three user-visible features (conversation mode, voice personas, focus/session-switcher) + the WS-event-cleanup migration silent-regression risk + retired endpoints + WS reconnect circuit-breaker

2. **Mobile port plan slate** (`2026.05.06-mobile-port-plans/`)
   - **`00-phase-0-dispatch-audit.md`** — WS dispatch audit prerequisite. Pre-confirmed PARTIAL DRIFT by REUSE pre-pass: outer routing in `app.dart:80-91` is correct; inner-type pivot missing in `notification_bloc.dart:146-170`
   - **Voice-persona Pattern A doc-set** (under `voice-persona/`): 5 docs with all five plan-review conventions in place (working contract, Q1-Q9 FROZEN decisions, EXECUTOR-tagged tasks, no TBD/OSQ markers, no "Manual E2E" residue)
   - **`02-conversation-mode-port-plan.md`** — skeleton; 4 UX directions sketched; awaits user direction
   - **`03-session-switcher-port-plan.md`** (renamed from focus-mode) — user articulated direction (Slack/Discord/Telegram-style chat picker as primary nav paradigm); 4 widget patterns sketched

3. **Three-pass plan-review on voice-persona milestone** (canonical workflow `<pip>/workflow/plan-review.md`)
   - **REUSE pre-pass** — Explore agent: 12 findings, 6 fix categories applied. Big finds: `voice_id` parameter is already shipping at `streaming_tts_player.dart:130-131` (reuse-as-is, collapses Phase 4 Task 4.1); `app.dart:80-91` already routes outer envelope correctly (extend-existing for Phase 0 narrowing). Q7-Q9 promoted from Open sub-questions to FROZEN at this gate
   - **Pass 1 Fitness** — Explore agent: 11 findings (F1-F11). User reviewed each individually via cosa-voice `ask_yes_no` + abstracts; approved all 11. 12 edits applied: Phase 1 sub-numbered as Tasks 1.1-1.5 with explicit dependency chain; null-defense contract; blocTest assertion shapes; badge wiring file paths; server ordering guarantee; emoji failure-mode contract; SIMULATE flag scope clarification. No Q1-Q9 challenged
   - **Pass 2 Adversarial** — Explore agent: 8 wording-polish findings (F12-F19) + meta-finding F20 (13 bare checkboxes in Phase 0 §5 lacking EXECUTOR tags). User picked option (b) — F20 only; 4 edits tagged all 13 with `EXECUTOR: AI`. Convergence check passed: bare-checkbox grep returns 0 hits in Phase 0 §5; all `EXECUTOR: HUMAN` lines have same-line justifications

4. **Session manifest** (`.claude-session.md`, gitignored)
   - Multi-Session v2.0 manifest tracking all session-touched files

### Files Created (10)

- `src/rnd/v0.1.7/2026.05.06-resync-baseline-mobile-vs-lupin.md`
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/00-phase-0-dispatch-audit.md`
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/01-voice-persona-port-plan.md` (entry pointer)
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/02-conversation-mode-port-plan.md`
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/03-session-switcher-port-plan.md`
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/00-index.md`
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/00-working-contract.md`
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/01-implementation.md`
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/03-decisions.md`
- `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/04-testing-validation.md`

### Test Results

| Suite | Start | End |
|-------|-------|-----|
| Unit + widget + service_integration | 273 | 273 |

No code changes this session; all work was planning + plan-review. Test count unchanged from prior session `0d54c763`.

### Key Decisions / Insights

- **Plan-review opt-in for Pattern 3**: Voice-persona is a Pattern 3 (Feature Development) plan; canonical mandate would be REUSE-only. User opted into the full three-pass review to harden the doc-set before implementation. Justified the upgrade to Pattern A right-sized doc-set (`voice-persona/` subdir).
- **Phase 0 scope tightened by REUSE**: original Phase 0 plan touched WS service + app.dart + bloc; REUSE confirmed only the bloc handler needs the inner-type pivot. Pre-confirmed verdict embedded in §10 of audit doc.
- **Q1-Q9 FROZEN decisions** anchor the milestone: Q1 (server-stamped persona, no mobile cache), Q2 (dashed border for `borrowed=true`), Q3 (optional `voice_id` parameter, server-fallback to Sam), Q4 (no `voice_id` for `flutter_tts` fallback path), Q5 (badge only, no theme sweep), Q6 (on-device verify bucketed in existing TTS runbook), Q7 (liberal fromJson), Q8 (badge in features/notifications), Q9 (DashedBorderPainter genuinely-new)
- **Session-switcher direction shifted**: was hypothesized to be implicit on mobile; user articulated direction (purpose-built first-class widget set for switching between Claude Code instantiations across repos). This couples session-switcher to conversation-mode (mic-glyph overlay lives on switcher icons); recommended order: session-switcher BEFORE conversation-mode plan-out
- **Cosa-voice MCP for one-at-a-time decisions**: Pass 1 walkthrough used `ask_yes_no` per finding with abstracts carrying details. Effective pattern for batch-decision sessions where each item warrants individual consideration

### Out of Scope (deferred to next session)

- Phase 0 dispatch audit execution (Task #5 in session manifest)
- Voice-persona Phases 1.1-5 implementation
- Conversation-mode UX direction selection + plan-mode + plan-review
- Session-switcher widget pattern selection + plan-mode + plan-review (recommended to land BEFORE conversation-mode)
- WS reconnect circuit-breaker handling (Tier-1 Mobile-Resync silent-regression item)
- `/api/claude-code/dispatch` fossil cleanup
- Doc-viewer scope=docs deep-link handling

---

## 2026.04.24 | Session `0d54c763` — TTS overlap bug fix + on-device verify prep

#### Session-End | 2026.04.24 | 273/273 non-legacy tests green (was 263 at session start; +10)

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`
**Runbook**: `src/rnd/v0.1.7/2026.04.24-on-device-tts-verify-runbook.md`

### Accomplishments

1. **TTS overlap bug audit + fix** (`lib/services/tts/streaming_tts_player.dart`)
   - Root cause: `handleWsEvent` for `audio_streaming_complete` fired `_completeCtrl` immediately, but `_playPcmBuffer()` was not awaited. Orchestrator advanced its FIFO while audio was still playing → scenario #7 (two rapid highs) would interrupt the first utterance.
   - Fix: extracted `StreamingTtsAudioPlayer` test seam (mirrors `AudioPlaybackController` pattern from `AudioArtifactPlayer`), gated `TtsCompleteEvent` emission on `onPlayerComplete` via a completer + identity guard so `stop()` (urgent preempt) doesn't emit a stray complete.

2. **Quota-simulation dart-define hook** (same file)
   - `LUPIN_DEV_SIMULATE_TTS_ERROR` dart-define, `kDebugMode`-gated, optional-constructor-override for tests. When true, `speak()` adds `debug_simulate_error: true` to the POST body. Backend `/api/get-speech-elevenlabs` already supports this flag (`speech.py:508,891`) and emits a `tts_error` WS event with `error_code=quota_exceeded`. Enables on-device scenario #8 without needing an exhausted ElevenLabs account.

3. **Regression + flag-coverage test suite** (`test/unit/services/tts/streaming_tts_player_test.dart`)
   - 10 new tests covering: complete-NOT-fired-before-onComplete, complete-IS-fired-after-onComplete, empty-buffer defensive, stop()-during-playback, preempt→next-utterance, isPlaying lifecycle, stray-event filter, tts_error mid-stream, simulateTtsError=true POST-body-inclusion, simulateTtsError=false POST-body-omission. Unit count: 177 → 187.

4. **Scenario-firing script** (`src/scripts/fire-tts-scenarios.py`)
   - 12-scenario Python script that POSTs each TODO.md scenario (lines 54-71) to `/api/notify`. Supports `--scenario all`, single-scenario, `--dry-run`, auto-fires s5b after s5 with 500ms rapid-fire gap. Uses `requests` (per CLAUDE.md no-curl rule). Loads API key from `$LUPIN_ROOT/src/conf/keys/notification-api-claude-code-dev`.

5. **On-device verify runbook** (`src/rnd/v0.1.7/2026.04.24-on-device-tts-verify-runbook.md`)
   - Copy-paste-ready runbook for the laptop leg of the next session. Covers rsync → pub get → build → install → per-scenario checklist with expected behavior, adb logcat filters, stub-injection for s8, channel-sound gotcha, PCM→WAV verification.

### Files Modified (2)

- `lib/services/tts/streaming_tts_player.dart` — overlap fix + test seam + dart-define hook
- `TODO.md` — will be updated at session-end to reflect next steps

### Files Created (3)

- `test/unit/services/tts/streaming_tts_player_test.dart`
- `src/scripts/fire-tts-scenarios.py`
- `src/rnd/v0.1.7/2026.04.24-on-device-tts-verify-runbook.md`

### Test Results

| Suite | Start | End |
|-------|-------|-----|
| Unit | 177 | 187 |
| Widget + service_integration | 86 | 86 |
| **Total** | **263** | **273** |

Pre-existing 44 `legacy_quarantine/` failures unchanged (per memory rule, drift-broken quarantined tests, not regressions).

### Key Decisions / Insights

- **Mock/real contract divergence**: The 11 existing `TtsOrchestrator` tests mocked `StreamingTtsPlayer` entirely and emitted `completeCtrl` at the intended contract time. The real player violated the contract (fired complete on WS stream, not on playback end). Tests passed against the mock, but scenario #7 would have failed on-device. The new regression suite closes this gap by exercising the real player with a mocked `StreamingTtsAudioPlayer`.
- **`_activePlaybackCompleter` identity guard**: chose field + capture-local + `identical()` check over a generation counter. Reason: completer + identity is idiomatic Dart for "supersede this async operation" and plays well with `stop()`'s need to wake hung awaits without emitting spurious complete events.
- **Dev-flag over backend stub**: `debug_simulate_error` was already baked into the backend but the mobile client didn't expose it. Adding a `kDebugMode`-gated dart-define + optional constructor override is cleaner than a backend debug endpoint, confined to the mobile app, and automated via unit tests (per memory: "Automate smokes before recommending on-device manual testing").
- **Script over curl**: `fire-tts-scenarios.py` uses `requests` per project CLAUDE.md's `NEVER use curl for API testing` rule. Dry-run mode validated the POST payload shape without mutating backend state.
- **No commits**: uncommitted through this session per memory rule "user drives commit cadence". Session-end ritual handles the commit prompt with explicit user approval.

### Out of Scope (deferred to next session)

- On-device execution of the 10 TTS scenarios (laptop + emulator, user-driven)
- Phase 4b (podcast `audio_path` field rename) — still blocked on parent-Lupin cross-repo fix
- Hygiene follow-ups from commit `edaec79` (flutter pub get sanity, history.md one-liner decision, etc.) — not picked up this session

---

## 2026.04.22 | Session `40aa03d3` — Tier 2 + Tier 4 polish slate (4 phases)

#### Session-End | 2026.04.22 | 263/263 non-legacy tests green (was 237 at session start; +26 across the slate)

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`
**Plan**: `src/rnd/v0.1.7/2026.04.22-tier-2-and-4-polish-plan.md` (serialized from approved plan-mode output; 4 phases + 2 doc cleanups, scoped excluding TimeSavedDashboard per user)

### Accomplishments

1. **Phase 0 — Doc cleanup + cross-repo bug filing**
   - `_emit_queue_update` parent-Lupin bug moved from Cross-Repo → Completed in `bug-fix-queue.md` (user confirmed fix landed in parent)
   - **NEW** Cross-Repo entry filed: parent Lupin `routers/queues.py:456,523` queue-metadata mapping omits `artifacts['audio_path']` for `pg-*`/`rp-*` jobs (confirmed by direct read; podcast `job.py:281,398` writes the field, queue router never reads it). Blocks Phase 4b.
   - `TODO.md` curated: `TimeSavedDashboard + StatsRepository + StatsBloc + fl_chart` removed and replaced with `[scope decision 2026-04-22]` line per user
   - Plan serialized to `src/rnd/v0.1.7/2026.04.22-tier-2-and-4-polish-plan.md`

2. **Phase 1 — TrustStateScreen drilldown** (5 widget tests, 237→242)
   - New `lib/features/decision_proxy/presentation/trust_state_screen.dart` — per-domain grouped trust-state list with circuit-breaker badge
   - Reused already-shipped `DecisionProxyLoadTrust` event/state/handler (no new bloc plumbing)
   - "View trust details" AppBar action wired on `TrustDashboardScreen` (re-loads dashboard on pop-back to handle `DecisionProxyTrustLoaded` → `DecisionProxyDashboardLoaded` state transition)

3. **Phase 2+3 — SenderDates + ConversationByDate** (12 widget + 2 bloc tests, 242→256)
   - 2 new bloc events (`NotificationsLoadSenderDates`, `NotificationsLoadConversationByDate`), 2 new states, 2 new handlers, +1 `_refreshCurrent()` branch for the by-date case
   - `sender_dates_screen.dart` — date tile list with `newCount` badge
   - `conversation_by_date_screen.dart` + `_NotificationItemCard` (Option A renderer per architectural decision — purpose-built for `NotificationItem`'s 44-field shape; rejects unifying with `ConversationMessage` to avoid cross-repo work)
   - Calendar AppBar action on `ConversationScreen` → push `SenderDatesScreen`; date tile tap → push `ConversationByDateScreen` anchored to date

4. **Phase 4a — AudioArtifactPlayer in-app playback** (7 widget tests, 256→263)
   - Full rewrite of `lib/features/artifacts/audio_artifact_player.dart` around `audioplayers` + `DeviceFileSource`
   - Extracted `AudioPlaybackController` interface so widget tests can mock it (audioplayers requires platform channels)
   - State machine: idle → loading → ready → playing/paused → idle (+ error)
   - Calls `TtsOrchestrator.stopAll()` before play to coordinate single audio stream
   - Preserves `IoFileService.shareToExternalApp` as Share overflow action

### Files Created (8)

- `src/rnd/v0.1.7/2026.04.22-tier-2-and-4-polish-plan.md` (serialized plan)
- `lib/features/decision_proxy/presentation/trust_state_screen.dart`
- `test/widget/decision_proxy/trust_state_screen_test.dart`
- `lib/features/notifications/presentation/sender_dates_screen.dart`
- `test/widget/notifications/sender_dates_screen_test.dart`
- `lib/features/notifications/presentation/conversation_by_date_screen.dart`
- `test/widget/notifications/conversation_by_date_screen_test.dart`
- `test/widget/artifacts/audio_artifact_player_test.dart`

### Files Modified (10)

- `bug-fix-queue.md`, `TODO.md`
- `lib/core/testing/test_keys.dart` (+12 constants across phases)
- `test/_harness/test_app.dart` (+3 mocktail fallbacks)
- `lib/features/notifications/domain/notification_event.dart` (+2 events)
- `lib/features/notifications/domain/notification_state.dart` (+2 states)
- `lib/features/notifications/domain/notification_bloc.dart` (+2 handlers, +1 `_refreshCurrent` branch)
- `lib/features/notifications/presentation/conversation_screen.dart` (calendar IconButton)
- `lib/features/decision_proxy/presentation/trust_dashboard_screen.dart` (View trust details action)
- `lib/features/artifacts/audio_artifact_player.dart` (full rewrite around `audioplayers`)
- `test/widget/notifications/conversation_screen_test.dart` (+1 calendar-nav test)
- `test/unit/notifications/notification_bloc_test.dart` (+2 blocTests)

### Test Results

| Suite | Start | End |
|-------|-------|-----|
| Unit + Widget + ServiceIntegration | 237 | 263 |

Pre-existing 44 `legacy_quarantine/` failures unchanged (drift-broken tests; per memory rule, not regressions).

### Key Decisions / Insights

- **Option A for date-grouped renderer**: Purpose-built `_NotificationItemCard` instead of unifying `NotificationItem` (44 fields, no delivery state) and `ConversationMessage` (20 fields incl. `state`/`deliveredAt`/`respondedAt`/`responseValue`). Trade: by-date view shows priority/played/responseRequested but NOT a "responded at X with Y" badge. Avoids cross-repo work and zero risk to existing `_MessageCard` tests.
- **`AudioPlaybackController` extraction**: Wrapping `audioplayers.AudioPlayer` behind a constructor-injected interface enables widget tests; otherwise platform channels block them. Real impl uses `DeviceFileSource(file.path)` (NOT `BytesSource`) since podcast MP3s can be multi-MB.
- **Audio focus**: `AudioArtifactPlayer.play()` calls `TtsOrchestrator.stopAll()` first. Inverse direction (urgent TTS preempts playback) already covered by `_preemptForUrgent`. No orchestrator changes required.
- **Phase 4a/4b split**: 4a builds the player UI now; 4b (field rename to `audioPath` in `JobSummary`) is gated on parent-Lupin merging the cross-repo `audio_path` mapping fix. Empty path = graceful no-op for now (filed as cross-repo bug).
- **Pop-back state recovery (Phase 1)**: `TrustDashboardScreen`'s `BlocBuilder` falls through to `SizedBox.shrink()` when state is `DecisionProxyTrustLoaded`. Solution: `await Navigator.push()` then re-fire `DecisionProxyLoadDashboard` if mounted. Same pattern applied to `ConversationScreen` calendar nav.

### Out of Scope (per user direction)

- `TimeSavedDashboard / StatsRepository / StatsBloc / fl_chart` — explicitly deferred indefinitely
- Phase 4b mobile field rename — gated on parent-Lupin backend fix
- Cross-repo authoring of parent-Lupin `audio_path` fix (filed as cross-repo bug only)

---

## 2026.04.21 | Session `214c47b6` — Stage 4 agentic + generate-gist UI + notification audio + FCM defer + agent-narration TTS

#### Session-End | 2026.04.21 22:10 | 237/237 tests green (was 178 at session start; +59 over the day)

**Day scope** (four logical deliverables across the 10-hour session):
1. **Auto-pilot phase (morning→lunch)**: Stage 4 agentic widget-test coverage + generate-gist UI — ~8 hr — see Checkpoint 1 below.
2. **Foreground notification audio**: `NotificationAudioService` + channels + settings + flutter_tts — ~2 hr — Checkpoint 2 below.
3. **FCM defer + R&D doc**: pulled cross-repo bug-queue item after investigation; preserved reasoning in `src/rnd/v0.1.7/2026.04.21-fcm-apns-push-considerations.md` — ~30 min — Checkpoint 3 below.
4. **Agent-narration TTS (ElevenLabs primary + flutter_tts fallback)**: slim `StreamingTtsPlayer` + `TtsOrchestrator` (FIFO + urgent preempt + quota-fallback); `NotificationAudioService` refactored for split responsibilities; 14 new tests — ~3 hr — Checkpoint 4 below (this session-end commit).

**Final test count**: 178 → 237 green (+59 total). No regressions.
**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`.
**Next session first-priority**: on-device verification of items #2 + #4 — see the "⭐ NEXT SESSION" banner at the top of TODO.md.

---

#### Checkpoint 4 | 2026.04.21 22:10 | Agent-narration TTS pipeline (ElevenLabs + flutter_tts fallback)

**Files**: `lib/services/tts/streaming_tts_player.dart` (new, ~230 lines), `lib/services/tts/tts_orchestrator.dart` (new), `lib/services/notification_audio/notification_audio_service.dart` (refactored — removed auto-priority speech branch, exposed `flutterTtsSpeak()` + `stopFallbackSpeech()`), `lib/features/notifications/domain/notification_bloc.dart` (injected orchestrator), `lib/app.dart` (routes `audio_streaming_*` + `tts_error` to player), `lib/core/di/service_locator.dart` (registered new services), `lib/services/websocket/websocket_service.dart` (renamed binary wrapper to `audio_streaming_chunk`), `test/unit/services/tts/tts_orchestrator_test.dart` (new, 11 cases), `test/unit/notifications/notification_bloc_test.dart` (extended), `test/unit/services/notification_audio/notification_audio_service_test.dart` (rewrote for split responsibilities), `src/rnd/v0.1.7/2026.04.21-agent-narration-tts-plan.md` (new plan doc), TODO.md (+1 manifest). Test count 225 → 237 green.
**Architecture note**: Abandoned the `EnhancedTTSService` revival approach after audit revealed 2,707-line dep chain (EnhancedWebSocketService + AdaptiveConnectionManager + AppLifecycleService) for marginal benefit. Legacy stack stays tree-shaken.
**Commit**: [pending — this session-end commit]

#### Checkpoint 3 | 2026.04.21 17:55 | FCM/APNs defer + R&D doc

**Decision**: After filing a cross-repo bug-queue item requesting backend FCM/APNs support, user asked whether push can be self-hosted. Walk-through of landscape (FCM/APNs are OS-gatekeepers; realistic alternatives are silent-push relay, Android foreground service with persistent notification, or UnifiedPush/ntfy) converged on "too early in the project to commit to any of this." **Pulled the parent-Lupin bug-queue item**; captured investigation + 2026-04-21 defer decision + trigger conditions to revisit in `src/rnd/v0.1.7/2026.04.21-fcm-apns-push-considerations.md` (322 lines). Updated mobile `TODO.md` Phase 5 entries; updated `2026.04.21-notification-audio-on-receipt-plan.md` Phase 5 + Cross-Repo Dependency sections to point at the R&D doc.
**Commit**: [pending — this session-end commit]
**Cross-repo side-effect**: `/mnt/DATA01/include/www.deepily.ai/projects/lupin/bug-fix-queue.md` was edited (FCM entry removed); left uncommitted in parent repo per cross-repo git rules.

#### Checkpoint | 2026.04.21 14:50 | Stage 4 agentic widget-test coverage + generate-gist UI

**Files**: test_keys.dart, 8 agentic forms, 8 agentic widget test files, notification event/state/bloc, conversation_screen + test, test_app harness, TODO.md, plan doc (+1 manifest)
**Commit**: 92852b6

#### Checkpoint | 2026.04.21 17:15 | Notification audio-on-receipt (dings + on-device TTS for medium/high/urgent)

**Files**: pubspec.yaml (+ `flutter_local_notifications` + `flutter_tts`), AndroidManifest.xml (`POST_NOTIFICATIONS`), 3 MP3 assets copied from Lupin web client into `android/app/src/main/res/raw/lupin_{medium,high,urgent}.mp3`, new `NotificationAudioService` + `NotificationPreferences`, new `NotificationAudioSettingsScreen` + gear-icon entry on home AppBar, extended `NotificationsExternalUpdate` event with `NotificationItem`, `app.dart` parses WS payload, `NotificationBloc._onExternalUpdate` triggers audio, DI wiring in `service_locator.dart`, +17 new tests (prefs + service + bloc + settings widget), plan doc `src/rnd/v0.1.7/2026.04.21-notification-audio-on-receipt-plan.md`, TODO.md (+1 manifest). Test count 206 → 223 green.
**Commit**: 94f0d77

### Session Summary
- **Objective**: Auto-pilot session while user was at lunch — close out Testing Playbook Stage 4 (TestKeys + widget tests for the 8 agentic forms that didn't yet have them) and deliver at least one Tier 2 polish feature. Skip anything requiring laptop / adb / on-device / manual testing.
- **Outcome**: ✅ **206/206 unit + widget tests green** (was 178 at session start; **+28 new tests**). 38 new `TestKeys` constants, 8 new widget test files, full `generate-gist` UI pipeline end-to-end.
- **Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`

### Accomplishments
1. **Plan serialized** — `src/rnd/v0.1.7/2026.04.21-stage-4-agentic-coverage-and-tier-2-polish.md` documents the re-ordered hands-free execution sequence, cost/value analysis for skipped fixture-capture phases, and the two TODO.md corrections discovered during exploration.
2. **Stale TODO corrections**:
   - `getIt` in `home_screen.dart` — confirmed already removed (grep-verified, only DI-canonical files reference `getIt`); marked done.
   - `lib/shared/models/notification_item.dart` — turned out NOT to be orphan. Re-exported via `shared/models/models.dart` and imported by 20+ production files (voice bloc, audio cache, repositories). Two `NotificationItem` classes now coexist (old in `shared/models/`, new in `features/notifications/data/notification_models.dart`) for different layers. Reclassified TODO as "leave in place; revisit with voice/audio refactor".
3. **TestKeys expansion** — 38 new constants added to `lib/core/testing/test_keys.dart` covering all 8 agentic forms (pg/px/sw/bfe/tfe/ts/rp/rx).
4. **TestKeys wired into 8 agentic forms** — podcast, presentation, SWE team, Bug Fix Expediter, Test Fix Expediter, Test Suite (including prefix-suffixed checkbox keys for all 4 test types), Research→Podcast, Research→Presentation.
5. **8 new widget test files** (`test/widget/agentic/`) — render + form-reset + required-field validation + valid-submit dispatch paths for all 8 forms. BFE test additionally verifies `deadJobId` constructor pre-fill. TSF test additionally verifies the "unchecking all types makes submit a no-op" path. 26 new test cases total.
6. **`generate-gist` UI** — new `NotificationsGenerateGistRequested` event + `NotificationsGistLoading`/`NotificationsGistReady` states + bloc handler that pulls currently-loaded messages and posts to `POST /api/notifications/generate-gist`. `ConversationScreen` AppBar gets a **Summarize** icon button; `NotificationsGistReady` triggers a bottom-sheet rendering of the LLM summary (keyed `TestKeys.convGistSheet`). After the sheet closes, the bloc re-emits the prior `NotificationsConversationLoaded` so the message list stays intact.
7. **3 new ConversationScreen widget tests** — Summarize button renders; tap dispatches the new event; `NotificationsGistReady` state materializes the gist bottom sheet.
8. **Test harness updated** — `registerHarnessFallbacks()` now registers a fallback for `NotificationsGenerateGistRequested` so mocktail `any()` works against the new event type.
9. **Auto-pilot hands-free pattern saved to memory** — when user signals away-status, re-order the queue to filter out any item needing their keyboard/laptop/device involvement.

### Files Added (9 new)
- `src/rnd/v0.1.7/2026.04.21-stage-4-agentic-coverage-and-tier-2-polish.md`
- `test/widget/agentic/podcast_generator_form_test.dart`
- `test/widget/agentic/presentation_generator_form_test.dart`
- `test/widget/agentic/swe_team_form_test.dart`
- `test/widget/agentic/bug_fix_expediter_form_test.dart`
- `test/widget/agentic/test_fix_expediter_form_test.dart`
- `test/widget/agentic/test_suite_form_test.dart`
- `test/widget/agentic/research_to_podcast_form_test.dart`
- `test/widget/agentic/research_to_presentation_form_test.dart`

### Files Modified (12)
- `lib/core/testing/test_keys.dart` — 38 new constants
- `lib/features/agentic/presentation/{podcast_generator,presentation_generator,swe_team,bug_fix_expediter,test_fix_expediter,test_suite,research_to_podcast,research_to_presentation}_form.dart` — TestKeys wired to primary inputs + switches + submit buttons
- `lib/features/notifications/domain/{notification_event,notification_state,notification_bloc}.dart` — gist event + states + handler
- `lib/features/notifications/presentation/conversation_screen.dart` — Summarize AppBar action + `_showGistSheet` bottom-sheet rendering
- `test/_harness/test_app.dart` — gist fallback registered
- `test/widget/notifications/conversation_screen_test.dart` — 3 new tests for gist flow
- `TODO.md` — stale entries corrected; new completions recorded

### Test Results
| Suite | At session start | At session end |
|-------|------------------|----------------|
| Unit   | 150 | 150 |
| Widget | 28  | 56  |
| **Total** | **178** | **206** |

### Key Decisions / Insights
- **Fixture-capture deferred with justification**: Unlike notifications/decision-proxy where real-backend fixtures caught the login envelope bug, agentic submit responses share ONE `AgenticSubmitResponse` envelope across all 10 endpoints. Capturing live fixtures would burn real LLM $$ (DR/podcast/presentation spawn real work) for marginal drift-detection value. Hand-stubbed envelopes in `agentic_repository_test.dart` are documented against the OpenAPI spec and left as-is.
- **Gist flow kept one-shot state**: The bloc emits `NotificationsGistReady` transiently, then re-emits the prior `NotificationsConversationLoaded` so the underlying list view doesn't collapse. UI uses a `BlocConsumer` listener (not builder) for the bottom sheet so the conversation stays rendered under the modal.
- **Double-emit pattern**: same pattern used for gist error handling — emit `NotificationsError(msg)` then re-emit prior state. No persistent "error banner" state; consistent with existing `_onRespond` flow.
- **`NotificationItem` vs `ConversationMessage`**: the former is the canonical shape from the REST list endpoint; the latter is a flattened conversation-specific shape with delivery/state fields. They diverge enough that switching ConversationScreen to `conversation-by-date` requires unified rendering — deferred, logged in TODO.md with blocker note.
- **TrustStateScreen drilldown** (from the original plan): deferred. More invasive (new screen, per-domain data shape) and of less immediate value than the gist delivery. Queued for user's return.

### Out of Scope (not touched this session)
- Device/emulator sanity pass (5 items in TODO.md) — laptop domain per memory
- Cross-repo parent-Lupin `_emit_queue_update` fix — different repo
- Stats dashboard / `fl_chart` integration
- In-app audio playback wiring in `AudioArtifactPlayer`
- Date-grouped ConversationScreen — blocked by model type divergence
- TrustStateScreen drilldown — deferred for user review

---

## 2026.04.19 – 2026.04.20 | Session `1fb8dc65` — URL-encoding, WS lifecycle wiring, HTTP-interceptor idempotency, bug-fix-queue split

### Session Summary
- **Objective**: Close out the 2026-04-17 hot-bug list (URL-encoding + post-login investigation), then act on whatever the investigation surfaced.
- **Outcome**: ✅ 4 bugs fixed, 1 cross-repo bug surfaced for parent Lupin. WS lifecycle wiring validated end-to-end on emulator (test `notify()` arrived in inbox in real time without pull-to-refresh). Bug tracker split from TODO.md per new convention. **178/178 unit + widget tests green** (was 169 at session start; +9 new).
- **Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`

### Accomplishments
1. **`NotificationRepository` URL-encoding** — top-level `_enc()` helper (`Uri.encodeComponent`) applied to all 11 path-interpolation sites (senderId / userEmail / userId / project / dateString). Regression test covers slash-bearing sender IDs + `@` in email. Updated 7 pre-existing handler keys in repo + bloc tests. Shipped as commit `ab2a56c`.
2. **Post-login investigation** — code-read audit surfaced that `WebSocketService.connect()` was never invoked post-login; the `_dispatchWsEvent` router in `app.dart` was dead code at runtime. Findings serialized to `src/rnd/v0.1.7/2026.04.19-hot-bugs-url-encoding-and-post-login-investigation.md`.
3. **WS lifecycle wiring** — new `WsLifecycleListener` widget (`BlocListener<AuthBloc>` with `listenWhen` on `runtimeType` change) drives `ws.connect(userId:)` on `AuthAuthenticated` and `ws.disconnect()` on `AuthUnauthenticated`/`AuthError`. 5 widget-test cases covering the full transition matrix. Plan doc at `src/rnd/v0.1.7/2026.04.19-ws-lifecycle-auth-wiring-plan.md`. Validated end-to-end on emulator.
4. **`DecisionProxyRepository` URL-encoding parity** — same `_enc()` pattern applied to 3 sites (`pending`, `trust`, `decisions/$domain/$category`). +1 regression test.
5. **Duplicate HTTP log output** — diagnosed as double `_configureDio()` on shared Dio: `CachedHttpService extends HttpService` + both get the same DI singleton, each adding `LogInterceptor`+`InterceptorsWrapper`. Fixed with `options.extra['_lupin_http_configured']` idempotency marker. +2 unit tests.
6. **Bug tracker / TODO split** — new `bug-fix-queue.md` (v2.0 format, mirrors parent Lupin's convention); `TODO.md` scoped to build-out work only with a header documenting the split.

### Files Added (7 new)
- `lib/features/auth/presentation/ws_lifecycle_listener.dart`
- `test/widget/auth/ws_lifecycle_listener_test.dart`
- `test/unit/services/network/http_service_test.dart`
- `src/rnd/v0.1.7/2026.04.19-hot-bugs-url-encoding-and-post-login-investigation.md`
- `src/rnd/v0.1.7/2026.04.19-ws-lifecycle-auth-wiring-plan.md`
- `bug-fix-queue.md`
- *(the URL-encoding regression test additions are inline in existing files)*

### Files Modified
- `lib/app.dart` — wrapped `MaterialApp` with `WsLifecycleListener`
- `lib/features/notifications/data/notification_repository.dart` — `_enc()` helper + 11 sites *(already shipped in `ab2a56c`)*
- `lib/features/decision_proxy/data/decision_proxy_repository.dart` — `_enc()` helper + 3 sites
- `lib/services/network/http_service.dart` — `_configureDio()` idempotency guard
- `test/unit/notifications/notification_{repository,bloc}_test.dart` — 7 handler keys + regression test *(committed)*
- `test/unit/decision_proxy/decision_proxy_{repository,bloc}_test.dart` — 3 handler keys + regression test
- `TODO.md` — scoped to build-out; bug entries migrated to `bug-fix-queue.md`

### Test Results
| Suite | At session start | At session end |
|-------|------------------|----------------|
| Unit   | 141 | 150 |
| Widget | 28  | 28  |
| **Total** | **169** | **178** |

### Key Decisions / Insights
- **Logging ≠ dispatching**: the apparent "duplicate dispatch" in emulator logcat was duplicate *logging* caused by `CachedHttpService` extending `HttpService` on a shared Dio. Using `options.extra` as the idempotency sentinel keeps the guard on the Dio itself, not on the service class, so any future service re-configuring the same Dio is also safe.
- **Bug-tracker convention**: split `bug-fix-queue.md` from `TODO.md` mirrors parent Lupin's format. TODO = *build*; bug-fix-queue = *fix*. Header on `TODO.md` documents the split so future sessions don't mistakenly file bugs there again.
- **WS token rotation** left as follow-up: `WebSocketService._authenticate()` reads the token once at connect time; token refresh inside a held WS is NOT handled. Filed as cross-cutting follow-up in the plan doc.

### Cross-Repo Surfaced
- **Lupin backend `NotificationFifoQueue._emit_queue_update` AttributeError** — `POST /api/notifications/{id}/played` returns 500 in parent Lupin. Tracked in `bug-fix-queue.md` under "Cross-Repo" so lupin-mobile contributors see it, but the actual fix belongs in the parent repo (`src/cosa/rest/`).

---

## 2026.04.17 - WS hookup + auth envelope fix + fixture-backed tests + broader widget coverage

### Session Summary
- **Objective**: Complete the on-device verification loop for the v0.1.6 resync work, then close the loop on test infrastructure (playbook Stage 1 → Stage 3 fixtures).
- **Status**: ✅ 169/169 unit + widget tests green. Login verified on-device. All server-side work uncommitted per user's explicit commit discipline.
- **Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`

### Accomplishments
1. **WebSocket hookup (Track C)** — wired `NotificationsExternalUpdate` dispatch in `app.dart` so `notification_queue_update` WS events now refresh the inbox without manual pull. +1 blocTest covering the refresh path.
2. **Testing playbook Stage 1** — added `mocktail` + `network_image_mock`, `TestKeys` class, shared `testApp` harness, `integration_test/` scaffold, first widget test (login). Renamed stale `test/integration/` → `test/service_integration/`.
3. **Widget coverage for three smoke scenarios** — `inbox_screen` (4 cases), `conversation_screen` (3 cases incl. yes_no response flow), `trust_dashboard_screen` (3 cases + 2 approve/reject), `deep_research_form` (3 cases incl. dry-run submit). On-device smokes downgraded from "primary verification" to "sanity pass".
4. **Dev-only credential pre-fill** — `LUPIN_DEV_EMAIL` + `LUPIN_DEV_PASSWORD` via `--dart-define`, gated by `kDebugMode`, wired in `auth_gate.dart` + `login_screen.dart` + `build-and-deploy-lupin-mobile.sh`.
5. **Auth login envelope fix** — `AuthRepository.login/refresh` were parsing flat tokens; real backend returns `LoginResponse`/`RefreshResponse` envelopes with `tokens` nested. Extracted `_parseTokensEnvelope` helper that throws `AuthException` on bad shape (no more raw `TypeError` swallowed by generic catch). Added `AuthGate` widget test suite covering the navigation contract.
6. **Stage 2 fixture-backed tests (auth)** — captured real `/auth/*` responses via Python script, redacted JWTs + PII, wrote JSON fixtures. Drift detection verified by deliberate fixture mutation.
7. **Stage 3 fixture expansion + broader TestKeys** — shared `_fixture_lib.py`, new capture scripts for notifications + decision-proxy, 8 new fixtures, 6 repository tests converted, keys applied to `InteractivePromptSheet` yes/no buttons + `_DecisionCard` approve/reject, new widget test for prompt sheet, approve/reject tests added to dashboard.

### Files Added (24 new)
- `src/scripts/_fixture_lib.py`, `capture-auth-fixtures.py`, `capture-notifications-fixtures.py`, `capture-decision-proxy-fixtures.py`
- `test/fixtures/README.md`, `test/fixtures/auth/*.json` (4), `test/fixtures/notifications/*.json` (4), `test/fixtures/decision_proxy/*.json` (4)
- `test/_helpers/fixture_loader.dart`, `test/_harness/test_app.dart`
- `test/widget/auth/{login_screen,auth_gate}_test.dart`
- `test/widget/notifications/{inbox_screen,conversation_screen,interactive_prompt_sheet}_test.dart`
- `test/widget/decision_proxy/trust_dashboard_screen_test.dart`
- `test/widget/agentic/deep_research_form_test.dart`
- `integration_test/smoke_hello_test.dart`
- `lib/core/testing/test_keys.dart`
- `src/rnd/v0.1.7/2026.04.17-{tracks-c-b-a-implementation-plan,auth-login-envelope-parse-fix,stage-3-fixture-expansion-and-testkeys}.md`

### Files Modified
- `lib/app.dart`, `lib/features/auth/presentation/{login_screen,auth_gate}.dart`, `lib/services/auth/auth_repository.dart`, `lib/features/notifications/presentation/{inbox_screen,interactive_prompt_sheet}.dart`, `lib/features/decision_proxy/presentation/trust_dashboard_screen.dart`, `lib/features/agentic/presentation/deep_research_form.dart`
- `pubspec.yaml` (mocktail + network_image_mock), `src/scripts/build-and-deploy-lupin-mobile.sh` (dart-define flags)
- `test/unit/notifications/notification_{repository,bloc}_test.dart`, `test/unit/decision_proxy/decision_proxy_repository_test.dart`, `test/unit/auth/{auth_repository,auth_interceptor}_test.dart`
- `TODO.md`

### Files Renamed
- `test/integration/` → `test/service_integration/` (2 files, non-canonical service-level notes, not the Flutter `integration_test/` at project root)

### Test Results
| Suite | Count |
|-------|-------|
| Unit   | 141 |
| Widget | 28  |
| **Total** | **169** |

### Key Decisions / Insights
- **Fixture-backed tests close the stub-drift gap** — the login envelope bug passed all unit tests because stubs matched the buggy parser, not the real backend. Captured fixtures + redaction script prevent that class of bug going forward.
- **Flagged latent URL-encoding bug** in `NotificationRepository.conversation()`: interpolates `$senderId` without encoding, breaks on sender IDs containing `/` (e.g. `peer-queue-watch/<uuid>`). Fixture capture works around it by filtering slash-free senders. Separate fix needed; tracked in TODO.md.
- **Commit discipline** — user explicitly pushed back on autonomous commits mid-session. Memory-persisted rule: only commit when user asks, regardless of plan content.

---

