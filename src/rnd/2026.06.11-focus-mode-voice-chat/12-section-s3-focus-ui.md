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

- [ ] SessionRail + unread overlays + selection ring
- [ ] FocusChatPane + bubbles + header (live held-count banner via S1 `queueDepthStream`)
- [ ] Pause/resume toggle bound to S1 streams
- [ ] Extract the THREE single-String prompt bodies to `lib/shared/widgets/prompt_bodies.dart`
      (injected `onRespond`); batch body stays in the legacy sheet (F-S3-S2-2(d)); refactor
      legacy sheet to compose the extracted three; legacy sheet tests stay green (F-S3-1)
- [ ] Inline prompt bubbles composing the extracted bodies, attached via `pendingPromptFor`
      (buried-ask rule, F-S3-S2-1); `onRespond` → `FocusRespondRequested` (F-S3-2); batch-ask
      fallback affordance → legacy sheet
- [ ] Cold-start empty-state hint + hydration loading spinner + error retry banner (F-S3-S2-3)
- [ ] Embed S4 `VoiceReplyField` in composer slot; wire `onSubmit` → `FocusRespondRequested`;
      gate composer availability on `pendingPromptFor(focusedSender)` (disabled + hint when null
      — presentation choice per F-S2-S2-3; the signal is S2's contract)
- [ ] Default-route swap at the `AuthGate.authenticatedChild` seam (`app.dart:139-141`) + legacy
      drawer
- [ ] EXECUTOR: AI (F-S3-S3-1) — author the "Focus-mode milestone gate" section in
      `../v0.1.7/2026.04.24-on-device-tts-verify-runbook.md` enumerating ALL Stage-1
      perceptual + hardware gates (testing-strategy rule 5). THREE RIDERS, one artifact:
      (i) S1's TTS-pacing-under-pause/resume item (F-S1-S3-3 consuming side);
      (ii) S4's transcript-quality gate pinned as "spoken test sentence appears with ≤2 word
      errors" (author-picked N=2 — generous enough for accent/acoustics, tight enough to catch
      a broken pipeline);
      (iii) the OSQ-3 boot-order note (Maria tops the rail only if most-recently-active at the
      cold-start snapshot) so the first device session isn't surprised.
- [ ] Record green baseline suite count in §8 Execution Log BEFORE first edit (testing-strategy
      rule 1; F-S1-S3-2 family)
- [ ] TestKeys + widget tests (§5) + full-suite regression

## 5. Acceptance Criteria

- [ ] EXECUTOR: AI — AC-S3.1 widget: rail renders badges in `senderOrder` (MockBloc state with 3
      senders) — top-to-bottom order asserted, not just presence.
- [ ] EXECUTOR: AI — AC-S3.2 widget: unread count renders on non-focused badge; absent on focused.
- [ ] EXECUTOR: AI — AC-S3.3 widget: rail tap dispatches `FocusSenderSelected(senderId)` exactly
      once; no TTS calls from the tap path (Q4/manual-focus, mock orchestrator).
- [ ] EXECUTOR: AI — AC-S3.4 widget: pane shows exactly the focused sender's window (7 bubbles max).
- [ ] EXECUTOR: AI — AC-S3.5 widget: pause toggle calls `pause()`; paused visual state renders
      with held count, and the count updates when `queueDepthStream` emits (mock orchestrator
      seam with a controllable stream); resume calls `resume()`.
- [ ] EXECUTOR: AI — AC-S3.6 widget: unanswered yes_no ask renders the extracted tri-state body;
      tap Yes dispatches `FocusRespondRequested` with "yes" (MockBloc verify); answered prompt
      collapses to result chip. Sub-case (F-S3-S2-1, buried ask): an unanswered ask followed by
      2 newer progress messages STILL renders its buttons and dispatches on tap. Sub-case
      (F-S3-S2-2(d)): a batch open-ended ask renders the fallback affordance (NO inline chips);
      tapping it opens the legacy sheet.
- [ ] EXECUTOR: AI — AC-S3.7 widget: post-auth route lands on FocusModeScreen; drawer opens and
      navigates to a legacy screen (smoke).
- [ ] EXECUTOR: AI — AC-S3.8 integration (F-S3-S3-2 binding): execute testing-strategy
      §Cross-Section Integration Checkpoints items 1–3 — (1) full-suite run reported
      count-vs-baseline in tabular form; (2) S2+S1 wiring blocTest (paused inbound accumulates
      TTS queue + increments unread; resume drains in order); (3) S3 rail-tap assembly widget
      test (pane switches without TTS state changes) — ALL THREE green. (Item 4, the HUMAN
      device gate, is the separate checkbox below.)
- [ ] EXECUTOR: AI — AC-S3.9 regression (F-S3-1): legacy `interactive_prompt_sheet` widget suite
      stays green after the sheet is refactored to compose the extracted bodies (incl. the
      Yes/No/Neither tri-state tests and the UNEXTRACTED batch body) — extraction must be
      behavior-neutral for the legacy surface.
- [ ] EXECUTOR: AI — AC-S3.10 widget (F-S3-S2-3): null-focus cold start renders the empty-state
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

- [ ] Green baseline suite count recorded BEFORE first edit: `____` (date/time, command, count)
- Per-AC evidence entries land here as each §5 checkbox flips to `[x]` (test output, probe
  response, or named HUMAN sign-off).
