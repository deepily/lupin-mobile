# Voice/Persona Allocation Surface — Mobile Port Plan (Entry Pointer)

**Date**: 2026-05-06
**Prefix**: [LUPIN-MOBILE]
**Status**: 🟡 Draft — pending plan-review (REUSE → Fitness → Adversarial)
**Pattern**: Pattern 3 (Feature Development), upgraded to Pattern A right-sized doc-set for plan-review compatibility (2026-05-06)
**Estimated effort**: ~5 days, ~12 tasks
**Blocked by**: `00-phase-0-dispatch-audit.md` AND plan-review completion

---

> 📁 **This file is now an entry pointer.** The full Pattern A doc-set lives in [`voice-persona/`](voice-persona/). This top-level file remains for cross-reference stability with peer plans (`02-conversation-mode-port-plan.md`, `03-session-switcher-port-plan.md`) which expect a `01-` filename here.

## Where everything went

The original flat plan content (drafted 2026-05-06 earlier in session `a756441c`) has been split per `<planning-is-prompting>/workflow/p-is-p-02-documenting-the-implementation.md` Pattern A. Each section maps to a destination file in [`voice-persona/`](voice-persona/):

| Original section | Now lives in |
|---|---|
| Project overview, status, phase summary | [`voice-persona/00-index.md`](voice-persona/00-index.md) |
| Working contract (NEW — Convention 1) | [`voice-persona/00-working-contract.md`](voice-persona/00-working-contract.md) |
| §1 Context, §2 Server-side facts, §3 Phases 1-5 with EXECUTOR tags, §4 Out of scope, §5 Risks, §7 Success Criteria, §8 Files, §9 Execution Log | [`voice-persona/01-implementation.md`](voice-persona/01-implementation.md) |
| §3 Decisions formalized as Q1-Q6 FROZEN (NEW — Convention 2) | [`voice-persona/03-decisions.md`](voice-persona/03-decisions.md) |
| §6 Test Plan + EXECUTOR-tagged matrix (NEW shape — Convention 3) | [`voice-persona/04-testing-validation.md`](voice-persona/04-testing-validation.md) |

## Why the upgrade

User opted into the full three-pass plan-review (REUSE → Pass 1 Fitness → Pass 2 Adversarial) per `<planning-is-prompting>/workflow/plan-review.md`. The grep-driven passes require Convention 1-5 in place (FROZEN decision anchors, EXECUTOR tags, TBD markers, "Manual E2E" semantics, optional working contract). The flat plan didn't have those; the Pattern A doc-set in [`voice-persona/`](voice-persona/) does.

For a Pattern 3 plan, this is slightly off-canonical — the canonical workflow says Pattern 3 plans skip Pattern A and use `history.md`. The user's choice is defensible because the plan crosses 5 phases and 5 subsystems and benefits from the gate. Documented explicitly in [`voice-persona/00-index.md` §"Why this Pattern A doc-set exists for a Pattern 3 plan"](voice-persona/00-index.md).

## Plan-review readiness checklist

| Convention | File / Marker | Status |
|---|---|---|
| 1 — Working contract | [`voice-persona/00-working-contract.md`](voice-persona/00-working-contract.md) — FROZEN 2026-05-06 | ✅ |
| 2 — FROZEN-dated numbered decisions | [`voice-persona/03-decisions.md`](voice-persona/03-decisions.md) — Q1-Q6 FROZEN 2026-05-06 | ✅ |
| 3 — EXECUTOR: AI / HUMAN tagging | [`voice-persona/01-implementation.md`](voice-persona/01-implementation.md) + [`voice-persona/04-testing-validation.md`](voice-persona/04-testing-validation.md) every checkbox tagged | ✅ |
| 4 — TBD / Open sub-question markers | [`voice-persona/03-decisions.md`](voice-persona/03-decisions.md) §"Open sub-questions" — 3 numbered | ✅ |
| 5 — "Manual E2E" semantics | No `Manual` qualifier used; on-device step is `EXECUTOR: HUMAN — laptop + Android SDK access required` | ✅ |

Plan-review can now run when user gives go-ahead.

---

## Cross-references

- Phase 0 prerequisite (separate plan): [`00-phase-0-dispatch-audit.md`](00-phase-0-dispatch-audit.md)
- Companion plans: [`02-conversation-mode-port-plan.md`](02-conversation-mode-port-plan.md), [`03-session-switcher-port-plan.md`](03-session-switcher-port-plan.md)
- Parent design (web — read fully before implementation): `<parent-lupin>/src/rnd/v0.1.7/2026.04.28-per-session-voice-personas/01-design.md`
- Mobile baseline: `<mobile>/src/rnd/v0.1.7/2026.05.06-resync-baseline-mobile-vs-lupin.md`
