# Working Contract — Voice/Persona Mobile Port

**Status**: FROZEN 2026-05-06
**Milestone**: Voice/Persona Allocation Surface for Mobile (Pattern 3, ~5 days)
**Prefix**: [LUPIN-MOBILE]

---

Before closing any phase of this milestone, the AI MUST have executed, on its own initiative, every verification step described in this contract. "Executed" means run, with the result reported in the phase's progress note. "Done" claims without executed verification are contract violations, not minor oversights.

This contract instantiates the global `~/.claude/CLAUDE.md` `TEST OWNERSHIP MANDATE` ("user is never a tester") and `<lupin-mobile>/CLAUDE.local.md` ("THE USER IS NEVER A TESTER") for the specific test layers used by this milestone.

---

## Test Layer Enumeration

This milestone has exactly two test layers.

### Layer 1 — `./flutter.sh test` (AI-discretionary)

The AI runs these proactively. No user permission needed.

| Suite | Command | Notes |
|---|---|---|
| Unit | `./flutter.sh test test/unit/` | Pure logic, no platform channels, ~1-10ms each |
| Widget | `./flutter.sh test test/widget/` | `mocktail` + `network_image_mock`, ~10-100ms each |
| Service integration | `./flutter.sh test test/service_integration/` | Repository-fixture tests, no live server |
| Full suite | `./flutter.sh test` | Must hit `273 + N green / 0 failed` baseline (273 was the post-`0d54c763` count; new tests added by this milestone increment N) |

Layer 1 is deterministic, reproducible, has no external deps beyond `flutter pub get`. The dev server can run all of it.

### Layer 2 — On-device emulator (`EXECUTOR: HUMAN`)

Cannot be run from the dev server. Per project memory: *"dev server has no Android SDK/adb; build scripts run on laptop via rsync + adb."*

Requires:
- Android emulator running on user's laptop
- `adb` for install
- Live Lupin backend reachable at `http://10.0.2.2:7999`
- Real ElevenLabs API key configured server-side

For this milestone specifically, Layer 2 is **NOT a new step** — it's bucketed into the existing TTS-verify runbook at `<mobile>/src/rnd/v0.1.7/2026.04.24-on-device-tts-verify-runbook.md` (Q6 in `03-decisions.md`). When voice-persona ships, the next time the user runs that runbook the per-session voice will be exercised.

---

## User Involvement Gate

The user's involvement is gated to **THREE things and ONLY these three things**:

1. **Plan-review approval** — review REUSE / Pass 1 Fitness / Pass 2 Adversarial findings tables; pick which findings to apply per pass before fixes are applied
2. **On-device verification execution** — run the existing TTS runbook on emulator (laptop leg); confirm right voice plays per session. This is `EXECUTOR: HUMAN — laptop + Android SDK access required`
3. **Final acceptance review** — confirm persona badge color/contrast meets visual taste in light + dark modes (subjective UX call)

**Anything else is a contract violation.** Asking the user to:
- run a Flutter test → violation (Layer 1 is AI-discretionary)
- pick a function name / import order / variable spelling → violation (these are AI-executable judgment calls)
- review a bloc test that just passed → violation (running the test IS the review)
- "verify the fix works" without specifying a Layer 2 step that genuinely needs human → violation
- "let me know if you hit any bugs" → violation (the AI runs the tests; if a test fails, the AI fixes it or surfaces a specific blocker)

---

## Cannot-Execute Rule

If the AI cannot execute a verification step, it must name the specific blocker on the **same line as the step's `EXECUTOR: HUMAN` tag**, and ASK — not skip, not defer, not declare done. Acceptable blocker reasons for this milestone:

- `laptop + Android SDK access required` (Layer 2 emulator runs)
- `subjective UX comparison` (color contrast, badge legibility — final acceptance)
- `live ElevenLabs quota required` — applies only to on-device runbook scenario #8 (simulated quota-exceeded path). Mitigated by the `LUPIN_DEV_SIMULATE_TTS_ERROR` dart-define documented in `<mobile>/src/rnd/v0.1.7/2026.04.24-on-device-tts-verify-runbook.md`. **Out of scope for this milestone's Phase 4 unit tests**, which mock HTTP and never call ElevenLabs. Per Pass 1 finding F8, applied 2026-05-06.

Unacceptable reasons (would be flagged by Pass 2 Adversarial):
- "easier for the user to verify"
- no reason given
- "manual test" by itself

---

## Phase-Complete Definition

A phase is complete when BOTH:

1. Every checkbox `[x]` in the phase has **executed-and-reported evidence** in the progress note — test output (pass/fail counts), file diff, commit-hash placeholder filled in, or equivalent observable artifact
2. The user has approved the phase's progress note — explicitly via response, OR implicitly via authorizing the next phase to begin

Anything less = contract violation. "Phases 1-3 done; verification tomorrow" is NOT phase-complete; "Phase 1 done, all 12 tests green, see test output below" with verifiable test output IS phase-complete.

---

## Idempotency Marker

This contract is **FROZEN 2026-05-06**. Any amendment must:

1. Re-date the FROZEN line above
2. Log the change in `00-index.md` Recent Updates with explicit reason
3. Note the amendment in the Pass 2 Adversarial findings table at next plan-review run

Silent edits to a FROZEN contract are themselves contract violations.
