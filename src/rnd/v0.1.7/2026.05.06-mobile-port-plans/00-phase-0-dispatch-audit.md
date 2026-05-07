# Phase 0 — WS Dispatch Audit + Regression Test

**Date**: 2026-05-06
**Prefix**: [LUPIN-MOBILE]
**Status**: ✅ COMPLETE — landed 2026-05-06 (session a756441c continuation). 276/276 baseline-tracked tests green (was 273; +3 new dispatch tests). Quarantined-test count unchanged at 44.
**Pattern**: Pattern 4 (Problem Investigation) flavored — audit, hypothesis-test, fix if drift detected
**Estimated effort**: 1-2 sessions
**Blocks**: `01-voice-persona-port-plan.md`, `02-conversation-mode-port-plan.md`, `03-focus-mode-port-plan.md` — UNBLOCKED 2026-05-06

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

### 5.1 Audit (single TodoWrite item, ~30 min) ✅ DONE 2026-05-06

- [x] EXECUTOR: AI — Read `lib/services/websocket_service.dart` end-to-end. Identify the outer event-name → handler mapping. — pure transport layer (`_handleMessage` lines 195-246); no event-name dispatch (correct — that's app.dart's job)
- [x] EXECUTOR: AI — Read `lib/app.dart` WS routing. Identify how `notification_queue_update` flows to the notification bloc. — `_dispatchWsEvent` lines 79-93 parse `data['notification']` → fire `NotificationsExternalUpdate(notification: notif)`; correct
- [x] EXECUTOR: AI — Read `notification_bloc.dart` `NotificationsExternalUpdate` handler. Identify whether it pivots on `notification.type` for sub-dispatch. — `_onExternalUpdate` lines 146-170 fired audio+TTS unconditionally; **NO inner-type pivot** — gap confirmed
- [x] EXECUTOR: AI — Document findings in this file's §10 (Audit Findings) — append, don't replace.

### 5.2 Fix (if drift detected, ~1-2 hours) ✅ DONE 2026-05-06 (partial-drift branch)

- [ ] ~~EXECUTOR: AI — If outer-only dispatch: extend the handler to pivot on inner `notification.type` and route to bloc events tagged by type (e.g., new `NotificationsTypedExternalUpdate(type, notification)`).~~ N/A — partial drift, not outer-only
- [x] EXECUTOR: AI — If partial drift: identify the missing inner-type cases. Add a default-case logger so future unknown types are visible (not silent). — `notification_bloc.dart:146-185` extended with `switch (n.type)`; whitelisted types `task|progress|alert|custom|user_initiated_message|session_topic` → existing audio+TTS path; default → `print("[NotificationBloc] Unknown notification.type: '${n.type}' (id=${n.id})")`
- [x] EXECUTOR: AI — Update `app.dart` if needed. — not needed; outer routing was already correct

### 5.3 Regression test (always, ~1 hour) ✅ DONE 2026-05-06

- [x] EXECUTOR: AI — New file: `test/unit/notifications/notification_bloc_dispatch_test.dart` — co-located with existing `notification_bloc_test.dart` (the actual unit tested is the bloc handler, not the WS service layer; revised path from plan §5.3's `test/unit/services/websocket_dispatch_test.dart` recommendation)
- [x] EXECUTOR: AI — Drives the bloc with a synthetic `notification_queue_update` envelope carrying `notification.type = "voice_persona_assigned"` — `_makeItem(type: "voice_persona_assigned")` constructs the `NotificationItem` directly (bypassing JSON path; same code path the WS layer ends at)
- [x] EXECUTOR: AI — Asserts the dispatch reaches a recognizable code path — `verifyNever()` on both `audio.handleIncoming` and `tts.enqueueIfSpeakable` proves the inner type was read (and routed to default branch, not the whitelisted-types branch); default-branch logger output is also visible in test stdout
- [x] EXECUTOR: AI — Add a second case for an **unknown** inner type to confirm graceful degradation (logged, not crashed). — `_makeItem(type: "some_unknown_type")` second test; identical assertion shape; plus a third regression test asserting `type="alert"` still fires audio AND TTS as before (whitelisted-types branch unchanged)

### 5.4 Verify (always, ~15 min) ✅ DONE 2026-05-06

- [x] EXECUTOR: AI — Run full mobile test suite: `./flutter.sh test` — 347 pass / 44 fail (44 = pre-existing legacy_quarantine drift baseline). Baseline-tracked dirs (`test/unit/ test/widget/ test/service_integration/`) reported `276 +; All tests passed` (273 → 276, +3 new dispatch tests).
- [x] EXECUTOR: AI — No quarantined tests reactivated. — confirmed: 44 quarantined failures unchanged; failure list matches the documented `legacy_quarantine/` drift surface (e.g., `dependency_injection_test.dart` referencing files that don't exist)

## 6. Success Criteria

- [x] Mobile WS dispatch demonstrably routes inner-type values to the right handler path — `notification_bloc.dart:146-185` now `switch (n.type)` with whitelisted-types audio+TTS branch and default-branch logger
- [x] Regression test passes when dispatch works — 3/3 new tests in `notification_bloc_dispatch_test.dart` green
- [x] Test count: 273 → 276 (+3 new tests) — confirmed by `./flutter.sh test test/unit/ test/widget/ test/service_integration/` returning `276 +; All tests passed`
- [x] This document's §10 (Audit Findings) updated with what was observed
- [x] No quarantined tests reactivated — `./flutter.sh test` (full) shows 347 pass / 44 fail, the 44 matching the documented `legacy_quarantine/` drift baseline

> Note: the "fails when dispatch is broken" criterion was demonstrated implicitly during write-time — the existing handler had no `switch`, so a test asserting "audio NOT called for unknown type" would fail against the pre-fix bloc (audio was called for every type). The first green run on the post-fix bloc confirms the test now locks the correct behavior.

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
[2026-05-06] Live audit during Phase 0 execution: session a756441c (post-/clear continuation)
- websocket_service.dart:195-246 (`_handleMessage`): pure transport — decodes JSON, wraps binary as
  `audio_streaming_chunk`, forwards via `_messageController`. NO event-name dispatch (correct — that
  layer lives in `app.dart`). No change needed.
- app.dart:79-93 (`_dispatchWsEvent` case `eventNotificationQueueUpdate`): outer routing correct.
  Parses `data['notification']` → `NotificationItem.fromJson` → fires
  `NotificationsExternalUpdate(notification: notif)`. No change needed.
- notification_bloc.dart:146-170 (`_onExternalUpdate`): handler exists; null-guards on
  `event.notification`; fires `_audio.handleIncoming` + `_tts.enqueueIfSpeakable` UNCONDITIONALLY
  for every non-null notification. NO `switch (n.type)` pivot — every inner type takes the same
  audio+TTS path. Gap confirmed.
- Supporting fact: `NotificationItem.type` field already on the model
  (`notification_models.dart:22,51,83`); `fromJson` is already liberal — accepts any string with
  `"custom"` fallback. Phase 0 fix is purely a handler-side switch; no model change required.
- Verdict: 🟡 partial drift (matches 2026-05-06 REUSE pre-confirm)
- Action taken: extend `_onExternalUpdate` with `switch (n.type)` — whitelist existing types
  (`task`/`progress`/`alert`/`custom`/`user_initiated_message`/`session_topic`) → existing audio+TTS
  path; `default` → log the unknown type so future migrations are visible (canary).
```

---

**Next plans** (gated on this one):
- `01-voice-persona-port-plan.md`
- `02-conversation-mode-port-plan.md`
- `03-session-switcher-port-plan.md`
