# Bug Fix Queue — Lupin Mobile

**Format Version**: 2.0
**Last Updated**: 2026-04-20T20:40:00
**Repo**: `src/lupin-mobile` (standalone Flutter subtree within Lupin)

> **Purpose**: Track known defects — things we need to *fix*. Build-out work
> (new features, polish, testing playbook stages) belongs in `TODO.md`.
> Mirrors the parent `/mnt/DATA01/include/www.deepily.ai/projects/lupin/bug-fix-queue.md` v2.0 format.

---

### Active Sessions

| Session ID | Started             | Last Activity        | Status    | Notes                                          |
|------------|---------------------|----------------------|-----------|------------------------------------------------|
| 1fb8dc65   | 2026-04-19T14:00:00 | 2026-04-20T20:20:00  | active    | URL-encoding fix + post-login WS lifecycle wiring |

---

### Queued

*(Available for any session to claim.)*

---

### Cross-Repo (fix lives in another repo, tracked here for visibility)

- [ ] **Lupin backend: `NotificationFifoQueue` has no attribute `_emit_queue_update`** *(Lupin backend → fix lives in `/mnt/DATA01/include/www.deepily.ai/projects/lupin/src/cosa/rest/`, severity: high)*
  - **Symptom**: `POST /api/notifications/{id}/played` returns HTTP 500 with body:
    ```json
    {"detail":"Failed to mark notification as played:
             'NotificationFifoQueue' object has no attribute '_emit_queue_update'"}
    ```
  - **Root cause**: Somebody renamed or removed `_emit_queue_update` on `NotificationFifoQueue` without updating the `mark_played` call site.
  - **Impact on lupin-mobile**: Every response submission ends with a failed mark-played; user sees no error banner (bloc catches it silently per `notification_bloc.dart:97`) but server-side unread-count tracking is broken.
  - **Fix location**: NOT in this repo. Suspected file: `src/cosa/rest/notification_fifo_queue.py` (parent Lupin repo). File this in the parent `bug-fix-queue.md` too when convenient; here it's for cross-repo visibility.
  - **Discovered**: 2026-04-20, session `1fb8dc65`, during WS-lifecycle on-device verification.

---

### In Progress

*(Claimed by a specific session — code is on disk pending commit or further review.)*

- [ ] **WebSocket lifecycle never wired to `AuthAuthenticated`** *(lupin-mobile, severity: high — fix validated, awaiting commit)*
  - **Symptom**: `WebSocketService.connect()` was never invoked after login. The `_dispatchWsEvent` router in `lib/app.dart` (notification/queue/claude-code events → BLoCs) was dead code at runtime. Track-C inbox auto-refresh (wired 2026-04-17) silently dropped every event.
  - **Fix** *(code on disk, uncommitted)*:
    - New `lib/features/auth/presentation/ws_lifecycle_listener.dart` — `BlocListener<AuthBloc>` with `listenWhen` on `runtimeType` change, firing injected `onAuthenticated(userId)` / `onSignedOut()` hooks.
    - `lib/app.dart` wraps `MaterialApp` with `WsLifecycleListener`; callbacks drive the DI-singleton `WebSocketService` with `isConnected` guards.
    - 5 new widget tests (`test/widget/auth/ws_lifecycle_listener_test.dart`) covering the transition matrix.
  - **Tests**: 175/175 green (170 baseline + 5 new).
  - **On-device verification (2026-04-20, emulator)**: Confirmed the test `notify()` arrived in the Inbox in real time without pull-to-refresh. ✅
  - **Plan doc**: `src/rnd/v0.1.7/2026.04.19-ws-lifecycle-auth-wiring-plan.md`.
  - **Session**: `1fb8dc65`.

---

### Completed

- [x] **Duplicate HTTP log output on every request (diagnosed as log-layer, not dispatch-layer)** — Every request appeared twice in logcat because `HttpService._configureDio()` was running twice on the shared DI-singleton Dio: once via `HttpService` ctor and again via `CachedHttpService` ctor (which `extends HttpService` and calls `super(dio)`). Each call re-added `LogInterceptor` + `InterceptorsWrapper` to the same Dio → one real HTTP call produced 2× log entries, masquerading as duplicate dispatch. **Fix**: guarded `_configureDio()` with an idempotency marker on `_dio.options.extra['_lupin_http_configured']`. Subsequent calls short-circuit. 2 new unit tests in `test/unit/services/network/http_service_test.dart` assert (a) second instance on same Dio adds 0 interceptors, (b) different Dios configure independently. 178/178 tests green. — 2026-04-20, session `1fb8dc65` *(uncommitted)*.
- [x] **`DecisionProxyRepository` URL-encoding parity** — applied the same `_enc()` helper pattern to DP repo. 3 sites encoded: `pending/$userEmail` (`:56`), `trust/$userEmail` (`:120`), `decisions/$domain/$category` (`:139`). Regression test asserts `+aliases` and `@` in userEmail are percent-encoded. Updated 3 pre-existing handler keys in repo + bloc tests (`u@x.y` → `u%40x.y`). 176/176 unit + widget tests green. — 2026-04-20, session `1fb8dc65` *(uncommitted; bundling with WS lifecycle commit per user direction)*.
- [x] **`NotificationRepository` URL-encoding bug** — raw path-param interpolation broke FastAPI routing on slash-bearing sender IDs (e.g. `peer-queue-watch/<uuid>`). Fixed via top-level `_enc()` helper (`Uri.encodeComponent`) applied to all 11 path-interpolation sites across senderId / userEmail / userId / project / dateString. Regression test covers slash-bearing sender IDs + `@` in email. Updated 7 pre-existing handler keys across repo + bloc tests to match the encoded form. 170/170 unit + widget tests green. — Commit `ab2a56c`, 2026-04-20, session `1fb8dc65`.
