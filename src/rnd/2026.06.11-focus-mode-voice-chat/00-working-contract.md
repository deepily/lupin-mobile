# Focus-Mode Voice Chat — Working Contract

**Status**: BINDING for all sections S1–S6
**Created**: 2026.06.11
**Anchors**: instantiates `~/.claude/CLAUDE.md` TEST OWNERSHIP MANDATE + DOCUMENTATION-FIRST PROTOCOL for this milestone.

Before closing any phase or section of this milestone, the AI MUST have executed, on its own
initiative, every verification layer that does not genuinely require human judgment or hardware
the AI cannot reach.

## Test-Layer Enumeration

| Layer | Runner | Who runs it | Where |
|---|---|---|---|
| Dart static analysis | `./flutter.sh analyze` | **AI, proactively** | dev server |
| Unit + bloc tests | `./flutter.sh test test/unit/` | **AI, proactively** | dev server |
| Widget tests | `./flutter.sh test test/widget/` | **AI, proactively** | dev server |
| Live HTTP probes (ASR contract, parity checks) | Dart/Python test client against `:7999` | **AI, proactively** (auth via `LUPIN_TEST_INTERACTIVE_MOCK_JOBS_*` env vars) | dev server |
| APK build + emulator/device verification | `build-and-deploy-lupin-mobile.sh` + on-device runbook | **HUMAN-assisted** — laptop has Android SDK/adb; dev server does not (`feedback_dev_server_laptop_split`) | laptop |
| Subjective audio/UX gates (TTS pacing under pause/resume, rail ergonomics, mic UX) | on-device runbook sign-off | **HUMAN** — perceptual judgment | laptop + device |

## User-Involvement Gate

The user's involvement is gated to FIVE things and ONLY these five:

1. Design decisions surfaced as `Open sub-question N:` or escalated cascade findings.
2. Laptop-side execution: APK build/deploy and on-device runbook steps (no Android SDK on dev server).
3. Perceptual judgments explicitly tagged `EXECUTOR: HUMAN <reason>` in section test plans.
4. Firebase/GCP console provisioning for Stage 2 (account-holder access only the user has).
5. Commit/push authorization (user drives commit cadence — `feedback_no_auto_checkpoint`).

Anything else handed to the user is a contract violation.

## Cannot-Execute Rule

If the AI cannot execute a verification step, it must name the specific blocker (e.g., "needs
Android emulator", "needs Firebase console access") and ASK — not skip, not defer, not declare done.

## Phase-Complete Definition

A section/phase is complete when BOTH hold:

1. Every checkbox in its task list is `[x]` with executed-and-reported evidence (test output,
   probe response, or named HUMAN sign-off recorded in the section's execution log).
2. The commit hash covering the work is filed in the section file (after user-authorized commit).

Anything less is not "done" and must not be reported as done.

## Process Gates (this milestone)

- **No implementation code before the cascaded review closes** (`/plan-review-cascaded`; user
  directive 2026-06-11 — full cascade, not the lightweight serial gate).
- Stage 1 implements before Stage 2 (user directive: UI first).
- 100% COVERAGE MANDATE note: lupin-mobile is an **excluded sub-repo** per parent Lupin CLAUDE.md;
  the operative bar here is the project's own baseline discipline — the green suite count never
  decreases, every section adds its enumerated tests, quarantine (44 ❌) stays untouched.
