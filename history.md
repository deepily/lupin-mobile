# LUPIN MOBILE - SESSION HISTORY

## 📚 Archived Sessions

Older session entries have been archived for token-limit hygiene. See:
- **[2026-04-17-to-24-history.md](history/2026-04-17-to-24-history.md)** — WS hookup → TTS overlap fix (5 sessions, Apr 17-24, 2026; archived 2026-05-11)
- **[2026-04-15-to-16-history.md](history/2026-04-15-to-16-history.md)** — Tier 1-4 buildout (5 sessions, Apr 15-16, 2026)
- **[2025-07-06-to-08-17-history.md](history/2025-07-06-to-08-17-history.md)** — Initial era (7 sessions, Jul 2025 – Aug 2025; project then dormant for 8 months)

Most recent entries (2026-05-06 onward — voice-persona milestone + CC dispatch retirement sync + yes/no/neither tri-state) are retained below.

---


## 2026.08.21 | Session `e082edd7` (Tiffany 💍) — v2 cutover WAVE 1: `/api/push` + retry → `/api/v2/ask`

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`

**Accomplishments** (per María 🌸's plan, lupin `src/rnd/v0.2.0/2026.08.21-lupin-mobile-v2-cutover-plan.md`; store row `1265204e` → review):
- **Both retired doors re-pointed to `/api/v2/ask`** — and the **synchronous-response shape change carried through**, not just the URL: `PushJobRequest` → `AskRequest`, NEW `AskResponse` (§8 result dict + `isDone`/`needsInput`/`isFailed`/`summary`), `QueueRepository.ask()`, `retryJob()` re-asks with client-supplied `questionText` (the server-side retry door pulled it off the row; it is gone), NEW `QueueAnswered` bloc state, submit sheet + dashboard snackbar show the answer / clarifying question. `RetryJobResponse` deleted.
- **Tests moved with the wave, fixtures carry the NEW body**: queue unit 19 → **30/30 ✅**; full `flutter test test/` **488 ✅ / 1 skip / 44 ❌ all in `legacy_quarantine/`** (0 outside); `flutter analyze` 0 new issues.
- **Live `:7999` probe**: `/auth/login` → `POST /api/v2/ask` → 200, answer "4", **key set identical to the Dart model** (0 missing / 0 extra). `/api/push` still 200 pre-bounce.
- **Untouched by design**: wave 2's eleven submit-shaped doors (wait for `/api/v2/submit`) and `/api/deep-research/report` (a read).
- **Record**: `src/rnd/2026.08.21-v2-cutover-wave1-ask.md` (+ README link, TODO.md wave-2 backlog). Receipt DM'd to María.

**Files Modified**: 9 lib/test files (`queue_models/repository/event/state/bloc`, `submit_job_sheet`, `queue_dashboard_screen`, 3 queue tests) + new R&D doc, README.md, TODO.md, history.md.

---


## 2026.06.25 | Session `f53bc7b3` (Tiffany 💍) — Focus UI active/history filter: planning doc

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`

**Accomplishments** (planning-only session — no app code touched):
- **Planning doc authored**: `src/rnd/2026.06.25-focus-ui-active-history-filter.md` — make the Focus rail default to currently-LIVE sessions with a Material-3 `SegmentedButton` toggle to a rolling 24h history. Mapped the existing `focus_mode/` feature (rail, `FocusChatBloc`/`State`, `SenderSummary`, repository) before designing.
- **Cross-client alignment via Mr Radio 🦉** (DM thread 77099736): confirmed both web clients (notifications.js + multiplexer) use IDENTICAL pure-client recency math — 🟢 `<1h` Live / 🟡 `<24h` History / ⚪ dropped; NO server liveness/presence signal. Plan mirrors the constants verbatim with source-citation comments. Caught the key trap: the bloc sorts by `lastActivity` then discards timestamps → plan adds `lastActivityBySender` + 30s aging tick + `senders-visible` switch.
- **Rick's visibility-model ruling** (the governing contract, §4.0): filter = VISIBILITY, not deletion — keep all cards, toggle `visible`; Live hides exited + aged, History re-reveals.
- **Exit handling (§4.8)** designed: `voice_persona_released` → mark-exited + hide in Live, guarded by a 3–5s debounce (benign seat-handback vs true exit are wire-identical — no `reason` field today); `session_reaped` = immediate worker-exit.
- **Upstream dependency minted**: Mr Radio filed parent-repo task `69edd619` (P2) adding `reason={exit|reassigned|borrowed_return|clear}` to the release payload (Rick-approved); mobile swaps off the debounce when it lands.

**Files Modified**: this session-end commit only — new `src/rnd/2026.06.25-focus-ui-active-history-filter.md`, README.md (index link), TODO.md (🆕 NEW BACKLOG entry), history.md. **No app/lib/ code changed.**

**Status**: plan review-ready; implementation NOT started (phasing in doc §6). One non-blocking open item (#8): History single-24h vs a 1h/24h sub-selector — Rick to confirm.

---


## 2026.06.23 | Session `e02f3101` (Tiffany 💍) — FCM live-service enablement + APK build fix; focus-mode UI device-verified working

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`

**Accomplishments**:
- **APK build fixed** — Rick's `flutter build apk` failed compiling Dart-only `record_linux 0.7.2` (didn't implement `record_platform_interface` 1.6.0's `hasPermission(request:)`/`startStream`; Flutter's plugin registrant pulls the Dart plugin into the Android kernel even on an android/ios/web-only app). Fix: `record ^5.1.2 → ^6.0.0` (resolves 6.2.1 → `record_linux 1.3.1`). Verified on dev server: pub get clean, `flutter analyze` no-issues, 15/15 ASR + voice-reply tests green (incl. live `:7999` WAV→transcript). **Rick device-confirmed: APK builds + loads + focus-mode UI works** (UX noted clunky but functional).
- **FCM live-service track reactivated + delivered** — coordinated end-to-end with Tiberius 👑 (client/server division of labor). Client: `google-services.json` in place + Google Services Gradle plugin wired. Server: Tiberius stood up FcmWakeService on the test VM (image `lupin:1.2.0`, keyless ADC, send-auth proven, project aligned all `hello-world-foo-423219`). Caught + cleared a project-alignment risk (google-services `project_id`) before it became a silent 403.
- **Docs**: new `src/rnd/2026.06.23-focus-mode-status-summary.md` (focus-mode status + session-progress addendum); TODO.md FCM reactivation/closure notes; README index link.
- **Board hygiene** (Rick-directed): store task `63790ce3` → done (receipts: commit `be03dd9` + status doc); redundant probe-tracker `81430c6b` dropped.

**Files Modified**: commit `be03dd9` (6 files: pubspec.yaml, android/{settings,app/build}.gradle.kts, TODO.md, README.md, status doc) + this session-end commit (history.md, TODO.md).

**Open (not Tiffany-owed)**: on-device FCM wake probe (runbook 92) is Rick's hardware verification; parked non-blocking decision — reuse `hello-world-foo-423219` vs dedicated `lupin-mobile` Firebase project (rec: keep reuse).

---


## 2026.06.12 | Session `dabf7fbb` (Mr. Radio 🦉) — Commit + Postgame + AFK-window wrap (post-/clear continuation)

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`

**Accomplishments** (post-ritual continuation, ~15:45–22:00 UTC):
- **Implementation batch committed** `b34fa01` (55 files, +7,046/−441) on Rick's authorization — selective staging from manifest sections dabf7fbb + 472b7468 (Tiffany) + ad7692cc (Rio); `io/` scratch excluded.
- **Postgame walkthrough COMPLETE** — Rick ran all 7 §POSTGAME items live via blocking asks, decided 6 (P5 two-file-contract parked pending explainer read). Decisions ledger in `TODO.md §POSTGAME DECISIONS`. Joint doc folded by María + my fresh-eyes PASS (v1.1): `src/rnd/2026.06.12-joint-postgame-focus-mode-build.md`.
- **6 R&D docs authored** (pointers): PIP redline draft (`2026.06.12-pip-redline-draft-workflow-guidance-ledger.md`), retirement scoping (`…-legacy-voice-stack-retirement-scoping.md`, GO posture), two-file-contract explainer (`…-two-file-contract-pattern-explainer.md`), resume-seat ticket draft (`…-cosa-voice-resume-seat-primitive-ticket-draft.md`), **PoC laptop-build runbook** (`…-poc-laptop-build-runbook.md` — real-device LAN-IP repoint finding), quarantine triage (`…-legacy-quarantine-triage.md` — 25 files dispositioned, `PerformanceMonitor` the one lost-coverage flag).
- **Ledger folds**: #11/#12 landed LOCALLY into `03-testing-strategy.md` Standing Rules 7+8; #14 relayed to Tiberius; manager-autonomy v1.1 §7–§8 acked.
- **Tiberius FCM/GCP coordination** (now back-burnered): S6 endpoints + `fcm_tokens` persistence IN-SERVICE on the test VM via the mount model; wake-SENDS still need image rebuild w/ firebase-admin + the OSQ-7 key (batch with runbook 91).
- **Weekly quota freeze survived**: limit hit ~19:26Z (resets Jun 15 11am EDT) — froze main loop + killed 2 helper subagents (zero output); recovered on model swap; both deliverables re-authored INLINE. Confirmed ledger-#14 class (a) — quota freeze indistinguishable from stall (this time it WAS one).

**Remaining (all Rick-gated or coordination)** — see `TODO.md`:
- Device pipeline: OSQ-7 console (runbook 91) → laptop build + probe p1–p11 (runbook 92) → doze gate + fm1–fm6. **PoC path needs NONE of it** — `2026.06.12-poc-laptop-build-runbook.md` gives a Stage-1 build with FCM OFF.
- Push this batch (Rick's word); ledger review-then-fold; full Tier A+B legacy-voice retirement (post-PoC; flutter_sound rides it).
- **Next cleared sessions** (Rick's priorities to Monday): (1) **task list** functionality, (2) **cosa-voice token efficiency** (~75% of budget). GCP migration BACK-BURNERED.

---

## 2026.06.12 | Session `dabf7fbb` continued (Mr. Radio 🦉, Implementation Manager) — Focus-mode milestone AI-IMPLEMENTATION + REVIEW COMPLETE

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work` (uncommitted — Rick drives commits)
**Plan-of-record**: `src/rnd/2026.06.11-focus-mode-voice-chat/` (status banner + per-section table = as-built record)

**Accomplishments** (post-cascade implementation phase, ~04:00–09:18 UTC):
- Step 9 closed: `90-cascade-revision-handoff.md` authored (7-section spec), cold-context self-test 6/6, Arnold light review 6/6 → `implementation_handoff_ready` 04:03Z; `manager_self_audit_sweep` posted (10 candidates → TODO.md, later +3 implementation-phase addenda)
- Phase-0 wire-grounding executed: OSQ-1 (transcribe endpoint UNAUTHENTICATED), OSQ-2 (PCM16 mono 44.1k), S2 raw-passthrough FAILS → thin-adapter branch decided (serializer source-grounded), hours-param asymmetry pinned, canned-WAV fixture created + live round-trip exact (4 fixtures committed with provenance)
- Stage-1 implemented S1→S2→S4→S3 (Tiffany 💍; Rio ⚡ took over S3 after the fleet-wide Max-plan quota freeze parked her seat — archaeology-first takeover, attribution preserved) — suite 321✅/3❌ start → 384✅/0❌ at Stage-1 close
- Stage-2: S5 FCM mobile AI tiers (Rio — locator-free FcmWakeChain, ENABLE_FCM default-OFF, builds green without google-services.json, probe runbook 92 authored) + S6 parent-side complete in parallel (Clayton/Tiberius Lane-3: merged `83990552`, AC-S6.5 impl-start 6/6, AC-S6.1 rehydration 6/6 on :8000) — **final suite 406 ✅ / 1 by-design skip / 0 ❌**
- Review pipeline (Arnold 🪨, 5 reviews): 4 real findings — F-S1-IMPL-1 + F-S2-IMPL-1 await-window races (both fixed + Completer-pinned), F-S2-IMPL-2 doc-drift (heads-up beat S3 calcification), F-S4-IMPL-1 typed-contract gap — all fixed mid-stream; S3 + S5 final reviews clean at ZERO findings
- Baseline triage 3/3: AC-B7 emit-shape test fix; AC-C4 keyed-boundary + runAsync; AC-D4 fixture captured (login = `/auth/login`, stale laptop-only assumption retired) → parent `assigned_at` gap fixed by Clayton → re-captured GREEN
- OSQ-6 second amendment Manager-concurred (POST `/api/fcm/unregister-token`), propagated S5§3.1+S6§3.1 same-round pre-implementation; reason-semantics + dual-socket marker quirks recorded as contract-environment notes
- Incidents survived: fleet-wide quota freeze (~01:10–03:45 EDT) with arbiter false-alarm stand-downs, classifier-blocked keystroke un-park (escalated to Rick; standing-grant takeover spawn instead), recycled-persona DM contamination flagged (ledger #13)
- HUMAN remainder queued in TODO.md: Firebase console (runbook 91) → probe p1–p11 (runbook 92) → doze + fm1–fm6 gates; worker dismissals await Rick's word

**Files**: 5 mobile sections of production+test code (Tiffany/Rio per manifest), 2 new runbook docs (91, 92), handoff doc 90, 5 fixtures, doc-set §8 evidence throughout, TODO/index/manifest current.

---

## 2026.06.11–12 | Session `dabf7fbb` (Mr. Radio 🦉, Manager) — Focus-mode voice-chat doc-set authored + cascade-focus-mode CLOSED 6/6

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`
**Plan-of-record**: `src/rnd/2026.06.11-focus-mode-voice-chat/` (12-doc set, ██ CASCADE CLOSED 2026-06-12T03:09Z ██)

**Accomplishments**:
- Authored the full focus-mode voice-chat + FCM wake-up doc-set (index, working contract, architecture, Q1–Q11 frozen decisions, testing strategy, six cascade sections S1–S6) and ran it through the complete 3-stage `/plan-review-cascaded` pipeline as Manager (cast: Tiffany 💍 author, Sam 🎙️ Stage-1, Arnold 🪨 Stage-2, Cheech 🌿 Stage-3, María 🌸 steward)
- ~43 findings processed (Stage-1: 17 · Stage-2: 13+1 · Stage-3: 12); every re-litigation round closed in ONE pass, zero votes; 0 foundational findings survived
- 2 user rulings: F-S1-1 (`enqueueAlways` ungated path + FocusChatBloc sole dispatcher via DI-seam withdrawal) and F-S5-S2-1 (FCM background handler-does-the-work per the 2026.04.21 A′ chain, Phase-0 on-device probe gated) — the latter backed by a web-sourced research synthesis (`20-fcm-background-isolate-explainer.md`, 14 primary sources)
- ALL 7 OSQs cascade-ratified into `02-decisions.md` (OSQ-2/3/6 as-amended)
- Cross-repo contract integrity: AC-S6.5 element-wise comparison caught 4/6 restatement drift at cascade close; fixed mechanically and re-verified to PASS 6/6
- Known v1 behavior on the record: paused focus session does NOT gate FCM background speech (prefs are the only background gate)
- Cast operations: Sam reaped EOL (253k tokens, post-completion, user-authorized); Tiffany rotated at >50% context via memento → fresh seat (user-ordered); survived a manager /clear + memento rehydration, a ~35-min platform tool outage, one worker seat-freeze, and two false-positive fleet-stall alarms

**Files**: 12 new docs in `src/rnd/2026.06.11-focus-mode-voice-chat/` + README/TODO/history updates. Implementation NOT started (Step 9 handoff doc + Stage-1 next — see TODO.md).

---

## 2026.05.22–23 | Session `1b3f8c46` (Tiffany 💍) — Cascade-review of notif-client-sync plan CLOSED + 4-section IMPLEMENTATION landed

#### Cascade authoring + implementation | 2026.05.22–23 | 4-section plan ran through `/plan-review-cascaded` Stage 0/1/2/3 with Sam Stage-3 zero findings; cascade closed; Rio implemented Section A overnight (~04:02 UTC); Tiffany implemented Sections B/C/D + ran Section A hygiene-pass on a self-driving 3-min cron through ~05:10 UTC. Code uncommitted in tree until this session-end commit.

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`
**Plan-of-record**: `src/rnd/2026.05.21-notif-client-sync-may-06-deltas.md` (Stage-1 + Sam-Step-0 edits this session)
**Cascade synthesis**: `src/rnd/2026.05.22-notif-client-sync-cascade-handoff.md` (NEW — Mr. Radio's Step-9 Manager-authored synthesis doc; PLAN BLESSED FOR IMPLEMENTATION; 25 findings, 0 foundational, 0 user-escalated)
**Commits**: `75ffa41` (2026-05-21 prior session-end) + this session-end commit

### Part 1 — Cascade authoring (2026-05-22 ~15:00–21:30 UTC)

1. **Readiness loop** — set up a 5-min cron to check Maria 🌸 + Mr. Radio 🦉 readiness for cascade kickoff while Rick was AFK. Both confirmed within ~5 min; loop retuned to quiet-poll; retired on cascade-LIVE event.

2. **Stage 0** — posted 4 section author_drafts (A WS stubs / B speakerphone / C overflow badge / D `assigned_at` E2E). Mr. Radio's premature pipeline-LIVE go crossed in flight with his stand-down correction; all 4 drafts retracted; Rick sent his explicit-go broadcast; Mr. Radio confirmed Step-3 closed; all 4 drafts re-affirmed under authorized go. Demonstrated discipline: held for Manager-authorized DM, never acted on broadcast or relay alone.

3. **Sam's Step-0 light-review** — passed all 6 criteria. 3 non-blocking observations applied directly to plan doc (parking-lot count fix, audit-provenance note, c8→flutter-coverage cross-wire fix).

4. **Stage 1 revisions** (Tiberius 🌑 findings, all 4 sections): A — test-file home + comment form + Assumption-2 re-grounding on `websocket_subscription_manager.dart`; B — collapsed emit path to canonical `_emitCurrentSnapshot` + proactive forward-sweep of F-Tib-A1 to B's blocTests; C — OSQ-C-1 resolved (reuse `DashedBorderPainter` + true round dots author call) + named widget-test home; D — corrected `test/features/` → `test/unit/notifications/` paths + named fixture home.

5. **Stage 2 revisions** (Krishna 🦚 findings): added **AC-A5** wire-string grounding; added **`SpeakerphoneRecord`** carrier (F-Krishna-B1); narrowed OSQ B-1 to `n.senderId` authoritative (F-Krishna-B2); added **AC-B7** payload-field-name grounding; AC-B1b doc-comment cleanup; AC-C1 reconciled to 4 tests; AC-C4 mechanism corrected to direct two-render pixel-diff (NOT golden); AC-D4 mandated live `:7999` capture; AC-D6 made non-optional. Plus **consolidated wire-grounding doctrine fold** (`valid_types` whitelist + emit sites; never hand-authored fixture) — superseding-reposts on A + B.

6. **Sam Stage-3 audit**: **ZERO findings across all 4 sections** ("audited and CLEAN"). Cascade CLOSED. Mr. Radio authored the Step-9 cascade-handoff synthesis doc.

### Part 2 — Implementation (2026-05-23 ~04:00–05:10 UTC)

7. **Role reassignment** (Rick's voice DM at ~04:18 UTC): Tiffany = Implementer (was Rio); Mr. Radio = Implementation Manager (was Tiberius). Rio's overnight Section A implementation (~04:02 UTC) inherited and hygiene-passed clean.

8. **Section A** (Rio's implementation, hygiene-pass CLEAN): 3 case-label constants + provenance comment + `@visibleForTesting personasBySenderForTesting` getter + 3 no-op cases with pinned `// no-op stub — <reason>; real behavior parked per Q3 (plan §8.0)` form + AC-A5 cosa-whitelist regex-read against `cosa/rest/routers/notifications.py:359`. Read-only filesystem boundary respected. 6 AC-A1–A5 tests.

9. **Section B — Speakerphone Adoption** (Tiffany implementation + tests):
   - `SpeakerphoneRecord { on, displaced, displacedBy }` Equatable carrier
   - `SpeakerphoneSnapshotMixin` + 4 state-class extensions
   - `NotificationsSpeakerphoneChanged(senderId, on)` typed event
   - Bloc: new field + helper + `@visibleForTesting` getter + typed-event handler + raw-WS `speakerphone_changed` case using `n.raw[...]` (OSQ B-1 resolution) + AC-B1b doc-comment cleanup + extended `_emitCurrentSnapshot` + 7 emit-site updates across load handlers + `_refreshCurrent`
   - **7 new tests**: AC-B1 production-source grep, AC-B2/B3/B4 typed-event injection (Equatable idempotency), AC-B5/B6 raw-payload extraction, AC-B7 cosa `e420ec0` wire-grounding scan.

10. **Section C — PersonaBadge Overflow Variant** (Tiffany implementation + tests):
    - `DashedBorderPainter` extended with `StrokeCap cap = StrokeCap.butt` parameter
    - `personaBadgeDottedPrefix` test key
    - `PersonaBadge` 3-way render branch (overflow → dotted + ✱ glyph; borrowed → dashed; plain) with overflow precedence; ✱ glyph as load-bearing disambiguator
    - **7 new widget tests**: AC-C1 × 4 (overflow, borrowed) combinations + AC-C2 ✱-glyph presence (4 cases) + AC-C3 dotted-prefix discovery + AC-C4 direct two-render pixel-diff via `RenderRepaintBoundary.toImage` (NOT Flutter golden-file).

11. **Section D — `assigned_at` Propagation E2E** (test-only, Tiffany):
    - 3 explicit AC-tagged tests in `voice_persona_test.dart` (AC-D1/D2/D3 parse contract)
    - 1 blocTest in `notification_bloc_test.dart` (AC-D5 WS-path `assigned_at` round-trip)
    - 1 fixture-load test + 1 `skip:`-documented test in `notification_repository_test.dart` (AC-D4 + AC-D6)
    - **Two laptop-side closures filed in TODO.md**: (a) capture `test/fixtures/notifications/voice_persona_pool.json` (`:7999` probe returned 401 from dev server — auth needed); (b) un-skip AC-D6 once laptop pipeline plumbs auth + WebSocket test client.

12. **Section A hygiene-pass CLEAN**: pinned comment form on all 3 no-op cases ✅; AC-A5 cosa-whitelist read confirmed at `cosa:359` matching Rio's `:359-364` provenance ✅; line numbers shifted from `:245-253` → `:294-301` due to Section B insertions (mechanical, not regression) ✅; read-only filesystem boundary preserved ✅.

13. **Self-driving 3-min cron `7d97461b`** carried implementation overnight while Rick slept. Mr. Radio polled on heartbeat ticks. Cron self-deleted at `IMPLEMENTATION COMPLETE` (~05:10 UTC).

14. **Turn-boundary insight surfaced + logged for post-game**: I'm session-driven (no auto-continue between turns without inbound trigger); Mr. Radio's SITREP-on-stall pattern was the working re-engagement loop until we agreed on the self-cron. Per Mr. Radio: "highest-signal observation tonight — it'll reshape how Manager-Implementer relationships are wired in future cascades."

### Files modified (15) + new (1)

**Production code (8)**:
- `lib/features/notifications/domain/notification_bloc.dart` (Section A by Rio + Section B by Tiffany)
- `lib/features/notifications/domain/notification_event.dart` (Section B)
- `lib/features/notifications/domain/notification_state.dart` (Section B)
- `lib/features/notifications/data/notification_models.dart` (Section B `SpeakerphoneRecord`)
- `lib/features/notifications/data/voice_persona.dart` (foundational `overflow` field — pre-existing modification, load-bearing for Section C compile)
- `lib/features/notifications/presentation/persona_badge.dart` (Section C overflow branch)
- `lib/shared/painters/dashed_border_painter.dart` (Section C `StrokeCap cap` param)
- `lib/core/testing/test_keys.dart` (Section C `personaBadgeDottedPrefix`)

**Test code (5)**:
- `test/unit/notifications/notification_bloc_dispatch_test.dart` (Section A by Rio + Section B by Tiffany — 7 new tests)
- `test/unit/notifications/notification_bloc_test.dart` (Section D AC-D5)
- `test/unit/notifications/notification_repository_test.dart` (Section D AC-D4 + AC-D6)
- `test/unit/notifications/voice_persona_test.dart` (Section D AC-D1/D2/D3)
- `test/widget/notifications/persona_badge_test.dart` (Section C — 7 new widget tests)

**Docs / tracking (3)**:
- `src/rnd/2026.05.21-notif-client-sync-may-06-deltas.md` (Sam's Step-0 observations applied)
- `src/rnd/2026.05.22-notif-client-sync-cascade-handoff.md` (NEW — Mr. Radio's Step-9 Manager-authored synthesis)
- `CLAUDE.md` (Doc Viewer Scope section — pre-existing pending modification)

**Test count delta**: +19 cascade-spec-traceable tests (B: 7; C: 7; D: 5) added by Tiffany; +6 by Rio (Section A) = **25 cascade tests in tree, all `EXECUTOR: AI`** except AC-C5 (`EXECUTOR: HUMAN` on-device VP, deferred to laptop pipeline).

**Verification gate**: laptop-side `flutter analyze` clean + `flutter test test/` (dev server lacks Flutter SDK per `feedback_dev_server_laptop_split`).


## 2026.05.21 | Session `1b3f8c46` (Tiffany 💍) — Notification-client change audit + mobile sync plan-of-record + cascade-review reshaping

#### Planning + coordination session | 2026.05.21 | Audited May 6 → May 21 parent-Lupin notification-client deltas; authored mobile sync plan; walked Rick through 4 design questions; reshaped plan for `/plan-review-cascaded` submission. No code changes — planning + coordination only.

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`
**Plan-of-record**: `src/rnd/2026.05.21-notif-client-sync-may-06-deltas.md` (NEW)
**Commits**: `1a71ab1` (audit + plan-of-record), `5cc11c9` (walk-through resolutions + cascade reshape), + session-end commit

### Accomplishments

1. **Notification-UI change audit** — swept parent-Lupin `history.md` + git log (parent + CoSA submodule) for every notification-client delta since the mobile's 2026-05-06 Phase 0 dispatch audit (anchor `fd8fc18`). Inventory: ~30 commits on legacy `notifications.js` (+1,255 LOC), 23 new multiplexer TS files (+5,558 LOC), 13 CoSA-side commits. Delivered to Rick as a locked inventory grouped by surface — legacy JS / multiplexer TS / server-side / WS event-surface deltas / cross-cutting doctrine.

2. **Cross-session coordination with Mr. Radio 🦉** (parent-Lupin session `679e8f04`) — two DM reply cycles. Pulled his in-flight Recent-Activity filter strip + focus-bar chronological-lock design; folded his walkthrough-locked delta (Kind axis 2→4 options; no new wire-contract impact). Identified `voice_persona.assigned_at` plumbing as the only cross-cutting Lupin↔mobile contract item.

3. **Mobile sync plan-of-record authored** — `2026.05.21-notif-client-sync-may-06-deltas.md`: 6 phases + pre-flight. Phase 1 WS handler stubs for 3 new event types; Phase 2 `speakerphone_changed` adoption; Phase 3 `PersonaBadge` overflow variant; Phase 4 `assigned_at` E2E; Phase 5 on-device VP. Confirmed the mobile data layer already carries `overflow` / `assignedAt` / `displayName`.

4. **Q1-Q4 walk-through with Rick** — 4 design questions resolved via cosa-voice `ask_multiple_choice`: speakerphone record-only (no UI); new-event-name-only + smoke-test guard; park all 6 deferred items in TODO.md; `assigned_at` E2E runs parallel to Mr. Radio's Part B (tests-as-spec).

5. **Plan reshaped for `/plan-review-cascaded`** — added §0 cascade-readiness block: 4-section decomposition (A WS stubs / B speakerphone / C overflow badge / D `assigned_at` E2E), cross-section dependency map, pre-cascade Recon checklist, 6-criterion light-review self-assessment (all PASS), requirement provenance table. Plan is cascade-review-ready, queued behind another plan.

**Files**: `src/rnd/2026.05.21-notif-client-sync-may-06-deltas.md` (NEW, ~470 LOC) + `history.md` + `TODO.md` (this session-end).


## 2026.05.11 (third session same day) | Session `51ee0afa` — Yes/No/**Neither** tri-state for `ask_yes_no` shipped; mobile now at parity with cosa-voice MCP v0.3.0 + parent-Lupin web UI

#### Implementation | 2026.05.11 | Priority-1 next-session item (from `fe7679c9`) executed end-to-end: verification → plan via `/p-is-p-01-planning` → code → tests → 301 ✅ baseline; backend already permissive so no cross-repo work; on-device verification bundled into existing milestone HUMAN gate; one new test-hygiene TODO filed (legacy quarantine triage)

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`
**Continues from**: same-day session `fe7679c9` (TODO triage, commit `29e8d6d`)
**Plan slate**: `src/rnd/2026.05.11-yes-no-neither-mobile-implementation.md` (Phase 0 doc-first artifact; serialized from approved `~/.claude/plans/humming-munching-globe.md`)

### Accomplishments

1. **Verification verdict delivered** — confirmed mobile gap via direct file probe (`_YesNoBody` at `interactive_prompt_sheet.dart:103-156` had only 2 buttons; `TestKeys` had no neither key; `grep -rn "neither" lib/ test/ integration_test/` → zero hits). Verdict doc serialized to `src/rnd/2026.05.11-yes-no-neither-mobile-verification.md`; delivered to user via cosa-voice viewer-link notification.

2. **Two Explore agents launched in parallel** to scope the work pre-plan: (a) full mobile context (NotificationRepository POST shape, BLoC handler, existing test patterns, all call sites) confirmed data layer is permissive (`dynamic responseValue`) end-to-end; (b) parent-Lupin backend probe confirmed `/api/notify/response` accepts `Dict[str, Any]` with no enum constraint, prediction engine normalizes generically, and **web UI already renders `⊘ Neither` button** at `notifications.js:13792-13794`. Verdict: mobile is the only surface lagging the contract; no cross-repo coordination needed.

3. **`/p-is-p-01-planning` plan-mode workflow executed**: Pattern 3 (Feature Development) selected via smart defaults; plan written to `~/.claude/plans/humming-munching-globe.md`, approved via `ExitPlanMode`, serialized to `src/rnd/2026.05.11-yes-no-neither-mobile-implementation.md` (Phase 0 doc-first artifact per CLAUDE.md Documentation-First mandate).

4. **Code implementation** (Phases 1-4 of plan): added `promptNeitherButton = 'prompt.neither'` to `TestKeys`; replaced `_YesNoBody` 2-button Row (12px gap) with 3-button Row (8px gaps): `OutlinedButton "No"` | `Tooltip("Neither — the question itself needs re-framing")` wrapping `TextButton "⊘ Neither"` | `FilledButton "Yes"`. Visual hierarchy honors cosa-voice contract's "never a default" rule (TextButton is most de-emphasized Material 3 tier); glyph + label + tooltip text are verbatim parity with parent-Lupin web UI.

5. **Tests landed** (Phase 5 verification all green):
   - `interactive_prompt_sheet_test.dart` — 4 existing tests, updated 1 render assertion to include Neither, added 2 new: tap Neither → `"neither"` emit; tap Neither with comment → `"neither [comment: ambiguous which backups]"` emit. **6/6 green**.
   - `conversation_screen_test.dart` — 9 existing tests, added 1 new integration case: open prompt sheet → tap Neither (via `promptNeitherButton` TestKey) → assert event has `responseValue == "neither"`. **10/10 green**.
   - Full suite `test/unit/ test/widget/ test/service_integration/`: **301 ✅ / 0 ❌** (298 baseline + 3 net new — render-update + 2 new in prompt-sheet + 1 new in conversation-screen).
   - Quarantine `test/legacy_quarantine/`: 44 ❌ unchanged (drift baseline preserved).
   - `flutter analyze` on modified files: clean (only pre-existing `_multi` info lint on unrelated `_MultipleChoiceBody`).

6. **Test-hygiene TODO filed** — user asked for an explanation of the 44 ❌ quarantine; responded with the 3-bucket breakdown (API drift / live-WS dependency / test-infra rot) from `test/legacy_quarantine/README.md` + Apr 16 triage log. User requested follow-up TODO: added new entry under "Testing Playbook — Stage 4+ (deferred with revisit triggers)" — produce per-file mapping `quarantined-test → covered-by-new-test` (or "still meaningful → fix and re-admit"); revisit-trigger is any change to the 44 drift number or next major data-layer change.

### Files Modified (8)

**Code (2)**:
- `lib/core/testing/test_keys.dart` — added `promptNeitherButton = 'prompt.neither'` constant
- `lib/features/notifications/presentation/interactive_prompt_sheet.dart` — `_YesNoBody` Row extended to 3 buttons (Outlined-No | Tooltip-wrapped-TextButton-⊘-Neither | Filled-Yes); 12→8px gaps

**Tests (2)**:
- `test/widget/notifications/interactive_prompt_sheet_test.dart` — render assertion extended to include `promptNeitherButton`; +2 new Neither cases (with + without comment)
- `test/widget/notifications/conversation_screen_test.dart` — +1 new integration case for Neither via prompt sheet

**Docs / planning (2 new)**:
- `src/rnd/2026.05.11-yes-no-neither-mobile-verification.md` — verdict doc delivered to user via cosa-voice viewer-link notification
- `src/rnd/2026.05.11-yes-no-neither-mobile-implementation.md` — Phase 0 doc-first artifact; serialized from approved plan

**Tracking docs (2)**:
- `TODO.md` — added legacy-quarantine-triage entry under Testing Playbook (revisit-triggered); priority-1 yes/no/neither block removed in session-end (this commit)
- `history.md` — this entry

### Test Results (mandatory tabular form per CLAUDE.md)

| Tier | Command | Result |
|---|---|---|
| `flutter analyze` (modified files) | `./flutter.sh analyze lib/core/testing/test_keys.dart lib/features/notifications/presentation/interactive_prompt_sheet.dart` | ✓ clean |
| Focused widget — prompt sheet | `./flutter.sh test test/widget/notifications/interactive_prompt_sheet_test.dart` | **6/6 ✅** |
| Focused integration — conversation screen | `./flutter.sh test test/widget/notifications/conversation_screen_test.dart` | **10/10 ✅** |
| Full suite | `./flutter.sh test test/unit/ test/widget/ test/service_integration/` | **301 ✅ / 0 ❌** (298 → 301; +3 net new) |
| Quarantine drift | `./flutter.sh test test/legacy_quarantine/` | 44 ❌ unchanged |

### Key Decisions / Insights

- **Skipped Plan-agent for the design phase** — Explore-agent findings converged so cleanly (backend already permissive; web UI already at parity; mobile surface is one widget) that the design was deterministic. Direct write to `humming-munching-globe.md` rather than a third agent round.
- **No on-device runbook step added** for tri-state — the existing prompt-sheet open/respond flow is unchanged structurally (still a `showModalBottomSheet` over `InteractivePromptSheet`); the widget tests fully cover the BLoC emit path; rendering smoke can be done opportunistically during the next voice-persona + CC-sync milestone HUMAN gate device session.
- **Visual hierarchy decision** (`TextButton` for Neither, not `OutlinedButton`) traces to the cosa-voice contract's explicit "Neither is never a default" rule. Material 3's text-button is the most de-emphasized peer-button tier; OutlinedButton would have signaled too much equivalence with No.

### Out of Scope (deferred)

- **Legacy quarantine triage pass** — new TODO under Testing Playbook; revisit-triggered by drift-number change OR next major data-layer migration.
- **Voice-persona HUMAN gate + CC sync UI smoke + yes/no/neither rendering smoke** — single bundled device handoff; unchanged from prior session (no new HUMAN gate added by this session).
- **Forward-compat triggers from session `c594308e`** — unchanged (4 items: transcript-path link, INTERACTIVE controls restoration, canonical URL propagation verification, LUPIN-CC-SUBMIT-RENAME alias migration).

---


## 2026.05.11 (later same day) | Session `fe7679c9` — TODO triage micro-session: yes/no/neither for `ask_yes_no` flagged as next-session priority 1

#### Session-End | 2026.05.11 | Single TODO.md edit recording the user directive that next-session priority-1 is tri-state yes/no/**neither** for the `ask_yes_no` flow; no code edits, no tests touched; baseline unchanged at 298 ✅ from session `c594308e`

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`
**Continues from**: same-day session `c594308e` (CC dispatch retirement sync, commit `ee6f081`)

### Accomplishments

1. **Session-start recap delivered** — accomplishments-and-pending summary across the prior two sessions (voice-persona milestone CODE-COMPLETE at `c25dbc3e` + CC dispatch sync at `c594308e`) plus the four open work buckets (HUMAN gate, forward-compat triggers, hygiene follow-ups, on-device sanity sweep). Delivered as terminal markdown + cosa-voice notification with rich abstract.

2. **Priority-1 next-session item recorded** — user flagged tri-state response (yes / no / **neither**) for the `ask_yes_no` notification flow as first-and-foremost next-session work. New `## 🎯 NEXT SESSION — PRIORITY 1` section in `TODO.md` above the existing CC-sync forward-compat block; header `Last updated:` line reframed to surface the directive on resume. Surfaces likely affected captured in the TODO body (`InteractivePromptSheet` + `NotificationBloc` response event + `NotificationRepository` POST body + fixture-backed tests); backend-contract scope deferred to resume.

3. **Session-end ritual executed** per `/plan-session-end` canonical workflow: history health check 10k/HEALTHY, bug-fix-mode skip (owned by session `1fb8dc65`, not this one), manifest section added for `fe7679c9` via §3.5, selective-staging (TODO.md + history.md auto-includes only), commit approval via cosa-voice multi-choice gate (no push, no backup per user direction).

### Files Modified (2)

- `TODO.md` — new PRIORITY 1 section for yes/no/neither at top + header note in Last-Updated line
- `history.md` — this entry

### Test Results

n/a — no code changes; no tests touched. Baseline remains **298 ✅** from session `c594308e`. `44 ❌` quarantine drift unchanged.

### Key Decisions / Insights

- **Capture-then-restart pattern**: user explicitly asked to record the directive before closing the session to restart MCP servers. Lightweight planning-only sessions are a valid use of the slash-command ritual — not every session needs to land code.
- **TODO header reframing**: the new priority-1 item is recorded BOTH as a top section AND in the `Last updated:` line so it can't be skimmed past on resume.

### Out of Scope (deferred)

- **yes/no/neither implementation itself** — captured as TODO Priority 1; resume in a fresh session after MCP restart.
- **Voice-persona HUMAN gate + CC sync UI smoke** — single bundled device handoff; unchanged from prior session.

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

