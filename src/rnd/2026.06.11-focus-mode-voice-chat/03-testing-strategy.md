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
7. **Await-window state-clobber guard** (folded 2026-06-12 from ledger addendum #11): in any
   bloc/async handler, NEVER `emit` (or merge into) state captured BEFORE an `await` — every
   suspension point is a window in which another event may have advanced the state, and emitting
   the stale capture clobbers it. Re-read `state` and merge SYNCHRONOUSLY after all awaits
   complete. Review checklist item for every new async handler; regression recipe when a
   violation is found: Completer-held async stubs + mid-flight event injection + a survival
   assertion on the racing field. (Confirmed twice in one night: F-S1-IMPL-1
   `_preemptNonDestructive`; F-S2-IMPL-1 `_reconnectRefresh` + `_coldStartBuild` — both caught
   by implementation light review, both regression-pinned, 2026-06-12.)
8. **`tester.runAsync` for real-event-loop futures** (folded 2026-06-12 from ledger addendum
   #12, twice-bitten): any future inside `testWidgets` that completes on the REAL event loop —
   engine image capture (`toImage` / `toByteData`), bloc-seeding waits, bare `Future.delayed` —
   MUST be wrapped in `tester.runAsync(...)`. Under the default fake-async zone these futures
   never complete; the failure presents as an opaque 10-minute timeout with no useful stack
   (`_RawReceivePort._handleMessage` only), in full-suite AND solo runs. Diagnostic cue: a
   widget test that times out rather than fails is a fake-async hang until proven otherwise.
   After seeding via runAsync, hard-gate with an `expect` on the seeded state before pumping.
   (Anchors: AC-C4 pixel-diff hang + `focus_assembly_test.dart` seeding hang, S3 close; full
   recipe in `12-section-s3-focus-ui.md` §8.)

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
