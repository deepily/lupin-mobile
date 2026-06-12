# Focus-Mode Voice Chat — Testing Strategy (Shared Anchor)

**Created**: 2026.06.11
**Scope**: tiers, venues, and executor split shared by all sections. Per-section test enumerations live in each section file; this anchor is the rubric they cite.

## Tiers & Venues

| Tier | Command | Venue | Executor |
|---|---|---|---|
| Static analysis | `./flutter.sh analyze` | dev server | EXECUTOR: AI — after every section's code lands |
| Unit/bloc | `./flutter.sh test test/unit/` | dev server | EXECUTOR: AI |
| Widget | `./flutter.sh test test/widget/` | dev server | EXECUTOR: AI |
| Live HTTP probe | Python/Dart client → `:7999` (read-only or net-zero mutation only) | dev server | EXECUTOR: AI — auth via `LUPIN_TEST_INTERACTIVE_MOCK_JOBS_*` |
| APK + emulator/device | `build-and-deploy-lupin-mobile.sh`, on-device runbook | laptop | EXECUTOR: HUMAN (no Android SDK/adb on dev server — `feedback_dev_server_laptop_split`) |
| Perceptual gates | on-device runbook sign-off | laptop + device | EXECUTOR: HUMAN (subjective audio/UX judgment) |

## Standing Rules

1. **Baseline discipline**: current green baseline is the suite count at section start (record it
   in the section execution log before first edit). It only goes UP. Quarantine (`test/legacy_quarantine/`,
   44 ❌) stays untouched.
2. **BLoC-first automation** (`feedback_automate_over_manual_tests`): widget-test BLoC-driven flows
   via `whenListen` + MockBloc BEFORE anything is routed to the device. The device verifies only
   what hardware alone can verify (mic capture, audio focus, FCM doze delivery).
3. **Per-section enumeration**: every section file lists its acceptance criteria as
   `EXECUTOR:`-tagged checkboxes. Bare checkboxes are a plan-review violation (Convention 3).
4. **Wire-grounding**: any test asserting a server contract (ASR response shape, WS event names,
   FCM payload) must derive its fixture from a live capture or a parent-repo source read with
   file:line provenance — never hand-authored from memory.
5. **On-device runbook**: Stage-1 perceptual gates extend the existing runbook
   (`../v0.1.7/2026.04.24-on-device-tts-verify-runbook.md`) with a new "Focus-mode milestone gate"
   section rather than spawning a parallel runbook; Stage 2 adds a doze/wake gate.
6. **"Manual" semantics**: per Convention 5, "Manual E2E" in any section means NOT-YET-AUTOMATED,
   never "the user does it". Steps the AI genuinely cannot run carry `EXECUTOR: HUMAN <reason>`.

## Cross-Section Integration Checkpoints

These run after the named sections' code lands (Stage-1 integration is part of S3's exit gate):

- [ ] EXECUTOR: AI — Full-suite run (`./flutter.sh test test/unit/ test/widget/ test/service_integration/`)
      green at every section close; report count vs baseline in tabular form.
- [ ] EXECUTOR: AI — S2+S1 wiring blocTest: inbound notification while paused accumulates the TTS
      queue and increments unread; resume drains in order.
- [ ] EXECUTOR: AI — S3 assembly widget test: rail tap switches focused pane without dispatching
      TTS state changes (manual-focus invariant, Q4).
- [ ] EXECUTOR: HUMAN (hardware: mic + speaker + doze) — on-device runbook gates enumerated in
      S3/S4/S5 files, single bundled laptop+emulator session per stage.
