# LUPIN MOBILE - SESSION HISTORY

## 📚 Archived Sessions

Older session entries have been archived for token-limit hygiene. See:
- **[2026-05-06-to-11-history.md](history/2026-05-06-to-11-history.md)** — voice-persona milestone Phases 0–5 + CC-dispatch retirement sync + yes/no/neither tri-state (9 entries, May 6–11, 2026; archived 2026-08-21)
- **[2026-04-17-to-24-history.md](history/2026-04-17-to-24-history.md)** — WS hookup → TTS overlap fix (5 sessions, Apr 17-24, 2026; archived 2026-05-11)
- **[2026-04-15-to-16-history.md](history/2026-04-15-to-16-history.md)** — Tier 1-4 buildout (5 sessions, Apr 15-16, 2026)
- **[2025-07-06-to-08-17-history.md](history/2025-07-06-to-08-17-history.md)** — Initial era (7 sessions, Jul 2025 – Aug 2025; project then dormant for 8 months)

Most recent entries (2026-05-21 onward — notif-client sync, focus-mode milestone, v2 cutover, focus-rail/stop-list/device-feedback rounds) are retained below.

---


## 2026.08.21 | Session `e082edd7` (Tiffany 💍) — v2 cutover wave 2: nine submit doors → `/api/v2/submit` · lane-2 harness door fix (SESSION-END)

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work` · **Doc**: `src/rnd/2026.08.21-v2-cutover-wave-2-readiness.md` · store rows `a938907a` (wave 2) / `c84e9313` (lane-2, closed)

**Accomplishments** (fifth commit of the session; Rick AFK 22:00–23:55Z; self re-spin #2 at 22:35Z, clean wake):
- **Wave 2 flipped** against integration `799e43d0` (Cheech's word 23:16Z): `SubmitRequest` + top-level `scheduledAt` / `monopolize` / `parentIdHash` (Cheech's ruling, serialized only when set); eight `AgenticRepository.submitX()` through one `_submit()` + `QueueRepository.pushAgentic()` → `POST /api/v2/submit`; per-door `submitCommand` + `toSubmitArgs()` (renames `research_source→research`, `target_languages→languages`, `source_path→source`); bloc/UI contracts kept via `AgenticSubmitResponse.fromAsk` / `PushJobResponse.fromAsk` — `waiting`+`job_id` = success, `needs_input`/receptionist/`failed` → Failure with the server's words. Doors 7 (TFE resume) and 11 stay v1 (checkpoint-built jobs); ask-side agentic dispatch is bug `b7fe8941` (Rachel).
- **Lane-2 gate failure (María's row)** — instrument: harness POSTed retired `/api/push` (410) then waited 1200s. Fixed in lupin worktree: `--door auto|v1|v2`, v2 ask→resume auto-answer, fail-fast, parked-after-budget terminal; two other stale src/rnd push sites stop on 410; +6 unit tests (20/20). Merged to integration `3c3f1f5e`.
- **Tests**: +11 mobile (repo semantics ×3, pushAgentic ×2, mappers ×6), mocks moved to v2 bodies. **Full suite 597 ✅ / 0 outside `legacy_quarantine/`** (was 585); analyze clean on touched features.

**Files Modified**: 15 (agentic data ×9 incl. repository + common models; queue models + repository; tests ×4 incl. `submit_mappers_test.dart` NEW; readiness doc NEW + README link).

**Open**: live check of the nine doors against `:7999` once `799e43d0` reaches wip + bounce; Rick's device check of the day; prune merged worktrees `lupin-wt-tiffany-{salutations,v2eval,lane2-door}`.

---


## 2026.08.21 | Session `e082edd7` (Tiffany 💍) — Rail grouping (Personas/All) · voice DM to a chip · login enter-to-submit · TTS queue viewer + speak-system-senders switch (SESSION-END)

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work` · **Plan**: `src/rnd/2026.08.21-focus-rail-liveness-icons-and-notification-stop-list.md` §5f–§5h · store rows `d0c9d8f4` / `2d1727d6` / `9a66e530` / `2e997558` / `b1480d02`

**Accomplishments** (fourth commit of the session, after `98a3a40` · `557e037` · `b9fa06b`; Rick driving by voice from the emulator):
- **§5f Rail grouping**: `FocusSenderScope {personas, all}` (default Personas, rail-only, resets each launch); persona group sorted **oldest session first** (`voice_persona.assigned_at` ASC, nulls after in arrival order), divider, system group in arrival order (Rick's ruling); `Personas (n) / All (n)` `SegmentedButton` beside Live/24h; focused sender always visible.
- **§5g Voice DM to a chip**: `VoiceReplyField` ungated — with a pending ask it replies, otherwise `FocusRespondRequested` → `POST /api/dm/send` (`DmSendRequest`/`DmSendAck`, `NotificationRepository.sendDm`; recipient by persona name else `#hash8`; sender `lupin-mobile:<email>` / "Ricardo 📱" / `lupin-mobile`); caption says which. **Verified end-to-end**: two DMs from Rick's emulator landed in this session as "PEER DM from Ricardo 📱".
- **Login**: password field `textInputAction: done` + `onFieldSubmitted → _submit()`; email `next`.
- **§5h Silencing system messages**: `TtsOrchestrator` gains `TtsSender`/`TtsQueueItem`, `queueStream`/`queueSnapshot`, `skipCurrent()` (epoch-guarded), `removeQueued(id)`, `clearQueued()`, `sender:` on both enqueue paths and a **speak-system-senders** gate (pref default ON); `TtsQueueSheet` (NEW — playing + queued; Skip / Delete / Clear queue / Stop all) from an app-bar button with a depth badge; "Speak system senders" switch in audio settings. Bloc call sites pass persona meta (item → registry).
- **Tests**: +30 new across unit/widget/repo (state ×2, bloc ×5, repo ×2, orchestrator ×3, prefs ×1, settings ×1, screen ×6, sheet ×2 NEW, login ×2); 22 existing enqueue matchers gained `sender: any(...)`; band-lens fixtures widened to `scope: all`. **Full suite 582 ✅ / 1 skip / 44 ❌ all `legacy_quarantine/`** (0 outside); analyze clean on touched files.
- **Ops**: self re-spin at 21:05Z (context 55%) — wake proof + memento resume; `/api/v2/submit` still absent in the parent ⇒ wave 2 stays blocked (Cheech's brain-integration crew owns the v2 router, per María); offered capacity — took Cheech/Pocholo's `salutations.py` contract-test slice and María's `v2_eval.py` row `48312293` for the AFK window.

**Files Modified**: 29 (lib: focus_mode domain ×3 + presentation ×5 incl. `tts_queue_sheet.dart` NEW, notifications data ×2 + domain ×1, auth login, settings audio screen, services tts_orchestrator + notification_preferences, test_keys; tests ×12 incl. `tts_queue_sheet_test.dart` NEW; plan doc, TODO.md, history.md + archive).

**Open (Rick)**: device check of the whole day (laptop APK rebuild, `src/rnd/2026.06.12-poc-laptop-build-runbook.md`); ruling on the speak-system-senders default; wave 2 when `/api/v2/submit` lands; parent nicety — user-originated DM direction (María informed).

---

## 2026.08.21 | Session `e082edd7` (Tiffany 💍) — Device-feedback round: stop-list render lens · lower-left timestamps + newest-first · TTS preview-fraction slider

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work` · **Plan**: `src/rnd/2026.08.21-focus-rail-liveness-icons-and-notification-stop-list.md` (§5b amendment, §5d, §5e) · store rows `bae1ecd4` / `f1bdd6e8` / `89e8e2a1`

**Accomplishments** (third commit of the session, after `98a3a40` + `557e037`; self re-spin at 21:05Z mid-round — memento `io/mementos/tiffany-2026-08-21T2105Z.md`):
- **Stop-list RENDER lens** (device finding: "Done: Bash" still showed in the focus pane) — `FocusChatPane` now applies the same `NotificationStopList` predicate at render, with a hidden-count line instead of "no messages yet"; the collapse fixtures were de-stop-listed so they still exercise collapse.
- **`MessageStamp`** (NEW, lower-left `HH:mm` on every bubble/card) + **newest-first ordering** in both the focus pane and `ConversationScreen` (stable chronological sort, then reversed); `messageStampPrefix` test key.
- **TTS preview-fraction slider** (web `#cc-tts-fraction-slider` parity): `TtsFractionBar` (NEW, pinned top of pane, 10% steps, **default 20%** — Rick changed it from 30% at checkpoint), `TtsPreviewTruncator` (NEW, port of web `_truncateAtBoundary`), `NotificationPreferences.ttsFraction`/`setTtsFraction`/`snapTtsFraction`, applied in `TtsOrchestrator._formatSpeech` at enqueue (queue holds text; audio plays one at a time).
- **Tests**: +19 (message_stamp ×2, preview_truncator ×11, orchestrator +2, preferences +1, pane widget +4, conversation +1). **Full suite 559 ✅ / 0 ❌ outside `legacy_quarantine/`**; targeted re-run after the 20% change 65/65 ✅; analyze clean.

**Files Modified**: 18 — lib: `focus_chat_pane.dart`, `conversation_screen.dart`, `message_stamp.dart` (NEW), `tts_fraction_bar.dart` (NEW), `tts_preview_truncator.dart` (NEW), `tts_orchestrator.dart`, `notification_preferences.dart`, `test_keys.dart`; tests as above; plan doc, TODO.md, history.md.

**Open (Rick, device)**: APK rebuild + check of the whole round (`src/rnd/2026.06.12-poc-laptop-build-runbook.md`). Wave 2 of the v2 cutover still waits on `/api/v2/submit`.

---


## 2026.08.21 | Session `e082edd7` (Tiffany 💍) — Focus rail Live/24h + persona icons · notification stop-list · progress-group collapse (A+B+C)

**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work` · **Plan**: `src/rnd/2026.08.21-focus-rail-liveness-icons-and-notification-stop-list.md` (Rick's voice rulings folded in; §5a/5b/5c implementation records) · store rows `341b1c9f` / `0193089c` / `530849ba`

**Accomplishments** (second commit of the session, after wave-1 `98a3a40`):
- **A — rail**: Live(<1h)/24h `SegmentedButton` with counts (`focus_filter_bar.dart`); cold start + reconnect → `senders-visible?hours=24` (146 → 6 senders on the dev box) seeding `lastActivityBySender` + persona badges; `visibleOrder` lens (filter = visibility, never deletion; focused sender pinned); 🟢/🟡 status dots; name-initial fallback (never the repo id); `voice_persona_released` → 4s exit debounce, `session_reaped` → immediate; 30s aging tick (DI only).
- **B — stop-list**: `NotificationStopList` (JSON in SharedPreferences, seeds `Done: mcp/Bash/ToolSearch/Read/Edit/Write/Grep/Glob`, case-insensitive prefix); ONE predicate at three seams — `TtsOrchestrator` (both enqueue paths), `FocusChatBloc` ingest + backfill (`hiddenCountBySender`, never the user's own replies), `ConversationScreen` lens with "N hidden" reveal chip; `NotificationFilterSettingsScreen` (checklist / add / swipe-delete / reset) linked from audio settings + focus drawer.
- **C — collapse**: pure `collapseByProgressGroup()`; consecutive same-`progress_group_id` messages → one expandable row (`×N`, latest text) in the focus pane + conversation list; pending asks never buried; `collapseGroups` pref default ON with a settings switch.
- **Tests**: +~45 across unit/bloc/widget/wiring (new files: stop-list unit, grouping unit, filter-settings widget, pane-collapse widget). **Full suite 538 ✅ / 1 skip / 44 ❌ all `legacy_quarantine/`, 0 outside** (baseline 488); analyze clean on every touched file. One self-inflicted test hang (helper recursing into itself) caught via the analyzer's unused-symbol warning.

**Files Modified**: ~40 (lib: focus_mode domain/presentation, notifications data/presentation, settings, services/notification_filter NEW, tts_orchestrator, DI, test_keys, app.dart; tests as above; plan doc, TODO.md, history.md).

**Open (Rick, device)**: toggle feel, 28px icon legibility, 30s aging, `×N` chip tap target.

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
