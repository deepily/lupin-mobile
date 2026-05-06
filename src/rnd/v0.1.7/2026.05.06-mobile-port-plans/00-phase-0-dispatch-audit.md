# Phase 0 — WS Dispatch Audit + Regression Test

**Date**: 2026-05-06
**Prefix**: [LUPIN-MOBILE]
**Status**: 🟢 Ready to execute (no design choices needed)
**Pattern**: Pattern 4 (Problem Investigation) flavored — audit, hypothesis-test, fix if drift detected
**Estimated effort**: 1-2 sessions
**Blocks**: `01-voice-persona-port-plan.md`, `02-conversation-mode-port-plan.md`, `03-focus-mode-port-plan.md`

---

## 1. Why this phase exists

Between **2026-04-29 and 2026-05-05** the parent Lupin/CoSA repos shipped a **WS-event-cleanup migration** (parent commit `70959c5`, CoSA `466ad30`). Top-level WebSocket event names that used to arrive as their own first-class events (`event.name = "voice_persona_assigned"`, etc.) were re-routed to ride **inside the canonical `notification_queue_update` envelope**, with the discriminator moved to a `notification.type` field.

Concretely, the new server-side dispatch shape (confirmed by reading `src/cosa/rest/routers/voice_persona.py:202-211`):

```
WS envelope:    notification_queue_update
inner payload:  { notification: { type: "voice_persona_assigned", voice_persona: {...}, ... } }
```

vs. the old shape (pre-migration):

```
WS envelope:    voice_persona_assigned
inner payload:  { ... }
```

Three of the four resync features (voice-persona, conversation-mode, focus-mode-relevant events) ride this new envelope shape. **If the mobile WS dispatch table still expects top-level event names that have since moved inside `notification_queue_update`, those events are silently dropped today** with no error — they never reach any bloc handler.

This is the "silent regression risk" flagged in the 2026-05-06 baseline doc §3.5. It must be resolved before any of the three feature ports ships, because every one of them depends on the new envelope shape arriving correctly at a bloc.

## 2. Goal

1. **Audit** — determine whether mobile's WS handler currently dispatches by inner `notification.type` or by outer envelope name.
2. **Fix** (if drift detected) — extend the dispatch so it routes by the inner-type discriminator for `notification_queue_update` envelopes.
3. **Lock with a regression test** — a widget/unit test that drives the bloc with a synthetic envelope carrying a known inner type and asserts dispatch reaches the right handler. The test will fail at write-time if the dispatch is broken; it will be the canary for any future migration drift.

## 3. Scope (in / out)

> 🔄 **Scope narrowed 2026-05-06 by REUSE pre-pass** of the voice-persona plan (see `voice-persona/00-index.md` "Prior art referenced"). The pass confirmed that the outer-envelope routing in `lib/services/websocket_service.dart` and `lib/app.dart:80-91` is **already correct** — only the inner-`notification.type` discriminator pivot in `notification_bloc.dart` is missing. The original wider scope is preserved here for context but the in-scope list is now tighter.

**In scope** (post-REUSE narrowing):
- `lib/features/notifications/domain/notification_bloc.dart` — `_onExternalUpdate` handler at lines **146-170**; specifically, add a `switch (notification.type)` discriminator pivot so future feature ports (voice-persona, conversation-mode, etc.) can route by inner type without further dispatch-table edits
- One new regression test file under `test/unit/` (likely `test/unit/features/notifications/domain/`) covering the inner-type discriminator with a synthetic envelope

**Confirmed already correct** (no audit changes needed; document the finding in §10 instead):
- `lib/services/websocket_service.dart` — outer envelope parsing
- `lib/app.dart:80-91` — routes `notification_queue_update` envelopes to `NotificationsExternalUpdate` correctly

**Out of scope** (deferred to the three feature plans):
- New event-type values (`voice_persona_assigned`, etc.) — only the dispatch *mechanism* is in scope here; specific type-handlers come in their feature plans
- Bloc state additions for personas/conv-mode/focus
- UI changes

## 4. Audit Step (do this first)

```bash
# In lupin-mobile repo
grep -nE 'notification_queue_update|notification.type|case ["\x27]voice_persona|case ["\x27]conversation_mode' \
    lib/services/websocket_service.dart lib/app.dart \
    lib/features/notifications/domain/notification_bloc.dart
```

**Expected outcomes** (pick whichever matches reality after the audit runs):

| Audit result | Severity | Action |
|---|---|---|
| Mobile already dispatches by `notification.type` discriminator | 🟢 None | Phase 0 collapses to: write the regression test only |
| Mobile dispatches by outer envelope name only | 🔴 Silent regression | Add inner-type discriminator dispatch + regression test |
| Mobile partially dispatches by inner type (some events yes, some no) | 🟡 Partial drift | Extend the dispatch table; document the canonical pattern for future event additions |

> ✅ **PRE-CONFIRMED PARTIAL DRIFT** by REUSE pre-pass on 2026-05-06 (see voice-persona plan): outer routing in `app.dart:80-91` is correct; `notification_bloc.dart` `_onExternalUpdate` handler at lines 146-170 exists but does NOT pivot on inner `notification.type`. Phase 0 is now firmly in the 🟡 partial-drift action lane — extend the existing handler.

## 5. Tasks

### 5.1 Audit (single TodoWrite item, ~30 min)

- [ ] EXECUTOR: AI — Read `lib/services/websocket_service.dart` end-to-end. Identify the outer event-name → handler mapping.
- [ ] EXECUTOR: AI — Read `lib/app.dart` WS routing. Identify how `notification_queue_update` flows to the notification bloc.
- [ ] EXECUTOR: AI — Read `notification_bloc.dart` `NotificationsExternalUpdate` handler. Identify whether it pivots on `notification.type` for sub-dispatch.
- [ ] EXECUTOR: AI — Document findings in this file's §10 (Audit Findings) — append, don't replace.

### 5.2 Fix (if drift detected, ~1-2 hours)

- [ ] EXECUTOR: AI — If outer-only dispatch: extend the handler to pivot on inner `notification.type` and route to bloc events tagged by type (e.g., new `NotificationsTypedExternalUpdate(type, notification)`).
- [ ] EXECUTOR: AI — If partial drift: identify the missing inner-type cases. Add a default-case logger so future unknown types are visible (not silent).
- [ ] EXECUTOR: AI — Update `app.dart` if needed.

### 5.3 Regression test (always, ~1 hour)

- [ ] EXECUTOR: AI — New file: `test/unit/services/websocket_dispatch_test.dart` (or wherever fits the existing test layout).
- [ ] EXECUTOR: AI — Drives the bloc with a synthetic `notification_queue_update` envelope carrying `notification.type = "voice_persona_assigned"` (use a stub payload — actual persona handling is out of scope for Phase 0).
- [ ] EXECUTOR: AI — Asserts the dispatch reaches a recognizable code path (a bloc emit, a handler invocation, a logger line — whatever signals "the inner type was actually read").
- [ ] EXECUTOR: AI — Add a second case for an **unknown** inner type to confirm graceful degradation (logged, not crashed).

### 5.4 Verify (always, ~15 min)

- [ ] EXECUTOR: AI — Run full mobile test suite: `./flutter.sh test` (273 tests should remain green; +1-2 new tests added).
- [ ] EXECUTOR: AI — No quarantined tests reactivated.

## 6. Success Criteria

- ✅ Mobile WS dispatch demonstrably routes inner-type values to the right handler path
- ✅ Regression test fails when the dispatch is broken (proven by temporarily breaking the dispatch and running the test)
- ✅ Regression test passes when dispatch works
- ✅ Test count: 273 → 274 or 275 (depending on how many cases the new test file covers)
- ✅ This document's §10 (Audit Findings) updated with what was observed

## 7. Risks / Gotchas

| # | Risk | Mitigation |
|---|---|---|
| 1 | Audit reveals MULTIPLE silent-regression vectors (not just inner-type) | Note them in §10; if any are blocking for the three feature plans, expand Phase 0 scope; otherwise file them as separate items in `TODO.md` |
| 2 | Regression test is too synthetic and doesn't actually exercise real envelope shapes | Capture a real envelope from `:7999` server using the existing fixture-capture scripts (`src/scripts/capture-*-fixtures.py` pattern), redact, save under `test/_fixtures/` |
| 3 | Server emits an inner `notification.type` value not yet documented | Add a default-case logger so unknowns are visible; this becomes the safety net for future migrations |

## 8. Test Venue

**:7999 (AI-discretionary)** per the existing mobile + project rubric. Unit + widget tests only. No on-device verification needed for this phase — silent-regression detection is a code-level concern, not a hardware concern.

## 9. Out of Scope (won't do here)

- Adding new bloc events for `voice_persona_assigned` / `voice_persona_released` / `conversation_mode_changed` — those land in the respective feature plans
- UI changes — feature plans
- TTS routing changes — voice-persona plan
- WS reconnect circuit-breaker handling (close codes 4001/4002) — this is a separate Tier-1 plumbing item; scope it under its own R&D doc when picked up

## 10. Audit Findings

*This section is populated during execution. Append observations here.*

```
[2026-05-06] Pre-audit observation from REUSE pre-pass (session a756441c, voice-persona plan):
- websocket_service.dart:        outer envelope parsing — confirmed correct (no change)
- app.dart:80-91:                 notification_queue_update → NotificationsExternalUpdate — confirmed correct (no change)
- notification_bloc.dart:146-170: handler exists but does NOT pivot on inner notification.type — gap confirmed
- Verdict: 🟡 partial drift
- Action required: extend _onExternalUpdate with switch (notification.type) discriminator
- Source: REUSE pre-pass executed by Explore agent against voice-persona/ doc-set
```

```
[2026-MM-DD] Live audit during Phase 0 execution: <session-id>
- websocket_service.dart: <findings>
- app.dart: <findings>
- notification_bloc.dart: <findings>
- Verdict: <none | partial drift | full drift>
- Action taken: <description>
```

---

**Next plans** (gated on this one):
- `01-voice-persona-port-plan.md`
- `02-conversation-mode-port-plan.md`
- `03-session-switcher-port-plan.md`
