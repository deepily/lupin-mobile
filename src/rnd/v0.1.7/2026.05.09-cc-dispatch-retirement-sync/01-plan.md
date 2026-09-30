# [LUPIN-MOBILE] Claude Code Dispatch Retirement Sync — Migrate to Canonical Submit Endpoint

**Status**: ✅ Plan approved 2026-05-10; Phase 0 serialised; PIP plan-review GATE **CLEARED 2026-05-11** (REUSE + Pass 1 Fitness + Pass 2 Adversarial all converged); Phase 1 implementation unblocked.
**Pattern**: Pattern 5 (Refactor) — fires the canonical PIP plan-review gate per `$PLANNING_IS_PROMPTING_ROOT/workflow/plan-review.md`.
**Branch**: `wip-v0.1.6-2026.04.16-tracking-lupin-work`
**last-reviewed-at**: 2026-05-11 (commit-hash: pending — placeholder until session commit; per `plan-review.md` §12 idempotency marker)
**Source draft**: `~/.claude/plans/piped-tumbling-quiche.md` (retained as draft history; this serialised copy is canonical)

---

## Context

**Why this change**: Parent Lupin retired 6 Claude Code dispatch endpoints on 2026-05-05 (commit `73bee1b`, plan at `<lupin>/src/rnd/v0.1.7/2026.05.05-claude-code-dispatch-retirement/01-plan.md`). The mobile app at `lib/features/claude_code/data/claude_code_repository.dart` still calls 5 of them and will receive HTTP 404 against any post-retirement Lupin server.

**Canonical submission endpoint** (per user direction 2026-05-10): `POST /api/claude-code/submit` (JWT, cj-flow). Mobile currently calls the longer-form `POST /api/claude-code/queue/submit` via `queueSubmit()` — this URL is the version live on `:7999` at the time of investigation, which lags the canonical state. User confirmed 2026-05-10: *"the fast API endpoint is being implemented in parallel: /api/claude-code/submit"*. The mobile cutover targets the canonical path; if the rename hasn't propagated to a given Lupin server, mobile receives the 404 correction loud-and-visibly (intentional per parent retirement strategy "obviously disable, don't silently mask").

This work tears out the dead paths, repoints mobile at the canonical submit URL, and visibly retires the orphaned INTERACTIVE UI.

**What's in flight (informational, wire-stable)**: A parent-side `ClaudeCodeJob` internal redesign began 2026-05-07 (`<lupin>/src/rnd/v0.1.7/2026.05.07-claude-code-bounded-redesign/`) — relocates `cosa/orchestration/claude_code/` → `cosa/agents/claude_code/`, adds `config.py` / `state.py` / `orchestrator.py` / `__main__.py` per canonical agentic-job pattern. **The wire shape (request + response body fields) is NOT changing**, only the URL is canonicalising. Q1 locked decision: BOUNDED with extensibility hooks; INTERACTIVE methods (`inject` / `interrupt` / `end_session`) will land as `NotImplementedError` stubs gated behind a future plan. So mobile-side INTERACTIVE controls cannot be migrated forward today — we mirror the parent retirement strategy ("obviously disable, don't silently mask") so any hidden dependency surfaces loudly via banners and 404s, not silent NoOps.

**Intended outcome**: Mobile posts Claude Code jobs only via `POST /api/claude-code/submit`. Five retired-endpoint callers are gone; mobile repository method is renamed `queueSubmit` → `submit` to match the canonical URL; INTERACTIVE UI surfaces show retirement banners with a CTA to the existing Queue Dashboard (where `cc-*` jobs already surface via the Tier 3 queue feature shipped 2026-04-16). The cumulative test baseline drops from 308 to ~300 as orphaned tests are pruned. The two pre-existing tracking docs that already carry retirement notices flip from "open" to "✅ DONE this session."

---

## Approach

Mirrors parent retirement plan §Phase 2. **Phasing**: Phase 0 documentation + 0.1/0.2/0.3 review GATE (no code) → Phases 1-5 implementation (all `:7999`-venue, AI-discretionary).

### Phase 0 — Plan serialization (DOCUMENTATION-FIRST PROTOCOL)

Serialise the approved plan from `~/.claude/plans/piped-tumbling-quiche.md` into the lupin-mobile `src/rnd/` tree at:

`src/rnd/v0.1.7/2026.05.09-cc-dispatch-retirement-sync/01-plan.md` (this file)

Companion `90-execution-log.md` scaffold created with phase-status table per `p-is-p-02-documentation` workflow (Pattern 3 single-design-doc shape — no Pattern A/B/C scaffolding for a plan this scoped). README link skipped: mobile project has no `src/rnd/README.md` yet (parent does); not creating one as a side-effect of this plan. Filed as a follow-up in execution log.

### Phase 0.1 — REUSE pre-pass (PIP plan-review §4)

Read-only investigation in this session. Per the canonical prompt: for each "new" thing this plan proposes (banner widget, retirement footnote, helper, model, route, etc.), grep the lupin-mobile codebase for prior art. Output the standard 3-column table (`New thing | Existing prior art (file:line) | Verdict`) with verdicts in `{reuse-as-is, extend-existing, genuinely-new}`. **Hard gate**: do not apply findings — deliver the table + wait for user approval. Resolution Loop applies approved fixes only.

Likely candidates to audit:
- "Retirement banner widget" — does `lib/shared/widgets/` already have a similar banner pattern (e.g., from any other deprecated-feature surface)?
- "Retirement footnote at top of class dartdoc" — pattern already used in `notification_models.dart` voice-persona breadcrumbs?
- "Banner CTA pushing to QueueDashboardScreen filtered to cc-*" — existing nav helper?
- "Retired test-pruning pattern" — has the project already retired test classes via in-place comment-out vs delete vs quarantine?

### Phase 0.2 — Pass 1 Fitness review (PIP plan-review §5)

Read-only investigation in this session. Hunt the 8 deficiency types (AMBIGUITY, COMPLETENESS, TESTABILITY, ORDERING, DECISION TRACEABILITY, SCOPE, RISK SURFACE, EXTERNAL DEPENDENCIES) in this serialised plan. Run the standard greps (`TBD`, `confirm during impl`, `Open sub-question`). Output the 5-column findings table + explicit answers to any TBDs + a "Design concerns" section (mandatory, even if empty). **Hard gate** — findings only. Resolution Loop applies approved fixes only.

Anchors for this pass:
- **Layer 1**: `~/.claude/CLAUDE.md` TEST OWNERSHIP MANDATE + DOCUMENTATION-FIRST PROTOCOL
- **Layer 2**: none (no `00-working-contract.md` for this scoped plan; per `plan-review.md` §1 Layer 2 is optional)
- **Layer 3**: this plan's "Approach" section, with the recommendation to mirror parent retirement strategy as the design anchor

### Phase 0.3 — Pass 2 Adversarial review (PIP plan-review §8)

Read-only investigation in this session. Reuses Pass 1 working memory of the docs (do NOT re-read per `plan-review.md` §8 anti-pattern). Hunt every place "done" could be claimed without AI-executed verification, or where a reader would default to thinking "the user will do this step." Output the 4-column findings table. Run the three standard greps (`Manual\|manual`, `EXECUTOR: HUMAN`, `^- \[ \] [^E]`). **Hard gate** — findings only. Resolution Loop applies approved fixes only.

**Termination per §10**: Resolution Loop iterates until 0 new structural findings remain (only wording tweaks) OR 2 full rounds complete. Open issues parked into the execution log "Open follow-ups" if any.

After 0.3 closes: the gate is cleared. Phases 1-5 implementation may begin.

### Phase 1 — Strip retired methods from data layer + repoint at canonical URL

**`lib/features/claude_code/data/claude_code_models.dart` + `claude_code_repository.dart` — literal dartdoc footnote (F1 fix)**

Both files get the **same 3-line footnote** added to their top-of-file dartdoc / `library;` block — literal text:

```dart
/// Retired endpoints: see <lupin>/src/rnd/v0.1.7/2026.05.05-claude-code-dispatch-retirement/01-plan.md
/// Mobile-side breadcrumbs: src/rnd/v0.1.6-migration/2026.04.15-{tier-3-queue-and-claude-code-plan,resync-mobile-with-lupin-api-v0.1.6}.md
/// Canonical successor: POST /api/claude-code/submit (this file)
```

**`lib/features/claude_code/data/claude_code_repository.dart`** — delete 5 methods (`dispatch`, `getStatus`, `inject`, `interrupt`, `endSession`). Rename `queueSubmit` → `submit` and repoint URL from `/api/claude-code/queue/submit` → `/api/claude-code/submit`. Update class dartdoc to read "Typed wrapper over `POST /api/claude-code/submit` — canonical Claude Code job submission endpoint after the 2026-05-05 dispatch-cluster retirement." Add the literal 3-line footnote above.

**`lib/features/claude_code/data/claude_code_models.dart`** — delete `ClaudeCodeDispatchRequest`, `ClaudeCodeSession`, `ClaudeCodeInjectResponse`, `ClaudeCodeTaskType` enum. Rename `ClaudeCodeQueueRequest` → `ClaudeCodeSubmitRequest` and `ClaudeCodeQueueResponse` → `ClaudeCodeSubmitResponse` to match the canonical URL. Wire field set unchanged (request: `prompt` / `project` / `task_type` / `max_turns` / `websocket_id` / `dry_run` / `scheduled_at` / `monopolize`; response: `status` / `job_id` / `queue_position` / `message`). Keep `ClaudeCodeApiException`. Add the literal 3-line footnote above (same prose as repository).

**Forward-compat NOT scaffolded**: `ClaudeCodeSubmitResponse.transcriptPath` (the parent redesign's Q2 artifact field) is deliberately omitted — it doesn't exist server-side yet, and the `transcript_path` artifact lives on the completed-job record (queue feature surface), not on the submit response. Filed as a TODO follow-up for when parent Phase 4 ships.

### Phase 2 — Strip BLoC handlers, events, and states

**Pre-delete grep (F7 fix)** — `EXECUTOR: AI` — before touching any source, run:

```bash
grep -rE "ClaudeCodeDispatch\b|ClaudeCodePollStatus\b|ClaudeCodeInject\b|ClaudeCodeInterrupt\b|ClaudeCodeEnd\b|ClaudeCodeExternalMessage\b|ClaudeCodeActive\b|ClaudeCodeAwaitingInput\b|ClaudeCodeDone\b|ClaudeCodeQueued\b|ClaudeCodeDispatching\b" lib/ test/
```

**Expected**: hits ONLY inside `lib/features/claude_code/**`, `test/unit/claude_code/**`, `lib/app.dart` (the WS bridge to be removed in Phase 4), and `lib/core/di/service_locator.dart` (type-only `ClaudeCodeBloc` reference — unchanged by rename). If any hit appears outside those paths, halt and reconvene — there's a hidden consumer.

**`lib/features/claude_code/domain/claude_code_event.dart`** — delete `ClaudeCodeDispatch`, `ClaudeCodePollStatus`, `ClaudeCodeInject`, `ClaudeCodeInterrupt`, `ClaudeCodeEnd`, `ClaudeCodeExternalMessage`. Rename `ClaudeCodeQueueSubmit` → `ClaudeCodeSubmit` (consistent with canonical URL + new model names).

**`lib/features/claude_code/domain/claude_code_state.dart`** — delete `ClaudeCodeActive`, `ClaudeCodeAwaitingInput`, `ClaudeCodeDone`. Rename `ClaudeCodeDispatching` → `ClaudeCodeSubmitting` (semantics changed: no longer dispatches; only submits via the canonical endpoint). Rename `ClaudeCodeQueued` → `ClaudeCodeSubmitted` (matches naming; field type updates to `ClaudeCodeSubmitResponse`). Keep `ClaudeCodeInitial`, `ClaudeCodeError`.

**`lib/features/claude_code/domain/claude_code_bloc.dart`** — shrink to just `_onSubmit` handler (was `_onQueueSubmit`). Drop `_stateFromSession` helper. Drop 6 retired event registrations from constructor. Final shape: `Initial → Submitting → (Submitted | Error)`.

### Phase 3 — UI: retire INTERACTIVE controls visibly, BOUNDED-only entry

Per parent retirement plan §Phase 2 ("obviously disable, don't silently mask"):

**Banner color spec (F2 fix)** — all three screens (dispatch_sheet, chat_screen, session_list_screen) use the SAME inline banner widget. Color spec is **literal**, matching parent web's `.cc-retired-banner` CSS rule verbatim (single source of truth across web + mobile UIs):

```dart
Container(
  decoration: BoxDecoration(
    color: const Color( 0xFFFFF3CD ),                                  // warm yellow, matches parent web
    border: const Border( left: BorderSide( color: Color( 0xFFFF9800 ), width: 4 ) ),   // orange accent
  ),
  padding: const EdgeInsets.all( 12 ),
  child: Row(
    children: [
      const Icon( Icons.warning_amber_rounded, color: Color( 0xFFFF9800 ) ),
      const SizedBox( width: 12 ),
      Expanded( child: Text( "<retirement copy here>", style: const TextStyle( fontStyle: FontStyle.italic ) ) ),
    ],
  ),
)
```

**`lib/features/claude_code/presentation/dispatch_sheet.dart`** — remove the `SegmentedButton<ClaudeCodeTaskType>`. Default and only mode is now BOUNDED submit via canonical endpoint. `_dispatch()` always builds a `ClaudeCodeSubmitRequest` and dispatches `ClaudeCodeSubmit`. Add a `Card` at top of the sheet wrapping the F2 banner widget with copy: *"INTERACTIVE controls retired 2026-05-05. Returns when ClaudeCodeJob gains inject / interrupt / end_session. See parent retirement plan."* Drop the `ClaudeCodeTaskType` import.

**AppBar pre-enumeration (F3 fix)** — `EXECUTOR: AI` — before rewriting `chat_screen.dart`, capture the current AppBar shape so keep/drop is concrete:

```bash
grep -nE "AppBar\b|actions:|IconButton|PopupMenuButton" lib/features/claude_code/presentation/chat_screen.dart
```

Record the result in the execution log so the new (slimmed) AppBar can be diffed against the old one in code review. Expected: `title:` slot kept; `actions:` slot (if present) emptied of inject/interrupt/end controls.

**`lib/features/claude_code/presentation/chat_screen.dart`** — replace body with the F2 banner widget. Preserve the file + route entry (path-stable) so any leftover navigation surfaces the banner rather than crashing. AppBar contents follow the F3-enumerated keep/drop decision (default: keep `title`; drop all retired-control `actions:`).

**`lib/features/claude_code/presentation/session_list_screen.dart`** — same banner-only treatment. Add a CTA `FilledButton.tonal( "View Claude Code jobs in Queue dashboard" )` that pushes to `QueueDashboardScreen` (Tier 3, already shipped; `cc-*` jobs surface there).

### Phase 4 — WS bridge + constants cleanup

**Pre-delete grep (F7 fix)** — `EXECUTOR: AI` — before touching any source, run:

```bash
grep -rE "eventClaudeCodeMessage\b|eventClaudeCodeStateChange\b|claude_code_message\b|claude_code_state_change\b" lib/ test/
```

**Expected**: hits ONLY in `lib/core/constants/app_constants.dart` (the constants being deleted), `lib/app.dart` (the bridge being deleted), and the `claude_code/` BLoC tests being pruned in Phase 5. Any other hit (especially in `lib/services/websocket/`) is a hidden subscriber that must be reviewed before deletion.

**`lib/app.dart`** (lines 74-75 region) — delete the WS handler block that fires `ClaudeCodeExternalMessage` on `claude_code_message` / `claude_code_state_change` events. Both event names were emitted only by the retired `ws/{task_id}` endpoint; they no longer arrive. Keep the `BlocProvider<ClaudeCodeBloc>` registration (~lines 128-129) — the BLoC still serves submit. Job state-changes for `cc-*` jobs ride the existing `queue_*_update` events bridged into `QueueBloc`.

**`lib/core/constants/app_constants.dart`** (lines 50-51) — delete `eventClaudeCodeMessage` + `eventClaudeCodeStateChange` constants.

### Phase 5 — Tests + tracking docs

**Widget-test enumeration (F4 fix)** — `EXECUTOR: AI` — before any test pruning, confirm widget-test surface:

```bash
ls test/widget/claude_code/ 2>/dev/null
```

**Expected**: directory absent (confirmed during REUSE pre-pass — `test/widget/` has no `claude_code/` subdirectory). Document the result in execution log: "no widget tests for claude_code present; banner-treatment in Phase 3 introduces no widget-test regression." If non-empty at execution time (unlikely but verify), enumerate per-file decision (delete vs rewrite-to-test-banner) before proceeding.

**Test pruning** (`test/unit/claude_code/`):
- `claude_code_models_test.dart` — delete tests for `ClaudeCodeDispatchRequest` / `Session` / `InjectResponse` / `TaskType`. Keep tests for the renamed `ClaudeCodeSubmitRequest` / `SubmitResponse` shape + JSON round-trip; update test names to match.
- `claude_code_repository_test.dart` — delete tests for the 5 retired methods. Keep `submit` happy + error paths (was `queueSubmit`); update Dio mock URL to `/api/claude-code/submit`.
- `claude_code_bloc_test.dart` — delete tests for the 6 retired events. Keep `ClaudeCodeSubmit` (was `ClaudeCodeQueueSubmit`). Add 2 new blocTests covering the stripped state surface: `Initial → Submitting → Submitted` and `Initial → Submitting → Error`.

**Tracking docs**:
- `history.md` — append session entry under heading `## 2026.05.10 | Session c594308e — Claude Code dispatch retirement sync (mobile)` summarizing files modified, test delta, and the unblock for full v0.1.7 catch-up.
- `TODO.md` — close the implicit "catch up to parent v0.1.7" pending; file new forward-compat: *"When parent's ClaudeCodeJob redesign Phase 4 ships, expose `artifacts.transcript_path` link in QueueDashboardScreen job detail (cc-* job type)."* and *"When parent restores INTERACTIVE inject / interrupt / end_session, restore mobile chat_screen + session_list_screen UI (preserved as banners)."*
- `src/rnd/v0.1.6-migration/2026.04.15-tier-3-queue-and-claude-code-plan.md` — flip the "Action required (mobile session)" block from open to ✅ DONE with this session's commit hash + date.
- `src/rnd/v0.1.6-migration/2026.04.15-resync-mobile-with-lupin-api-v0.1.6.md` — flip the retirement-notice block from open to ✅ DONE.

---

## Critical files

**Create (Phase 0 serialisation)**:
- `src/rnd/v0.1.7/2026.05.09-cc-dispatch-retirement-sync/01-plan.md` (this file)
- `src/rnd/v0.1.7/2026.05.09-cc-dispatch-retirement-sync/90-execution-log.md` (phase-status table scaffold; populated as work progresses, including 0.1/0.2/0.3 review evidence)

**Modify (lib)**:
- `lib/features/claude_code/data/claude_code_repository.dart`
- `lib/features/claude_code/data/claude_code_models.dart`
- `lib/features/claude_code/domain/claude_code_event.dart`
- `lib/features/claude_code/domain/claude_code_state.dart`
- `lib/features/claude_code/domain/claude_code_bloc.dart`
- `lib/features/claude_code/presentation/dispatch_sheet.dart`
- `lib/features/claude_code/presentation/chat_screen.dart`
- `lib/features/claude_code/presentation/session_list_screen.dart`
- `lib/app.dart` (lines 74-75)
- `lib/core/constants/app_constants.dart` (lines 50-51)

**Modify (tests + docs)**:
- `test/unit/claude_code/claude_code_models_test.dart`
- `test/unit/claude_code/claude_code_repository_test.dart`
- `test/unit/claude_code/claude_code_bloc_test.dart`
- `history.md`
- `TODO.md`
- `src/rnd/v0.1.6-migration/2026.04.15-tier-3-queue-and-claude-code-plan.md`
- `src/rnd/v0.1.6-migration/2026.04.15-resync-mobile-with-lupin-api-v0.1.6.md`

**Reused (do not touch)**:
- `lib/services/network/http_service.dart` — Dio + JWT interceptor unaffected
- `lib/features/queue/` — Tier 3 dashboard already surfaces `cc-*` jobs; banner CTA points here
- `lib/services/websocket/` — WS routing unaffected (`queue_*_update` events still flow)
- `lib/core/di/service_locator.dart` lines 299-300 — `ClaudeCodeBloc(_repo)` registration still valid (BLoC shrinks but signature unchanged)

---

## Reuse references (existing utilities to call directly)

- `ClaudeCodeApiException` — existing in `claude_code_models.dart`; reuse for submit errors.
- Authenticated `Dio` instance — existing in `http_service.dart`; JWT interceptor handles auth header.
- `ClaudeCodeRepository.queueSubmit()` body shape — reuse the JSON mapping verbatim under the new method name `submit()` and new URL `/api/claude-code/submit`. Signature unchanged.
- For the retirement banner, search `lib/shared/widgets/` first; if no shared banner widget exists, inline a small `Container( color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.4), padding, child: Row[Icon(warning_amber), SizedBox, Expanded(Text)] )`. One-off retirement notice — not worth a new shared component.
- Request defaults already correct on the existing `ClaudeCodeQueueRequest`: `project: 'lupin'`, `taskType: 'BOUNDED'`, `maxTurns: 50`, `dryRun: false`, `monopolize: false` — preserve verbatim under the renamed `ClaudeCodeSubmitRequest`.

---

## Verification

**Phase 0 / 0.1 / 0.2 / 0.3 verification** (gate work, not code):
- Phase 0 close: serialised doc + execution-log scaffold land in `src/rnd/v0.1.7/2026.05.09-cc-dispatch-retirement-sync/`; lock-down + plan file in `~/.claude/plans/piped-tumbling-quiche.md` retained as draft history.
- Phase 0.1 close: REUSE findings table delivered; user-approved findings applied to this plan; "Prior art referenced" section appended to plan doc per `plan-review.md` §4. Re-grep convergence: zero unaddressed prior-art hits.
- Phase 0.2 close: Pass 1 findings table + TBD answers + Design concerns section delivered; user-approved findings applied; Resolution Loop re-grep zero new hits per `plan-review.md` §7.
- Phase 0.3 close: Pass 2 findings table delivered; user-approved findings applied; Resolution Loop converges. Idempotency marker `last-reviewed-at: 2026-05-10 (commit-hash)` recorded above + in execution log.

**Pre-Phase-1 gates (F6 fix — these MUST pass before any code change)**:

| Gate | Executor | Check | Command | Expected | If fails |
|------|----------|-------|---------|----------|----------|
| G1 | `EXECUTOR: AI` | Canonical URL live (401 sanity) | `curl -sS -o /dev/null -w "%{http_code}" -X POST http://localhost:7999/api/claude-code/submit` | HTTP `401` — JWT-required; correct without auth; confirms canonical URL has propagated | HTTP `404` → rename has NOT propagated to local server. **HALT** Phase 1; reconvene with user. Do NOT fall back to legacy URL. |
| G2 | `EXECUTOR: AI` | Schema-parity probe (F5 fix) | `curl -sS -X POST http://localhost:7999/api/claude-code/submit -H "Authorization: Bearer ${LUPIN_TEST_INTERACTIVE_MOCK_JOBS_JWT}" -H "Content-Type: application/json" -d '{"prompt":"smoke","dry_run":true}' -w "\nHTTP:%{http_code}\n"` | HTTP `200` or `202`; response body parseable as `ClaudeCodeQueueResponse`-shape JSON (`status` / `job_id` / `queue_position` / `message`) | HTTP `422` → backend schema diverged from mobile's `ClaudeCodeSubmitRequest`. **HALT** Phase 1; reconvene with user on field diff. HTTP `5xx` → server-side bug; reconvene. |
| G3 | `EXECUTOR: AI` | Legacy `/queue/submit` disposition (informational) | `curl -sS -o /dev/null -w "%{http_code}" -X POST http://localhost:7999/api/claude-code/queue/submit` | EITHER `401` (legacy still wired in parallel — pre-cutover server) OR `404` (legacy retired alongside rename — post-cutover server) | Both outcomes are informational; record disposition in execution log. Influences only the parent-side cutover timeline, NOT mobile work. |

**Warning baseline (F8 fix)** — `EXECUTOR: AI` — run **before** Phase 1 code changes start; record in execution log:

```bash
./flutter.sh analyze 2>&1 | grep -cE "^\s*(warning|info)"
```

Save the integer count as `BASELINE_WARNINGS_PRE_PHASE_1`. The Phase 1-5 verification table below references this baseline.

---

**Phase 1-5 verification** (code-touching work):

| # | Executor | Check | Command | Expected |
|---|----------|-------|---------|----------|
| 1 | `EXECUTOR: AI` | Compile clean | `./flutter.sh analyze 2>&1` | Zero new **errors** (must remain `0`). Zero new **warnings** above `BASELINE_WARNINGS_PRE_PHASE_1` (the pre-change baseline recorded above). Pre-existing warnings unchanged is acceptable; new warnings introduced by this work are NOT. |
| 2 | `EXECUTOR: AI` | Focused test | `./flutter.sh test test/unit/claude_code/` | all green; ~6-8 tests after pruning (vs. ~25 before) |
| 3 | `EXECUTOR: AI` | Full baseline | `./flutter.sh test test/unit/ test/widget/ test/service_integration/` | green; baseline drops 308 → ~300 (final count recorded in execution evidence) |
| 4 | `EXECUTOR: AI` | Quarantine drift | `./flutter.sh test test/legacy_quarantine/` | 44 ❌ unchanged (drift baseline) |
| 5 | `EXECUTOR: AI` | Retired endpoint 404 | `curl -X POST http://localhost:7999/api/claude-code/dispatch` | HTTP 404 (no live caller path remaining in mobile to hit it) |
| 6 | `EXECUTOR: HUMAN` | UI smoke (deferred) | bundle with voice-persona HUMAN gate (laptop+emulator) | dispatch sheet shows BOUNDED-only entry; submission lands as `cc-*` in QueueDashboard |

**Test venue**: All `:7999` (AI-discretionary). No `:8000` scheduling required for this work.

**Note**: G1 / G2 / G3 (lifted above) replace the previous rows 6a / 6b — they are gates, not post-implementation checks, and run **before** Phase 1 begins.

---

## Out of scope

- Parent Lupin internal `ClaudeCodeJob` redesign — separate plan, currently blocked on PIP plan-review (4/11 findings applied).
- Reading `artifacts.transcript_path` from completed `cc-*` jobs in `QueueDashboardScreen` — forward-compat TODO; field doesn't exist server-side yet.
- INTERACTIVE controls (`inject` / `interrupt` / `end_session`) — return only when parent ships them; mobile-side restoration is a follow-up plan.
- On-device verification — bundled with the existing voice-persona HUMAN runbook gate per `feedback_dev_server_laptop_split`.
- Generic `/api/push` integration — mobile already has `lib/features/queue/` Tier 3 wiring for that surface; `cc-*` jobs route through the Claude-Code-specific endpoint per server architecture.

---

## Prior art referenced (REUSE pre-pass close-out, 2026-05-10)

Per `plan-review.md` §4 — `reuse-as-is` and `extend-existing` verdicts captured here for code-write-time reference. Source: 2026-05-10 direct greps against `lib/` + `test/`.

### `reuse-as-is` (verified — copy verbatim or use directly)

| Pattern | Source (file:line) |
|---------|---------------------|
| `*Submitting` loading-state class name + shape (`class XxxSubmitting extends XxxState { const XxxSubmitting(); }`) | `lib/features/queue/domain/queue_state.dart:36` |
| `*Submitted` success-state class wrapping the API response (`final XxxResponse response;`) | `lib/features/queue/domain/queue_state.dart:40` |
| `*Submit*` event-class naming family | `lib/features/agentic/domain/agentic_submission_event.dart:12` (`AgenticSubmitRequested`) |
| BLoC handler shape (`emit(XxxSubmitting()) → repo call → emit(XxxSubmitted(res))`) | `lib/features/queue/domain/queue_bloc.dart:98-101` |
| Submit-sheet `BlocListener` state-transition pattern (`if (state is XxxSubmitted) Navigator.pop()` + `if (state is XxxSubmitting) setState(_submitting = true)`) | `lib/features/queue/presentation/submit_job_sheet.dart:49-58` |
| `blocTest<XxxBloc, XxxState>` test shape (`Initial → action → expected-state-sequence`) | `test/unit/notifications/notification_bloc_test.dart:27-73` + `test/unit/decision_proxy/decision_proxy_bloc_test.dart:21-97` |
| Existing `ClaudeCodeQueueRequest` constructor defaults (preserve verbatim under renamed `ClaudeCodeSubmitRequest`) | `lib/features/claude_code/data/claude_code_models.dart:93-102` |

### `extend-existing` (rename / relocate / add fields — NOT net-new)

| Plan claim | Existing source | What changes |
|------------|----------------|--------------|
| Banner CTA "View Claude Code jobs in Queue dashboard" pushes to existing screen | `lib/features/home/home_screen.dart:78` (`QueueDashboardScreen`) + `lib/features/queue/presentation/job_detail_screen.dart:16` (`JobDetailScreen` is canonical detail target) | CTA pushes to unfiltered `QueueDashboardScreen`; user scrolls to `cc-*` jobs. No filter helper needed (none exists; filtering is out of scope) |

### `genuinely-new` (no prior art; novelty justified)

| Item | Why novel |
|------|-----------|
| Retirement banner widget (yellow bg, warning icon, retirement copy) | `lib/shared/widgets/` and `lib/shared/components/` are empty; no existing deprecated/retired/sunset banner pattern in mobile. One-off retirement notice — not worth a new shared component per `plan-review.md` minimal-novelty bar. Inline `Container` approach (Plan's "Reuse references" section) is correct. |
| Class dartdoc retirement footnote pattern on Dart code | No mobile-side dartdoc-retirement-footnote pattern exists. Pattern prose borrowed from parent `<lupin>/src/cosa/rest/routers/claude_code_queue.py` module docstring (lines 8-13). |

### Reuse density

**6 of 10 plan items are direct reuse** (4 `reuse-as-is` + 1 `extend-existing` + 1 default-set preservation). **2 of 10 are genuinely-new but minimal** (one-off banner copy + dartdoc footnote). The plan is reuse-rich; no proposed component dissolves entirely under prior-art scrutiny.

---

## Canonical-URL note

User direction 2026-05-10: canonical submission URL is `POST /api/claude-code/submit`. Live `:7999` probe at investigation time (2026-05-09) showed only `/api/claude-code/queue/submit` in the OpenAPI; no source/rnd references to the shorter URL found in the parent codebase as of investigation. User confirmed mid-session: *"the fast API endpoint is being implemented in parallel: /api/claude-code/submit"* — the rename is in flight on parent and may not have propagated to the local dev server yet. Verification step 6a in the table above proves propagation before any mobile cutover. If 6a returns 404 at implementation time (Phase 1 start), pause and reconvene with the user — do not fall back silently to the legacy URL.
