# Section S6 — FCM Backend Interface (Cross-Repo, Parent Lupin)

**Stage**: 2
**Anchors**: [01-architecture.md](01-architecture.md) · [02-decisions.md](02-decisions.md) Q10, OSQ-6, OSQ-7 · [03-testing-strategy.md](03-testing-strategy.md) · prior R&D `../v0.1.7/2026.04.21-fcm-apns-push-considerations.md` §7
**Provides**: push + token-registration + WS client-type contract (consumed by S5)
**Consumes**: nothing from sibling sections

> **Cross-repo note**: implementation lands in PARENT LUPIN (`src/cosa/rest/...`), not this repo.
> This section file is the INTERFACE SPEC + work order that a parent-Lupin session executes; it is
> reviewed in this cascade so the contract is ratified before either side builds. Mobile-side
> tracking stays here; parent-side execution gets its own session/branch per the nested-repo rule
> (no parent git ops from mobile context, and vice versa).

## 1. Purpose

Give the parent backend the ability to (a) know each mobile device's FCM token and (b) fire a
content-free, high-priority, data-only `ws_wake` push when it has traffic for a user whose mobile
WS is gone (Q10 silent-relay).

## 2. Scope

**In (spec'd here, built in parent)**: Firebase Admin credentials handling; token-registration
endpoint + storage; WS client-type marker recording at connect/auth (F-S6-1); wake-trigger logic
(when notifications target a user with a registered token and NO live MOBILE WS); send via FCM
HTTP v1 API; INI keys; parent-side tests.

**Out**: any mobile code (S5); message content over FCM (forbidden by design); APNs/iOS; broader
push-notification UX (already deferred indefinitely by the 2026-04-21 decision — this milestone
implements ONLY the silent-relay wake channel).

## 3. The Contract (consumed by S5 — change requires updating both files)

### 3.0 WS client-type marker (F-S6-1, added 2026-06-12 under OSQ-6 amendment rights)

The parent WS layer currently cannot distinguish a mobile WS from a web-browser WS
(`websocket_manager.py:58` `user_sessions` has no platform field; `connect()` `:105` takes no
client-type param). The contract therefore adds: the mobile app includes
`"client_type": "mobile"` in its WS `auth_request` payload; the parent records it on the session
entry; absent marker ⇒ treated as web (backward-compatible — existing web clients send nothing).
This is an S5 connect-time OBLIGATION and an S6 trigger INPUT; it appears verbatim in S5 §3.1
(AC-S6.5 verifies the marker in BOTH files). A desktop browser session must NOT suppress the
phone's wake — that is the "one listening channel" goal.

### 3.1 Token registration

- `POST /api/fcm/register-token` (JWT) — body `{ "token": str, "platform": "android",
  "user_email": str }` → 200 `{ "status": "ok" }`. Upsert keyed on token; multiple devices per
  user allowed.
- `POST /api/fcm/unregister-token` (JWT) — body `{ "token": str }` → 200 `{ "status": "ok" }`.
  Best-effort logout path. *Amended 2026-06-12 under OSQ-6 amendment rights (parent design-gate
  recommendation, Manager-concurred)*: was `DELETE /api/fcm/register-token` with JSON body — the
  Stage-1 residual's proxy-fragility flag is hereby DISCHARGED by switching to the POST shape
  (DELETE-with-body is dropped by some proxies/LBs on the anticipated GCP cutover path).
  Propagated to S5 §3.1 in the same round per the rule below.
- *(OSQ-6: exact path/shape is the proposed answer; parent-side design may amend — amendment must
  propagate to S5 §3.1 before either implements.)*

### 3.2 Wake push

- Data-only FCM HTTP v1 message, `android.priority: HIGH` (Doze delivery), payload
  `{ "type": "ws_wake", "reason": "<undelivered|reconnect-hint>", "ts": iso8601 }`. The `reason`
  field is the two-value ENUM shown (aligned with S5 §3.1 per F-S5-2.ii — enum, not free string,
  so AC-S6.3's contract-pinning test can assert it). NO `notification` block, NO message content,
  NO sender identity beyond what reconnect will fetch anyway. *Semantics pinned at parent build
  (2026-06-12, informational — not an AC-S6.5 comparison element)*: `undelivered` = the
  notification-enqueued trigger (the only automatic emitter); `reconnect-hint` =
  administrative/manual summons.

### 3.3 Trigger policy (parent-side)

Fire on: notification enqueued for a user who has ≥1 registered token AND no live WS session
marked `client_type: "mobile"` (per §3.0 — web sessions do not suppress the wake). Debounce: at
most one wake per user per N seconds (INI key, default 60) — a wake is a summons, not a stream.

## 4. Tasks (parent-Lupin work order)

- [x] Firebase service-account credential wiring (env-var path, never committed; INI-named).
      **Two-Firebases separation (F-S6-2)**: the parent already contains a MOCK Firebase layer
      for AUTH (`auth.py:17-22`, `FIREBASE_INITIALIZED = False`) — the REAL `firebase_admin` FCM
      init is a SEPARATE touchpoint with its own INI-named credentials; the auth mock stays
      untouched; no shared initialization or credential paths.
- [x] WS client-type marker: record `client_type` from `auth_request`; absent ⇒ web (F-S6-1).
      Implementation clause (Stage-2 residual fold): `user_sessions`
      (`websocket_manager.py:58`) stores BARE session-id strings today — there is no session
      object to hang the marker on; a side map (`session_id → client_type`) or a
      session-metadata restructure is required, parent's choice.
- [x] Token registry: storage + register/unregister endpoints per §3.1. **Durability
      requirement (F-S6-S2-1a)**: the registry SURVIVES parent restart — in-memory-only is NOT
      acceptable (restart would silently kill the wake channel: token unchanged, user logged in,
      no re-registration trigger; S5's reconnect re-register is the belt, this is the
      suspenders). Storage per the parent's existing persistence conventions (e.g., the
      notification-DB repository pattern in `src/cosa/rest/`); final medium parent-side under
      OSQ-6.
- [x] Wake trigger + debounce per §3.3, hooked at the notification fan-out point where
      mobile-WS liveness (per the §3.0 marker) is visible. Precision clauses (Stage-2 residual
      folds): liveness keys on the QUEUE WS (`/ws/queue/{session_id}`) — NOT the audio WS — since
      notification fan-out rides the queue socket; and parent design pins which trigger condition
      emits `reason: undelivered` vs `reconnect-hint` (informational field, semantics
      parent-defined).
- [x] INI keys (`fcm *` family) + splainer entries
- [x] Parent-side unit tests + endpoint tests (parent venue rules apply: `:7999`-eligible if
      net-zero, else `:8000` scheduled)
- [x] Documentation touchpoints per parent CLAUDE.md (rest-api-reference, notification docs,
      websocket-events/architecture for the client-type marker)

## 5. Acceptance Criteria

- [x] EXECUTOR: AI (parent session; executability conditional on OSQ-6 resolution — the storage
      medium is parent-side under OSQ-6; until it closes, this AC carries this same-line
      dependence note) — AC-S6.1: register/unregister round-trip persists + removes a token
      (endpoint test). Extended (F-S6-S2-1a, mechanism per F-S6-S3-1): register a token →
      RE-INSTANTIATE the registry component from the durable medium (fresh instance, ZERO
      in-memory carryover; a full process restart is acceptable but not required) → the token
      still resolves for the wake trigger. A raw store-read does NOT satisfy this — the
      assertion must prove boot-time REHYDRATION; a write-through-cache-never-read-back
      implementation must FAIL it.
- [x] EXECUTOR: AI (parent session) — AC-S6.2: wake fires for token-registered user with no live
      MOBILE WS; does NOT fire when a live `client_type: "mobile"` WS exists; DOES fire when only
      a web (unmarked) WS exists (§3.0/§3.3); debounce suppresses the second wake inside the
      window (unit + endpoint tests with mocked FCM transport).
- [x] EXECUTOR: AI (parent session) — AC-S6.3: outgoing FCM payload asserts data-only +
      high-priority + content-free shape + `reason` ∈ {undelivered, reconnect-hint} (§3.2) —
      contract-pinning test.
- [ ] EXECUTOR: HUMAN (Firebase/GCP console access, OSQ-7) — Firebase project + service account
      provisioned; `google-services.json` (mobile) + service-account JSON (parent) placed; AI
      validates both configs once present.
- [x] EXECUTOR: AI (cascade instant: Stage-3 reviewer, at S5's Stage-3 close
      post-F-S5-S2-1-reshape, result posted to the section topic) / EXECUTOR: AI (parent
      session, at implementation start) — AC-S6.5 cross-repo contract sync check (instants
      owned per F-S6-S3-2). Comparison surface (F-S6-S2-2 — element-wise, NOT a text diff;
      prose may differ): each of the following is IDENTICAL in S5 §3.1 and this §3 — endpoint
      paths + HTTP methods; request/response field names and types; the `client_type` marker key
      + value + absent-means-web rule (F-S6-1); push payload keys; the `reason` enum values; the
      priority flag.

## 6. Open Items

OSQ-6 (final endpoint shape — amended 2026-06-12 with the client-type marker, F-S6-1), OSQ-7
(console provisioning). Anchored in 02-decisions.md.

## 7. Revision Log

- **2026-06-12 (Stage-1 close, findings F-S6-1..2 + F-S5-2.ii thread)**: F-S6-1 (inconsistency,
  CONCUR option (a), Manager-concurred) — NEW §3.0 WS client-type marker (`client_type: "mobile"`
  in `auth_request`; absent ⇒ web); §3.3 trigger re-worded to "no live MOBILE WS"; work-order
  task + AC-S6.2 web-doesn't-suppress case + AC-S6.5 marker-sync check added; OSQ-6 amendment
  recorded in 02-decisions.md. F-S6-2 (cosmetic) — two-Firebases separation sentence in §4 task 1
  (real FCM admin init separate from the `auth.py:17-22` auth mock). F-S5-2.ii thread — `reason`
  pinned as the two-value enum in §3.2 (matches S5 §3.1); AC-S6.3 asserts it. Stage-1 residual
  recorded: DELETE-with-body proxy-fragility flag on §3.1 for parent design.
- **2026-06-12 (Stage-2 close, findings F-S6-S2-1..2 + residual folds + F-S1-S3-2 family fix)**:
  F-S6-S2-1 (inconsistency, cross-section, CONCUR both halves) — durable-storage requirement
  pinned in §4 (in-memory NOT acceptable; medium parent-side under OSQ-6) + AC-S6.1
  restart-survival extension; S5-side belt applied as the §3.2 re-register-on-WS-reconnect
  touchpoint + AC-S5.2 extension. F-S6-S2-2 (cosmetic) — AC-S6.5 comparison surface enumerated
  (element-wise, prose may differ). Arnold's three parent residuals folded into §4: bare-id
  side-map clause, queue-WS-not-audio-WS trigger precision, `reason` value-semantics pin. §8
  Execution Log placeholder + parent-side baseline task line added.
- **2026-06-12 (Stage-3 close, findings F-S6-S3-1..2)**: F-S6-S3-1 (inconsistency, CONCUR
  Cheech's re-word verbatim) — AC-S6.1 pins mechanism (b) re-instantiate-from-store (fresh
  instance, zero in-memory carryover; write-through-cache implementations must fail) + the
  OSQ-6 same-line conditionality clause (AC-S4.1 pattern). F-S6-S3-2 (cosmetic, CONCUR;
  Manager concurrence granted on ownership) — AC-S6.5 tag split per instant: cascade-close =
  Stage-3 reviewer at S5's Stage-3 pass post-reshape; implementation-start = parent session.
  Complete OSQ ledger recorded in 02-decisions.md (all seven cascade-ratified). S6 closes all
  three stages with this revision.
- **2026-06-12 (post-cascade OSQ-6 amendment — unregister endpoint POST switch)**: §3.1
  unregister element amended `DELETE /api/fcm/register-token` (body) → `POST
  /api/fcm/unregister-token` `{token}` → 200 `{"status":"ok"}` (parent design-gate
  recommendation, Manager-concurred; proxy-fragility residual DISCHARGED — DELETE-with-body is
  dropped by some proxies/LBs on the GCP cutover path). S5 §3.1 propagated same-round before
  either side implemented (propagation rule held); element-wise sync re-verifiable under
  AC-S6.5's comparison surface.

## 8. Execution Log

*(Placeholder per working-contract §Phase-Complete Definition + testing-strategy rule 1 —
populated at implementation time by the PARENT-Lupin session, NOT during the cascade.)*

- [x] Parent-side green baseline (relevant suite scope) recorded BEFORE first edit:
      **2026-06-12 00:33–00:35 EDT (04:33–04:35 UTC)**, by the parent-Lupin S6 session (Clayton,
      worktree branch `s6-fcm-backend-clayton` off `wip-v0.1.8`, base `6be15f46` + task-zero
      `4ccbfe90`):
      - `pytest src/tests/unit/` → **6508 passed, 1 xfailed**, 185.27s
      - `src/scripts/run-websocket-smoke-tests.sh` (live `:7999`) → **50 passed, 0 failed**, ~45s
- AC-S6.5 implementation-start re-run (parent-session instant per F-S6-S3-2): **PASS 6/6**
  element-wise (endpoints+methods · req/resp fields+types · client_type marker incl.
  absent-means-web · push payload keys · reason enum · priority flag) — 2026-06-12 00:28 EDT,
  result DM'd to both managers BEFORE any parent-side edit.
- Per-AC evidence entries land here as each §5 checkbox flips to `[x]` (test output, probe
  response, or named HUMAN sign-off).
- **2026-06-12 01:05 EDT — BUILD GREEN (Clayton, parent worktree `s6-fcm-backend-clayton`,
  held commit `319fdab4`, stacked on task-zero `4ccbfe90`)**: all §4 tasks implemented —
  WS marker side map + `has_live_mobile_session` (queue-WS only) · `FcmWakeService`
  (named-app `lupin-fcm-wake` init, F-S6-2 separation; DISABLED-boot OSQ-7 tolerance; per-user
  debounce; reason pin: `undelivered` = notification-enqueued trigger, `reconnect-hint` =
  administrative/manual summons) · enqueue-chokepoint trigger hook · durable `fcm_tokens`
  Postgres registry + Alembic migration `a1b2c3d4e5f6` (stacks on `f0a1b2c3d4e5` per
  merge-train ruling) · POST register/unregister endpoints per the AMENDED §3.1 · INI `fcm *`
  + splainer · parent docs (rest-api-reference §25, websocket-events/architecture,
  notification-api).
  **Verification**: 78 new unit tests; `fcm_wake_service.py` / `routers/fcm.py` /
  `fcm_token_repository.py` at 100% lines+branches; full parent unit suite
  **6586 passed + 1 xfailed** (baseline 6508 + 78 new, zero regressions).
  - AC-S6.2 evidence (unit, mocked transport): fires with no mobile WS ✓ · suppressed by live
    mobile WS ✓ · web-only does NOT suppress ✓ · debounce suppresses second wake ✓
    (`test_fcm_wake_service.py::TestMaybeSendWakePolicy`).
  - AC-S6.3 evidence (contract-pinning unit): payload exactly `{type, reason, ts}`, data-only
    (no `notification` kwarg), `reason` ∈ two-value enum enforced (ValueError otherwise),
    `AndroidConfig(priority="high")` at the real-transport seam
    (`TestBuildWakePayload` + `TestRealTransport`).
  - AC-S6.1 STATUS: endpoint round-trip + cross-process re-instantiate-from-store rehydration
    test WRITTEN (`src/tests/integration/test_fcm_token_registration.py`) — executes on `:8000`
    via `/api/test-suite/submit` AFTER the merge train lands the code there; checkbox stays
    `[ ]` until that receipt.
  - AC-S6.5 (implementation-start instant): PASS 6/6 — recorded above, pre-edit.
  - OSQ-7 (HUMAN): unchanged — Firebase console provisioning pending; service boots DISABLED
    with a clear log line until then (verified by smoke + unit).
- **2026-06-12 ~04:15 EDT — Rachel 🕊️ fresh-critical review: APPROVE-WITH-FINDINGS; three
  pre-merge fixes landed as a stacked commit** (parent worktree): R1 HIGH — absent `client_type`
  no longer downgrades an established "mobile" marker (the audio-WS connect reuses the queue-WS
  session id without a marker; same-sid regression tests added); R2 MED — `/api/fcm/*` handlers
  switched async→sync def (threadpool; avoids the event-loop starvation pattern); R3 MED-LOW —
  `upsert_token` rebuilt as atomic PG `INSERT .. ON CONFLICT (token) DO UPDATE` (concurrent
  same-token registration race eliminated); R5 nit — `platform` pinned to the spec enum
  `{"android"}` (422 otherwise). **R4 (BACKLOG, Rachel, noted per Manager ruling): move the
  remaining on-caller-thread wake-policy work (notably the token DB lookup in
  `maybe_send_wake`) onto the sender's executor** — currently bounded by the debounce
  (≤1 lookup per user per window), so deferred, not forgotten.
- **2026-06-12 ~04:26 EDT — S6 LANDED (parent-side execution COMPLETE; all AI-executable ACs
  flipped above)**: Rachel 🕊️ delta-verified the fix commit `0ea371e8` (all five scope items
  adversarially reproduced) → Tiberius 👑 merged to `wip-v0.1.8` as **`83990552`** (held, not
  pushed) with the R6 hook-outside-lock recheck verified in the merged file → migration
  `a1b2c3d4e5f6` applied in-band to BOTH `lupin_db_dev` and `lupin_db_test` (`fcm_tokens`
  verified present) → post-merge **WS smoke 50/50 on `:7999`** → **AC-S6.1 integration GREEN on
  `:8000`: run receipt `ts-05d941f6`, 6/6 passed** (cross-process re-instantiate-from-store
  rehydration + upsert-never-duplicates + idempotent unregister + auth matrix, against the
  bounced post-merge snapshot). Remaining `[ ]` in §5 is solely the EXECUTOR: HUMAN OSQ-7
  Firebase-console row — the wake channel boots DISABLED with a clear log line until Rick's
  console pass; everything code-side is live behind it.
