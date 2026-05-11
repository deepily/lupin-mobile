# LUPIN MOBILE - SESSION HISTORY

## 📚 Archived Sessions

Older session entries have been archived for token-limit hygiene. See:
- **[2026-04-17-to-24-history.md](history/2026-04-17-to-24-history.md)** — WS hookup → TTS overlap fix (5 sessions, Apr 17-24, 2026; archived 2026-05-11)
- **[2026-04-15-to-16-history.md](history/2026-04-15-to-16-history.md)** — Tier 1-4 buildout (5 sessions, Apr 15-16, 2026)
- **[2025-07-06-to-08-17-history.md](history/2025-07-06-to-08-17-history.md)** — Initial era (7 sessions, Jul 2025 – Aug 2025; project then dormant for 8 months)

Most recent ~6 days (2026-05-06 onward — voice-persona milestone + CC dispatch retirement sync) are retained below.

---


## 2026.05.11 | Session `c594308e` — Claude Code dispatch retirement sync (mobile cutover to canonical `/api/claude-code/submit`)

#### Implementation | 2026.05.11 | Mobile migrated to canonical Claude Code submit endpoint; 5 retired methods + 4 retired model classes + 6 retired BLoC events deleted; INTERACTIVE UI surfaces preserved as banner-only screens per "obviously disable, don't silently mask" strategy; PIP plan-review GATE cleared (REUSE + Pass 1 Fitness + Pass 2 Adversarial all converged); baseline 308 → 298 (-10 from test pruning); 8/8 focused claude_code tests green

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`
**Plan slate**: `src/rnd/v0.1.7/2026.05.09-cc-dispatch-retirement-sync/` (01-plan + 90-execution-log)
**Continues from**: voice-persona milestone CODE-COMPLETE (session-end `c25dbc3e` 2026-05-07; voice-persona HUMAN gate still outstanding, now joined by this CC sync work also requiring eventual on-device smoke)

### Accomplishments

1. **Parent-Lupin audit complete**: identified the 2026-05-05 retirement of `/api/claude-code/dispatch` cluster (6 endpoints, commit `73bee1b`) + the in-flight Bounded ClaudeCodeJob redesign (commit `c1cec74` 2026-05-07; internal architecture, wire-stable). Two mobile rnd docs (`2026.04.15-tier-3-queue-and-claude-code-plan.md` + `2026.04.15-resync-mobile-with-lupin-api-v0.1.6.md`) flipped from open retirement-notice to ✅ DONE migration banners.

2. **Canonical URL change captured**: user direction 2026-05-10 confirmed parent's parallel re-implementation of submission endpoint as `POST /api/claude-code/submit` (shorter form; supersedes original `/api/claude-code/queue/submit`). Mobile cut over to canonical URL today; gets 404 against pre-rename Lupin servers (G1 returned 404 against local `:7999` at session time — rename in flight, not propagated; G3 confirmed legacy `/queue/submit` still wired). Per user direction via cosa-voice gate: chose Option C (cutover now, accept 404) matching parent's "obviously disable" strategy.

3. **PIP plan-review GATE executed end-to-end** (per `$PLANNING_IS_PROMPTING_ROOT/workflow/plan-review.md`):
   - REUSE pre-pass: 10 items reviewed; 6 reuse-as-is + 1 extend-existing + 2 genuinely-new (minimal) + 1 default-set preservation. "Prior art referenced" section appended to plan doc.
   - Pass 1 Fitness: 8 findings (F1-F8) — user approved ALL via cosa-voice multi-select; applied verbatim. Convergence loop closed (no new TBDs).
   - Pass 2 Adversarial: 3 findings (A1-A3) — user approved A1 (EXECUTOR tags across all verification surfaces); A2 + A3 skipped per user. Convergence loop closed.
   - Idempotency marker `last-reviewed-at: 2026-05-11` recorded.

4. **Code migration (Phases 1-5)**:
   - **data layer**: `claude_code_repository.dart` shrunk to single `submit()` method targeting `/api/claude-code/submit`; `claude_code_models.dart` shrunk to `ClaudeCodeSubmitRequest`/`Response` (8 + 4 wire fields preserved verbatim) + `ClaudeCodeApiException`. Literal 3-line retirement footnote added to both file dartdocs.
   - **domain layer**: `claude_code_event.dart` shrunk to single `ClaudeCodeSubmit` event; `claude_code_state.dart` to `Initial → Submitting → (Submitted | Error)`; BLoC handler family shrunk to `_onSubmit` only.
   - **presentation layer**: `dispatch_sheet.dart` rewritten as BOUNDED-only with yellow-bg retirement banner (`Color(0xFFFFF3CD)` matching parent web's `.cc-retired-banner` rule verbatim); `chat_screen.dart` + `session_list_screen.dart` preserved as banner-only screens; CTA on session list pushes to `QueueDashboardScreen` (Tier 3 surface where `cc-*` jobs land).
   - **WS bridge**: `lib/app.dart` `claude_code_message` / `claude_code_state_change` handler block deleted; 2 retired event-name constants removed from `lib/core/constants/app_constants.dart`.

5. **Tests rewritten** (`test/unit/claude_code/`): 8 tests across 3 files (4 model + 2 repo + 2 bloc). All 8 green. Old test count was ~13 (3 dispatch + 1 inject + 1 interrupt + 1 queueSubmit repo + 6 bloc dispatch/inject/end/queue + 4 model). New count is 8. Pruning achieved planned scope.

### Files Modified (13)

**Code**:
- `lib/features/claude_code/data/claude_code_repository.dart` — 107 → 35 lines; 5 retired methods deleted; `queueSubmit` → `submit`; URL `/api/claude-code/queue/submit` → `/api/claude-code/submit`; literal 3-line footnote
- `lib/features/claude_code/data/claude_code_models.dart` — 169 → 67 lines; 4 retired classes + 1 enum deleted; `ClaudeCodeQueueRequest`/`Response` → `ClaudeCodeSubmitRequest`/`Response`; literal 3-line footnote
- `lib/features/claude_code/domain/claude_code_event.dart` — 54 → 12 lines; 6 retired events deleted; `ClaudeCodeQueueSubmit` → `ClaudeCodeSubmit`
- `lib/features/claude_code/domain/claude_code_state.dart` — 51 → 25 lines; 3 retired states deleted; `Dispatching` → `Submitting`; `Queued` → `Submitted`; field type `ClaudeCodeQueueResponse` → `ClaudeCodeSubmitResponse`
- `lib/features/claude_code/domain/claude_code_bloc.dart` — 141 → 30 lines; shrunk to single `_onSubmit` handler; 6 retired event registrations + `_stateFromSession` helper deleted
- `lib/features/claude_code/presentation/dispatch_sheet.dart` — rewritten: BOUNDED-only; `SegmentedButton<ClaudeCodeTaskType>` removed; retirement banner at top; `_dispatch()` → `_submit()` builds `ClaudeCodeSubmitRequest`
- `lib/features/claude_code/presentation/chat_screen.dart` — 202 → 48 lines; INTERACTIVE chat body replaced with banner; AppBar title preserved (`Claude Code Chat (retired)`), actions dropped
- `lib/features/claude_code/presentation/session_list_screen.dart` — 98 → 87 lines; state-driven session list body replaced with banner + `FilledButton.tonal` CTA pushing to `QueueDashboardScreen`; FAB preserved for new BOUNDED submissions
- `lib/app.dart` — WS handler block for `claude_code_message`/`claude_code_state_change` events removed (10 lines)
- `lib/core/constants/app_constants.dart` — 2 retired event-name constants removed (`eventClaudeCodeMessage`, `eventClaudeCodeStateChange`)

**Tests**:
- `test/unit/claude_code/claude_code_models_test.dart` — rewritten: 4 tests covering `ClaudeCodeSubmitRequest.toJson` (defaults + optionals) + `ClaudeCodeSubmitResponse.fromJson` (parse + defaults)
- `test/unit/claude_code/claude_code_repository_test.dart` — rewritten: 2 tests covering `submit()` happy path against canonical URL + error path (HTTP 500 → `ClaudeCodeApiException`)
- `test/unit/claude_code/claude_code_bloc_test.dart` — rewritten: 2 blocTests covering `Initial → Submitting → Submitted` and `Initial → Submitting → Error`

**Docs / planning**:
- `src/rnd/v0.1.7/2026.05.09-cc-dispatch-retirement-sync/01-plan.md` — NEW (serialised from `~/.claude/plans/piped-tumbling-quiche.md`; F1-F8 + A1 fixes applied via PIP plan-review)
- `src/rnd/v0.1.7/2026.05.09-cc-dispatch-retirement-sync/90-execution-log.md` — NEW (phase-status + REUSE/Fitness/Adversarial close-out evidence + gate G1/G2/G3 results + warning baseline + pre-delete grep verdicts)
- `src/rnd/v0.1.6-migration/2026.04.15-tier-3-queue-and-claude-code-plan.md` — RETIREMENT NOTICE → ✅ RETIREMENT MIGRATION COMPLETE
- `src/rnd/v0.1.6-migration/2026.04.15-resync-mobile-with-lupin-api-v0.1.6.md` — same flip
- `TODO.md` — voice-persona milestone HUMAN gate joined by this session's forward-compat items (parent transcript_path artifact + INTERACTIVE controls restoration triggers)

### Test Results

| Suite | Pre-session | Post-session | Δ |
|---|---|---|---|
| Focused `test/unit/claude_code/` | ~13 ✅ (mixed dispatch/queue) | **8 ✅** (canonical submit only) | -5 by design (pruning) |
| Baseline `test/unit/ test/widget/ test/service_integration/` | 308 ✅ | **298 ✅** | -10 (matches plan's ~300 estimate) |
| Retired endpoint 404 sanity | n/a | HTTP 404 for `/api/claude-code/dispatch` ✅ | — |
| Gate G1 (canonical URL live) | n/a | HTTP 404 (rename in flight on parent) | informational HALT → user chose cutover |
| Gate G3 (legacy disposition) | n/a | HTTP 401 (legacy still wired) | informational |

### Key Decisions / Insights

- **PIP plan-review gate saved a real bug**: F5 fix (schema-parity probe in G2) + F6 fix (gates lifted above verification table) were exactly the structure that surfaced G1's 404. Without them, mobile would have committed to a URL and discovered the rename gap only at runtime. The gate did its job.
- **Wire-stable internal redesign means mobile is decoupled from parent's in-flight Bounded ClaudeCodeJob redesign** (`<lupin>/src/rnd/v0.1.7/2026.05.07-claude-code-bounded-redesign/`). Parent can land that redesign without mobile rework — only the new `artifacts.transcript_path` field is future-relevant, and that surfaces on completed-job records (queue feature surface), not on the submit response.
- **Color literal matching parent web verbatim** (`Color(0xFFFFF3CD)` from F2 fix): single source of truth across web and mobile retirement banners. Same yellow + orange accent the user sees on the parent's notifications page.
- **User-stated contract overrode local probe state**: G1 returned 404 against local `:7999` but user-stated canonical is `/api/claude-code/submit`. Mobile committed to user-stated value per `feedback_user_stated_contract_is_authoritative` (auto-memory saved 2026-05-10).

### Out of Scope (deferred / forward-compat)

- **Voice-persona HUMAN gate** (laptop+emulator runbook vp1-vp7) — still outstanding from voice-persona milestone close 2026-05-07; now joined by this session's UI smoke (dispatch sheet BOUNDED-only verification on device). Bundle into a single device handoff.
- **`artifacts.transcript_path` consumption** in `QueueDashboardScreen` job detail (cc-* job type) — forward-compat TODO. Triggers when parent ships ClaudeCodeJob redesign Phase 4 (currently blocked on parent-side plan-review at 4/11 findings).
- **INTERACTIVE controls restoration** (`inject` / `interrupt` / `end_session`) — banner-preserved chat_screen + session_list_screen ready for restoration; triggers when parent's `ClaudeCodeJob` gains bidirectional control.
- **Commit cadence** — per `feedback_no_auto_checkpoint`: user drives commits. Files modified above are uncommitted as of session-time.

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

