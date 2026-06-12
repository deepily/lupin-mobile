# Section S5 — FCM Silent-Relay Wake-Up (Mobile)

**Stage**: 2
**Anchors**: [01-architecture.md](01-architecture.md) · [02-decisions.md](02-decisions.md) Q10, OSQ-6, OSQ-7 · [03-testing-strategy.md](03-testing-strategy.md) · prior R&D `../v0.1.7/2026.04.21-fcm-apns-push-considerations.md` §7
**Provides**: background wake-up capability (no API surface consumed by other sections)
**Consumes**: S6 interface — data-only FCM push contract + token-registration endpoint + WS
client-type marker obligation (restated in §3.1 so this section reviews cold). The
missed-message pull is NOT a section dependency: it terminates into Stage 1's app-level WS-reconnect
re-hydration wiring (S2 §3.3), which exists before Stage 2 lands — see 00-index.md DAG
clarifying amendment (F-S5-1c).

## 1. Purpose

When the app is backgrounded/dozed, Android kills the WebSocket — notifications stop. The
silent-relay variant (Q10) restores the "one listening channel": a data-only FCM message wakes a
background handler that FETCHES the notification from the parent and SPEAKS it (the 2026.04.21
§Option A′ chain — hear-while-dozing is the delivered value, F-S5-S2-1 USER-RULED shape (2)).
Notification CONTENT never rides Google's infrastructure — FCM carries only the wake; the
content travels over the authenticated fetch. On next foreground, the normal WS reconnect +
re-hydration path (Stage 1) catches up the visual surface.

## 2. Scope

**In**: Firebase SDK bootstrap (`firebase_core`, `firebase_messaging`); `FcmWakeupService`
(`lib/services/push/fcm_wakeup_service.dart`); token lifecycle (obtain, register with parent,
refresh, re-register on WS reconnect); WS client-type marker at connect (F-S6-1 obligation);
background data-message handler performing the A′ fetch→notify→speak chain in its own isolate
(F-S5-S2-1 ruling); Phase-0 on-device probe gating that chain; doze-aware behavior notes; tests.

**Out**: parent-side sender + token registry + Firebase project provisioning (S6); rendering
notification CONTENT from FCM payloads (FORBIDDEN — the payload is content-free; content arrives
only via the handler's authenticated fetch or the reconnected WS); iOS/APNs (out of milestone
scope entirely); ANY WebSocket interaction from the background handler (Rick directive 1 —
reconnect stays foreground-lifecycle, owned by `WebSocketService`/`AppLifecycleService` per
F-S5-1a/b); main-isolate service-locator access from the handler (unreachable by construction —
see §3.2.4 bootstrap).

## 3. Design

### 3.1 Consumed contract (provided by S6 — restated for cold review)

- **Push shape**: data-only FCM message (no `notification` block, so no OS-rendered banner),
  payload `{ "type": "ws_wake", "reason": "<undelivered|reconnect-hint>", "ts": "<iso8601>" }`.
  `reason` is the two-value ENUM shown (aligned with S6 §3.2, F-S5-2.ii). Sent at
  `android.priority: HIGH` (FCM HTTP v1 — the Doze-delivery flag, S6 §3.2; the same element is
  noted narratively in §3.2.5). Content-free by design.
- **Token registration** (OSQ-6 proposed shape — S6 owns the final shape and must update BOTH
  section files if it changes; explicit cross-section dependency, see 00-index.md DAG):
  - `POST /api/fcm/register-token` (JWT) — body `{ "token": str, "platform": "android",
    "user_email": str }` → 200 `{ "status": "ok" }`. Upsert keyed on token.
  - `DELETE /api/fcm/register-token` (JWT) — body `{ "token": str }` → 200. Best-effort logout
    path (consumed by §3.2.2; AC-S5.2 tests it). *Parent-design flag (S6 Stage-1 residual)*:
    DELETE-with-JSON-body is proxy-fragile — parent design confirms or switches to
    `POST /api/fcm/unregister-token` under the OSQ-6 amendment rights; any switch propagates to
    this restatement before either side implements.
- **WS client-type marker (F-S6-1, S5-side OBLIGATION)**: the mobile app includes
  `"client_type": "mobile"` in its WS `auth_request` payload so the parent can distinguish the
  mobile WS from web sessions; absent marker ⇒ treated as web (backward-compatible — existing
  web clients send nothing); the wake trigger fires on "no live MOBILE WS" (a desktop browser
  must not suppress the phone's wake). Restated verbatim from S6 §3.0; AC-S6.5's sync check
  covers both files. Implementation note: this lands in the WS auth payload assembly
  (`WebSocketService` connect/auth path) — a one-field addition, active in Stage 1 builds too
  (harmless: parent treats absent-or-present uniformly until S6 lands).

### 3.2 FcmWakeupService

1. **Bootstrap**: `Firebase.initializeApp()` behind a COMPILE-TIME flag (F-S5-2.i — repo
   precedent: `const bool.fromEnvironment` as in `performance_monitor.dart` /
   `streaming_tts_player.dart`): `--dart-define=ENABLE_FCM=true`, default OFF, so Stage-1 builds
   don't require `google-services.json` (OSQ-7: file provisioning is EXECUTOR: HUMAN,
   laptop-side).
2. **Token lifecycle**: on login (hook = the existing auth-state stream's AUTHENTICATED
   transition — the same signal `AuthGate` renders on; seam named per Arnold residual #1) →
   obtain FCM token → register with parent; listen to `onTokenRefresh` → re-register; on
   logout → best-effort unregister. ALSO re-register on every
   WS RECONNECT (F-S6-S2-1(b)): registration is an idempotent upsert keyed on token, so this is
   one cheap call — it covers parent-restart registry loss, which `onTokenRefresh` can never see
   (the FCM token didn't change; Google doesn't know Lupin restarted), plus any
   durable-storage-with-data-loss case.
3. **Foreground data message**: no-op beyond a debug log (WS is already live).
4. **Background data message — HANDLER-DOES-THE-WORK (F-S5-S2-1, USER-RULED shape (2), per the
   2026.04.21 §Option A′ chain; research grounding:
   [20-fcm-background-isolate-explainer.md](20-fcm-background-isolate-explainer.md))**: the
   top-level `@pragma('vm:entry-point')` handler runs in a FRESH isolate — empty service
   locator, main isolate possibly dead — and performs the A′ single-utterance chain ITSELF:
   - **Self-contained bootstrap** (Arnold residual #3, mandated): the handler initializes its
     OWN minimal dependencies — fresh Dio instance; REFRESH token read from secure storage and
     EXCHANGED for a fresh access token (the access token is memory-only,
     `auth_token_provider.dart:14` — it does not exist in a fresh isolate; Arnold spot-check
     amendment 2026-06-12); speak-toggle prefs read from local storage. It NEVER touches the
     main app's service locator or singletons (unreachable by construction — isolate boundary).
   - **Fetch**: authenticated GET of the user's latest undelivered notifications via the
     EXISTING notifications API (the FCM payload stays content-free — NO new S6 contract
     element; exact endpoint pinned at implementation Phase 0).
   - **Notify + speak**: `flutter_local_notifications.show` (plugin RE-INITIALIZED inside the
     handler) + ONE `flutter_tts` utterance speaking the TTS-brevity `message` field ONLY —
     never abstract/payload bodies. Fresh `flutter_tts` instance; strict fetch-one-speak-one
     shape (`flutter_tts#260` rapid-repeat crash mode). Respects the user's persisted
     speak-toggle prefs (the background path's only gate — the foreground pause is bloc state
     and does not persist).
   - **WS lifecycle (Rick directive 1)**: the handler NEVER touches the WebSocket. Each FCM
     push is an independent wake→fetch→speak event; WS reconnect remains the existing
     foreground-lifecycle behavior (app resume → lifecycle hook → reconnect → S2 §3.3
     re-hydration) — normal pickup IS the trigger, automatically, no manual user action.
     Optional rider (author's call, recorded): the IsolateNameServer poke for the
     backgrounded-but-alive case is DEFERRED from v1 — cheap but adds a release-mode
     version-pin check (`flutter#113825`) and the pickup path already covers its benefit;
     documented as a v1.1 candidate.
   - **Long text / 30s budget (Rick directive 2)**: background audio is BEST-EFFORT — if the
     OS reclaims the isolate mid-utterance, audio truncates, and NOTHING is lost: notifications
     are durably stored server-side and re-hydrate into the focus chat on next foreground.
     Re-speak-on-pickup (author-ruled per recommendation): NO auto re-speak — unread badges
     carry the signal; surprise audio on pickup would violate the surface's predictability
     ethos. The handler must complete inside the ~30-second budget; the Phase-0 probe measures
     whether plugin-initiated TTS playback survives Dart-handler completion.
   - **Contingency (probe-informed)**: if a single utterance cannot reliably complete, the
     Android-12+ foreground-service exemption window following a high-priority FCM message is
     the documented fallback path (check `RemoteMessage.priority == high`, start fast) —
     design detail deferred to the probe outcome; if the probe fails outright, fall back to
     catch-up-on-pickup (shape 3) with evidence in hand, per the ruling.
5. **Doze reality**: FCM data-only messages are subject to Doze batching unless sent
   high-priority; S6's sender uses `android.priority: HIGH` for `ws_wake` (contract element in
   §3.1; restated from §7 R&D).

## 4. Tasks

- [ ] Firebase deps + `ENABLE_FCM` dart-define-gated bootstrap (default OFF; no hard dependency
      for Stage-1 builds)
- [ ] FcmWakeupService: token lifecycle vs S6 endpoint
- [ ] `client_type: "mobile"` field in the WS auth payload (F-S6-1 obligation; §3.1)
- [ ] Phase-0 PROBE (gates all §3.2.4 implementation tasks; F-S5-S2-1 ruling condition):
      EXECUTOR: AI authors the probe — throwaway `@pragma('vm:entry-point')` handler +
      synthesized wake payload + step-by-step device runbook; EXECUTOR: HUMAN executes on the
      device (laptop split — no adb on dev server): authenticated fetch + ONE TTS utterance
      with screen OFF under doze, AND measure whether plugin-initiated TTS playback survives
      Dart-handler completion. The probe MUST exercise the refresh→access EXCHANGE path (a
      fresh-login access token would mask it — the memory-only token never exists in the
      isolate). Probe failure ⇒ documented fall-back to catch-up-on-pickup (shape 3) with
      evidence, per the ruling.
- [ ] Background handler per §3.2.4: self-contained bootstrap (Dio + secure-storage auth +
      local-storage prefs) → fetch → local notification → single utterance. Foreground catch-up
      stays the Stage-1 wiring (WS reconnect → S2 §3.3 re-hydration, F-S5-1c — no new pull code;
      handler never touches the WS, Rick directive 1)
- [ ] Debug hook: log every wake with reason + chain outcome (fetched n / shown /
      spoke|muted|truncated — field-debuggable from `adb logcat`)
- [ ] Record green baseline suite count in §8 Execution Log BEFORE first edit (testing-strategy
      rule 1; F-S1-S3-2 family)
- [ ] Tests (§5) + full-suite regression

## 5. Acceptance Criteria

- [ ] EXECUTOR: AI (executability conditional on OSQ-6 resolution — the registration payload
      shape is S6-owned; until OSQ-6 closes, this AC carries this same-line dependence note) —
      AC-S5.1 unit: token obtained → registration POST fired with the §3.1-declared payload
      (mock Dio + mock messaging).
- [ ] EXECUTOR: AI — AC-S5.2 unit: `onTokenRefresh` re-registers; logout unregisters. Extended
      (F-S6-S2-1(b)): WS reconnect triggers a re-registration POST (idempotent upsert — mock Dio
      asserts the repeat call).
- [ ] EXECUTOR: AI — AC-S5.3 unit (re-targeted per the F-S5-S2-1 reshape): `ws_wake` data
      message → the handler performs token-exchange → fetch → show → ONE speak, in order, using
      ONLY its constructor-injected/bootstrapped seams (mock secure-storage/refresh-exchange
      seam + mock Dio + mock notifications plugin + mock TTS;
      ZERO service-locator access — assert the locator is never queried); speak-toggle prefs OFF
      ⇒ fetch + show fire, speak does NOT; the spoken text is the `message` field only; unknown
      types logged and ignored (defensive).
- [ ] EXECUTOR: AI — AC-S5.4 widget/unit: app builds and runs with `ENABLE_FCM` OFF (the
      default) — Stage-1 regression safety; flag grep-able as `--dart-define=ENABLE_FCM`.
- [ ] EXECUTOR: AI — AC-S5.5 unit (F-S6-1): WS auth payload includes `client_type: "mobile"`
      (fixture-pinned against the §3.1 contract).
- [ ] EXECUTOR: HUMAN (hardware: real doze + Play-services FCM delivery cannot be emulated
      faithfully in unit tests) — on-device gate: background the app (screen off, doze),
      dispatch a wake via S6's sender, observe the LOCAL NOTIFICATION + the SPOKEN utterance
      from the background handler; then pick up the device and observe foreground re-hydration
      (S2 §3.3) with NO auto re-speak (the author-ruled pickup behavior); bundled into the
      Stage-2 runbook session. (The Phase-0 probe gate in §4 runs FIRST and separately.)

## 6. Open Items

OSQ-6 (endpoint shape — owned by S6; amended 2026-06-12 with the client-type marker), OSQ-7
(Firebase provisioning — EXECUTOR: HUMAN). Anchored in 02-decisions.md.

## 7. Revision Log

- **2026-06-12 (Stage-1 close, findings F-S5-1..2 + F-S6-1 thread)**: F-S5-1 (inconsistency) —
  three seams NAMED: (a) reconnect pokes `WebSocketService`'s existing machinery
  (`:17-24`/`:77`/`:281-286`), never owns retry; (b) next-resume hooks `AppLifecycleService`
  (`:106`/`:154`), no second observer; (c) missed-message pull rides Stage 1's WS-reconnect
  re-hydration (S2 §3.3 `FocusColdStartRequested`) — Consumes line + 00-index DAG note amended
  accordingly (no Stage-1 section dependency; integration-level seam). AC-S5.3 re-pinned at the
  poke-not-reimplement assertion. F-S5-2 (cosmetic) — (i) flag mechanism named:
  `const bool.fromEnvironment`/`--dart-define=ENABLE_FCM`, default OFF (repo precedent
  `performance_monitor.dart`/`streaming_tts_player.dart`); AC-S5.4 grep-able. (ii) `reason` enum
  aligned with S6 §3.2 (enum pinned S6-side). F-S6-1 thread — §3.1 gains the client-type marker
  obligation verbatim + implementation note; new AC-S5.5 pins the auth-payload field. Author
  pre-flag closed: AC-S5.1 carries the same-line OSQ-6 conditionality clause (Run-2 close
  pattern).
- **2026-06-12 (F-S6-S2-1(b) touchpoint + F-S1-S3-2 family fix)**: token lifecycle gains
  re-register-on-WS-reconnect (idempotent upsert — covers parent-restart registry loss invisible
  to `onTokenRefresh`); AC-S5.2 extended. §8 Execution Log placeholder + baseline task line
  added. NOTE: all OTHER S5 Stage-2 revisions are ON HOLD pending the user's goal-level ruling on
  F-S5-S2-1 (background-isolate gap) per Manager instruction — this entry is the only authorized
  touch.
- **2026-06-12 (F-S5-S2-1 RESHAPE — USER-RULED shape (2) "handler-does-the-work", hold
  lifted)**: §1/§2/§3.2.4 re-specified to the 2026.04.21 §Option A′ chain per Rick's verbatim
  ruling (recorded on the section topic 02:50Z; grounding:
  20-fcm-background-isolate-explainer.md). Both embedded directives answered in operative
  text — (1) WS lifecycle: handler NEVER touches the WS; each push = independent
  wake→fetch→speak; reconnect stays foreground-lifecycle; IsolateNameServer poke DEFERRED to
  v1.1 (author's call: version-pin risk `flutter#113825`, pickup path covers it). (2) Long
  text/30s: handler speaks the TTS-brevity `message` field only; audio best-effort; durable
  store + re-hydration = zero data loss; NO auto re-speak on pickup (author-ruled — unread
  badges carry the signal). Self-contained dependency bootstrap mandated (Arnold residual #3);
  login-hook seam named (auth-state authenticated transition, residual #1); Phase-0 on-device
  probe task gates the chain (AI authors / HUMAN executes per the laptop split; measures
  TTS-survives-handler-completion); AC-S5.3 re-targeted to the new mock seams (zero
  service-locator access asserted, prefs gate, message-field-only); HUMAN doze gate re-worded
  (notification + spoken utterance under doze; no auto re-speak on pickup).
  **PROPAGATION CHECK: NO §3.1 contract ELEMENT changed** — payload stays content-free, the
  fetch rides the EXISTING notifications API, endpoints/fields/marker/enum/priority all
  untouched; S6 §3 re-sync NOT required; Cheech's AC-S6.5 cascade-close comparison may run.
- **2026-06-12 (Arnold spot-check micro-amendment)**: bootstrap auth corrected — the ACCESS
  token is memory-only (`auth_token_provider.dart:14`) and never exists in a fresh isolate;
  the handler reads the REFRESH token from secure storage and exchanges it for an access token.
  Clause added to the §3.2.4 bootstrap, the §4 Phase-0 probe (MUST exercise the exchange path —
  fresh-login tokens mask it), and AC-S5.3's seam list.
- **2026-06-12 (Stage-3 close, finding F-S5-S3-1 — CONCUR, mechanical §3.1 completion pass)**:
  Cheech's AC-S6.5 cascade-close comparison FAILED 4/6 elements, all S5-§3.1
  restatement-completeness gaps (zero semantic conflicts; each element verified against S6 §3
  before editing). §3.1 completed: (1) DELETE `/api/fcm/register-token` unregister endpoint
  added with full body/response shape + the S6 proxy-fragility parent-design flag (S5 consumes
  it — §3.2.2 logout, AC-S5.2); (2) registration response shape `200 {"status": "ok"}` added;
  (3) absent-means-web rule stated explicitly in the marker bullet (was implied — the
  "restated verbatim" claim is now true); (4) `android.priority: HIGH` added to the push-shape
  element (was only in §3.2.5 with the drifted `priority: high` spelling — §3.2.5 aligned to
  the canonical key name, pointing back at §3.1). No S6-side edit; the implementation-start
  AC-S6.5 re-run (parent session) re-verifies. S5 closes all three stages with this revision —
  cascade's last open finding.

## 8. Execution Log

*(Placeholder per working-contract §Phase-Complete Definition + testing-strategy rule 1 —
populated at implementation time, NOT during the cascade.)*

- [ ] Green baseline suite count recorded BEFORE first edit: `____` (date/time, command, count)
- Per-AC evidence entries land here as each §5 checkbox flips to `[x]` (test output, probe
  response, or named HUMAN sign-off).
