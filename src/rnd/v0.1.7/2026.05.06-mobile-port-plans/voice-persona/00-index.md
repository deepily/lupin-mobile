# Voice/Persona Mobile Port — Master Index

**Project ID**: `voice-persona-mobile-port`
**Created**: 2026-05-06
**Pattern**: Pattern A (Multi-Phase Implementation Documentation), right-sized for a Pattern 3 (Feature Development) plan that opted into the full plan-review gate
**Duration**: ~5 days, 5 phases, 12 tasks
**Status**: Draft — pending plan-review (REUSE → Pass 1 Fitness → Pass 2 Adversarial)
**Prefix**: [LUPIN-MOBILE]

---

## Why this Pattern A doc-set exists for a Pattern 3 plan

The canonical `<planning-is-prompting>/workflow/p-is-p-02-documenting-the-implementation.md` says Pattern 3 plans should SKIP this step and use `history.md`. The user has explicitly opted in **specifically to satisfy plan-review's grep-based prerequisites** (`workflow/plan-review.md` §2). The Pattern A structure here is right-sized — five docs, no architecture doc (no system design beyond what's inline in implementation), no archive directory.

If this milestone weren't going through plan-review, this subdirectory would not exist; `01-voice-persona-port-plan.md` at the parent level would be the single source of truth.

---

## Quick Navigation

- **[Working Contract](00-working-contract.md)** — Rules of engagement (Convention 1: project-level anchor for Pass 2 Adversarial)
- **[Implementation](01-implementation.md)** — Phases 1-5, tasks, files (with `EXECUTOR: AI/HUMAN` tags per Convention 3)
- **[Decisions](03-decisions.md)** — `Q1`–`Q6` FROZEN 2026-05-06 (Convention 2: milestone-level anchor for Pass 1 Fitness)
- **[Testing & Validation](04-testing-validation.md)** — EXECUTOR-tagged verification matrix
- **[Parent entry pointer](../01-voice-persona-port-plan.md)** — thin link doc; lives at parent level for cross-ref stability with peer plans (`02-conversation-mode-port-plan.md`, `03-session-switcher-port-plan.md`)

---

## Project Overview

Port the per-session voice persona surface (parent-Lupin commit `eedc823`, CoSA `2116566`, 2026-04-28) into the mobile client. Server stamps a persona dict `{ name, voice_id, icon, color, borrowed, assigned_at, display_name }` onto every notification envelope. Mobile must:

1. Display a persona badge keyed to each session
2. Route the assigned `voice_id` through the existing `StreamingTtsPlayer` pipeline so per-session voices are honored (instead of always falling through to Sam)
3. Handle `voice_persona_assigned` / `voice_persona_released` events that ride **inside** `notification_queue_update` envelopes (the 2026-04-29 WS-event-cleanup migration)

Clean port — no UX redesign. Persona model is well-defined server-side; mobile mirrors it.

---

## Current Status

**Active Phase**: None — design phase, plan-review pending
**Progress**: 0% (no code written yet)
**Last Updated**: 2026-05-06

---

## Phase Summary

| Phase | Status | Where | Notes |
|---|---|---|---|
| 0 (prereq) | ⏳ pending | [`../00-phase-0-dispatch-audit.md`](../00-phase-0-dispatch-audit.md) | Separate plan; WS dispatch audit blocks this milestone + the other two feature ports |
| 1 — Data model | ⏳ pending | [01-implementation.md §2](01-implementation.md) | `VoicePersona` model + `NotificationItem` extension + fixture variants |
| 2 — WS dispatch | ⏳ pending | [01-implementation.md §3](01-implementation.md) | Inner-type discriminator + bloc events + bloc state map |
| 3 — UI badge | ⏳ pending | [01-implementation.md §4](01-implementation.md) | `PersonaBadge` widget + wiring into 3 surfaces |
| 4 — TTS routing | ⏳ pending | [01-implementation.md §5](01-implementation.md) | `voice_id` parameter on `StreamingTtsPlayer.speak()` + orchestrator pipe-through |
| 5 — Docs + verify | ⏳ pending | [01-implementation.md §6](01-implementation.md) | `TODO.md` / `history.md` updates + full test run |

---

## Recent Updates

- **2026-05-06 (Pass 2 close)**: Pass 2 Adversarial complete (Task #9); 8 wording-polish findings + 1 meta-finding (F20). User picked option (b) — F20 only: tag the 13 bare checkboxes in `00-phase-0-dispatch-audit.md` §5 with `EXECUTOR: AI`. Plan-review FULLY CLOSED. Phase 0 implementation + voice-persona Phase 1.1-1.5 unblocked.
- **2026-05-06 (latest)**: Pass 1 Fitness complete (Task #8); user approved all 11 findings. 12 edits applied across `01-implementation.md`, `04-testing-validation.md`, `00-working-contract.md`. Phase 1 tasks renumbered as Task 1.1-1.5 with explicit dependency chain. Null-defense, blocTest assertion shapes, badge wiring file paths, server ordering guarantee, emoji failure-mode contract, and 5 other clarifications added. No Q1-Q9 challenged. Convergence check: 0 TBD hits, only "all resolved at REUSE" references for Open sub-question grep.
- **2026-05-06 (later)**: REUSE pre-pass complete (Task #7); 6 fix categories applied. Phase 4 Task 4.1 collapsed (`voiceId` already wired). Phase 0 scope narrowed to bloc handler only. Q7/Q8/Q9 promoted from Open sub-questions to FROZEN. Prior-art section added below.
- **2026-05-06**: Pattern A doc-set created from `../01-voice-persona-port-plan.md` per user direction (upgrade for plan-review compatibility). Existing flat doc replaced with thin pointer.

---

## Key Decisions

- **[Q1](03-decisions.md#q1-persona-storage-no-mobile-cache)** — Persona storage: server-stamped on notification envelope; no separate mobile-side cache
- **[Q2](03-decisions.md#q2-borrowed-persona-rendering)** — Borrowed-persona rendering: dashed-border badge variant
- **[Q3](03-decisions.md#q3-tts-voice_id-routing)** — TTS `voice_id` routing: optional named parameter; server falls back to Sam if absent
- **[Q4](03-decisions.md#q4-fallback-tts-out-of-scope-for-voice_id)** — `flutter_tts` fallback path: NOT routed through `voice_id` (different voice space)
- **[Q5](03-decisions.md#q5-persona-theming-scope-badge-only)** — Persona theming scope: badge only; no inbox/bubble color sweep in this milestone
- **[Q6](03-decisions.md#q6-on-device-verification-bucketed)** — On-device verification: bucketed with existing TTS runbook; not a new on-device step
- **[Q7](03-decisions.md#q7-fromjson-shape-liberal-not-enum-validated)** (FROZEN at REUSE 2026-05-06, was OSQ #1) — `VoicePersona.fromJson` is **liberal** — accepts any string `name` / `icon` / `voice_id`; not gated against a hard-coded enum
- **[Q8](03-decisions.md#q8-personabadge-widget-location-features-not-shared)** (FROZEN at REUSE 2026-05-06, was OSQ #2) — `PersonaBadge` lives in `lib/features/notifications/presentation/`; `lib/shared/widgets/` is empty and would be premature generalization
- **[Q9](03-decisions.md#q9-dashedborderpainter-genuinely-new)** (FROZEN at REUSE 2026-05-06, was OSQ #3) — `DashedBorderPainter` is genuinely new — no `CustomPainter` subclass found and no dashed-border package in `pubspec.yaml`

---

## Prior Art Referenced (canonical post-REUSE-pre-pass output, 2026-05-06)

Per `<planning-is-prompting>/workflow/plan-review.md` §4: "Append a 'Prior art referenced' section to `00-index.md` listing all `reuse-as-is` and `extend-existing` verdicts with their file:line pointers — this persists past the review and is useful at code-write time."

### `reuse-as-is`

| What | Where | Notes |
|---|---|---|
| `String? voiceId` parameter on `StreamingTtsPlayer.speak()` | `lib/services/tts/streaming_tts_player.dart:130` | **Already shipping.** Body wiring at `:141` uses `if (voiceId != null) body['voice_id'] = voiceId`. Phase 4 Task 4.1 collapses from "write new" to "verify + comment". |
| Bloc test harness (mocktail `MockBloc` pattern) | `test/unit/notifications/notification_bloc_test.dart:1-47` | Existing pattern is directly reusable for the new persona-related blocTest cases (Phase 2). |
| `StubAdapter` test infrastructure | (per REUSE-pass observation; specific path not captured) | Reusable for fixture-backed tests in Phase 1. |

### `extend-existing`

| What | Where | Notes |
|---|---|---|
| Inner `notification.type` discriminator pivot | `lib/app.dart:80-91` (envelope routing — already correct); `lib/features/notifications/domain/notification_bloc.dart:146-170` (handler that needs the pivot) | Phase 0 (`../00-phase-0-dispatch-audit.md`) narrows to extending the existing handler with a `switch (notification.type)` block. Outer routing is unchanged. |
| `PersonaBadge` widget — wraps `CircleAvatar` | `lib/features/notifications/presentation/inbox_screen.dart:~186` (`CircleAvatar` usage); `lib/features/auth/presentation/login_screen.dart:24` (sibling pattern: `_ContextBadge`) | Phase 3 Task 3.1: `PersonaBadge` is a `StatelessWidget` wrapping `CircleAvatar` with persona color/icon, plus `CustomPaint` overlay for the `borrowed=true` dashed-border variant. |

### Cross-reference

REUSE pre-pass executed by Explore agent in session `a756441c` on 2026-05-06; full findings table stored in conversation transcript (not serialized — convergence loop §7 has closed; this section is the persisted artifact).

---

## Token Budget Status

| Document | Target | Notes |
|---|---|---|
| 00-index.md (this doc) | 500-1000 | Index/navigation |
| 00-working-contract.md | 400-700 | Convention 1 anchor |
| 01-implementation.md | 4000-7000 | Phases 1-5 |
| 03-decisions.md | 1500-3000 | Q1-Q6 FROZEN |
| 04-testing-validation.md | 1500-3000 | Test matrix |

**Project total estimate**: ~10-15k tokens across 5 files. Fits comfortably under the 25k single-doc limit; no archival needed for this short-lived milestone.

---

*Last updated: 2026-05-06*
