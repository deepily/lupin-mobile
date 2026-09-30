# Cascade Revision Handoff — focus-mode-voice-chat

**Artifact**: Step-9 revision-handoff doc (review-cascade single-artifact flavor, per
planning-is-prompting `workflow/plan-review-cascaded.md` §9.1)
**Cascade**: `cascade-focus-mode` — closed 2026-06-12T03:09:22Z
**Author**: Mr. Radio 🦉 (Manager, session `dabf7fbb`), 2026-06-12
**State at authoring**: `cascade_complete` → this doc + cold-context test + light review (Arnold 🪨)
flips `implementation_handoff_ready`

---

## §1 Purpose + cross-reference to the input plan

This doc is the single bridge between the closed cascade and the implementer. **The cascade ran in
live-revision mode: every ratified revision is ALREADY APPLIED to the section files by the Author
(Tiffany 💍).** The doc-set at `src/rnd/2026.06.11-focus-mode-voice-chat/` is therefore the
**current, implementation-ready plan-of-record** — an implementer reads the section files as they
stand and this handoff doc, and needs NOTHING from the cascade topic files.

- Input plan: [00-index.md](00-index.md) (master index + DAG) with shared anchors
  [00-working-contract.md](00-working-contract.md), [01-architecture.md](01-architecture.md),
  [02-decisions.md](02-decisions.md) (FROZEN Q1–Q11 + 7 ratified OSQs),
  [03-testing-strategy.md](03-testing-strategy.md)
- Section files: 10-s1 (TTS pause/resume) · 11-s2 (FocusChatBloc) · 12-s3 (Focus UI) ·
  13-s4 (voice→ASR) · 14-s5 (FCM mobile) · 15-s6 (FCM backend interface)
- Escalation companion: [20-fcm-background-isolate-explainer.md](20-fcm-background-isolate-explainer.md)

**What "implement" means here**: execute each section's §Tasks against its §Acceptance Criteria,
recording evidence in its §Execution Log. No plan revision remains to be applied.

## §2 Cascade telemetry

Closure metrics (from the `cascade_complete` post, topic `cascade-focus-mode-input-plan`, 03:09:22Z):

| Metric | Value |
|---|---|
| Sections closed | 6/6 × 3 stages (usability/reuse → viability/gap → ownership) |
| Findings processed | ~43 (Stage-1: 17 · Stage-2: 13 + 1 spot-check · Stage-3: 12) |
| Re-litigation rounds | every round closed in ONE pass |
| Votes called | 0 |
| User rulings | 2 (F-S1-1, F-S5-S2-1) |
| OSQs ratified | 7/7 (OSQ-1/4/5/7 straight; OSQ-2/3/6 as-amended) |
| Foundational findings unresolved | 0 |
| Cast | 1 author (rotated once, memento-seeded) · 3 reviewers (1 reaped EOL post-completion) · 1 observer/steward |
| Incidents survived | manager /clear + rehydration · ~35-min platform tool outage · 1 worker seat-freeze · 2 false-positive fleet-stall alarms |

Per-section findings by stage:

| Section | St1 | St2 | St3 | Notable |
|---|---|---|---|---|
| S1 TTS pause/resume | 4 | 3 | 3 | F-S1-1 USER-RULED; ACs 6→12-equivalent; OSQ-5 ratified |
| S2 FocusChatBloc | 3 | 3 | 4 | OSQ-3 amended+ratified; OSQ-4 ratified |
| S3 Focus UI | 2 | 3 (+delta re-verify, 0 new) | 2 | provisional-plus-delta disposition discharged |
| S4 Voice→ASR | 3 | 1 | 2 | OSQ-1 + OSQ-2 ratified |
| S5 FCM mobile | 2 | 1 (+ spot-check micro-amendment) | 1 | F-S5-S2-1 USER-RULED reshape; AC-S6.5 re-verify 6/6 |
| S6 FCM backend | 2 | 2 | 2 | OSQ-6 + OSQ-7 ratified |

Verbatim-accept rate: high — the Author CONCURred with reviewer-proposed fixes verbatim or
near-verbatim on the large majority of findings (per-finding stamps live in each section topic's
`manager_classification` posts; not needed for implementation).

## §3 Per-section revision summary

Format per section: severity tally → headline applied revisions → documented-not-revised
stragglers → escalations/ratifications → AC impact → **shared-state watch-pairs** (cross-component
mutable-state surfaces an implementer must hold in mind together; unit tests structurally cannot
catch these pair-wise).

### §3.1 S1 — TTS pause/resume (`10-section-s1-tts-pause-resume.md`)

- **Findings closed**: 10 — foundational 1 (F-S1-1) · inconsistency 5 · cosmetic 4.
- **Headline applied revisions** (all in §3/§5/§6 of the section file + 01-architecture §1/§2/§4.1):
  `enqueueAlways()` ungated TTS path; FocusChatBloc = SOLE TTS dispatcher (legacy dispatch disabled
  via S2's DI-seam withdrawal — legacy bloc file untouched, Q2-literal); non-destructive urgent
  preempt with replay-from-start on the focus path; paused multi-urgent ordering (urgent block
  arrival-ordered, inserts behind leading urgents; no urgent-preempts-urgent); legacy path declared
  pause-EXEMPT BY DESIGN; `queueDepthStream` added for S3's held-count banner; wire-grounded stop()
  semantics (`streaming_tts_player.dart:162-165`, `:169-176`, `:242-249`) + utterance-epoch
  re-entry guard.
- **Stragglers**: none section-local. Perceptual TTS-pacing gate rides S3's on-device runbook
  (F-S1-S3-3 pointer in §6 — EXECUTOR: HUMAN, enumerated by S3).
- **Escalations/ratifications**: F-S1-1 USER-RULED ("ungated path + sole dispatcher"); OSQ-5
  cascade-ratified (pause-absolute, utterance-boundary; recorded in 02-decisions.md).
- **AC impact**: 6 → 11 ACs + Execution-Log gate (AC-S1.3 re-worded to the real completion seam;
  AC-S1.4/S1.7 extended for multi-urgent + epoch guard; AC-S1.9 legacy parity incl.
  legacy-urgent-while-paused = preempts; AC-S1.10 error-while-paused; AC-S1.11 queueDepthStream).
- **Watch-pairs**: (a) TtsOrchestrator internal queue ← written by BOTH the focus path
  (`enqueueAlways`) and the pause-exempt legacy path — assert both behaviors in the same test
  fixture, not separately; (b) `_tryStartNext()` pause gate × urgent-preempt logic — the resume
  drain and the preempt replay touch the same head-of-queue state.

### §3.2 S2 — FocusChatBloc (`11-section-s2-focus-chat-bloc.md`)

- **Findings closed**: 10 — foundational 0 · inconsistency 7 · cosmetic 2 · pre-closed 1
  (F-S2-S3-4, discharged by the doc-set-wide execution-log family pass; severity moot).
- **Headline applied revisions**: DI-seam scope amendment (withdraw legacy `tts` injection in
  `service_locator` — the F-S1-1 mechanism); AC-S2.5 re-targeted at S1's `enqueueAlways`;
  cold-start ordering = one-time `lastActivity` DESC snapshot from the single `senders()` fetch
  (OSQ-3 as-amended — the original earliest-timestamp mechanism was unimplementable); backfill
  mapping = raw-passthrough CONTINGENT on the Phase-0 `msg.raw` fixture check (thin-adapter
  fallback documented); typed `FocusPromptContext{notificationId}`; `pendingPromptFor(senderId)`
  selector (newest `responseRequested && !responded`) pinned ONCE in S2 with two declared
  consumers; NEW `FocusRespondRequested` event (single-String `text` end-to-end);
  WS-reconnect re-hydration (`FocusColdStartRequested`) with the full Stage-3 merge contract
  (order kept, new senders append, dedupe by id, unread preserved, focus unchanged).
- **Stragglers**: none.
- **Escalations/ratifications**: OSQ-3 RATIFIED-AS-AMENDED (documented approximation: NOT
  establishment order on cold start; rail never re-sorts live — Q7 intent preserved in practice);
  OSQ-4 RATIFIED (backfill on first focus, window capped at 7).
- **AC impact**: AC-S2.4 extended (mapping discriminators); AC-S2.5/S2.6 re-targeted; AC-S2.8
  single-dispatch integration pin; AC-S2.9 three-case prompt dispatch (fixture with ≥2 unanswered
  asks asserting newest-id selection); AC-S2.10 full reconnect-merge contract.
- **Watch-pairs**: (a) `pendingPromptFor` — ONE selector, TWO consumers (S4 voice-reply fallback +
  S3 buried-ask bubble): any change must re-verify both; (b) sender registry ← written by
  cold-start snapshot AND live arrivals AND reconnect merge — three writers, one ordered map;
  (c) the 7-item window × backfill dedupe (id-keyed) on reconnect.

### §3.3 S3 — Focus UI (`12-section-s3-focus-ui.md`)

- **Findings closed**: 7 (+1 delta re-verify pass, 0 new) — foundational 0 · inconsistency 5 ·
  cosmetic 2.
- **Headline applied revisions**: prompt bodies extract-to-shared (public `prompt_bodies.dart` +
  injected `onRespond`; legacy-presentation touch DECLARED, AC-S3.9 legacy-sheet regression);
  ALL responses (inline prompts + S4 `onSubmit`) dispatch via S2's `FocusRespondRequested`;
  route-swap seam pinned exactly (`AuthGate( authenticatedChild: ... )`, `app.dart:139-141`);
  held-count banner consumes S1's `queueDepthStream`; buried-ask rule (buttons attach to newest
  UNANSWERED ask via `pendingPromptFor`); batch asks scoped OUT of inline rendering v1 (fallback
  affordance → legacy sheet); cold-start empty-state hint + loading spinner + error retry banner
  (AC-S3.10); runbook task now OPERATIVE — a NEW EXECUTOR: AI task authors the on-device
  "Focus-mode milestone gate" runbook section with three riders (S1 TTS-pacing; S4 transcript
  quality ≤2 word errors; OSQ-3 boot-order note).
- **Stragglers**: auto-focus on cold start DECLINED (F-S3-S2-3 Q4-LITERAL — author's call on the
  record; one rail tap is the entire cost); auto-follow-blocking-asks remains the documented v1.1
  candidate (Q4).
- **Escalations/ratifications**: none user-level; provisional-plus-delta disposition (Arnold's S2
  review raced a hold order) discharged clean — delta re-verify found 0 new findings.
- **AC impact**: AC-S3.5 (live held-count), AC-S3.6 re-pinned at the event + buried-ask sub-case,
  AC-S3.8 enumerates bound checkpoints (testing-strategy §Cross-Section 1–3 green; item 4 = the
  separate HUMAN checkbox), AC-S3.9, AC-S3.10 new.
- **Watch-pairs**: (a) `prompt_bodies.dart` ← consumed by BOTH the legacy InteractivePromptSheet
  and the new bubble rendering — AC-S3.9 exists precisely for this pair; (b) default-route swap ×
  drawer demotion (`app.dart` AuthGate child + drawer routes touch the same navigation table).

### §3.4 S4 — Voice input → ASR (`13-section-s4-voice-input-asr.md`)

- **Findings closed**: 6 — foundational 0 · inconsistency 4 · cosmetic 2.
- **Headline applied revisions**: `record` package justified on the record (flutter_sound =
  DI-dead legacy + streaming-oriented; flagged REMOVAL-CANDIDATE DEBT); §4.1 divergence sentence +
  shared-Dio seam + MP3-trap disarm annotation (`/api/upload-and-transcribe-mp3` queues a
  multimodal job — WRONG endpoint for chat replies); permission task = verify-not-add
  (manifest `:5`, permission_handler `:29`); VoiceReplyField re-shaped to `onSubmit` callback —
  dispatch lives in S2's event; `transcribing` state gains failure exit + cancel exit (no
  spinner-trap); `sending` state DROPPED (orphaned by the onSubmit re-shape); AC-S4.7 re-worded to
  POST-the-checked-in-fixture (no live mic on the dev server) + fixture-creation task added
  (synthesized known-content speech → OSQ-2 params → provenance block → `test/fixtures/asr/`);
  `voiceReplyError` TestKey; 200-empty-transcript → typed AsrException.
- **Stragglers**: flutter_sound removal rides the legacy-stack retirement (TODO.md debt item —
  see §5 fold bundle).
- **Escalations/ratifications**: OSQ-1 RATIFIED (probe-as-resolution); OSQ-2
  RATIFIED-AS-AMENDED (record-package justification).
- **AC impact**: AC-S4.1 + AC-S4.7 carry same-line OSQ-2 conditionality clauses; AC-S4.2 extended
  (empty-transcript exception); AC-S4.4 re-pinned (onSubmit); NEW AC-S4.8 (failure/cancel exits).
- **Watch-pairs**: (a) composer availability — S3 presentation gated off S2's `pendingPromptFor`
  signal (three sections meet at one widget seam: S4 owns the widget, S2 owns the signal, S3 owns
  the gating); (b) AsrService × shared Dio client (auth headers ride the shared instance).

### §3.5 S5 — FCM silent-relay mobile (`14-section-s5-fcm-silent-relay-mobile.md`)

- **Findings closed**: 4 + 1 spot-check micro-amendment — foundational 1 (F-S5-S2-1) ·
  inconsistency 2 · cosmetic 1 (+1 comparison-caught Stage-3).
- **Headline applied revisions**: **F-S5-S2-1 USER-RULED RESHAPE to shape (2)
  "handler-does-the-work"** — §1/§2/§3.2.4 re-specified to the 2026.04.21 §Option A′ chain
  (background isolate fetches + speaks). Embedded directives in operative text: handler NEVER
  touches the WS (each push = independent wake→fetch→speak; reconnect stays foreground-lifecycle);
  message-field-only TTS, audio best-effort, durable store + re-hydration = zero data loss, NO
  auto re-speak on pickup (badges carry it). Self-contained dependency bootstrap; login-hook seam
  named; **bootstrap auth corrected (Arnold spot-check): handler reads the REFRESH token from
  secure storage and exchanges it for an access token** (access token is memory-only,
  `auth_token_provider.dart:14` — never exists in a fresh isolate); reuse seams named (reconnect
  pokes `WebSocketService` machinery; next-resume hooks `AppLifecycleService`; missed-message pull
  rides S2 §3.3 — integration seam, NOT a section dependency); `--dart-define=ENABLE_FCM`
  default-OFF (grep-able, AC-S5.4); token re-register-on-WS-reconnect (idempotent upsert);
  §3.1 contract restatement COMPLETED per the failed-then-fixed AC-S6.5 comparison (DELETE
  unregister endpoint + response shape + absent-means-web rule + `android.priority: HIGH`).
- **Stragglers**: IsolateNameServer foreground-poke DEFERRED to v1.1 (author's call on the record:
  version-pin risk `flutter#113825`; pickup path covers it).
- **Escalations/ratifications**: F-S5-S2-1 USER-RULED (verbatim on the section topic 02:50Z),
  gated by the Phase-0 on-device probe — **probe MUST exercise the refresh→access exchange path
  and measure TTS-survives-handler-completion; failure ⇒ shape-3 fallback WITH evidence**.
  Research grounding: `20-fcm-background-isolate-explainer.md`.
- **AC impact**: AC-S5.1 same-line OSQ-6 conditionality; AC-S5.2 extended twice (lifecycle +
  DELETE consumption); AC-S5.3 re-targeted at the new mock seams (zero service-locator access,
  prefs gate, message-field-only, exchange-path bootstrap); AC-S5.4 grep-able flag; AC-S5.5
  client-type auth payload; HUMAN doze gate re-worded (no auto re-speak on pickup).
- **Watch-pairs**: (a) **durable notification store ← written by the background isolate handler,
  read by foreground re-hydration** — the cascade's highest-risk shared surface (cross-isolate,
  no shared memory; store is the only bridge); (b) token registry lifecycle — THREE writers
  (`onTokenRefresh`, login hook, WS-reconnect re-register), one parent-side row (idempotent upsert
  is the invariant); (c) FCM handler × notification prefs gate (prefs are the ONLY background
  gate — see §5 known-v1-behavior record).

### §3.6 S6 — FCM backend interface (`15-section-s6-fcm-backend-interface.md`)

- **Findings closed**: 6 — foundational 0 · inconsistency 4 · cosmetic 2.
- **Headline applied revisions**: NEW §3.0 WS client-type marker (`client_type: "mobile"` in
  `auth_request`; ABSENT ⇒ web); trigger re-worded to "no live MOBILE WS" (a desktop browser must
  NOT suppress the phone's wake); two-Firebases separation (real FCM admin init ≠ `auth.py:17-22`
  auth mock); durable token storage REQUIRED parent-side (in-memory unacceptable; AC-S6.1 pins
  mechanism (b) re-instantiate-from-store — write-through-cache implementations must FAIL the
  test); `reason` two-value enum pinned S6-side; Arnold's three parent residuals folded into §4
  (bare-id side-map clause; queue-WS-not-audio-WS trigger precision; reason value-semantics);
  AC-S6.5 comparison surface enumerated element-wise + tag split per instant (cascade-close =
  DONE, PASS 6/6 at 03:07Z; **implementation-start re-run = PARENT session, still owed**).
- **Stragglers**: DELETE-with-body proxy-fragility flag carried to parent design (recorded §3.1).
- **Escalations/ratifications**: OSQ-6 RATIFIED-AS-AMENDED (endpoint shape + client-type marker +
  durability + propagation rule); OSQ-7 RATIFIED (Firebase console = EXECUTOR: HUMAN — the one
  genuinely-human step; AI prepares click-path + validates config after).
- **AC impact**: AC-S6.1 restart-survival + mechanism pin + OSQ-6 same-line conditionality;
  AC-S6.2 web-doesn't-suppress case; AC-S6.3 reason enum; AC-S6.5 split-instant contract check.
- **Watch-pairs**: (a) S5 §3.1 ↔ S6 §3 — the TWO-FILE CONTRACT (any §3 element change requires
  same-round propagation + AC-S6.5 element-wise re-comparison); (b) token registry × WS
  connection-state map (the trigger policy reads both).

## §4 Cross-section ratification summary

**Survived the cascade intact**: Q1–Q11 (all FROZEN decisions untouched); the 6-section DAG
(one edge ADDED: S1→S2 `enqueueAlways`, F-S1-1/F-S2-2); the stage boundary (S5/S6 independent of
Stage 1 — re-affirmed by the F-S5-1c clarifying amendment: the missed-message pull is an
integration seam, not a dependency); the executor split; the coverage bar (baseline-never-decreases
+ 44-test quarantine untouched).

**Retired/dropped during the cascade**: TTS-queue mirror in the architecture anchor (F-S2-3);
S4 `sending` state (F-S4-S2-1(b)); earliest-timestamp cold-start mechanism (OSQ-3 original —
unimplementable, replaced by `lastActivity` DESC snapshot); batch asks from the inline v1 path
(F-S3-S2-2(d)); auto re-speak on FCM pickup (author-ruled out); IsolateNameServer poke (deferred
v1.1); shape-1/shape-3 background-isolate designs (superseded by the user-ruled shape-2;
shape-3 remains the documented Phase-0-failure fallback).

**Cross-section contract surfaces pinned**: `enqueueAlways` (S1→S2); `FocusRespondRequested`
single-String event (S2←S3/S4); `FocusPromptContext` + `pendingPromptFor` (S2→S3/S4);
`queueDepthStream` (S1→S3); `onSubmit` callback (S4→S3); S5 §3.1 ↔ S6 §3 two-file FCM contract
incl. client-type marker; token-registry lifecycle (S5 three-writer registration ↔ S6 durable
store + DELETE unregister — see §3.5/§3.6 watch-pairs).

## §5 Post-cascade fold bundle

Items that fold OUTSIDE the section files; each names its owner + instant:

1. **TODO.md debt item** — `flutter_sound` REMOVAL-CANDIDATE (rides legacy-voice-stack
   retirement; OSQ-2 amendment). Owner: Manager; single instant: implementation close-out
   (filed to TODO.md then).
2. **Known v1 behavior (USER-INFORMED, on the record)**: a PAUSED focus session does NOT gate FCM
   background speech — a pocketed paused phone still speaks on wake; notification prefs are the
   only background gate. Told to Rick at cascade close; no design change owed in v1.
3. **AC-S6.5 implementation-start re-run** — owner: PARENT-Lupin session (Tiberius's work order,
   §3.6); instant: before parent-side first edit.
4. **On-device runbook** — "Focus-mode milestone gate" session: AI authors (S3 task), HUMAN
   executes on the laptop; carries the three riders (S1 TTS-pacing; S4 ≤2-word-error transcript
   bar; OSQ-3 boot-order note).
5. **OSQ-7 Firebase console provisioning** — EXECUTOR: HUMAN (Rick); AI prepares click-path
   instructions + validates `google-services.json` placement after.
6. **Parent design flag** — DELETE-with-body proxy fragility (S6 §3.1) — owner: Tiberius's
   parent design pass.

## §6 Workflow-guidance candidates — brief index

Manager close-out self-audit sweep (cold-context rubric Q#6) — 10 candidates accumulated across
the cascade, each with empirical anchor; deep redline is PIP-side work, NOT implementer work.
Posted as `kind: manager_self_audit_sweep` on `cascade-focus-mode-input-plan` (2026-06-12).

1. Topic-post standing dispatches are LOSSY — DM is the only reliable worker wake (anchor:
   Arnold's 13-min stall). Fold: common.md §worker-dispatch.
2. Manager batched `manager_classification` per-SECTION with per-finding stamps in the body —
   context-economy deviation from the 6-field-per-finding schema; worked well (anchor: all 6
   sections). Fold: defaults.md §kind schema.
3. `ask_multiple_choice` timeout_seconds caps at 600 — long user-gates need re-ask loops
   (anchor: F-S5-S2-1 escalation). Fold: cosa-voice integration notes.
4. Stream-error on a blocking ask can register an accidental rejection — verbatim re-send
   recovered (anchor: first F-S5-S2-1 ask). Fold: common.md §escalation mechanics.
5. Auto-mode classifier FALSE-POSITIVEs on relaying a user ruling it hadn't seen — quote the
   ruling VERBATIM with provenance metadata, never paraphrase (anchor: F-S5-S2-1 relay block).
   Fold: common.md §user-ruling relay.
6. Classifier blocks worker reap/dismiss on standing CLAUDE.md grants — needs the user's
   per-session word (anchor: 2 blocked dismissals tonight). Fold: manager-autonomy.md caveat.
7. ~35-min platform tool outage mid-cascade — pipeline survived via disk-state + resend
   discipline; arbiter WHOLE-FLEET-STALL alarms during outages are false positives, ack with
   progress evidence (anchor: 02:09/02:24Z alarms). Fold: common.md §failure-mode catalog.
8. Provisional-plus-delta disposition for a review racing a hold order — worked perfectly
   (anchor: Arnold's S3 Stage-2). Fold: common.md §disposition vocabulary.
9. Contract-comparison ACs need OWNERS + execution INSTANTS + sequencing (anchor: AC-S6.5 caught
   real 4/6 drift at exactly the designed moment). Fold: personas.md §Persona 5 conventions.
10. Worker rotation at >50% context: finish-current-item → memento → dismiss → respawn with
    seed_memento (anchor: Tiffany's textbook rotation; repeated post-cascade for Arnold + Cheech
    incl. a lost-overflow-persona wrinkle — voice slot died with the seat; user delegated
    re-voicing). Fold: manager-autonomy.md §rotation pattern.

## §7 Hand-off statement

**Mode**: implementer implements the input plan AS CASCADE-REVISED (no revision application
remains — Author applied all ratified revisions live; this section is the implementer brief).

**Implementation order** (per 00-index DAG + user directive UI-first):

1. **Phase 0 (before ANY section's first edit)**: OSQ-1 auth probe + OSQ-2 format probe
   (S4 §3, dev server, `LUPIN_TEST_INTERACTIVE_MOCK_JOBS_*` creds); `msg.raw` fixture check
   (S2 — decides raw-passthrough vs thin-adapter); hours-param live probe (S2); synthesized
   canned-WAV fixture (S4, `test/fixtures/asr/` with provenance block).
2. **Stage 1, section order S1 → S2 → S4 → S3.** Per section: record green baseline suite count
   in §Execution Log BEFORE first edit → implement §Tasks → `./flutter.sh analyze` + `test`
   green → per-AC evidence into §Execution Log.
3. **Stage 2**: S5 mobile (ENABLE_FCM default-OFF; §3.2.4 chain gated on the Phase-0 on-device
   probe — laptop/HUMAN executes, AI authors; probe must exercise refresh→access exchange +
   measure TTS-survives-handler-completion; failure ⇒ shape-3 fallback with evidence) + S6 parent
   work order to the parent-Lupin session (cite 15-section-s6 §4 — self-contained; AC-S6.5
   implementation-start re-run owed there).
4. **Cross-cutting gates**: testing-strategy §Cross-Section items 1–3 (AI) + item 4 = the
   on-device "Focus-mode milestone gate" runbook session (HUMAN, scripted by the S3 runbook task).

**Standing rules binding the implementer** (Recon checklist, restated):

1. lupin-mobile is a STANDALONE nested repo — NO git commands by any worker; Rick drives commits.
2. Every repo Edit/Write logged in `.claude-session.md` under YOUR session section.
3. Executor split: `./flutter.sh analyze` + `test` on the dev server (AI); APK/emulator/device =
   laptop (HUMAN with reason).
4. Q1–Q11 are FROZEN; OSQ-1..7 are now ALL RATIFIED — re-opening any requires a user ruling.
5. Wire-grounding doctrine: server-contract claims cite file:line or live capture; hand-authored
   fixtures are findings.
6. No time-of-day gating on spawns/work (user struck the off-peak rule).
7. Coverage bar: parent Lupin's 100% mandate does NOT apply (excluded sub-repo); operative bar =
   green baseline never decreases + 44-test quarantine untouched + every section's enumerated
   tests added.
8. Test-automation default: widget-test BLoC-driven flows first; device verifies only what
   hardware alone can.

**Conditional-executability registry** (every "verify on the wire" item, tagged):

| Item | Tag | Resolution branch |
|---|---|---|
| OSQ-1 auth contract | NEW, conditional | Phase-0 probe pins fixture; ACs S4.1/S4.7 carry same-line clauses |
| OSQ-2 recording params | NEW, conditional | Phase-0 probe mirrors web client; same-line clauses on AC-S4.1/S4.7 |
| S2 backfill mapping | NEW, conditional | `msg.raw` fixture check → raw-passthrough OR thin-adapter (both designed) |
| S2 hours-param | NEW, conditional | live probe; fetch-depth documented either way |
| S5 §3.2.4 chain | CARRIED with caveat | on-device probe (HUMAN) → shape-2 confirmed OR shape-3 fallback with evidence |
| AC-S6.5 impl-start re-run | CARRIED | parent session, before parent first edit |
| OSQ-7 console | CARRIED, HUMAN | click-path doc + AI config validation after |

All other Recon items: RESOLVED (ratified OSQs 1–7) or RETIRED (see §4 retired list).

---

*Step-9 closure flow: Manager cold-context self-test (6-question rubric) → light review
(Arnold 🪨, 5+1-criterion focused rubric, 1-revision-turn cap) → `implementation_handoff_ready`
state-flip on `cascade-focus-mode-input-plan`.*
