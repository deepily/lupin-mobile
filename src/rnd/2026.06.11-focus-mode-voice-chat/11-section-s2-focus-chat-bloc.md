# Section S2 — FocusChatBloc (State + Session Registry)

**Stage**: 1
**Anchors**: [01-architecture.md](01-architecture.md) · [02-decisions.md](02-decisions.md) Q2, Q4, Q6, Q7, Q8, OSQ-3, OSQ-4 · [03-testing-strategy.md](03-testing-strategy.md)
**Provides**: `FocusChatBloc` state contract (consumed by S3): insertion-ordered session registry,
focused sender, per-sender last-7 message windows, per-sender unread counts, and the
`pendingPromptFor( senderId )` selector (F-S2-S2-3 contract-signal — null ⇒ no unanswered ask);
`FocusRespondRequested(senderId, text, promptContext?)` response-dispatch event with TYPED
`FocusPromptContext { notificationId, promptType? }` (consumed by S3's inline prompts and — via
an S3-wired callback — S4's `VoiceReplyField`; F-S3-2 resolution)
**Consumes**: S1 interface — `enqueueAlways()` ungated TTS entry point (F-S1-1 user ruling;
restated: bypasses `masterMute` + `_isSpeakable`, takes `priority`/`message`/`title?`/`voiceId?`)

## 1. Purpose

The slim, purpose-built state engine for the focus surface (Q2). Holds exactly the state the 5%
needs and nothing else — deliberately NOT an extension of the legacy NotificationBloc.

## 2. Scope

**In**: `lib/features/focus_mode/domain/` — `focus_chat_bloc.dart`, `focus_chat_event.dart`,
`focus_chat_state.dart`; WS bridging from `lib/app.dart` (incl. reconnect re-hydration); TTS
enqueue call-outs via S1's `enqueueAlways()`; response dispatch via
`NotificationRepository.respond()`; backfill via `NotificationRepository`; DI registration; bloc
tests.

**Scope amendment (F-S1-1 USER RULING, mechanism per F-S2-1, 2026-06-12)**: `service_locator.dart`
STOPS injecting the legacy NotificationBloc's Optional `tts` dependency
(`notification_bloc.dart:35`/`:90` — the param is already nullable). The legacy bloc FILE is not
edited (Q2 stays literal); its TTS dispatch simply goes dead, and FocusChatBloc becomes the SOLE
TTS dispatcher via S1's `enqueueAlways()`. Without this, every high/urgent frame would be enqueued
TWICE on the shared singleton orchestrator (legacy call site `notification_bloc.dart:244` + this
bloc) — F-S2-1's double-speak.

**Out**: all rendering (S3); TTS pause mechanics (S1 — the bloc only calls `enqueueAlways`);
voice capture (S4); legacy NotificationBloc (file untouched; its TTS injection is withdrawn via
DI per the scope amendment above).

## 3. Design

### 3.1 State

```dart
class FocusChatState extends Equatable {
  final List<String>                       senderOrder;     // establishment order (Q7)
  final Map<String, VoicePersona?>         personasBySender;
  final Map<String, List<NotificationItem>> windows;        // capped at 7 per sender (Q8)
  final Map<String, int>                   unreadBySender;  // 0 for focused sender (Q4)
  final String?                            focusedSender;
  final FocusHydration                     hydration;       // idle | loading | ready | error
}
```

Single state class + flags (not a sealed hierarchy): the surface re-renders wholesale on any
change and the matrix is small. `senderOrder` is append-only within an app run; first-seen first
(Q7). Cold start (OSQ-3 as amended 2026-06-12, F-S2-S2-1): ONE `senders()` fetch
(`notification_repository.dart:143`), registry ordered by `SenderSummary.lastActivity` DESC — a
one-time recency snapshot (earliest-per-sender does not exist on the wire); establishment order
governs every live arrival thereafter and the rail NEVER re-sorts (Q7's anti-shuffle rationale is
about live re-ordering, untouched by the snapshot).

**Reconnect-refresh mode (F-S2-S3-1)**: `FocusColdStartRequested` is MODE-DEPENDENT on existing
state. COLD START (`senderOrder` empty): build per the snapshot rule above. RECONNECT-REFRESH
(`senderOrder` non-empty): existing senders KEEP their positions (Q7 anti-shuffle — the rail
NEVER re-sorts, not even on refresh); new senders APPEND in fetch order; windows MERGE-DEDUPE by
notification id, capped at 7 newest-last; unread counts are PRESERVED for existing senders
(a refresh is not a read); `focusedSender` is unchanged; `pendingPromptFor` stays a pure
derivation over the merged windows (no reset side-effects — a backfilled answer flipping an ask
to answered is correct behavior). This seam is where Stage 2's doze/wake correctness terminates
(F-S5-1c), so the contract is explicit by design.

The state additionally exposes a **`pendingPromptFor( senderId )` selector** (F-S2-S2-3): returns
the sender's newest item with `responseRequested && !responded`, or null. This is the
contract-signal S3 uses to enable/disable the composer AND to attach inline prompt buttons
(F-S3-S2-1 buried-ask rule — pinned ONCE here, two consumers: the voice-reply fallback and S3's
bubble rendering) — presentation stays with S3/S4; the SIGNAL is S2's.

**Backfill mapping (F-S2-S2-2)**: the OSQ-4 backfill (`conversation()`, `:191`) returns
`ConversationMessage` (`notification_models.dart:158`) while windows hold `NotificationItem`
(`:51`) — and NEITHER alone carries everything the surface needs (`ConversationMessage` lacks
`voicePersona`/`responseOptions`; `NotificationItem` lacks `state`/`responseValue`). Mapping
mechanism: PREFERRED raw-passthrough — `NotificationItem.fromJson( msg.raw )` — CONTINGENT on an
implementation-Phase-0 fixture check that `raw` carries the full wire shape including
`response_options` and the response-state fields; if it does not, a THIN ADAPTER (view-model
wrapping `NotificationItem` + answered-state) is the fallback, and Task 1's "no new data models"
is amended accordingly. Answered/unanswered discriminator for backfilled prompts: a backfilled
ask is ANSWERED iff its source carries `state == responded` / non-null `responseValue`. User
replies appended by `FocusRespondRequested` are pinned to `type: user_initiated_message`
(existing enum, `notification_models.dart:56`) — S3's direction-styling discriminator.

No TTS-queue mirror: S3 renders pause state + held count directly from S1's
`pausedStream`/`queueDepth` — single source of truth. The architecture anchor's §3 "TTS-queue
mirror" entry was amended away (F-S2-3; S3's Stage-1 review confirmed it binds to S1's stream and
consumes no mirror).

### 3.2 Events

| Event | Source | Effect |
|---|---|---|
| `FocusInboundNotification(item)` | WS bridge in `app.dart` | upsert sender (append if new) → append to window (evict >7) → unread++ if not focused → emit; then `TtsOrchestrator.enqueueAlways(...)` (S1's ungated entry, F-S1-1) with the item's `voicePersona?.voiceId` — EVERY item, EVERY priority (Q6) |
| `FocusSenderSelected(senderId)` | S3 rail tap | set focused, zero its unread, trigger backfill if window not yet hydrated (OSQ-4) |
| `FocusColdStartRequested` | screen init AND WS reconnect (§3.3) | fetch via NotificationRepository → MODE-DEPENDENT: cold-start build vs reconnect-refresh MERGE (§3.1 reconnect-refresh paragraph, F-S2-S3-1) |
| `FocusPersonaUpdated(senderId, persona)` | WS `voice_persona_assigned`/`released` bridge | update badge data |
| `FocusRespondRequested(senderId, text, promptContext?)` | S3 inline-prompt taps; S4 `VoiceReplyField` send via S3-wired `onSubmit` callback | resolve target notificationId (F-S2-S2-3): `promptContext` is a TYPED `FocusPromptContext { notificationId, promptType? }` — inline prompts pass it explicitly; when absent (voice reply), fall back to `pendingPromptFor(senderId)` (newest `responseRequested && !responded`); if NO pending prompt resolves → NO repository call, debug log, state unchanged (defined non-crash outcome — S3 disables the composer off the same selector, making this path defensive). With an id: build `NotificationResponsePayload(notificationId, responseValue: text)` → `NotificationRepository.respond()`; append the user reply (`type: user_initiated_message`) to the window (evict >7); on failure set `hydration = error` (F-S3-2 — ONE bloc-mediated dispatch shape). `text` is a SINGLE String end-to-end: batch open-ended asks are scoped OUT of the focus inline path in v1 and route to the legacy sheet (F-S3-S2-2(d)) — this event never carries a Map |

### 3.3 Wiring

`app.dart` already bridges WS frames to the legacy bloc; add a parallel dispatch to
`FocusChatBloc` for `notification_queue_update` (same whitelist the legacy dispatch uses — the
`valid_types` doctrine) + persona events. Additionally, `app.dart` re-dispatches
`FocusColdStartRequested` on WS RECONNECT (freshness re-hydration — covers foreground WS drops in
Stage 1, and is the missed-message pull seam Stage 2's wake path terminates into, F-S5-1c).
Registered in `service_locator.dart`; same registration pass WITHDRAWS the legacy bloc's `tts`
injection (scope amendment, F-S2-1). Both blocs receive the same frames; legacy screens keep
their full visual function (Q1) — only speech ownership moves.

## 4. Tasks

- [ ] Models/state/events per §3 incl. `FocusRespondRequested` + typed `FocusPromptContext` +
      `pendingPromptFor` selector (reuse `NotificationItem`, `VoicePersona`; no new data models
      EXCEPT the typed prompt-context and — only if the Phase-0 raw-passthrough check fails — the
      thin backfill adapter per §3.1, F-S2-S2-2)
- [ ] Bloc handlers: inbound, select, cold-start/reconnect-refresh (mode-dependent merge,
      F-S2-S3-1), persona-update, respond
- [ ] Phase 0 (EXECUTOR: AI; F-S2-S3-3): (a) fixture-check that `msg.raw` carries
      `response_options` + response-state fields → DECIDES the §3.1 mapping branch
      (raw-passthrough vs thin adapter); (b) live-probe `senders()`/`conversation()` hours-param
      semantics (null = full history?) → pin as fixture (affects cold-start completeness +
      backfill depth)
- [ ] 7-item window eviction + insertion-ordered registry
- [ ] `app.dart` parallel dispatch + WS-reconnect re-hydration dispatch + DI registration +
      withdraw legacy `tts` injection (F-S2-1)
- [ ] TTS enqueue call-out via `enqueueAlways` with voiceId pipe-through
- [ ] Record green baseline suite count in §8 Execution Log BEFORE first edit (testing-strategy
      rule 1; F-S1-S3-2 family)
- [ ] Bloc tests (§5) + full-suite regression

## 5. Acceptance Criteria

- [ ] EXECUTOR: AI — AC-S2.1 blocTest: inbound from new sender appends to `senderOrder` END
      (establishment order preserved across 3 senders arriving B, A, C → order B, A, C).
- [ ] EXECUTOR: AI — AC-S2.2 blocTest: 8th message for a sender evicts the oldest; window length
      stays 7, newest-last.
- [ ] EXECUTOR: AI — AC-S2.3 blocTest: inbound for NON-focused sender increments its unread;
      focused sender's stays 0; viewport pointer (`focusedSender`) unchanged (Q4 invariant).
- [ ] EXECUTOR: AI — AC-S2.4 blocTest: `FocusSenderSelected` zeroes unread + sets focus + emits
      hydration=loading→ready when backfill fires (mock repository). Extended (F-S2-S2-2):
      backfilled-structured-ask fixture — an unanswered ask coming through the §3.1 mapping
      retains its `responseOptions` (chips renderable) and its answered/unanswered discriminator.
- [ ] EXECUTOR: AI — AC-S2.5 blocTest: EVERY inbound (low AND urgent) produces exactly one
      `enqueueAlways` call with the sender's voiceId (mock orchestrator; Q6 — re-targeted at the
      ungated surface per F-S2-2).
- [ ] EXECUTOR: AI — AC-S2.6 unit: cold-start ordering — `SenderSummary` fixture with interleaved
      `lastActivity` values rebuilds the registry `lastActivity` DESC (OSQ-3 as amended,
      F-S2-S2-1); a subsequent live arrival from a NEW sender APPENDS (snapshot never re-sorts).
- [ ] EXECUTOR: AI — AC-S2.7 regression: legacy NotificationBloc suite stays green — the bloc
      FILE is untouched (Q2); only `service_locator` withdraws its `tts` injection, and legacy
      unit tests construct the bloc with their own mocks, unaffected by DI registration.
- [ ] EXECUTOR: AI — AC-S2.8 service-integration (F-S2-1): one `notification_queue_update` frame
      through the real `app.dart` wiring → EXACTLY ONE orchestrator enqueue across BOTH blocs
      (FocusChatBloc's `enqueueAlways`; legacy path silent because `tts` is not injected) —
      single-dispatch pin.
- [ ] EXECUTOR: AI — AC-S2.9 blocTest (F-S3-2, extended F-S2-S2-3 — three cases): (i) explicit
      id: event with typed `promptContext` → `respond()` called with THAT `notificationId`;
      (ii) resolved id: event without context, focused sender has ≥2 UNANSWERED asks in the
      fixture → `respond()` called with the NEWEST one's id (F-S2-S3-2 — discriminates the
      newest-selection rule, not just any-pending); (iii) no-prompt: event without
      context, NO pending ask → NO `respond()` call, no crash, state unchanged. All cases: a
      successful respond appends a `type: user_initiated_message` reply to the window;
      repository failure sets `hydration = error` (mock repository).
- [ ] EXECUTOR: AI — AC-S2.10 (F-S5-1c seam; extended F-S2-S3-1): WS reconnect triggers a
      `FocusColdStartRequested` re-dispatch (mock WS service through the app-level wiring).
      Reconnect-refresh fixture asserts the FULL merge contract: existing sender order preserved
      (no re-sort), new sender APPENDED, windows merge-deduped by notification id (no duplicates;
      cap 7 newest-last), unread counts preserved for existing senders, `focusedSender`
      unchanged.

## 6. Open Items

OSQ-3 (cold-start ordering) and OSQ-4 (backfill source) — anchored in 02-decisions.md with
proposed answers; cascade to ratify.

## 7. Revision Log

- **2026-06-12 (Stage-1 close, findings F-S2-1..3 + cross-section threads)**: F-S2-1
  (inconsistency, CONCUR with Sam's DI-seam) — scope amendment: withdraw legacy `tts` injection in
  `service_locator`; bloc file untouched, Q2 literal; AC-S2.8 single-dispatch integration pin
  added. F-S2-2 (inconsistency) — §3.2 call-out + AC-S2.5 re-targeted at S1's `enqueueAlways`
  (F-S1-1 consumer side); Consumes line now names the S1 edge. F-S2-3 (inconsistency, CONCUR
  amend-the-anchor) — no-mirror note added §3.1; 01-architecture §3 row amended. F-S3-2 resolution
  (cross-section) — NEW `FocusRespondRequested` event + AC-S2.9; Provides line amended. F-S5-1c
  seam — WS-reconnect re-hydration added to §3.3 + AC-S2.10.
- **2026-06-12 (Stage-2 close, findings F-S2-S2-1..3)**: F-S2-S2-1 (inconsistency, CONCUR
  option (c) + author sort-direction ruling DESC) — cold-start = one-time `lastActivity` DESC
  snapshot from the single `senders()` fetch; OSQ-3 amended in 02-decisions.md with the
  documented approximation; AC-S2.6 re-targeted. F-S2-S2-2 (inconsistency, cross-section, CONCUR
  full set) — §3.1 backfill-mapping paragraph (raw-passthrough contingent on Phase-0 fixture
  check, thin-adapter fallback); answered/unanswered discriminator declared; user replies pinned
  `type: user_initiated_message`; Task-1 wording honest; AC-S2.4 extended. F-S2-S2-3
  (inconsistency, cross-section, CONCUR all four) — typed `FocusPromptContext{notificationId}`;
  voice-reply fallback = `pendingPromptFor(senderId)` (newest `responseRequested && !responded`);
  no-prompt = defined non-crash outcome with the selector as S2's contract-signal; AC-S2.9
  extended to three cases; S3/S4 touchpoints applied same round.
- **2026-06-12 (S3 Stage-2 merge amendment, F-S3-S2-1/-2)**: `pendingPromptFor` documented as
  the single pinned selector with two consumers (voice-reply fallback + S3 buried-ask bubble
  rendering); `FocusRespondRequested.text` annotated single-String end-to-end — batch asks
  scoped out of the focus inline path v1 (F-S3-S2-2(d)), the event never carries a Map.
- **2026-06-12 (F-S1-S3-2 family fix, doc-set-wide)**: §8 Execution Log placeholder + baseline
  task line added (working-contract §Phase-Complete + testing-strategy rule 1).
- **2026-06-12 (Stage-3 close, findings F-S2-S3-1..4)**: F-S2-S3-1 (inconsistency,
  cross-section, CONCUR Cheech's merge sketch as baseline) — reconnect-refresh mode made
  explicit in §3.1 (existing order kept, new senders append, merge-dedupe by id, unread
  preserved, focus unchanged, `pendingPromptFor` pure derivation); event row updated; AC-S2.10
  extended to the full merge contract. F-S2-S3-2 (cosmetic) — AC-S2.9(ii) fixture now carries
  ≥2 unanswered asks asserting newest-id selection. F-S2-S3-3 (cosmetic) — Phase-0 task line
  owns both declared probes (msg.raw fixture-check; hours-param live-probe). F-S2-S3-4 —
  pre-closed by the 02:28Z doc-set-wide execution-log family pass; no work.

## 8. Execution Log

*(Placeholder per working-contract §Phase-Complete Definition + testing-strategy rule 1 —
populated at implementation time, NOT during the cascade.)*

- [ ] Green baseline suite count recorded BEFORE first edit: `____` (date/time, command, count)
- Per-AC evidence entries land here as each §5 checkbox flips to `[x]` (test output, probe
  response, or named HUMAN sign-off).
