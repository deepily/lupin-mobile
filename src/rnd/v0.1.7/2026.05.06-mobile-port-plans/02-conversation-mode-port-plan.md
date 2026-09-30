# Conversation Mode — Mobile Port Plan (SKELETON)

**Date**: 2026-05-06
**Prefix**: [LUPIN-MOBILE]
**Status**: 🟡 Skeleton — UX design needed before scope-out
**Pattern**: TBD (likely Pattern 3 + Pattern 5 hybrid — feature dev with architecture decision upfront)
**Estimated effort**: TBD (depends on UX direction; range 5-15 days)
**Blocked by**: `00-phase-0-dispatch-audit.md` AND user decision on UX direction (see §5)
**Parent design**: `<parent-lupin>/src/rnd/v0.1.7/2026.04.27-conversation-mode-design.md` + v1.1 hardening commits + 3-layer enforcement docs (2026-04-30)

---

## 1. Why this plan is a skeleton, not a full plan

User flagged in the 2026-05-06 baseline kickoff: *"In the case of a mobile app conversation mode might lend itself to being its own widget set outside of the UI widgets that you have already created."*

The web client implements conversation mode as a **per-session toggle on the sender card** — a small icon button (📞 / 🔔) embedded in the existing notifications-list UI. Each card has its own state. Mutex-1 (only one session active at a time) is enforced server-side.

That model **does not map cleanly to mobile**:
- Mobile screen real estate is too small for per-card toggles inside a list
- The user enters conversation mode specifically to **be at a distance** — the screen is off; UI density doesn't matter, audio routing does
- Mobile's natural conversation surface is a dedicated screen (think: phone-call UI, voice-assistant overlay, dictation mode)

Until that UX question is settled, scoping a precise plan is premature. This skeleton captures the technical inventory and open questions so the eventual plan-mode session has a head start.

## 2. Server-side facts (locked, no design exposure)

### HTTP endpoint (mobile WILL call)

| Verb | Path | Purpose |
|---|---|---|
| POST | `/api/cosa-voice/conversation-mode/{session_id}` | Toggle on/off; body: `{ active: bool }` |

### Bridge field

```json
"conversation_mode_active": false
```

### WS events mobile MUST handle

All ride **inside `notification_queue_update`** (Phase 0 prerequisite).

| Inner `notification.type` | Payload | When |
|---|---|---|
| `conversation_mode_changed` | `{ session_id, active: bool }` | Toggle propagation; **also fires for OTHER sessions when this session takes the mutex slot** (displaces them) |
| `notification` envelopes with `action: enter_conversation_mode` or `action: exit_conversation_mode` | cross-session reminder | Used as a hint payload for self-exit signal symmetry — see commit `1a05fdb` and CoSA `7ec3335` |

### Mutex-1 (only one session active at a time)

Server enforces this. If session A is in conv-mode and session B toggles ON, session A is **automatically displaced** (broadcast `conversation_mode_changed { active: false }` for A, then `{ active: true }` for B). The mobile UI must reflect this displacement immediately — if the user is currently in mode for session A, A's mode flips off without the user touching anything.

### 3-layer enforcement (server-side, no mobile work)

Parent shipped `conv_mode_wrap` + sanitize helpers + thread-wrappers + `_notify_impl` gate + Stop-hook auto-narrate (commits `02af97b` through `d7a6c9f`, 2026-04-30). This is internal server-side discipline enforcement. **Mobile has no work here** — the user-facing surface is just the toggle and the audio.

### "Acknowledge receipt before tool work" rule

Codified in commits `4513f08` + `14b0289` (2026-04-28). When conv-mode is active, Claude must `notify()` an acknowledgment BEFORE any tool call. **This is Claude-side discipline**, enforced by the agent itself — mobile has no work here either.

## 3. UX directions to consider

The fundamental design question for mobile: **when the user enters conversation mode, what does the app become?**

### Direction A: Dedicated full-screen conversation surface

- Tap a global toggle (FAB or AppBar icon) → app transitions to a **conversation screen**
- Screen shows: large mic affordance, current session indicator, persona badge (color + icon + name), text of current notification being narrated, "exit" button
- Inbox / decision-proxy / agentic UIs are hidden
- TTS plays via the existing `StreamingTtsPlayer` pipeline (already shipped)
- Audio focus claim (Android `AudioManager.requestAudioFocus`) so this app gets priority
- Possibly: lock screen / notification-area persistent UI showing "in conversation mode"

**Pros**: Natural to the at-a-distance use case; clear modality signal; large hit targets for screen-on glance
**Cons**: Requires more work; new widgets; navigation changes; possible state-management complexity

### Direction B: Per-session in-line toggle (web-mirror)

- Add a 📞/🔔 icon button to each `_SenderTile` in the inbox or each `ConversationScreen` AppBar
- Tap to toggle; visual highlight on active session
- Otherwise inbox UX unchanged

**Pros**: Smallest change; mirrors web exactly; no new widgets
**Cons**: Wastes the at-a-distance ergonomic; tiny tap targets on small screens; user is asking for it to be different

### Direction C: Hybrid — global toggle that overlays UI (Telegram-style)

- Global toggle in app bar
- When ON, a persistent banner / bottom sheet hangs over whatever screen is showing, with mic icon + "in conversation mode for: <session name>"
- User can still navigate the app
- Conversation surface is "always there but always small"

**Pros**: Discoverable; non-modal; preserves existing UX; reasonable effort
**Cons**: Banner steals real estate; not the cleanest at-a-distance experience

### Direction D: User defines (not yet articulated)

The user may have a fourth option in mind that none of the above captures. Worth asking before plan-out.

## 4. Likely scope (regardless of UX direction)

These will be in the plan no matter which direction wins:

- **HTTP**: new method `ConversationModeRepository.setMode(sessionId, active)` that POSTs to `/api/cosa-voice/conversation-mode/{sid}`
- **WS dispatch**: new bloc events `ConversationModeChanged(sessionId, active)` (+ probably `ConversationModeDisplaced` for the mutex-displacement case, though that's just a `{ active: false }` flavor)
- **Bloc**: new `ConversationModeBloc` (or add to existing `NotificationBloc` — debatable; likely its own bloc since it's a global modality)
- **State persistence**: shared_preferences cache of "is this session currently in conv-mode" — mirroring the localStorage pattern from the parent design §3
- **Audio focus**: claim audio focus when entering, release when exiting
- **Existing TTS pipeline**: `StreamingTtsPlayer` already handles the audio — no new TTS work here
- **Acknowledgment rule**: mobile probably doesn't need to enforce (Claude-side concern), but a confirmation chime or vibration when entering/exiting might help the user know the state changed without looking

## 5. Open Questions (must answer before plan-out)

| # | Question | Why it matters |
|---|---|---|
| 1 | UX direction (A / B / C / D from §3)? | Drives effort estimate from 5 to 15 days |
| 2 | Is conversation mode a per-session selector on mobile, or always "the one CC session you're focused on"? | If the user only has 1-2 sessions on mobile usually, the selector might be skippable |
| 3 | Should mobile expose enter/exit voice phrases? | Server-side voice ASR isn't routed to mobile today; this is a separate workstream |
| 4 | Audio focus behavior — duck other apps, exclusive, or transient? | Affects how the app coexists with podcasts/music |
| 5 | Wake-screen behavior on incoming notification while in conv-mode? | iOS/Android have different policies; affects perceived responsiveness |
| 6 | Keyboard / mic input — does the user respond by voice? | Mobile has built-in voice input; integrating with cosa-voice's response endpoints is a non-trivial extension |
| 7 | Visual confirmation when entering — subtle (pulse) or unmissable (full-screen overlay)? | At-a-distance use case means subtle won't be noticed |

## 6. Files Likely To Touch (skeleton)

**New**:
- `lib/features/conversation_mode/data/conversation_mode_repository.dart`
- `lib/features/conversation_mode/domain/conversation_mode_bloc.dart`
- `lib/features/conversation_mode/presentation/conversation_mode_screen.dart` (Direction A) OR
  `lib/features/conversation_mode/presentation/conversation_mode_banner.dart` (Direction C) OR
  embedded toggle in existing screens (Direction B)
- Tests under `test/unit/features/conversation_mode/`, `test/widget/conversation_mode/`

**Modified**:
- `lib/services/websocket_service.dart` (dispatch)
- `lib/app.dart` (routing)
- `lib/core/di/service_locator.dart` (DI registration)
- `lib/services/tts/streaming_tts_player.dart` — possibly to claim/release audio focus
- `pubspec.yaml` — possibly `audio_session` package for focus management

## 7. Recommended Process

1. ✅ Phase 0 dispatch audit lands (`00-phase-0-dispatch-audit.md`)
2. ✅ Voice persona port lands (`01-voice-persona-port-plan.md`) — gives mobile a working in-list UI for personas, which is necessary context for conversation-mode visual design
3. 🟡 **Run `/p-is-p-01-planning` for conversation mode** with all four UX directions on the table — likely use Pattern 5 (Architecture & Design) for Phase 1 to make the UX decision, then Pattern 3 for implementation
4. 🟡 Consider running `interactive-requirements-elicitation` skill first if the user is still exploring direction
5. 🟡 Write `01-design.md` in this same directory once direction is chosen
6. 🟡 Implement

## 8. Out of Scope (won't do here)

- Voice ASR for "enter conversation mode" / "exit conversation mode" voice phrases — separate workstream
- Multi-device sync of conv-mode state — server-canonical bridge already covers this; mobile just listens
- "Acknowledge receipt" Claude-side rule enforcement — server/Claude concern

## 9. Cross-references

- Phase 0 prerequisite: [`00-phase-0-dispatch-audit.md`](00-phase-0-dispatch-audit.md)
- Companion plans: [`01-voice-persona-port-plan.md`](01-voice-persona-port-plan.md), [`03-session-switcher-port-plan.md`](03-session-switcher-port-plan.md)
- Parent design (read fully before plan-out):
  - `<parent-lupin>/src/rnd/v0.1.7/2026.04.27-conversation-mode-design.md`
  - `<parent-lupin>/src/rnd/v0.1.7/2026.04.30-conv-mode-three-layer-enforcement/`
  - `<parent-lupin>/src/rnd/v0.1.7/2026.05.05-conv-mode-self-exit-signal-gap/`
- Mobile baseline: `<mobile>/src/rnd/v0.1.7/2026.05.06-resync-baseline-mobile-vs-lupin.md`
