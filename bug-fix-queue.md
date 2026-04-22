# Bug Fix Queue — Lupin Mobile

**Format Version**: 2.0
**Last Updated**: 2026-04-22T10:00:00
**Repo**: `src/lupin-mobile` (standalone Flutter subtree within Lupin)

> **Purpose**: Track known defects — things we need to *fix*. Build-out work
> (new features, polish, testing playbook stages) belongs in `TODO.md`.
> Mirrors the parent `/mnt/DATA01/include/www.deepily.ai/projects/lupin/bug-fix-queue.md` v2.0 format.

---

### Active Sessions

| Session ID | Started             | Last Activity        | Status    | Commit               | Notes                                          |
|------------|---------------------|----------------------|-----------|----------------------|------------------------------------------------|
| 1fb8dc65   | 2026-04-19T14:00:00 | 2026-04-20T20:50:00  | committed | ab2a56c + 660374a    | URL-encoding (notif + DP) · WS lifecycle · HTTP idempotency |

---

### Queued

*(Available for any session to claim.)*

---

### Cross-Repo (fix lives in another repo, tracked here for visibility)

- [ ] **Lupin backend: queue-metadata mapping omits `artifacts['audio_path']` for podcast jobs** *(Lupin backend → fix lives in `/mnt/DATA01/include/www.deepily.ai/projects/lupin/src/cosa/rest/routers/queues.py`, severity: medium)*
  - **Symptom**: `JobSummary.reportPath` is always `null` for `pg-*` and `rp-*` jobs in the mobile client. The done-queue / dead-queue metadata payload from the backend never carries the audio file path.
  - **Root cause**: `routers/queues.py:456` and `:523` enumerate `artifacts.get('report_path')`, `artifacts.get('yaml_path')`, `artifacts.get('pptx_path')`, etc., but **never read `artifacts.get('audio_path')`**. Meanwhile, podcast `job.py:281,398` writes `self.artifacts["audio_path"] = self.audio_path`, so the field exists on the server side but is never surfaced.
  - **Impact on lupin-mobile**: Blocks Phase 4b of the in-app `AudioArtifactPlayer` work (Phase 4a ships the playback UI; 4b switches it to use the real `audio_path` once exposed). With no fix, podcast jobs cannot be played in-app — the UI renders an empty download path.
  - **Fix sketch (parent repo)**: Add `"audio_path": job.artifacts.get('audio_path') if is_agentic_job else None,` to the dict at lines 456 and 523. Mobile follow-up (Phase 4b): add `audioPath` to `JobSummary` model in `queue_models.dart`, switch `JobDetailScreen._viewArtifact()`'s `pg-*`/`rp-*` branch to use it (~10 lines + 1 fixture refresh).
  - **Discovered**: 2026-04-22, session `40aa03d3`, during Phase 0 of the Tier 2 + Tier 4 polish slate.

---

### In Progress

*(none)*

---

### Completed

- [x] **Lupin backend: `NotificationFifoQueue` had no attribute `_emit_queue_update`** *(parent Lupin, severity: high)* — `POST /api/notifications/{id}/played` returned HTTP 500 because `mark_played` called a method that had been renamed/removed on `NotificationFifoQueue`. Impact on mobile: every response submission ended with a silently-swallowed mark-played failure (caught at `notification_bloc.dart:97`); server-side unread-count tracking was broken. **Fix landed in parent Lupin repo** (`src/cosa/rest/notification_fifo_queue.py` — restored the method). Confirmed fixed by user on 2026-04-22. — Discovered 2026-04-20 session `1fb8dc65`; resolved 2026-04-22.

- [x] **WebSocket lifecycle never wired to `AuthAuthenticated`** *(lupin-mobile, severity: high)* — `WebSocketService.connect()` was never invoked after login; the `_dispatchWsEvent` router in `lib/app.dart` was dead code at runtime. **Fix**: new `WsLifecycleListener` widget driving `ws.connect(userId:)` on `AuthAuthenticated` and `ws.disconnect()` on `AuthUnauthenticated`/`AuthError`; wrapped `MaterialApp` in `lib/app.dart`. 5 widget tests covering the full state-transition matrix. Plan doc: `src/rnd/v0.1.7/2026.04.19-ws-lifecycle-auth-wiring-plan.md`. **On-device validated (emulator, 2026-04-20)**: test `notify()` arrived in the Inbox in real time without pull-to-refresh. — Commit `660374a`, 2026-04-20, session `1fb8dc65`.

- [x] **Duplicate HTTP log output on every request (diagnosed as log-layer, not dispatch-layer)** — Every request appeared twice in logcat because `HttpService._configureDio()` was running twice on the shared DI-singleton Dio: once via `HttpService` ctor and again via `CachedHttpService` ctor (which `extends HttpService` and calls `super(dio)`). Each call re-added `LogInterceptor` + `InterceptorsWrapper` to the same Dio → one real HTTP call produced 2× log entries, masquerading as duplicate dispatch. **Fix**: guarded `_configureDio()` with an idempotency marker on `_dio.options.extra['_lupin_http_configured']`. Subsequent calls short-circuit. 2 new unit tests in `test/unit/services/network/http_service_test.dart` assert (a) second instance on same Dio adds 0 interceptors, (b) different Dios configure independently. 178/178 tests green. — Commit `660374a`, 2026-04-20, session `1fb8dc65`.
- [x] **`DecisionProxyRepository` URL-encoding parity** — applied the same `_enc()` helper pattern to DP repo. 3 sites encoded: `pending/$userEmail` (`:56`), `trust/$userEmail` (`:120`), `decisions/$domain/$category` (`:139`). Regression test asserts `+aliases` and `@` in userEmail are percent-encoded. Updated 3 pre-existing handler keys in repo + bloc tests (`u@x.y` → `u%40x.y`). 176/176 unit + widget tests green. — 2026-04-20, session `1fb8dc65` Commit `660374a`.
- [x] **`NotificationRepository` URL-encoding bug** — raw path-param interpolation broke FastAPI routing on slash-bearing sender IDs (e.g. `peer-queue-watch/<uuid>`). Fixed via top-level `_enc()` helper (`Uri.encodeComponent`) applied to all 11 path-interpolation sites across senderId / userEmail / userId / project / dateString. Regression test covers slash-bearing sender IDs + `@` in email. Updated 7 pre-existing handler keys across repo + bloc tests to match the encoded form. 170/170 unit + widget tests green. — Commit `ab2a56c`, 2026-04-20, session `1fb8dc65`.
