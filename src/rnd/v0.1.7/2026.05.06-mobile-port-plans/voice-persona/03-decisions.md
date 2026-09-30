# Decisions — Voice/Persona Mobile Port

**Status**: FROZEN 2026-05-06
**Milestone**: Voice/Persona Allocation Surface for Mobile

---

This document is the **milestone-level anchor** that Pass 1 (Fitness) of plan-review uses to trace findings. Every design claim in `01-implementation.md` must trace back to one of `Q1`–`Q6` below, OR to the parent design at `<parent-lupin>/src/rnd/v0.1.7/2026.04.28-per-session-voice-personas/01-design.md`.

Findings that challenge a frozen `Q` are surfaced via Pass 1's "Design concerns" lane (not silently overridden) and require explicit user decision before review continues.

---

## Q1: Persona storage — no mobile cache

### Question

Where does the mobile client read persona-per-session from? Two structural options:

- **Option A** — server stamps `voice_persona` onto every outbound notification envelope; mobile reads it directly from each `NotificationItem` it processes
- **Option B** — mobile maintains a `Map<senderId, VoicePersona>` cache, populated from `voice_persona_assigned` events, consulted at TTS dispatch time

### ✅ Decision

**Option A.** Server stamps the persona on every notification (parent design §4.3). Mobile reads it from the notification object at the point of TTS dispatch and badge rendering. **No mobile-side persona cache.**

### Rationale

- Avoids cache-invalidation problems (mobile doesn't have to track allocate/release/reassign correctly)
- Matches server's decision in parent §4.3: "the persona always travels with the notification it'll vocalize"
- One source of truth (server bridge) instead of two (server + mobile mirror)
- If a notification arrives with no `voice_persona` field, server's TTS endpoint already falls back to Sam — mobile simply omits the parameter and gets the same fallback. No mobile-side fallback logic needed.

### Implication

The bloc state DOES still maintain a small `Map<String, VoicePersona> personasBySender` derived from `voice_persona_assigned` events, but it's used **only for header rendering** in screens where the user is "in" a session (`ConversationScreen`, inbox tile) — not for TTS dispatch. TTS reads the persona directly off each notification. This is a softer use of state and decouples the audio path from cache freshness.

---

## Q2: Borrowed-persona rendering

### Question

Server's allocation algorithm has a fallback when the 6-voice pool is exhausted: it picks `pool[hash(sid) % 6]` and marks `borrowed=true` (parent design §4.2 Mermaid step 6). How does mobile render a borrowed persona?

### ✅ Decision

**Dashed-border badge variant.** Same color and icon as the regular allocation; `borrowed=true` toggles a dashed `BoxBorder` around the persona avatar.

### Rationale

- Mirrors web's planned rendering (parent design §4.2 line 121: "UI renders dashed-border badge")
- Visual difference is subtle but discoverable on close inspection — appropriate for a "you're sharing this voice with another session" status
- No change to the audio path: borrowed personas use the real `voice_id`, server treats them identically

### Implication

`PersonaBadge` widget takes `borrowed` as a parameter and switches between `BoxBorder.all` (solid) and a custom `DashedBorderPainter` for the dashed variant. Widget tests must cover both states.

---

## Q3: TTS `voice_id` routing

### Question

How does the per-session `voice_id` reach `StreamingTtsPlayer.speak()` and ultimately the `/api/get-speech-elevenlabs` POST body?

### ✅ Decision

**Optional named parameter** `String? voiceId` on `speak()`. When present, append `voice_id: voiceId` to the POST body. When absent, omit the field entirely — server falls back to Sam (today's behavior, preserved).

### Rationale

- Additive change to `StreamingTtsPlayer` API; no existing callers break
- Server's body-key spec is `voice_id` (parent design §6 — server's bug-fix changed key from `voice` → `voice_id` in the same parent PR; mobile uses no key today, so we're additive only)
- Explicit `null`-passing is preferred over `getattr`-style fallback chains (per project Python style; same idiom applied here in Dart)

### Implication

`tts_orchestrator.dart` reads `notification.voicePersona?.voiceId` and passes it to `streamingTtsPlayer.speak(text, voiceId: ...)`. Tests must verify body inclusion when present, body omission when absent, and that omission triggers server-side Sam fallback (verified by integration test or fixture, not unit test).

---

## Q4: Fallback TTS — out of scope for voice_id

### Question

When ElevenLabs quota-exceeds and the orchestrator falls back to `flutter_tts` (the on-device TTS used as the quota-backstop, shipped 2026-04-21 + overlap-fixed 2026-04-24), should the per-session `voice_id` be honored there too?

### ✅ Decision

**No.** `flutter_tts` uses on-device voices keyed by language code, NOT ElevenLabs voice IDs. The per-session persona's `voice_id` is irrelevant to the fallback path.

### Rationale

- Different voice space — `flutter_tts` cannot render an ElevenLabs voice ID
- Translating ElevenLabs personas to `flutter_tts` voice profiles is out of scope (would require curating a parallel mobile-voice pool)
- Quota fallback is meant to be functional-but-degraded, not pixel-perfect

### Implication

`tts_orchestrator.dart`'s fallback path stays unchanged. A code comment must call out **why** the persona's `voiceId` is intentionally not piped through (so a future maintainer doesn't "fix" what isn't broken). Pass 2 Adversarial would otherwise flag this as a missing test case.

---

## Q5: Persona theming scope — badge only

### Question

The parent web client did a "persona theming Round 1" sweep across notification chrome, bubble gradients, and badge right-alignment (parent commits `06e5795`, `21e92f1`, `d8bce7f`). Does mobile do the same in this milestone?

### ✅ Decision

**No — badge only.** This milestone scopes persona rendering to:

1. The `PersonaBadge` widget (new)
2. Three integration sites: `ConversationScreen` header, `_NotificationItemCard` (in `conversation_by_date_screen.dart`), inbox sender tile

NOT in scope: bubble gradients, AppBar theming, color-keyed backgrounds, contrast-aware text recolor, etc.

### Rationale

- Scope discipline — bubble gradients are a separate UX investment with their own A/B testing surface
- The badge alone is sufficient to disambiguate sessions audibly + visually (the user-pain that motivated the parent feature)
- Bubble theming on web didn't ship cleanly in one round; mobile shouldn't pre-commit to it without observing whether the badge alone is enough on a phone-sized screen

### Implication

`01-implementation.md` does NOT include "theme conversation bubbles" or "color-key the AppBar" tasks. If user later wants bubble theming, that's a separate milestone with its own plan.

---

## Q6: On-device verification — bucketed

### Question

Does this milestone add a new on-device verification step (beyond `EXECUTOR: AI` Flutter tests)?

### ✅ Decision

**No.** On-device verification of the per-session voice is bucketed into the existing TTS-verify runbook at `<mobile>/src/rnd/v0.1.7/2026.04.24-on-device-tts-verify-runbook.md` (the laptop leg of session `0d54c763`).

### Rationale

- The existing runbook already exercises the audio path end-to-end (10 scenarios, including FIFO and quota-fallback)
- Once persona is wired, the runbook's "Speech — ElevenLabs primary path" scenarios automatically validate per-session voice routing — no new runbook needed
- Adding a parallel runbook is duplicative

### Implication

`01-implementation.md` Phase 5 does NOT include a new on-device step. Existing TODO item *"On-device verify TTS: live ElevenLabs audio plays in the emulator"* is sufficient — when next run, it implicitly validates this milestone too.

The user-involvement gate at `00-working-contract.md` §"User Involvement Gate" item 2 covers this: the user runs the existing runbook, NOT a new milestone-specific one.

---

## Q7: `fromJson` shape — liberal, not enum-validated

### Question

Should `VoicePersona.fromJson` accept any string `name` / `icon` / `voice_id` (liberal), or validate against the known 6-voice + Sam pool (enum-gated)?

### ✅ Decision

**Liberal.** Accepts any string fields. No hard-coded enum.

### Rationale

- REUSE pre-pass on 2026-05-06 confirmed there is **no existing persona enum** anywhere in the mobile codebase that liberal parsing would conflict with (it could neither be reused-as-is nor extend-existing — there's nothing to extend).
- Server may grow the pool later (parent design §3 reserves Sam as default; the 6-voice allocatable pool is configurable). An enum-gated mobile parser would silently drop an envelope's persona field if a 7th voice was added server-side. Failure mode is silent; not acceptable.
- Server is the source of truth for the pool. Mobile shouldn't second-guess the schema.

### Implication

`VoicePersona.fromJson` accepts the four string fields (`name`, `icon`, `voice_id`, `display_name`) and the bool `borrowed` plus the timestamp `assigned_at` without validation. If a future server change introduces an additional field, the parser ignores it (forward-compatibility); if a field is missing the parser uses null (graceful degradation, with the consumer code defending via null-checks).

### Provenance

Promoted from **Open sub-question 1** at REUSE pre-pass on 2026-05-06.

---

## Q8: `PersonaBadge` widget location — features, not shared

### Question

Where should `PersonaBadge` live: `lib/features/notifications/presentation/persona_badge.dart` (feature-scoped) or `lib/shared/widgets/persona_badge.dart` (cross-feature)?

### ✅ Decision

**`lib/features/notifications/presentation/persona_badge.dart`** (feature-scoped).

### Rationale

- REUSE pre-pass confirmed that `lib/shared/widgets/` is **empty** in the current mobile codebase. Promoting a single new widget there would be premature generalization.
- The widget is currently only consumed by notification surfaces (`_NotificationItemCard`, `ConversationScreen` header, inbox sender tile). All three live under `lib/features/notifications/`.
- The session-switcher milestone (`../03-session-switcher-port-plan.md`) is the future second consumer. If/when that milestone lands, `PersonaBadge` can be **promoted** to `lib/shared/widgets/` then — promotion-on-demand is cheap and well-precedented; pre-emptive promotion is harder to justify.

### Implication

`PersonaBadge` ships in `lib/features/notifications/presentation/persona_badge.dart`. Test in `test/widget/notifications/persona_badge_test.dart`. The session-switcher plan (`../03-session-switcher-port-plan.md`) will need a follow-up "promote `PersonaBadge` to shared" task line if/when it consumes the widget.

### Provenance

Promoted from **Open sub-question 2** at REUSE pre-pass on 2026-05-06.

---

## Q9: `DashedBorderPainter` — genuinely new

### Question

Does the mobile codebase already have a dashed-border helper that `Q2`'s borrowed-persona variant can use, or must we write a new `DashedBorderPainter`?

### ✅ Decision

**Write a new `DashedBorderPainter` from scratch.**

### Rationale

- REUSE pre-pass confirmed: **no `CustomPainter` subclass exists in `lib/`** that could be reused.
- `pubspec.yaml` has **no dashed-border packages** (no `dotted_border`, no `flutter_dotted_border`, no equivalent).
- Flutter Material's built-in `BoxBorder` only supports solid borders. Dashed strokes require a `CustomPainter`.

### Implication

- New file: `lib/shared/painters/dashed_border_painter.dart` — a `CustomPainter` subclass that draws a dashed stroke around its `Rect` boundary
- This is the one piece of code in the milestone that lives under `lib/shared/` (NOT under `lib/features/notifications/`) — painters are inherently cross-cutting and the `lib/shared/painters/` directory is the right home even though it's currently empty
- Unit-testable via `CustomPainter.semanticsBuilder` + paint stroke assertions

### Provenance

Promoted from **Open sub-question 3** at REUSE pre-pass on 2026-05-06.

---

## Open sub-questions

*All three Open sub-questions resolved at REUSE pre-pass on 2026-05-06 → see Q7, Q8, Q9 above.*

If new sub-questions arise during Pass 1 Fitness review, they will be added back here as `Open sub-question N:` lines for Pass 1 to demand answers per Convention 4.
