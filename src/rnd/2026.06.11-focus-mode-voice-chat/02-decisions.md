# Focus-Mode Voice Chat — Decision Log

**Status**: FROZEN 2026-06-11 (Q1–Q11 untouched. Cascade outcomes 2026-06-12: ALL SEVEN OSQs
cascade-RATIFIED — OSQ-1/OSQ-4/OSQ-5/OSQ-7 straight; OSQ-2/OSQ-3/OSQ-6 as-amended. Ledger
stamped by Manager 02:44Z; see in-line notes)
**Provenance**: interactive requirements elicitation, session `dabf7fbb` (Mr. Radio 🦉), all answers given by Rick via cosa-voice blocking tools on 2026-06-11.

Every design claim in sections S1–S6 must trace back to a Q-number here. Re-date the header when amending.

---

## Q1: Where does the focus-mode UI live?

- **Question**: New screen in the existing app, new route, or separate app target?
- **✅ Decision**: New screen in the existing lupin-mobile app, and it becomes the DEFAULT/launch
  surface. Legacy screens stay routed but are demoted to a drawer/menu.
- **Rationale**: Purity of a fresh UI with zero duplication of auth/WS/DI plumbing; the 5% surface
  should be what greets the user. Separate app target would double laptop build/deploy burden.
- **Implication**: S3 owns the default-route swap + drawer demotion. AuthGate flow lands on
  FocusModeScreen post-login.

## Q2: How much existing plumbing does the new UI sit on?

- **Question**: Reuse NotificationBloc, build a new slim bloc on existing services, or full greenfield?
- **✅ Decision**: New slim `FocusChatBloc` over existing `WebSocketService` /
  `NotificationRepository` / `TtsOrchestrator`. UI + state from scratch; transport + audio reused.
- **Rationale**: NotificationBloc has grown kitchen-sink state (personas, speakerphone, gists,
  date drilldowns); dragging it into the minimal surface defeats the purpose. TtsOrchestrator
  already implements the serial-queue/preempt/fallback contract. Full greenfield would re-derive
  ~2 months of tested code.
- **Implication**: S2 defines the new bloc; legacy bloc untouched (legacy screens keep working).

## Q3: How are voice replies captured?

- **Question**: On-device STT, server-side ASR, or hybrid?
- **✅ Decision**: Server-side ASR — record on device, POST WAV to the existing improved-Whisper
  endpoint `POST /api/upload-and-transcribe-wav` (parent `src/cosa/rest/routers/speech.py`),
  transcript editable before send. On-device STT REJECTED.
- **Rationale**: User correction during elicitation — the web client already uses this
  improved-Whisper model and it is "incredibly good". Android's built-in recognizer has roughly
  double the WER on technical vocabulary and varies by OEM; the endpoint already exists (zero
  backend work); the app is online-only anyway (WS-driven).
- **Implication**: S4 consumes this endpoint. The MP3 sibling (`/api/upload-and-transcribe-mp3`)
  queues the transcript as a multimodal job — it is the WRONG endpoint for chat replies.

## Q4: What happens when TTS speaks a NON-focused session's message?

- **Question**: Manual focus, auto-follow blocking asks, or auto-follow the voice?
- **✅ Decision**: Manual focus only. The viewport never jumps; non-focused senders light an
  unread badge on the rail; the user taps to switch.
- **Rationale**: Matches "I attend to one at a time"; predictable, no surprise viewport churn.
- **Implication**: S2 tracks per-sender unread counts; S3 renders badges. Auto-follow-blocking-asks
  is a documented v1.1 candidate, not in scope.

## Q5: How are blocking asks (yes/no, multiple choice, open-ended) handled?

- **✅ Decision**: Structured prompts render INLINE in the chat — Yes/No/Neither buttons and
  choice chips inside the message bubble. Open-ended asks are answered by voice (or typed text).
- **Rationale**: Tri-state + choice widgets already exist and are widget-tested; answering a
  4-option menu by voice is the one place pure-voice UX reliably fails.
- **Implication**: S3 adapts the InteractivePromptSheet body widgets into bubble form; responses
  go through the same `NotificationRepository.respond()` path as voice replies.

## Q6: Which notifications get spoken, and what is the kill switch?

- **✅ Decision**: EVERY notification from EVERY session is queued and spoken serially, regardless
  of priority. The control is PAUSE/RESUME — not mute: pause holds the queue (messages keep
  accumulating, nothing is dropped); resume drains in arrival order.
- **Rationale**: "The point is hearing Claude." Pause models "I can't attend right now — wait for
  me" — user's explicit reframe of my mute proposal.
- **Implication**: S1 adds pause/resume to TtsOrchestrator; S3 surfaces a single prominent toggle.
  Priority-preference gating (speakOnHigh etc.) explicitly NOT carried into the focus surface.

## Q7: What keys and orders the session rail?

- **✅ Decision**: Keyed by `sender_id`, displayed as PersonaBadge (+ name). Ordered by SESSION
  ESTABLISHMENT — first-seen first (Maria, typically the day's first session, is always at the
  top); ephemeral workers append at the end. NOT recency-ordered.
- **Rationale**: Stable spatial memory — the user always knows where Maria is. Recency ordering
  shuffles the rail under multi-session traffic.
- **Implication**: S2's registry is insertion-ordered (see OSQ-3 for the cold-start tiebreak).

## Q8: How much history does the focused chat show?

- **✅ Decision**: The last 7 messages of the focused conversation.
- **Rationale**: "I'm really only concerned about the most recent ones." No infinite scroll, no
  pagination — the 5% philosophy.
- **Implication**: S2 maintains a bounded 7-item window per sender; deep history remains reachable
  via the legacy ConversationScreen in the drawer (Q1).

## Q9: Process — plan shape and review routing

- **✅ Decision**: ONE multi-stage implementation (Stage 1 = focus-mode UI, Stage 2 = FCM wake-up),
  NOT two separate plans. Full design + implementation tracking doc-set, work breakdown built
  cascade-ready, and the FULL `/plan-review-cascaded` process runs before any implementation.
  (General policy, memorized: lightweight `/plan-review` is the floor for small plans; cascaded
  review for endeavors of this scale.)
- **Rationale**: User directive 2026-06-11, superseding my two-coordinated-plans proposal.
- **Implication**: This doc-set's structure; the working contract's process gates.

## Q10: Stage 2 mechanism

- **✅ Decision**: Standardized GCP + Android + Firebase wake-up via the one-listening-channel
  approach — the FCM **silent-relay variant** recommended in
  `../v0.1.7/2026.04.21-fcm-apns-push-considerations.md` §7: data-only FCM message wakes the app,
  the app reconnects its WS and pulls missed messages. Notification CONTENT never rides FCM.
- **Rationale**: User explicitly triggered the documented revisit condition of the 2026-04-21
  deferral; silent-relay keeps Google's infrastructure out of the message-content path.
- **Implication**: S5 (mobile handler) + S6 (parent sender + token registry). Cross-repo work in
  S6 needs its own parent-Lupin session for implementation.

## Q11: Widget pattern for the focus surface

- **✅ Decision**: Vertical badge rail + chat pane (Pattern A of the May skeleton) — narrow
  always-visible left rail of PersonaBadges in establishment order; focused chat fills the rest.
- **Rationale**: One-tap switching with chat always in view; "Maria at the TOP of the list" is
  inherently vertical; PersonaBadge variants already built. Horizontal strip was runner-up;
  list-as-home fails rapid toggling (3-tap round-trip); collapsible hybrid violates no-kitchen-sink.
- **Implication**: S3 layout. ~56dp rail; portrait-first design.

---

## Open Sub-Questions (TBD — each carries a proposed answer for the cascade)

**Open sub-question 1**: Auth contract of `POST /api/upload-and-transcribe-wav` — does it require
a JWT/Bearer or X-API-Key, and what error shape does it return unauthenticated? *Proposed
resolution*: EXECUTOR: AI live probe against `:7999` during S4 Phase 0 (auth via
`LUPIN_TEST_INTERACTIVE_MOCK_JOBS_*` creds); pin the answer as a fixture. ***RATIFIED
2026-06-12*** — cascade ratification of the probe-as-resolution (S4 Stage-3 ownership-lens
verdict + Manager concurrence: AI-owned, task-owned, venue-compliant, safe under either outcome).

**Open sub-question 2**: Recording package + format. The endpoint takes a WAV upload. *Proposed
resolution*: `record` package emitting PCM16 WAV (16 kHz mono — verify what the web client sends
during S4 Phase 0 and mirror it). *Amended 2026-06-12 (F-S4-1, prior-art justification on the
record)*: `flutter_sound ^9.2.13` already sits in pubspec (`:27`) with a recorder wrapper
(`VoiceInputOutputService`, `FlutterSoundRecorder` at `:23`/`:130`) — but that wrapper belongs to
the DI-DISABLED legacy voice stack (`service_locator.dart:55-60`), and flutter_sound is
streaming-oriented where S4 needs a simple one-shot record-to-file push-to-talk API. `record` is
actively maintained, lighter, and purpose-fit. CONSEQUENCE accepted: two recording engines in the
dependency tree until the legacy stack is retired — `flutter_sound` is hereby flagged as
REMOVAL-CANDIDATE DEBT (TODO.md item to be filed with the legacy-stack retirement).
***RATIFIED-AS-AMENDED 2026-06-12*** — cascade ratification (S4 Stage-3 ownership-lens verdict +
Manager concurrence: justification on the record, debt flagged, executability dependency
surfaced same-line on every riding AC — AC-S4.1, AC-S4.7).

**Open sub-question 3**: Establishment-order source of truth across app restarts. *Proposed
resolution*: in-session, order = first-notification-seen. On cold start, rebuild from the initial
fetch ordered by each sender's EARLIEST message timestamp (approximates true establishment order
without new server state). No persistence in v1. *Amended 2026-06-12 (F-S2-S2-1 — the original
mechanism is unimplementable: `senders()` returns `SenderSummary.lastActivity`, the LATEST
timestamp; no earliest field exists, and N+1 per-sender fetches can't guarantee true earliest
either)*: cold-start order = ONE-TIME `lastActivity` DESC snapshot from the single `senders()`
fetch (most-recently-active first — the day-long manager session lands at/near the top, which is
the Maria-at-top intent in practice). Accepted approximation, documented: this is NOT
establishment order; Q7's anti-shuffle rationale protects against LIVE re-ordering, which a
one-time cold-start snapshot does not violate — establishment order governs every live arrival
thereafter, and the rail never re-sorts. ***RATIFIED-AS-AMENDED 2026-06-12*** (Manager ledger
stamp 02:44Z).

**Open sub-question 4**: Last-7 hydration on focus switch — live accumulation only, or backfill?
*Proposed resolution*: backfill via the existing per-sender fetch in NotificationRepository on
first focus of a sender, then live accumulation; window stays capped at 7. ***RATIFIED
2026-06-12*** — contingency (F-S2-S2-2 window-item mapping) resolved by the S2 review rounds;
Manager ledger stamp 02:44Z.

**Open sub-question 5**: Pause semantics for the in-flight utterance and urgent preempt. *Proposed
resolution*: pause takes effect at the utterance boundary (current utterance finishes — never cut
mid-sentence); while paused, urgent notifications do NOT break through audio (pause is absolute)
but still ding + badge. Preempt logic resumes on resume. ***RATIFIED 2026-06-12*** — cascade
ratification: S1 Stage-3 ownership-lens verdict (pause-absolute + utterance-boundary fully pinned
in observable ACs S1.3/S1.4/S1.10) + Manager concurrence; recorded per the S1 Stage-3 close.

**Open sub-question 6**: S6 token-registration endpoint shape (path, auth, payload). *Proposed
resolution*: `POST /api/fcm/register-token` JWT-authed `{token, platform, user_email}` — to be
designed in the parent repo during S6; mobile codes against the section-declared interface.
*Amended 2026-06-12 (F-S6-1, under this OSQ's amendment rights)*: the S5/S6 contract additionally
carries a WS CLIENT-TYPE MARKER — the mobile app declares `client_type: "mobile"` at WS
connect/auth so the parent can distinguish a mobile WS from a web-browser WS; the wake trigger
fires on "no live MOBILE WS" (a desktop browser session must NOT suppress the phone's wake).
Restated in BOTH S5 §3.1 and S6 §3; AC-S6.5's element-wise sync check verifies the marker appears
in both files. ***RATIFIED-AS-AMENDED 2026-06-12*** — endpoint shape + client-type marker +
durability requirement + executable propagation rule (S6 Stage-3 ownership-lens verdict +
Manager concurrence; ledger stamp 02:44Z).

**Open sub-question 7**: Firebase project provisioning ownership. *Proposed resolution*:
EXECUTOR: HUMAN (GCP/Firebase console access + `google-services.json` placement on the laptop);
AI prepares exact click-path instructions and validates the resulting config. ***RATIFIED
2026-06-12*** — the one genuinely-human step: tagged, reasoned, working-contract gate #4,
AI-validates-after (S6 Stage-3 ownership-lens verdict + Manager concurrence; ledger stamp
02:44Z).
