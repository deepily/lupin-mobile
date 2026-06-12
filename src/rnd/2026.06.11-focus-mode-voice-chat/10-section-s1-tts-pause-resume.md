# Section S1 — TTS Pause/Resume (TtsOrchestrator Extension)

**Stage**: 1
**Anchors**: [01-architecture.md](01-architecture.md) · [02-decisions.md](02-decisions.md) Q6, OSQ-5 · [03-testing-strategy.md](03-testing-strategy.md)
**Provides**: `pause()` / `resume()` / `isPaused` / `pausedStream` / `queueDepthStream` on
`TtsOrchestrator` (consumed by S3 — `queueDepthStream` is the live held-count signal,
F-S1-S2-3); `enqueueAlways()` ungated enqueue entry point (consumed by S2 — the focus surface's
SOLE TTS dispatch path, per user ruling F-S1-1 2026-06-12)
**Consumes**: nothing from sibling sections

## 1. Purpose

Give the single serial TTS queue a HOLD: pause stops dequeuing without dropping anything; resume
drains accumulated utterances in arrival order (Q6 — explicitly a pause, not a mute).

Additionally (F-S1-1, USER-RULED): give the focus surface an UNGATED entry point —
`enqueueAlways()` — so EVERY notification is spoken regardless of priority or mute preferences
(Q6). The legacy gated `enqueueIfSpeakable()` cannot deliver Q6: it drops low/medium at
`_isSpeakable` (`tts_orchestrator.dart:110-116`) and everything under `masterMute` (`:78`).

## 2. Scope

**In**: paused-state flag on `TtsOrchestrator` (`lib/services/tts/tts_orchestrator.dart`);
pause/resume API; NEW ungated `enqueueAlways()` entry point (F-S1-1); non-destructive urgent
preempt for the focus path (F-S1-2); interaction with the existing FIFO, urgent-preempt, and
quota-fallback paths; state-change stream so UI can render the toggle; regression tests.

**Out**: any UI (S3); any change to `StreamingTtsPlayer`; priority-preference gating (rejected, Q6);
dropping/clearing the queue (existing `stopAll()` remains the only destructive control);
disabling the legacy NotificationBloc TTS dispatch — that lands via the S2 §2 scope amendment
(F-S2-1 DI-seam mechanism: `service_locator` stops injecting the bloc's Optional `tts`
dependency; S2 owns DI wiring), though the ruling is recorded here because this section provides
the replacement path.

## 3. Design

Current behavior (verified against source 2026-06-11/12): `enqueueIfSpeakable()` gates
(`masterMute` `:78`; `_isSpeakable` `:110-116` — low/medium NEVER spoken, high/urgent
preference-gated) + enqueues + dispatches if idle; `_tryStartNext()` dequeues (`:131`);
`_preemptForUrgent()` FLUSHES pending via `_fifo.clear()` (`:124`) then stops current playback;
the completion seam is `_player.completeStream → _onUtteranceFinished` (`:49`, `:213`); error
continuation re-enters dequeue via `_onElevenLabsError → _tryStartNext()` (`:205`, `:210`); quota
errors open a 5-minute `flutter_tts` fallback window.

Changes:

1. `bool _paused = false;` + public `bool get isPaused` + `Stream<bool> get pausedStream`
   (broadcast) so S3's toggle renders reactively without polling. PLUS
   `Stream<int> get queueDepthStream` (broadcast; emits the new depth on EVERY enqueue and
   dequeue) — the live held-count signal for S3's paused banner (F-S1-S2-3: the synchronous
   `queueDepth` getter at `:58` has no change notification; a badge that ticks up under hold
   needs the stream). One controller; the getter stays for synchronous reads.
2. **Pause gate lives in `_tryStartNext()`** (F-S1-4): its first line parks when `_paused`. One
   choke point covers ALL continuation paths — utterance completion (`:49` →
   `_onUtteranceFinished` `:213`), error continuation (`:205`/`:210`), and the dispatch-if-idle
   step in both enqueue entry points. `void pause()` sets the flag; the IN-FLIGHT utterance
   finishes naturally (OSQ-5: utterance-boundary semantics — never cut mid-sentence).
3. `void resume()` — clears `_paused`, calls `_tryStartNext()`; queue drains FIFO.
4. **NEW `void enqueueAlways( {required String priority, required String message, String? title,
   String? voiceId} )`** (F-S1-1, USER-RULED — "Ungated path + sole dispatcher"): bypasses BOTH
   the `masterMute` gate and `_isSpeakable` — every notification enqueues and speaks.
   `FocusChatBloc` calls it for EVERY inbound notification (Q6). `enqueueIfSpeakable()` itself is
   UNCHANGED (legacy parity); the legacy NotificationBloc dispatch is DISABLED via the DI seam
   per the S2 §2 scope amendment (the bloc's `tts` param is Optional — `notification_bloc.dart:35`
   /`:90` — `service_locator` simply stops injecting it; the legacy bloc FILE stays untouched,
   keeping Q2 literal), making FocusChatBloc the SOLE TTS dispatcher.
5. Enqueue-while-paused: `enqueueAlways` enqueues ALWAYS (accumulate, Q6) and skips the
   dispatch-if-idle step when `_paused`; the legacy `enqueueIfSpeakable` NON-URGENT path likewise
   parks (its dispatch-if-idle step is gated). **Legacy-urgent exception (F-S1-S2-2)**: the
   legacy urgent branch routes through `_preemptForUrgent()` (`:87-88` → `:123-129`), which
   dispatches DIRECTLY and never passes the `_tryStartNext()` gate — the legacy path is
   pause-EXEMPT BY DESIGN (verbatim parity; pause is a focus-path concept; zero production
   callers remain post-F-S2-1 DI-withdrawal, verified). Pinned by AC-S1.9.
6. Urgent while paused via `enqueueAlways`: do NOT preempt audio (pause is absolute, OSQ-5
   proposed); the urgent item inserts at the queue front BEHIND any existing leading urgents —
   the urgent block stays arrival-ordered ahead of non-urgents (no `addFirst` LIFO inversion,
   F-S1-S2-1a). Ding/badge behavior is S2/S3 territory and unaffected here.
7. **Urgent while UNPAUSED via `enqueueAlways` — non-destructive preempt** (F-S1-2): stop current
   playback, RE-QUEUE the interrupted utterance at the queue front (immediately behind the
   urgent), dispatch the urgent. Interrupted-utterance semantics (author-ruled, documented here
   per the finding): the interrupted utterance REPLAYS FROM THE START on its next turn —
   `StreamingTtsPlayer` exposes no mid-utterance position, so utterance-level replay is the only
   implementable granularity, and it matches OSQ-5's utterance-boundary philosophy. Nothing is
   dropped: post-urgent order = interrupted utterance (full replay) → remaining FIFO in arrival
   order. **No urgent-preempts-urgent (F-S1-S2-1b)**: if the in-flight utterance is ITSELF
   urgent, a newly arriving urgent does NOT preempt it — U2 enqueues at the head of the
   non-urgent portion, behind any earlier-queued urgents, and plays when U1 finishes
   (replay-from-start makes preempt churn costly under bursts; arrival order is this section's
   ethos). The legacy `enqueueIfSpeakable` urgent path keeps `_preemptForUrgent()`'s flush
   behavior verbatim (legacy parity, pinned by AC-S1.9).
   **Preempt re-entry guard (F-S1-S3-1, wire-grounded)**: the real `StreamingTtsPlayer.stop()`
   does NOT emit on `completeStream` — documented contract at `streaming_tts_player.dart:162-165`
   ("A stopped utterance does NOT fire TtsCompleteEvent") and enforced by the
   completer-identity mechanism (`stop()` clears `_activePlaybackCompleter` before completing the
   stale completer, `:169-176`; `_playPcmBuffer`'s identity check `:242-249` then skips the
   `_completeCtrl` emission). So no completion-driven double-advance exists at parity. Chosen
   guard, stated for robustness against future player changes: an UTTERANCE-EPOCH counter on the
   orchestrator — incremented on every dispatch and every preempt-stop; the completion/error
   handlers capture the epoch they were armed under and no-op if stale. Mocks MUST mirror the
   wire-grounded stop()-emits-nothing semantics (testing-strategy rule 4).
8. Quota-fallback interaction: the 5-minute window timer is orthogonal — pausing does not stop the
   window clock; resumed utterances route per whatever the window says at dequeue time.

## 4. Tasks

- [ ] Add paused flag, `pause()`, `resume()`, `isPaused`, `pausedStream`, `queueDepthStream`
      (emits on every enqueue/dequeue)
- [ ] Gate `_tryStartNext()` on `_paused` (single choke point — completion, error continuation,
      dispatch-if-idle all covered) + skip dispatch-if-idle in both enqueue entry points
- [ ] NEW `enqueueAlways()` ungated entry point (F-S1-1)
- [ ] Urgent-while-paused: insert behind leading urgents (urgent block arrival-ordered), no
      audio preempt (F-S1-S2-1a)
- [ ] Urgent-while-unpaused via `enqueueAlways`: non-destructive preempt + re-queue interrupted
      utterance, replay-from-start (F-S1-2); no urgent-preempts-urgent (F-S1-S2-1b)
- [ ] Document legacy pause-exemption in dartdoc (F-S1-S2-2)
- [ ] Dartdoc on all public members stating Q6/OSQ-5/F-S1-1 semantics
- [ ] Record green baseline suite count in §8 Execution Log BEFORE first edit (testing-strategy
      rule 1; F-S1-S3-2)
- [ ] Tests (§5) + full-suite regression run

## 5. Acceptance Criteria

- [ ] EXECUTOR: AI — AC-S1.1 unit: `pause()` then 3 × `enqueueAlways` (one of them priority
      `low`) → player.speak NOT called; queue length 3.
- [ ] EXECUTOR: AI — AC-S1.2 unit: `resume()` after AC-S1.1 → utterances dispatched in arrival
      order (capture order via mock player).
- [ ] EXECUTOR: AI — AC-S1.3 unit: pause during in-flight utterance → current completes
      (completion event on `_player.completeStream` → `_onUtteranceFinished` honored), next does
      NOT start.
- [ ] EXECUTOR: AI — AC-S1.4 unit: urgent via `enqueueAlways` while paused → no preempt call; on
      resume it plays FIRST. Extended (F-S1-S2-1a): TWO urgents arriving while paused (U1 then
      U2, with non-urgents already queued) drain U1 → U2 → non-urgents in arrival order — no
      LIFO inversion.
- [ ] EXECUTOR: AI — AC-S1.5 unit: quota-fallback window opened pre-pause routes resumed
      utterances through `flutterTtsSpeak` while window active (`enqueueAlways` path).
- [ ] EXECUTOR: AI — AC-S1.6 regression: existing orchestrator suite (incl. 2026-04-24 overlap
      fix tests) stays green; report counts.
- [ ] EXECUTOR: AI — AC-S1.7 unit (F-S1-2): urgent via `enqueueAlways` while UNPAUSED with 3
      queued → current playback stops, urgent plays immediately, then the interrupted utterance
      replays from the start, then the 3 queued in arrival order; nothing dropped (capture via
      mock player). Extended (F-S1-S2-1b): if the in-flight utterance is itself URGENT, a second
      urgent does NOT preempt — U2 plays after U1 completes. Extended (F-S1-S3-1): the mock
      player MUST mirror the wire-grounded semantics — `stop()` emits NOTHING on `completeStream`
      (`streaming_tts_player.dart:162-176`, `:242-249`) — and the test asserts exactly ONE
      dispatch follows the preempt via TOTAL speak-call COUNT (not sequence order alone): no
      completion-driven double-advance.
- [ ] EXECUTOR: AI — AC-S1.8 unit (F-S1-1): `low`-priority via `enqueueAlways` with
      `masterMute=true` and `speakOnHigh`/`speakOnUrgent` false IS enqueued and spoken — gates
      bypassed.
- [ ] EXECUTOR: AI — AC-S1.9 unit (F-S1-1): legacy gated path unchanged — low/medium via
      `enqueueIfSpeakable` still never speak; `masterMute` still suppresses; legacy urgent still
      flush-preempts via `_preemptForUrgent()` (parity pins). Sub-case (F-S1-S2-2):
      legacy-urgent-while-paused PREEMPTS (flush + speak) — the legacy path is pause-exempt by
      design.
- [ ] EXECUTOR: AI — AC-S1.10 unit (F-S1-4): ElevenLabs error on the in-flight utterance while
      paused → queue does NOT advance (error continuation `:205`/`:210` parks at the
      `_tryStartNext()` gate); on resume, the queue drains normally.
- [ ] EXECUTOR: AI — AC-S1.11 unit (F-S1-S2-3): 3 × `enqueueAlways` while paused →
      `queueDepthStream` emits 1, 2, 3; on resume-drain it emits decrements back to 0.

## 6. Open Items

None — OSQ-5 cascade-RATIFIED 2026-06-12 (Stage-3 ownership-lens verdict + Manager concurrence;
recorded in 02-decisions.md).

**Perceptual-gate pointer (F-S1-S3-3)**: TTS pacing under pause/resume (working-contract layer 6)
is EXECUTOR: HUMAN and is enumerated in S3's on-device runbook milestone gate — S1 closes on AI
tiers only; the perceptual sign-off rides S3's bundled device session. (S3's runbook gate must
enumerate pause/resume pacing — consuming-side check on record for S3 Stage 3.)

## 7. Revision Log

- **2026-06-12 (Stage-1 close, findings F-S1-1..4)**: F-S1-1 (foundational, USER-RULED "Ungated
  path + sole dispatcher") — added `enqueueAlways()`; FocusChatBloc becomes sole TTS dispatcher;
  legacy TTS dispatch disabled via the S2 §2 DI-seam amendment (F-S2-1 mechanism — bloc file
  untouched, Q2 literal); touchpoints updated in 01-architecture.md §1/§2/§4.1.
  F-S1-2 (inconsistency) — non-destructive urgent preempt on the focus path, replay-from-start
  semantics documented, AC-S1.7 added; legacy flush parity pinned (AC-S1.9). F-S1-3 (cosmetic) —
  AC-S1.3 re-worded to the real completion seam (`_player.completeStream → _onUtteranceFinished`).
  F-S1-4 (cosmetic) — pause gate placed in `_tryStartNext()` (Design §3.2 aligned with task list);
  error-while-paused AC-S1.10 added.
- **2026-06-12 (Stage-2 close, findings F-S1-S2-1..3)**: F-S1-S2-1 (inconsistency, CONCUR both
  recommendations) — (a) paused multi-urgent inserts behind leading urgents, urgent block
  arrival-ordered (§3.6, AC-S1.4 extended); (b) no urgent-preempts-urgent (§3.7, AC-S1.7
  extended). F-S1-S2-2 (inconsistency, CONCUR Arnold's fix verbatim) — legacy path declared
  pause-EXEMPT BY DESIGN; §3.5 BOTH-entry-points wording corrected; AC-S1.9 sub-case pins
  legacy-urgent-while-paused = preempts. F-S1-S2-3 (inconsistency, cross-section, CONCUR
  option (1)) — `queueDepthStream` added (Provides line + §3.1 + AC-S1.11); S3 consumption
  wording + 01-architecture §3 anchor re-aligned in the same revision (touchpoint authority per
  Manager routing).
- **2026-06-12 (Stage-3 close, findings F-S1-S3-1..3 + OSQ-5 ratification)**: F-S1-S3-1
  (inconsistency, CONCUR all three elements) — wire-grounded: `stop()` does NOT emit on
  `completeStream` (`streaming_tts_player.dart:162-165` doc + `:169-176`/`:242-249` identity
  mechanism); utterance-epoch re-entry guard stated in §3.7; AC-S1.7 extended (mock mirrors wire
  semantics; exactly-one-dispatch via total speak-call count). F-S1-S3-2 (cosmetic) — §8
  Execution Log placeholder + baseline-before-first-edit task line; ALSO applied doc-set-wide to
  S2–S6 per the Manager's family instruction (Cheech's predicted family confirmed). F-S1-S3-3
  (cosmetic) — providing-side perceptual-gate pointer added to §6 (TTS pacing → S3's runbook;
  consuming-side check on record for S3 Stage 3). OSQ-5 recorded RATIFIED in 02-decisions.md.
  Section S1 closes ALL THREE STAGES with this revision.

## 8. Execution Log

*(Placeholder per working-contract §Phase-Complete Definition + testing-strategy rule 1 —
populated at implementation time, NOT during the cascade.)*

- [ ] Green baseline suite count recorded BEFORE first edit: `____` (date/time, command, count)
- Per-AC evidence entries land here as each §5 checkbox flips to `[x]` (test output, probe
  response, or named HUMAN sign-off).
