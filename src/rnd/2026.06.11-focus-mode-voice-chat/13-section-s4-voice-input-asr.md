# Section S4 — Voice Input → Whisper ASR → Reply

**Stage**: 1
**Anchors**: [01-architecture.md](01-architecture.md) · [02-decisions.md](02-decisions.md) Q3, Q5, OSQ-1, OSQ-2 · [03-testing-strategy.md](03-testing-strategy.md)
**Provides**: `VoiceReplyField` widget (consumed by S3) — self-contained record→transcribe→edit→send
composer taking a required `onSubmit( String text )` callback + optional `promptContext` (F-S3-2:
the widget never dispatches responses itself — S3 wires `onSubmit` to
`FocusChatBloc.add( FocusRespondRequested(...) )`); plus `AsrService`
**Consumes**: nothing from sibling sections (existing recorder/HTTP plumbing + parent endpoint only)

## 1. Purpose

Voice-to-text replies via the parent's improved-Whisper endpoint (Q3): push-to-talk record on
device, upload WAV, show the transcript editable, send through the focus surface's single
response-dispatch shape (F-S3-2).

## 2. Scope

**In**: `lib/services/asr/asr_service.dart`; `VoiceReplyField` widget
(`lib/features/focus_mode/presentation/voice_reply_field.dart`); `record` package dependency
(justified vs the in-tree `flutter_sound` in OSQ-2's 2026-06-12 amendment — F-S4-1);
mic-permission runtime flow via the EXISTING `permission_handler` (pubspec `:29`); Phase-0
wire-grounding of the ASR contract; MP3-trap disarm annotation (F-S4-2); tests.

**Out**: on-device STT (REJECTED, Q3); the MP3 endpoint (`/api/upload-and-transcribe-mp3` — queues
a multimodal job, wrong tool); structured-prompt buttons (S3); response dispatch mechanics (S2's
`FocusRespondRequested` handler owns the repository call); any TTS interaction.

## 3. Phase 0 — Wire-Grounding (BEFORE implementation tasks)

Already grounded from source (2026-06-11): `POST /api/upload-and-transcribe-wav` in parent
`src/cosa/rest/routers/speech.py` (router prefix `/api`, endpoint at `:646-653`) — accepts
multipart `file: UploadFile`, optional `prefix` query param, transcribes via Whisper, returns
transcription text. (Independently re-verified by Stage-1 review.)

Remaining to pin live (OSQ-1, OSQ-2):

- [x] EXECUTOR: AI — probe `:7999` authed + unauthenticated: confirm auth requirement, response
      Content-Type/shape, error envelope; capture as fixture with `_capture` provenance block.
      The probe also pins whether the endpoint expects the bearer the app's SHARED Dio attaches
      (AsrService receives the shared, auth-wired Dio instance from the service locator — see
      §4.1).
- [x] EXECUTOR: AI — read the web client's recorder parameters (sample rate / channels / encoding)
      in parent source; mirror them in `RecordConfig`. The `prefix` query param stays UNSET for
      chat replies unless the web client sends one (pin during this probe).

## 4. Design

### 4.1 AsrService

```dart
class AsrService {
  AsrService( { required this.dio, required this.recorder } );

  Future<void>   startRecording();                 // record pkg → WAV (PCM16; params per Phase 0)
  Future<String> stopAndTranscribe();              // stop → multipart POST → transcription text
  Future<void>   cancelRecording();                // discard, delete temp file
}
```

- Temp WAV under app cache dir; deleted after upload (success or failure).
- Timeouts: generous upload timeout (cellular); typed `AsrException` with context per error path
  (denied mic permission, recorder failure, HTTP non-200, empty transcript).
- Injected via service locator; `recorder` + `dio` are constructor seams for testing. The `dio`
  is the app's SHARED auth-wired instance (the one the auth repository rides,
  `service_locator.dart:162`) so the bearer travels for free.
- **Why not extend `HttpService`** (F-S4-2 divergence justification): AsrService's job bundles
  recorder lifecycle + temp-file hygiene + typed `AsrException` mapping around the upload —
  cohesion that doesn't belong in the generic HTTP wrapper. The multipart mechanics themselves
  follow the existing `HttpService` pattern (`http_service.dart:197-198`), so no novel wire code.
- **MP3-trap disarm** (F-S4-2): `HttpService.uploadAndTranscribe()` (`http_service.dart:192-211`)
  is LIVE, does the same multipart shape, advertises WAV in its docstring — but POSTs to the
  multimodal-job MP3 endpoint this plan brands wrong-tool. Task below annotates/deprecates it
  with a pointer to AsrService + the trap warning.

### 4.2 VoiceReplyField (the widget S3 embeds)

States: idle → recording (mic held / toggled, elapsed-time indicator) → transcribing (spinner,
CANCELABLE — a cellular timeout must never spinner-trap) → review (transcript in editable
TextField + Send / Cancel) → idle. **Transcribe failure** (any `AsrException` path): inline error
affordance (message + dismiss) → idle — a lost recording is VISIBLE feedback, never a vanishing
spinner (F-S4-S2-1a). **No `sending` state** (F-S4-S2-1b — dropped, orphaned by the F-S3-2
re-shape): Send invokes the injected `onSubmit( editedText )` callback EXACTLY ONCE and resets to
idle; send-failure surfacing belongs to S2/S3 bloc state (`hydration = error`), not this widget.
Mic-permission denial shows inline guidance, no crash (runtime request via the existing
`permission_handler`). Composer AVAILABILITY (no-pending-prompt case) is gated by S3 off S2's
`pendingPromptFor` signal (F-S2-S2-3) — the widget itself renders wherever embedded. Typed-text
entry remains available in review state (transcript is a seed, not a cage).

## 5. Tasks

- [x] Phase-0 probes + fixtures (§3)
- [x] EXECUTOR: AI (F-S4-S3-1; part of Phase 0, immediately after the OSQ-2 param pin — feeds
      AC-S4.7 directly): create the canned WAV fixture — SYNTHESIZED known-content speech (no
      microphone involved; dev server has none) rendered to the OSQ-2-pinned params, with a
      `_provenance` block (generation command, params, expected transcript), checked in at
      `test/fixtures/asr/`
- [x] `record` dependency (per OSQ-2 amended justification) + DI registration
- [x] Verify `RECORD_AUDIO` present in AndroidManifest (`:5` — already declared) +
      runtime-request via existing `permission_handler` (F-S4-3: verify-not-add)
- [x] AsrService per §4.1 (shared Dio seam)
- [x] Annotate/deprecate `HttpService.uploadAndTranscribe()` with MP3-trap warning + pointer to
      AsrService (F-S4-2 disarm; doc-comment touch on `lib/services/http/http_service.dart`,
      no behavior change)
- [x] VoiceReplyField per §4.2 + TestKeys (`voiceReplyMic`, `voiceReplyTranscript`,
      `voiceReplySend`, `voiceReplyCancel`, `voiceReplyError` — the F-S4-S2-1a error affordance
      AC-S4.8 asserts against, F-S4-S3-2a)
- [x] Record green baseline suite count in §9 Execution Log BEFORE first edit (testing-strategy
      rule 1; F-S1-S3-2 family)
- [x] Tests (§6) + full-suite regression

## 6. Acceptance Criteria

- [x] EXECUTOR: AI (executability conditional on OSQ-2 resolution — `RecordConfig` params come
      from the §3 Phase-0 web-client read; until OSQ-2 closes, this AC carries this same-line
      dependence note) — AC-S4.1 unit: AsrService happy path — recorder stop → multipart POST to
      `/api/upload-and-transcribe-wav` (mock Dio asserts path + multipart field name) → returns
      transcript string.
- [x] EXECUTOR: AI — AC-S4.2 unit: HTTP 500 / network error → typed AsrException; temp file
      deleted. Extended (F-S4-S3-2b): HTTP 200 with an EMPTY transcript (real Whisper outcome for
      silence/noise) ALSO throws the typed AsrException — never returns the empty string (which
      would ride AC-S4.8's error rendering instead of showing a blank review field).
- [x] EXECUTOR: AI — AC-S4.3 unit: cancel discards recording, no upload fired.
- [x] EXECUTOR: AI — AC-S4.4 widget: full state machine idle→recording→transcribing→review→idle
      with mocked AsrService; Send invokes `onSubmit` EXACTLY ONCE with the edited text and
      resets to idle (F-S3-2 callback shape + F-S4-S2-1b no-sending-state — no repository call
      from the widget).
- [x] EXECUTOR: AI — AC-S4.5 widget: mic-permission denied path renders guidance, no exception.
- [x] EXECUTOR: AI — AC-S4.6 fixture test: response-shape fixture from Phase-0 capture parses;
      pins the wire contract every run.
- [x] EXECUTOR: AI (executability conditional on OSQ-2 resolution — the fixture is rendered to
      the Phase-0-pinned params; F-S4-S3-1 rider) — AC-S4.7 live probe (net-zero): POST the
      CHECKED-IN canned WAV fixture (`test/fixtures/asr/`, created by the §5 fixture task with
      its `_provenance` block) to `:7999` → non-empty transcript returned matching the fixture's
      known content. (Runs on dev server; NO recording involved — the dev server has no mic.)
- [x] EXECUTOR: AI — AC-S4.8 widget (F-S4-S2-1): transcribe failure (mock AsrService throws
      `AsrException`) renders the inline error affordance then returns to idle — no stuck
      spinner, no `onSubmit` fired; cancel during `transcribing` discards and returns to idle,
      no `onSubmit` fired.
- [ ] EXECUTOR: HUMAN (hardware mic + real acoustics) — on-device gate: speak a reply on the
      emulator/device, verify transcript quality end-to-end; bundled into Stage-1 runbook session.

## 7. Open Items

OSQ-1 (auth contract), OSQ-2 (recording format — package justification amended on the record
2026-06-12, F-S4-1) — anchored in 02-decisions.md; resolved by §3 Phase-0 probes before
implementation tasks begin.

## 8. Revision Log

- **2026-06-12 (Stage-1 close, findings F-S4-1..3 + F-S3-2 thread)**: F-S4-1 (inconsistency,
  CONCUR justify-`record`) — OSQ-2 amended with the prior-art justification (flutter_sound is
  DI-dead-legacy + streaming-oriented; `record` is one-shot push-to-talk-fit) + flutter_sound
  flagged removal-candidate debt. F-S4-2 (inconsistency) — §4.1 divergence sentence (cohesion
  rationale) + shared-Dio seam named + MP3-trap disarm annotation task added. F-S4-3 (cosmetic) —
  permission task reworded verify-not-add (manifest `:5`, permission_handler `:29`). F-S3-2
  thread — VoiceReplyField re-shaped to `onSubmit` callback (Provides + §4.2 + AC-S4.4); dispatch
  moved to S2's `FocusRespondRequested`. Author pre-flag closed: AC-S4.1 carries the same-line
  OSQ-2 conditionality clause (Run-2 close pattern).
- **2026-06-12 (Stage-2 close, finding F-S4-S2-1 + S2 Stage-2 touchpoint)**: F-S4-S2-1
  (inconsistency, CONCUR both halves) — (a) `transcribing` gains a failure exit (inline error
  affordance → idle; visible feedback, never a vanishing spinner) and a cancel exit (no
  spinner-trap on cellular timeouts); (b) `sending` state DROPPED (orphaned by the F-S3-2
  `onSubmit` re-shape) — Send fires `onSubmit` once and resets to idle; send-failure surfacing
  stays with S2/S3 bloc state. AC-S4.4 re-pinned; NEW AC-S4.8. F-S2-S2-3 touchpoint — §4.2 notes
  composer availability is S3-gated off S2's `pendingPromptFor` signal.
- **2026-06-12 (F-S1-S3-2 family fix, doc-set-wide)**: §9 Execution Log placeholder + baseline
  task line added.
- **2026-06-12 (Stage-3 close, findings F-S4-S3-1..2 + OSQ ratifications)**: F-S4-S3-1
  (inconsistency, CONCUR full fix shape) — AC-S4.7 re-worded to POST-the-checked-in-fixture (no
  "record" on a mic-less dev server); fixture-creation task added (synthesized known-content
  speech → OSQ-2 params → provenance block → `test/fixtures/asr/`), part of Phase 0; OSQ-2
  same-line conditionality rider on AC-S4.7. F-S4-S3-2 (cosmetic, CONCUR both) —
  `voiceReplyError` TestKey added; AC-S4.2 extended with 200-empty-transcript → typed
  AsrException. OSQ-1 RATIFIED + OSQ-2 RATIFIED-AS-AMENDED recorded in 02-decisions.md
  (ownership-lens verdicts + Manager concurrence). S4 closes all three stages with this revision.

## 9. Execution Log

*(Placeholder per working-contract §Phase-Complete Definition + testing-strategy rule 1 —
populated at implementation time, NOT during the cascade.)*

- [x] Baseline suite count recorded BEFORE first edit (2026-06-12T04:38Z, carried forward from
  the S2-close run per Manager dispatch — zero edits between): `./flutter.sh test test/unit/
  test/widget/ test/service_integration/` → **351 ✅ / 1 skip / 1 ❌** (sole failure =
  pre-existing AC-D4, parent-side `assigned_at` gap, fixed in a held parent commit — not an S4
  surface). Operative bar: 351 never decreases + quarantine untouched.
- [x] **Implementation landed 2026-06-12T04:58Z (session `472b7468`, Tiffany 💍)**:
  `record: ^5.1.2` (resolved 5.2.1) added with the OSQ-2 justification + flutter_sound
  do-not-remove note; `lib/services/asr/asr_service.dart` (§4.1 — typed `AsrException`, OSQ-2
  `RecordConfig` PCM16/mono/44100, shared-Dio multipart POST, temp-file hygiene
  success-or-failure, empty-transcript exception); `voice_reply_field.dart` (§4.2 —
  idle→recording→transcribing→review, failure + cancel exits, NO sending state, exactly-once
  `onSubmit`, op-epoch stale-result guard, `permission_handler`-backed seam); five
  `voiceReply.*` TestKeys; F-S4-2 MP3-trap disarm (`@Deprecated` + docstring on
  `HttpService.uploadAndTranscribe` — zero active callers, no behavior change); DI registration
  on the shared Dio; `RECORD_AUDIO` VERIFIED present (`AndroidManifest.xml:5` — verify-not-add,
  F-S4-3). NOTE: `promptContext` rides S3's `onSubmit` closure rather than a widget param —
  the widget never dispatches (F-S3-2), so it has no use for the value; S3 wiring closes over
  it. Flagged in the close DM for contest.
- [x] **AC evidence (2026-06-12T05:02Z)** — `asr_service_test.dart` (7) +
  `asr_contract_test.dart` (2) + `voice_reply_field_test.dart` (5): **14/14 ✅**. Mapping:
  AC-S4.1 (endpoint path + multipart field name pinned via captured FormData); AC-S4.2 ×3
  (HTTP 500 w/ statusCode, network error, 200-EMPTY-transcript → typed exception; temp file
  deleted in every path); AC-S4.3 (cancel → no upload, file removed); AC-S4.4 (full machine,
  exactly-once edited-text submit, reset to idle); AC-S4.5 (denied-permission guidance, no
  exception); AC-S4.6 (Phase-0 contract fixture pinned incl. the silence-hallucination fact);
  **AC-S4.7 live probe RAN GREEN against `:7999`** — POSTed the checked-in canned WAV, exact
  provenance-transcript match (venue guard: skips with a named reason when `:7999` is
  unreachable, keeping laptop suites portable); AC-S4.8 (failure → error affordance → idle, no
  stuck spinner + cancel-during-transcribing drops the stale in-flight result) + a
  cancel-during-recording supplement.
- [x] Full-suite regression (2026-06-12T05:03Z): `./flutter.sh test test/unit/ test/widget/
  test/service_integration/` → **365 ✅ / 1 skip / 1 ❌** vs baseline 351 — passing increased
  (+14 S4 tests); failure = pre-existing AC-D4 (parent-owned), skip = pre-existing AC-D6;
  analyze clean on changed files (sole warning = pre-existing `dart:convert` unused import in
  `http_service.dart`, predates the doc-only touch); 44-test quarantine untouched.
- HUMAN mic gate (real acoustics): remains open by design — bundled into the Stage-1 on-device
  runbook session (S3's runbook task carries the ≤2-word-error rider).

**SECTION S4 IMPLEMENTATION COMPLETE (AI tiers) — 2026-06-12.**

- **2026-06-12T04:07Z — Phase-0 CLOSED (EXECUTOR: AI, Mr. Radio 🦉)**: (a) OSQ-1 probe:
  `POST /api/upload-and-transcribe-wav` requires **NO auth** — unauthenticated AND bearer'd
  POSTs both 200 (`speech.py:646-653` carries no auth dependency); response = JSON string
  literal of the transcript; no 401/403 envelope exists. The shared auth-wired Dio's bearer is
  harmless. (b) OSQ-2 recorder params pinned from source: **PCM16 mono 44100 Hz**
  (`lupin_client.py:79-81`); `prefix` stays UNSET for chat replies (only the legacy GUI client
  sends it, `:384`). (c) **Silence behavior**: 0.5 s silence → 200 with Whisper HALLUCINATION
  ("You know,") — NOT an empty transcript; AC-S4.2 implementers note: empty-recording does not
  reliably yield empty text. (d) Canned-WAV fixture CREATED + round-trip VERIFIED:
  `test/fixtures/asr/canned-focus-mode-test.wav` (gTTS-synthesized, ffmpeg → OSQ-2 params) →
  live POST returned the exact expected transcript "Focus mode voice chat test one two three."
  (0 word errors). Provenance sidecar + endpoint-contract fixture:
  `canned-focus-mode-test.provenance.json`, `transcribe_endpoint_contract.json`. Both §3
  Phase-0 checkboxes are satisfied by this evidence.
