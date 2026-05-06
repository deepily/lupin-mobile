# Session Switcher (mobile equivalent of web focus-mode) — Mobile Port Plan (SKELETON)

**Date**: 2026-05-06
**Prefix**: [LUPIN-MOBILE]
**Status**: 🟡 Skeleton — direction articulated, widget pattern still TBD
**Pattern**: Likely Pattern 1 (multi-phase) or Pattern 5 (architecture-first) — promoted from prior "maybe Pattern 3" guess once user articulated this is a primary navigation paradigm, not a small addition
**Estimated effort**: 8-15 days (depends on widget pattern)
**Blocked by**: `00-phase-0-dispatch-audit.md` (mild) + UX widget-pattern decision
**Parent design**: `<parent-lupin>/src/rnd/v0.1.7/2026.04.30-cc-session-focus-mode/01-design.md`

---

## 1. What changed since v1 of this doc

The v1 skeleton (in this same directory's earlier draft) led with the hypothesis that **mobile's existing inbox already implements focus-mode implicitly** (Direction A: single-screen-at-a-time = focus-mode by default). User explicitly **rejected that direction** in conversation on 2026-05-06:

> "It may very well end up being its own separate widget set that allows me to choose with which repo/Claude code in instantiation I am conversing with. As opposed to manually loading and reloading different session lists."

The pain articulated: **navigation churn between sessions**. Today on mobile (per inferred current state), switching from one CC session to another requires going back to the inbox, finding the right sender tile, and tapping in. Across 3+ active sessions in different repos, that's 6+ taps to round-trip A → B → A. The user wants this to be 1 tap.

Direction A is therefore retired. Direction B+ (a dedicated session-switcher widget set) is the new lead.

## 2. What the user is asking for, restated

The user runs Claude Code instantiations across multiple repos simultaneously: lupin, lupin-mobile, cosa, planning-is-prompting, lupin-plugin-firefox, possibly more. Each is its own CC session with:

- A `session_id` (cosa-voice's 8-char hex, e.g. `a756441c`)
- A `project` (lupin-mobile, lupin, etc.)
- A `voice_persona` (Adam 🌑, Nora 🌸, Arnold 🪨, etc. — once Plan 01 lands)
- A user-edited friendly `session_name` (like "wise penguin")
- An `unread_count` accumulated since last visit
- A `conversation_mode_active` flag (once Plan 02 lands)

On mobile, the user wants a **first-class widget surface** that shows all of these at once and lets them pivot between sessions in a single tap. Not a strip-on-top-of-inbox (that's web's pattern); not a hamburger drawer (too many taps); a primary navigation paradigm.

This puts the mobile app closer to: **Slack** (vertical workspace switcher on left edge), **Discord** (vertical server-icon sidebar), **Telegram** (chat list as home view), **Stories on Instagram** (horizontal avatar carousel). Different platforms; same pattern: pick one of {n} active conversation contexts.

## 3. Server-side facts (unchanged — this is a client-only feature)

- No new endpoints
- No new WS events (focus state is purely visual/local)
- All driven by existing `notification_queue_update` events that already enumerate active senders
- Persona color/icon reused from Plan 01 (`voice_persona_assigned` envelope payload)
- Conv-mode mic-glyph reused from Plan 02 (`conversation_mode_changed` envelope payload)

## 4. Widget Pattern Options

### Pattern A: Vertical Sidebar (Slack/Discord style)

A persistent narrow column on the left edge of the screen. Each row = one active session, rendered as a persona-colored circle with the project initial (e.g., `L` for lupin, `M` for lupin-mobile). Tap → switch to that session. Rest of the screen (~80-90% of width) is the session view.

```
+--+------------------------------+
|GR|                              |
| L|   ConversationScreen         |
|  |   (currently selected        |
|YE|    session content)          |
| M|                              |
|  |                              |
|RD|                              |
| C|                              |
+--+------------------------------+
```

**Pros**:
- Persistent — always visible, lowest cognitive load
- Familiar from Slack/Discord — proven pattern
- Reorder-by-recency lives at the top

**Cons**:
- Steals horizontal real estate on already-narrow phone screens
- Awkward in landscape mode
- May not work cleanly at the top of conversation hierarchy + below other UI chrome

### Pattern B: Horizontal Strip (Stories style)

A scrollable horizontal row of avatars across the top of the home screen (or persistent across screens). Each avatar = one session. Currently selected is highlighted. Tap → switch session.

```
+------------------------------+
| GR-L  YE-M  RD-C  BL-P       |
+------------------------------+
|                              |
|   ConversationScreen         |
|   (selected session)         |
|                              |
|                              |
+------------------------------+
```

**Pros**:
- Mirrors web's strip pattern (lower porting friction; design already done in parent)
- Compact; doesn't steal vertical or horizontal real estate
- Familiar from Instagram/WhatsApp Stories
- Reorder-by-recency reads left-to-right

**Cons**:
- Limited horizontal slots before overflow scroll kicks in (~6-8 visible)
- Tap targets are smaller (~40-44dp) than Pattern A
- Less of a "first-class" navigation surface — feels like a row of buttons, not a nav paradigm

### Pattern C: Session List as Home (Telegram/iMessage style)

The app's home view IS the session list. Each row is a tile with persona avatar + project name + session name + unread badge + last-message preview. Tap → drill into that session's conversation/inbox. Back button returns to the list.

```
+------------------------------+
| GR  lupin · "wise penguin"   |
|     Adam · 3 unread          |
+------------------------------+
| YE  lupin-mobile · "Arnold"  |
|     Arnold · 1 unread        |
+------------------------------+
| RD  cosa · "calm dolphin"    |
|     Rachel · idle            |
+------------------------------+
```

**Pros**:
- Deeply familiar — every messaging app does this
- Lots of metadata visible at a glance
- Scales gracefully to N sessions (vertical scroll)

**Cons**:
- Always 1 tap to enter, 1 tap to exit, 1 tap to switch — 3 taps minimum to round-trip A → B → A (improves over today by 3 taps but doesn't get to 1-tap switching)
- Not "always visible" — user must navigate back to the list to switch
- Resembles existing inbox; risk of just being inbox v2

### Pattern D: Hybrid — Sidebar + Conversation, with Sidebar collapsible

Pattern A by default; user can swipe-to-collapse the sidebar to reclaim screen real estate, then swipe-from-edge to bring it back. Combines Pattern A's always-visible benefit with Pattern C's scalability.

**Pros**:
- Best of both worlds when user has 3-5 sessions
- Adapts to screen orientation

**Cons**:
- Most complex to build
- Gesture conflicts with browser-style back-swipe on Android
- More state to manage

## 5. The "Session View" — what fills the right pane (Patterns A/B/D) or the drilled-in screen (Pattern C)

Regardless of widget pattern, when the user is "in" a session, the view shows:

- **Header**: persona-colored bar with persona icon + name + project + user-edited session name + session_id-hash + conv-mode toggle
- **Body**: conversation/inbox stream (existing `ConversationScreen` content, lightly adapted)
- **Audio state**: mini-player when TTS is active (already shipped)
- **Voice input**: mic button (cross-cuts with conv-mode plan)
- **Toolbar**: existing actions (calendar, summarize, etc.)

The session view is **mostly already built** — it's the existing `ConversationScreen` plus some persona theming + a conv-mode affordance. The new work is the SWITCHER, not the view.

## 6. How conversation-mode lives inside the session switcher

**Key coupling**: doc 02 (conversation-mode) and this plan are now structurally coupled. The session switcher becomes the **spine** that conv-mode UI hangs off of:

- **Switcher icon**: when a session is in conv-mode, its avatar gets a mic-glyph overlay (mirroring web's pattern)
- **Session view header**: when conv-mode is active for the selected session, the header shows a prominent mic indicator + "exit conversation mode" button
- **Cross-session displacement**: when user toggles conv-mode for session B while session A holds the slot, the switcher icon for A loses its mic-glyph and B gains it (server-driven mutex via `conversation_mode_changed` events)

**Implication**: this plan should land **before** doc 02's plan-out. The switcher widget choice constrains where conv-mode UI lives. If we plan conv-mode first, we make a UX decision (where does the toggle live? how big?) that the switcher then has to retcon.

This reverses the order proposed in v1 of this doc.

## 7. Open Questions (must answer before plan-out)

| # | Question | Why it matters |
|---|---|---|
| 1 | Which widget pattern (A / B / C / D) — or a fifth option not yet articulated? | Drives effort estimate from 8 to 15 days |
| 2 | Should the switcher be visible on every screen (Patterns A/B), or only on a dedicated "home" view (Pattern C)? | Affects how `app.dart` routes; may force significant nav rework |
| 3 | What's the cap on simultaneous active sessions? 5? 8? 10+? | Drives whether overflow handling matters |
| 4 | When user installs the app fresh and has 0 sessions, what does the empty switcher look like? | UX onboarding question |
| 5 | When all sessions are "idle" (no recent activity), does the switcher dim them? Strike them through? Move to a separate "quiet" group? | Quality-of-life detail |
| 6 | Does long-press on a session avatar offer pin / mute / archive / delete? | Determines whether we add a new contextual menu surface |
| 7 | Cross-platform: does this app target iOS too? | Pattern A/D feel iOS-foreign; Pattern B/C are platform-agnostic |
| 8 | Persistence: does the "last selected session" survive app cold-start? | Likely yes via `shared_preferences`; mirrors web's localStorage focus-state |

## 8. Likely Scope (regardless of widget pattern)

These are common to all patterns:

- **New `SessionRegistry` service** — single source of truth for "all active CC sessions on this device's user account". Fed by WS notifications, persona events, conv-mode events. Exposes a `Stream<List<SessionSummary>>` for the switcher widget to listen to.
- **`SessionSummary` model** — `sessionId, project, persona, sessionName, unreadCount, lastActivity, conversationModeActive`
- **New `SessionSwitcherBloc`** — manages the currently-selected session + the per-session UI state (collapsed/expanded for Pattern D, etc.)
- **DI wiring** — register the new services in `service_locator.dart`
- **App-level rework** — `app.dart` routes need to know about the selected session. Probably converts the current `MultiBlocProvider` shell into a session-scoped shell, where some blocs are scoped to the selected session and others remain app-global
- **shared_preferences cache** — last-selected session, sidebar-collapsed state, etc.
- **Test coverage** — bloc tests, widget tests for the switcher, integration tests for switching mid-conversation

## 9. Recommended Process

1. ✅ Phase 0 dispatch audit lands (`00-phase-0-dispatch-audit.md`)
2. ✅ Voice-persona port lands (`01-voice-persona-port-plan.md`) — gives the switcher its color/icon vocabulary
3. 🟡 **Pick widget pattern** (A / B / C / D / other) — could use `interactive-requirements-elicitation` skill or sketch all four side-by-side and let user choose
4. 🟡 **Plan-mode session** for the chosen pattern → produces `01-design.md` in this same directory
5. 🟡 **Run plan-review** (REUSE → Fitness → Adversarial) per `<planning-is-prompting>/workflow/plan-review.md` — this plan will be Pattern 1 or 5, plan-review is mandatory
6. 🟡 **Implement** — likely 3-4 phases (registry + bloc + widget + integration)
7. 🟢 Now **doc 02 (conversation-mode) plan-out** can proceed because it knows where the conv-mode UI lives

## 10. Out of Scope (won't do here)

- Cross-device session sync — conv-mode handles cross-device for the audio mutex via the bridge file; switcher is per-device
- Multi-window / split-screen mobile support — not a target
- Session archival / cold-storage of completed sessions — handled by the existing inbox flow if it stays around
- Voice ASR for "switch to <session>" voice phrases — separate workstream

## 11. Files Likely To Touch (skeleton — varies by pattern)

**Common to all patterns**:
- `lib/features/sessions/data/session_summary.dart` (new)
- `lib/features/sessions/data/session_registry.dart` (new — singleton service)
- `lib/features/sessions/domain/session_switcher_bloc.dart` (new)
- `lib/features/sessions/domain/session_event.dart` (new)
- `lib/features/sessions/domain/session_state.dart` (new)
- `lib/core/di/service_locator.dart` (modify — register registry + bloc)
- `lib/app.dart` (modify — wrap routes with session-scoped shell)

**Pattern-specific** (one of):
- `lib/features/sessions/presentation/session_sidebar.dart` (Pattern A or D)
- `lib/features/sessions/presentation/session_strip.dart` (Pattern B)
- `lib/features/sessions/presentation/session_list_screen.dart` (Pattern C)

**Tests**:
- `test/unit/features/sessions/`
- `test/widget/sessions/`
- New TestKeys constants

## 12. Cross-references

- Phase 0 prerequisite: [`00-phase-0-dispatch-audit.md`](00-phase-0-dispatch-audit.md)
- Companion plans: [`01-voice-persona-port-plan.md`](01-voice-persona-port-plan.md), [`02-conversation-mode-port-plan.md`](02-conversation-mode-port-plan.md) (note: now structurally couples to this plan; this plan should land first per §6)
- Parent design (web): `<parent-lupin>/src/rnd/v0.1.7/2026.04.30-cc-session-focus-mode/01-design.md`
- Mobile baseline: `<mobile>/src/rnd/v0.1.7/2026.05.06-resync-baseline-mobile-vs-lupin.md`
- User direction articulation: 2026-05-06 conversation in session `a756441c` (this skeleton's source-of-truth quote)

---

## Status Summary

This is no longer the lowest-priority of the three feature ports. The user's articulation promotes it to **likely the structural anchor of the mobile resync** — if the session switcher is going to be the primary navigation paradigm, it should land before conversation-mode, and probably before voice-persona's badge work integrates into more than just notification cards (the switcher avatars also use persona colors).

**Not yet ready to plan-mode**. Decision needed first: which widget pattern (§4)?
