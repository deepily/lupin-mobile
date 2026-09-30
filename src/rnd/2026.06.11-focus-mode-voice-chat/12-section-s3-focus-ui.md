# Section S3 — Focus UI Surface (Badge Rail + Chat Pane + Route Swap)

**Stage**: 1
**Anchors**: [01-architecture.md](01-architecture.md) · [02-decisions.md](02-decisions.md) Q1, Q4, Q5, Q6, Q11 · [03-testing-strategy.md](03-testing-strategy.md)
**Provides**: the user-facing surface; default-route swap; legacy drawer; shared prompt-body
extraction (`lib/shared/widgets/prompt_bodies.dart` — F-S3-1)
**Consumes**: S1 interface (`pause()` / `resume()` / `isPaused` / `pausedStream` /
`queueDepthStream` on TtsOrchestrator — `queueDepthStream` is the LIVE held-count signal,
F-S1-S2-3) ·
S2 interface (`FocusChatState`: `senderOrder`, `personasBySender`, `windows`, `unreadBySender`,
`focusedSender`, `pendingPromptFor( senderId )` selector — null ⇒ no unanswered ask
(F-S2-S2-3); events `FocusSenderSelected`, `FocusColdStartRequested`,
`FocusRespondRequested(senderId, text, promptContext?)` with typed
`FocusPromptContext { notificationId, promptType? }` — the single response-dispatch shape,
F-S3-2; inline prompts pass `promptContext` explicitly with their bubble's notificationId) ·
S4 interface (`VoiceReplyField` widget: self-contained record→transcribe→edit→send composer
taking a required `onSubmit( String text )` callback + optional `promptContext`; S3 wires
`onSubmit` to `FocusRespondRequested`)

## 1. Purpose

Assemble the focus-mode surface (Q11 — vertical badge rail + chat pane) and make it the app's
default screen with legacy surfaces demoted to a drawer (Q1).

## 2. Scope

**In**: `lib/features/focus_mode/presentation/` — `focus_mode_screen.dart`, `session_rail.dart`,
`focus_chat_pane.dart`, inline prompt bubbles; prompt-body EXTRACTION to
`lib/shared/widgets/prompt_bodies.dart` (F-S3-1 — declared legacy-presentation touch, see §3.1);
pause/resume control; route/default-screen swap; drawer with legacy entries; TestKeys; widget
tests.

**Out**: bloc logic (S2); TTS mechanics (S1); recording/ASR internals (S4 — consumed as a widget);
response dispatch mechanics (S2's `FocusRespondRequested` handler); any new server contract.

## 3. Design

### 3.1 Layout (Q11, Pattern A of the May skeleton)

```
+------+--------------------------------+
| rail |  FocusChatPane                 |
| 56dp |  header: PersonaBadge + name   |
|      |  + pause/resume toggle          |
| [M]  |  last-7 message bubbles        |
| [R]  |  (inline prompts where asked)  |
| [T]• |                                |
| [w]  |  VoiceReplyField (S4 widget)   |
+------+--------------------------------+
```

- **SessionRail**: vertical `ListView` of PersonaBadges (28px, existing variants incl. overflow/
  borrowed) in `senderOrder` (establishment order — Maria top, workers below, Q7 via S2 state).
  Unread dot/count overlays non-focused senders. Tap → `FocusSenderSelected`. Selected badge gets
  a highlight ring. No reordering, ever.
- **FocusChatPane**: header (badge + sender name); body renders the focused sender's 7-item window
  newest-at-bottom; bubbles styled by direction (Claude-sent vs user replies) and priority accent.
- **Pause/resume toggle**: single prominent control in the header bound to `pausedStream`/`pause()`/
  `resume()` (S1). Paused state is loudly visible (e.g., banner tint) — held ≠ silent-forever
  (Q6); the paused banner shows a LIVE held count bound to S1's `queueDepthStream` (ticks up as
  messages accumulate under hold — F-S1-S2-3) so held ≠ lost is visible.
- **Inline prompts (Q5) — extract-to-shared mechanism (F-S3-1, CONCUR with Stage-1
  recommendation; batch scope per F-S3-S2-2(d))**: the prompt-body widgets are currently
  library-PRIVATE and bloc-coupled (`_YesNoBody` `:103`, `_MultipleChoiceBody` `:171`,
  `_OpenEndedBody` `:254`, `_OpenEndedBatchBody` `:292` in `interactive_prompt_sheet.dart`;
  dispatch via `NotificationsRespond` `:39-52`). S3 EXTRACTS the THREE single-String bodies
  (yes/no, multiple-choice, open-ended) to public shared widgets in
  `lib/shared/widgets/prompt_bodies.dart` with an injected `onRespond( String response )`
  callback — the ONLY shape where Q5's "already widget-tested" rationale survives. **Batch
  open-ended asks are scoped OUT of inline rendering in v1 (F-S3-S2-2(d))**: `_OpenEndedBatchBody`
  submits `Map<String, String>` and a multi-question form doesn't belong in a chat bubble — it
  stays in the legacy sheet UNEXTRACTED; a batch ask's bubble renders the question text + an
  "Answer in full view…" affordance that opens the legacy `InteractivePromptSheet` (whose
  existing dispatch path handles the Map intact). This keeps `onRespond` and
  `FocusRespondRequested.text` String-typed end-to-end. The legacy sheet is refactored to COMPOSE
  the three extracted bodies (wiring `onRespond` to its existing `NotificationsRespond`
  dispatch); the new bubbles compose the same bodies wiring `onRespond` to
  `FocusRespondRequested` (F-S3-2). DECLARED legacy-presentation touch:
  `interactive_prompt_sheet.dart` is edited (allowed — only the legacy BLOC is Q2-frozen);
  existing sheet widget tests must stay green (AC-S3.9).
- **Buried-ask rule (F-S3-S2-1)**: inline buttons attach to the focused sender's newest
  UNANSWERED ask within the window — `pendingPromptFor( senderId )`, the SAME S2 selector the
  voice-reply fallback uses (pinned once in S2's contract, two consumers) — REGARDLESS of
  position: a chatty session's progress notifications never bury its own ask. Answered prompts
  collapse to a result chip.
- **Cold-start & hydration renders (F-S3-S2-3, Q4-LITERAL — recorded choice, no auto-focus)**:
  at cold start `focusedSender` is null and the pane renders an empty-state hint ("tap a session
  to focus"); auto-focus is OFF — Q4's manual-focus invariant is frozen and taken literally
  (one tap on the always-visible rail is the entire cost). `hydration = loading` → pane spinner;
  `hydration = error` → retry banner whose tap re-dispatches `FocusColdStartRequested`.
- **Manual-focus invariant (Q4)**: nothing in this surface changes `focusedSender` except a rail tap.

### 3.2 Route swap + drawer (Q1)

- Post-auth landing becomes `FocusModeScreen`. Exact seam (F-S3-3):
  `AuthGate( authenticatedChild: const LupinHomeScreen() )` at `app.dart:139-141` — the
  `authenticatedChild` swaps to `FocusModeScreen`; one-point change.
- New `Drawer` on FocusModeScreen with entries for the legacy surfaces (Home grid, Inbox, Queue
  Dashboard, Trust Dashboard, Settings…). Legacy routes stay registered; nothing is deleted.

### 3.3 TestKeys

New constants in `lib/core/testing/test_keys.dart`: `focusRail`, `focusRailBadgePrefix`,
`focusPauseToggle`, `focusChatPane`, `focusDrawerButton` (+ inline-prompt keys reusing existing
prompt-key constants).

## 4. Tasks

- [x] SessionRail + unread overlays + selection ring
- [x] FocusChatPane + bubbles + header (live held-count banner via S1 `queueDepthStream`)
- [x] Pause/resume toggle bound to S1 streams
- [x] Extract the THREE single-String prompt bodies to `lib/shared/widgets/prompt_bodies.dart`
      (injected `onRespond`); batch body stays in the legacy sheet (F-S3-S2-2(d)); refactor
      legacy sheet to compose the extracted three; legacy sheet tests stay green (F-S3-1)
- [x] Inline prompt bubbles composing the extracted bodies, attached via `pendingPromptFor`
      (buried-ask rule, F-S3-S2-1); `onRespond` → `FocusRespondRequested` (F-S3-2); batch-ask
      fallback affordance → legacy sheet
- [x] Cold-start empty-state hint + hydration loading spinner + error retry banner (F-S3-S2-3)
- [x] Embed S4 `VoiceReplyField` in composer slot; wire `onSubmit` → `FocusRespondRequested`;
      gate composer availability on `pendingPromptFor(focusedSender)` (disabled + hint when null
      — presentation choice per F-S2-S2-3; the signal is S2's contract)
- [x] Default-route swap at the `AuthGate.authenticatedChild` seam (`app.dart:139-141`) + legacy
      drawer
- [x] EXECUTOR: AI (F-S3-S3-1) — author the "Focus-mode milestone gate" section in
      `../v0.1.7/2026.04.24-on-device-tts-verify-runbook.md` enumerating ALL Stage-1
      perceptual + hardware gates (testing-strategy rule 5). THREE RIDERS, one artifact:
      (i) S1's TTS-pacing-under-pause/resume item (F-S1-S3-3 consuming side);
      (ii) S4's transcript-quality gate pinned as "spoken test sentence appears with ≤2 word
      errors" (author-picked N=2 — generous enough for accent/acoustics, tight enough to catch
      a broken pipeline);
      (iii) the OSQ-3 boot-order note (Maria tops the rail only if most-recently-active at the
      cold-start snapshot) so the first device session isn't surprised.
- [x] Record green baseline suite count in §8 Execution Log BEFORE first edit (testing-strategy
      rule 1; F-S1-S3-2 family)
- [x] TestKeys + widget tests (§5) + full-suite regression

## 5. Acceptance Criteria

- [x] EXECUTOR: AI — AC-S3.1 widget: rail renders badges in `senderOrder` (MockBloc state with 3
      senders) — top-to-bottom order asserted, not just presence.
- [x] EXECUTOR: AI — AC-S3.2 widget: unread count renders on non-focused badge; absent on focused.
- [x] EXECUTOR: AI — AC-S3.3 widget: rail tap dispatches `FocusSenderSelected(senderId)` exactly
      once; no TTS calls from the tap path (Q4/manual-focus, mock orchestrator).
- [x] EXECUTOR: AI — AC-S3.4 widget: pane shows exactly the focused sender's window (7 bubbles max).
- [x] EXECUTOR: AI — AC-S3.5 widget: pause toggle calls `pause()`; paused visual state renders
      with held count, and the count updates when `queueDepthStream` emits (mock orchestrator
      seam with a controllable stream); resume calls `resume()`.
- [x] EXECUTOR: AI — AC-S3.6 widget: unanswered yes_no ask renders the extracted tri-state body;
      tap Yes dispatches `FocusRespondRequested` with "yes" (MockBloc verify); answered prompt
      collapses to result chip. Sub-case (F-S3-S2-1, buried ask): an unanswered ask followed by
      2 newer progress messages STILL renders its buttons and dispatches on tap. Sub-case
      (F-S3-S2-2(d)): a batch open-ended ask renders the fallback affordance (NO inline chips);
      tapping it opens the legacy sheet.
- [x] EXECUTOR: AI — AC-S3.7 widget: post-auth route lands on FocusModeScreen; drawer opens and
      navigates to a legacy screen (smoke).
- [x] EXECUTOR: AI — AC-S3.8 integration (F-S3-S3-2 binding): execute testing-strategy
      §Cross-Section Integration Checkpoints items 1–3 — (1) full-suite run reported
      count-vs-baseline in tabular form; (2) S2+S1 wiring blocTest (paused inbound accumulates
      TTS queue + increments unread; resume drains in order); (3) S3 rail-tap assembly widget
      test (pane switches without TTS state changes) — ALL THREE green. (Item 4, the HUMAN
      device gate, is the separate checkbox below.)
- [x] EXECUTOR: AI — AC-S3.9 regression (F-S3-1): legacy `interactive_prompt_sheet` widget suite
      stays green after the sheet is refactored to compose the extracted bodies (incl. the
      Yes/No/Neither tri-state tests and the UNEXTRACTED batch body) — extraction must be
      behavior-neutral for the legacy surface.
- [x] EXECUTOR: AI — AC-S3.10 widget (F-S3-S2-3): null-focus cold start renders the empty-state
      hint (no crash, no auto-focus — `FocusSenderSelected` never dispatched without a tap);
      `hydration = loading` renders the pane spinner; `hydration = error` renders the retry
      banner and its tap re-dispatches `FocusColdStartRequested` (MockBloc verify).
- [ ] EXECUTOR: HUMAN (subjective UX: rail ergonomics, badge legibility light+dark, paused-state
      visibility at arm's length, AND TTS pacing under pause/resume — S1's perceptual layer,
      F-S3-S3-1/F-S1-S3-3) — on-device gate, scripted by the runbook section the §4 authoring
      task writes, bundled into the Stage-1 runbook session.

## 6. Open Items

None new — consumes OSQ resolutions owned by S1/S2/S4.

## 7. Revision Log

- **2026-06-12 (Stage-1 close, findings F-S3-1..3 + cross-section threads)**: F-S3-1
  (inconsistency, CONCUR extract-to-shared) — §3.1 names the mechanism (public
  `prompt_bodies.dart` + injected `onRespond`); legacy-presentation touch DECLARED; AC-S3.9
  legacy-sheet regression added. F-S3-2 (inconsistency, CONCUR option (a)) — responses dispatch
  via S2's new `FocusRespondRequested` from both inline prompts and the S4 widget's `onSubmit`;
  Consumes line restates the event + the new S4 callback signature; AC-S3.6 re-pinned at the
  event. F-S3-3 (cosmetic) — route-swap seam named exactly
  (`AuthGate( authenticatedChild: ... )`, `app.dart:139-141`). Stage-1 residual adopted: paused
  banner shows held count via S1 `queueDepth` (held ≠ lost, Q6).
- **2026-06-12 (S1 Stage-2 touchpoint, F-S1-S2-3)**: held-count consumption re-pointed at S1's
  new `queueDepthStream` (live signal — the bare `queueDepth` getter has no change
  notification); Consumes line, §3.1 banner bullet, task list, and AC-S3.5 updated. Applied
  under Manager-granted S3 touchpoint authority in the S1 Stage-2 revision round.
- **2026-06-12 (S2 Stage-2 touchpoint, F-S2-S2-3)**: Consumes line restates the typed
  `FocusPromptContext { notificationId, promptType? }` + the `pendingPromptFor( senderId )`
  contract-signal; composer task gates availability on the selector (disabled + hint when null —
  presentation choice owned here, signal owned by S2). Applied under Manager-granted touchpoint
  authority in the S2 Stage-2 revision round.
- **2026-06-12 (Stage-2 close, findings F-S3-S2-1..3 — merged pass with the S2 Stage-2 bundle)**:
  F-S3-S2-1 (inconsistency, CONCUR) — buried-ask rule: buttons attach to the newest UNANSWERED
  ask in the window via S2's `pendingPromptFor` (same selector as the voice-reply fallback,
  pinned once in S2); AC-S3.6 buried-ask sub-case. F-S3-S2-2 (inconsistency, cross-section,
  CONCUR option (d)) — batch asks scoped OUT of inline rendering v1 (fallback affordance →
  legacy sheet); extraction shrinks to the three single-String bodies; `onRespond` +
  `FocusRespondRequested.text` stay String-typed end-to-end (S2 event row annotated in the same
  pass). F-S3-S2-3 (inconsistency, CONCUR Q4-LITERAL — author declines to escalate auto-focus:
  one rail tap is the entire cost and predictability is the user's own Q4 rationale) —
  cold-start empty-state hint + loading spinner + error retry banner; NEW AC-S3.10.
- **2026-06-12 (F-S1-S3-2 family fix, doc-set-wide)**: §8 Execution Log placeholder + baseline
  task line added. NOTE for the Stage-1 runbook task: per F-S1-S3-3, the runbook milestone gate
  MUST enumerate TTS-pacing-under-pause/resume (S1's perceptual layer rides here — consuming-side
  check on record for S3 Stage 3).
- **2026-06-12 (Stage-3 close, findings F-S3-S3-1..2)**: F-S3-S3-1 (inconsistency, CONCUR
  two-part fix) — the F-S1-S3-3 consuming-side hook is now OPERATIVE, not commentary: §5 HUMAN
  gate enumeration gains TTS-pacing-under-pause/resume, and a NEW EXECUTOR: AI task authors the
  runbook "Focus-mode milestone gate" section with the three riders (S1 pacing; S4 transcript
  quality pinned ≤2 word errors, author-picked N; OSQ-3 boot-order note). F-S3-S3-2 (cosmetic,
  CONCUR) — AC-S3.8 enumerates its bound checkpoints (testing-strategy §Cross-Section items 1–3,
  all green; item 4 explicitly excluded as the separate HUMAN checkbox). S3 closes all three
  stages with this revision.

## 8. Execution Log

*(Placeholder per working-contract §Phase-Complete Definition + testing-strategy rule 1 —
populated at implementation time, NOT during the cascade.)*

- [x] Baseline suite count recorded BEFORE first edit (2026-06-12T05:05Z, carried forward from
  the S4-close run per Manager dispatch — zero edits between): `./flutter.sh test test/unit/
  test/widget/ test/service_integration/` → **365 ✅ / 1 skip / 1 ❌** (failure = pre-existing
  AC-D4 parent-side; skip = pre-existing AC-D6). Operative bar: 365 never decreases +
  legacy `interactive_prompt_sheet` suite green post-extraction (AC-S3.9) + quarantine untouched.
- Per-AC evidence entries land here as each §5 checkbox flips to `[x]` (test output, probe
  response, or named HUMAN sign-off).
- [x] **PARTIAL-WORK INVENTORY (2026-06-12T08:20Z, takeover implementer Rio ⚡, session
  `ad7692cc`)** — archaeology of Tiffany 💍's parked disk edits (session `472b7468` froze mid-S3
  in the fleet quota freeze AFTER her 05:04 manifest entry; everything below is unlogged in her
  manifest section but present + consistent on disk):
  - **LANDED (production surface — complete)**: `lib/features/focus_mode/presentation/`
    `session_rail.dart` (rail + unread overlays + selection ring + initial-fallback badge),
    `focus_chat_pane.dart` (header, 7-window bubbles, buried-ask via `pendingPromptFor`,
    answered chip, batch/multi-select/null-options fallback affordance → legacy sheet,
    cold-start hint + spinner + retry banner), `focus_mode_screen.dart` (assembly, pause toggle,
    paused banner on `queueDepthStream`, composer gating off `pendingPromptFor`, legacy drawer);
    `lib/shared/widgets/prompt_bodies.dart` (F-S3-1 three-body extraction, implementer call
    documented: multi-select multiple_choice routes to the fallback affordance with batch);
    `interactive_prompt_sheet.dart` refactored to COMPOSE the extracted bodies (batch body
    retained private); 8 S3 TestKeys; `app.dart` route swap landed at the AuthGate seam
    (`authenticatedChild: const FocusModeScreen()`, now `app.dart:205-210` post-WsBlocDispatcher
    extraction — seam name governed, cite drift confirmed harmless).
  - **LANDED (the queued 3-finding bundle — ALL THREE already applied)**: F-S2-IMPL-1 phased
    `_coldStartBuild` + `_reconnectRefresh` in `focus_chat_bloc.dart` (awaits→locals, one
    synchronous re-read→merge→emit; cold-start unions fetched order with `state.senderOrder`)
    PLUS both Completer-gated mid-flight regression tests — verified passing 15/15 in
    `test/unit/focus_mode/`; F-S2-IMPL-2 AC-S2.4 wire-truth amendment present in 11-section-s2
    §5 with provenance (`notifications.py:1940-1962` + `conversation_wire_sample.json`);
    F-S4-IMPL-1 `_recorder.stop()` try→typed-AsrException in `asr_service.dart` (+ the optional
    `start()` orphan-cleanup half).
  - **HALF-DONE (tests authored, NOT green)**: as-found full suite
    `./flutter.sh test test/unit/ test/widget/ test/service_integration/` →
    **377 ✅ / 1 skip / 7 ❌** (wall 10:25 incl. two 10-min hangs). Attribution:
    (1–2) `focus_mode_screen_test` AC-S3.2 + AC-S3.4 fail on a REAL production bug — the
    composer-hint Row (`focus_mode_screen.dart:111`) overflows 132px (unwrapped long hint Text);
    (3) AC-S3.10 sub-cases (b)/(c) re-seed the SAME MockBloc — element reuse keeps BlocBuilder
    subscribed to the old stub, spinner never renders; (4) AC-S3.7 drawer smoke —
    `pumpAndSettle` after navigating to InboxScreen never settles (infinite spinner animation);
    (5) `focus_assembly_test` — `await Future.delayed` inside `testWidgets` fake-async hangs →
    10-min timeout; (6) `persona_badge_test` AC-C4 (Manager triage surface, was green at S4
    close) now reproducibly HANGS — `toImage`/`toByteData` real futures without
    `tester.runAsync`; (7) pre-existing AC-D4 (parent-owned `assigned_at` gap — not an S3
    surface). Items 1–6 are fix-forward work this session; item 7 stays.
  - **UNTOUCHED**: the EXECUTOR: AI runbook task ("Focus-mode milestone gate" section with the
    three riders — absent from `../v0.1.7/2026.04.24-on-device-tts-verify-runbook.md`); §4 task
    flips; §5 AC flips; per-AC evidence below; AC-S3.8 item-1 tabular report; AC-S3.9
    legacy-suite verification statement.
  - Analyze (lib/ + test/, project scope): S3 surfaces clean; sole changed-file warning
    (`app.dart` unused `claude_code_event.dart` import) is PRE-EXISTING at HEAD:15.
- [x] **Fix-forward pass (2026-06-12T09:20Z, Rio ⚡ — Manager-concurred plan, DM 08:36Z)**:
  (1) PRODUCTION FIX — composer-hint Text wrapped in `Flexible` (`focus_mode_screen.dart`; the
  Row overflowed 132px — a real device-visible bug, caught by Tiffany's own AC-S3.2/S3.4 tests);
  (2) `focus_mode_screen_test.dart` — `seed()` now creates a FRESH MockBloc per call (element
  reuse kept BlocBuilder subscribed to the prior stub; AC-S3.10 (b)/(c) now exercise real
  re-subscription) + AC-S3.7 drawer smoke post-nav `pumpAndSettle` → bounded pumps (InboxScreen's
  mock-initial spinner never settles); (3) `focus_assembly_test.dart` — bloc seeding + teardown
  closes moved onto the REAL event loop via `tester.runAsync` with a hard-gate `expect` on
  `senderOrder` post-seed + defensive repo stubs (bare `Future.delayed` — and even a fake-clock
  `pump(20ms)` — hung under testWidgets fake async to the 10-min timeout; runAsync is the
  recipe); (4) `persona_badge_test.dart` AC-C4 (Manager's surface, Manager-concurred) — both
  `toImage`/`toByteData` captures wrapped in `tester.runAsync` (real-event-loop futures; hung
  reproducibly in full-suite AND solo runs). **Test-recipe lesson for the ledger (twice-bitten
  tonight): any real-event-loop future awaited inside `testWidgets` — engine image capture,
  bloc-seeding waits, `Future.delayed` — must ride `tester.runAsync`; fake-async hangs present as
  opaque 10-minute timeouts with no useful stack.**
- [x] **AC evidence (2026-06-12T09:25Z)** — `focus_mode_screen_test.dart` (12) +
  `focus_assembly_test.dart` (1) + `focus_s1_s2_wiring_test.dart` (1): **14/14 ✅**. Mapping:
  AC-S3.1 (top-to-bottom y-coordinate order asserted, B<A<C); AC-S3.2 (unread '3' on non-focused,
  none on focused); AC-S3.3 (exactly-once `FocusSenderSelected`, zero TTS calls verified);
  AC-S3.4 (focused sender's 7 bubbles only + disabled-composer hint); AC-S3.5 (pause() verified,
  banner + LIVE depth tick 2→5 via controllable `queueDepthStream`, resume() verified); AC-S3.6
  (tri-state body renders, Yes → `FocusRespondRequested` w/ explicit typed context, answered →
  chip; buried-ask sub-case: ask + 2 newer progress messages still renders buttons + dispatches;
  batch sub-case: fallback affordance, NO inline chips, tap opens legacy sheet w/ "Submit all");
  AC-S3.7 (real AuthGate seam shape lands on the focus rail; drawer → Inbox navigates away);
  AC-S3.10 (cold-start hint + `FocusSenderSelected` never dispatched; loading spinner; error
  retry banner re-dispatches `FocusColdStartRequested` w/ authed email). AC-S3.9: legacy
  `interactive_prompt_sheet_test.dart` + `conversation_screen_test.dart` → **16/16 ✅**
  (extraction behavior-neutral incl. tri-state Yes/No/Neither + UNEXTRACTED batch body).
- [x] **AC-S3.8 — Cross-Section Integration Checkpoints items 1–3 (2026-06-12T09:30Z)**:
  item 2 = `focus_s1_s2_wiring_test.dart` ✅ (REAL FocusChatBloc + REAL TtsOrchestrator: paused
  inbound accumulates depth 2 + unread increments; resume drains `['msg-1','msg-2']` in arrival
  order); item 3 = `focus_assembly_test.dart` ✅ (REAL bloc behind the real screen: rail tap
  switches pane, `focusedSender`='B', ZERO TTS state mutations — Q4); item 1 = full-suite
  count-vs-baseline, tabular:

  | Run | ✅ | skip | ❌ | Note |
  |---|---|---|---|---|
  | S3 pre-edit baseline (S4-close carry-forward) | 365 | 1 | 1 | ❌ = AC-D4 (parent-owned, then) |
  | As-found at takeover (Tiffany's parked edits) | 377 | 1 | 7 | 6 fix-forward + AC-D4 |
  | **S3 close** | **384** | **1** | **0** | **ALL GREEN; skip = by-design AC-D6** |

  365-baseline never decreased (+19 net new passing); AC-D4 returned green via the parent-side
  merge + Manager's 08:28Z fixture re-capture; 44-test quarantine untouched; analyze clean on
  every changed surface (0 errors/warnings; only style infos). (Item 4 = the HUMAN device gate,
  scripted by the runbook section below — open by design.)
- [x] **Runbook task (F-S3-S3-1) — AUTHORED (2026-06-12T08:50Z)**: NEW section "Focus-mode
  milestone gate (added 2026-06-12)" in `../v0.1.7/2026.04.24-on-device-tts-verify-runbook.md` —
  fm1 rail ergonomics/legibility light+dark, fm2 OSQ-3 boot-order note (rider iii), fm3
  paused-visibility at arm's length, fm4 S1 TTS-pacing under pause/resume (rider i), fm5 S4
  transcript gate ≤2 word errors vs "Focus mode voice chat test one two three." (rider ii), fm6
  prompt-interplay spot check + sign-off table mapping each gate to its section AC.
- HUMAN gate (§5 last checkbox): remains open by design — executes on the laptop via the
  runbook's fm1–fm6, bundled Stage-1 session.

**SECTION S3 IMPLEMENTATION COMPLETE (AI tiers) — 2026-06-12. STAGE 1 (S1+S2+S4+S3) AI-COMPLETE;
full suite 384 ✅ / 1 skip / 0 ❌.**
