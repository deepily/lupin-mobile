# S5 Phase-0 On-Device Probe — Background-Isolate Wake Chain

**Artifact**: the S5 §4 Phase-0 probe (EXECUTOR: AI authors / EXECUTOR: HUMAN executes —
laptop split: the dev server has no adb, no device, no Play services).
**Gates**: ALL §3.2.4 milestone claims — the handler-does-the-work chain (F-S5-S2-1,
USER-RULED shape (2)) is NOT declared delivered until this probe's receipt lands in
14-section-s5 §8. Probe failure ⇒ documented fallback to catch-up-on-pickup (shape 3)
WITH evidence, per the ruling.
**Author**: Rio ⚡ (session `ad7692cc`), 2026-06-12.
**Research grounding**: [20-fcm-background-isolate-explainer.md](20-fcm-background-isolate-explainer.md)

## What the probe must establish (the two ruling conditions)

1. **The refresh→access EXCHANGE path works in a fresh isolate.** The access token is
   memory-only (`auth_token_provider.dart:14`) and never exists in the background isolate;
   the handler reads the REFRESH token from secure storage and exchanges it
   (`POST /auth/refresh`). The probe MUST confirm the exchange fires — a fresh-login
   access token cannot mask it here because the production chain never reads one, but the
   probe still asserts the logcat line as positive evidence.
2. **Plugin-initiated TTS playback survives (or doesn't survive) Dart-handler completion.**
   The handler awaits utterance completion (`awaitSpeakCompletion(true)`), but the OS may
   reclaim the isolate at the ~30s budget. The probe measures where audio stops relative
   to the handler-complete log line — this pins the 30s-budget posture and the
   foreground-service-exemption contingency decision (§3.2.4 contingency bullet).

The probe reuses the PRODUCTION chain verbatim — `fcmBackgroundHandler` →
`buildBackgroundWakeChain()` (`lib/services/push/fcm_bootstrap.dart`) — no throwaway
handler code to drift; the "throwaway" part is only the synthesized wake payload below.

## Prerequisites (laptop-side)

1. **OSQ-7 console pass complete** (Rick — see
   [91-osq7-firebase-console-runbook.md](91-osq7-firebase-console-runbook.md)):
   Firebase project, Android app `ai.deepily.lupin_mobile` registered,
   `google-services.json` downloaded, service-account key JSON saved, FCM v1 API enabled.
2. **Gradle wiring** (the step the committed code intentionally leaves open — applying the
   plugin without the json breaks every build, so it rides THIS pass):
   - copy `google-services.json` → `android/app/google-services.json`
   - `android/settings.gradle.kts` → plugins block: add
     `id("com.google.gms.google-services") version "4.4.2" apply false`
   - `android/app/build.gradle.kts` → plugins block: add
     `id("com.google.gms.google-services")`
   - Do NOT commit these three changes until the probe passes (they hard-gate every
     subsequent build on the json being present).
3. **Build with the flag ON** (the default-OFF flag is AC-S5.4's Stage-1 safety):
   ```bash
   rsync (dev-server → laptop, per the established build split)
   flutter build apk --debug --dart-define=ENABLE_FCM=true
   adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```
4. **Login once** on the device against the dev context (`:7999`) — this writes the
   refresh token + last email to secure storage (the handler's bootstrap inputs) and
   registers the FCM token with the parent (watch for
   `[FcmWakeup] token registered (upsert)` in logcat).
5. **Capture the device token** for the synthesized send: logcat the registration POST,
   or query the parent registry (S6's durable store) for the row just upserted.

## Synthesized wake payload (the throwaway part)

Send a data-only, HIGH-priority message directly via the FCM v1 HTTP API using the
OSQ-7 service-account key — S6's sender does not need to exist yet:

```python
# probe-send-wake.py — laptop-side, throwaway
# pip install google-auth requests
import google.auth.transport.requests, google.oauth2.service_account, requests, json

SA_KEY  = "path/to/service-account.json"   # from OSQ-7
PROJECT = "<firebase-project-id>"
TOKEN   = "<device-fcm-token>"             # from prerequisite 5

creds = google.oauth2.service_account.Credentials.from_service_account_file(
    SA_KEY, scopes=[ "https://www.googleapis.com/auth/firebase.messaging" ] )
creds.refresh( google.auth.transport.requests.Request() )

msg = {
    "message": {
        "token"   : TOKEN,
        "data"    : { "type": "ws_wake", "reason": "undelivered",
                      "ts": "2026-06-12T00:00:00Z" },
        "android" : { "priority": "HIGH" },           # the Doze-delivery flag (S6 §3.2)
    }
}
r = requests.post(
    f"https://fcm.googleapis.com/v1/projects/{PROJECT}/messages:send",
    headers={ "Authorization": f"Bearer {creds.token}",
              "Content-Type": "application/json" },
    data=json.dumps( msg ) )
print( r.status_code, r.text )
```

Note the payload is EXACTLY the §3.1 contract shape (`type`/`reason`/`ts`, data-only,
no `notification` block, `android.priority: HIGH`).

## Probe steps

Seed one undelivered notification first (so the fetch has something to find): from the
dev server, `POST /api/notify` a HIGH-priority message to your user while the phone app
is killed.

| # | Step | Expect (logcat filter: `adb logcat | grep -E "FcmWake|flutter"`) |
|---|---|---|
| p1 | App killed (swipe away), screen OFF, wait 2 min (light doze) | — |
| p2 | Run `probe-send-wake.py` | HTTP 200 from FCM |
| p3 | Watch logcat | `[FcmWake] wake received, reason=undelivered` |
| p4 | **Ruling condition 1** | `[FcmWake] refresh→access exchange ok` — the exchange path, exercised in a fresh isolate |
| p5 | Fetch + show | `[FcmWake] fetched 1 (...)` then `[FcmWake] shown` + the LOCAL notification appears |
| p6 | Speak | ONE spoken utterance (the `message` field only), audible with screen off |
| p7 | **Ruling condition 2** | note WHEN `[FcmWake] outcome: ...` logs vs when audio STOPS: audio finishing BEFORE the outcome line = handler-held playback (expected with awaitSpeakCompletion); audio CONTINUING after = survives completion; audio TRUNCATING at the line = does NOT survive — record which |
| p8 | Repeat p2 immediately (dedupe) | `[FcmWake] fetched 0 — nothing undelivered` (mark-played dedupe held) |
| p9 | Speak-toggle OFF (Settings → notification audio → master mute), re-seed + re-send | `shown` fires, `muted by speak-toggle prefs` — no audio |
| p10 | Deep doze (optional, stronger): `adb shell dumpsys deviceidle force-idle`, re-seed + re-send | same chain (HIGH priority pierces Doze); record latency |
| p11 | Pick the phone up, open the app | focus surface re-hydrates (unread badge on the rail), NO auto re-speak |

## Receipt (file into 14-section-s5 §8)

```
PROBE RECEIPT — <date>, executor: <name>, device: <model/Android version>
p3 wake received:            PASS / FAIL
p4 exchange in fresh isolate: PASS / FAIL
p5 fetch+show:               PASS / FAIL
p6 single utterance audible:  PASS / FAIL
p7 TTS-vs-handler-completion: held-open / survives / truncates  (+ observed seconds)
p8 dedupe:                   PASS / FAIL
p9 prefs gate:               PASS / FAIL
p10 deep doze (optional):     PASS / FAIL / skipped (+ latency)
p11 pickup, no auto re-speak: PASS / FAIL
VERDICT: shape-2 CONFIRMED / shape-3 FALLBACK (attach failing-step evidence)
```

- **All green** → §3.2.4 milestone DELIVERED; the HUMAN doze gate (AC-S5 last checkbox)
  can then be folded into the Stage-2 runbook session.
- **p6/p7 failure** (utterance unreliable inside the budget) → evaluate the §3.2.4
  contingency (foreground-service exemption window) before falling back.
- **Hard failure** → shape-3 catch-up-on-pickup fallback WITH this receipt as evidence,
  per the USER ruling.
