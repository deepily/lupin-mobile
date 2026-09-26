# TODO

Last updated: 2026-09-26 (Session `90e34e30` — Tiffany 💍, Skeleton Shift): TaskRow call-site guard merged (`92a3fc0`, row `d5bbd786` closed); `file_picker` verified on Rick's phone; first real broadcast from the app delivered. Suite 2010 / 1 skipped / 0 failed.
Prior: 2026-09-20 (Session `cc9c1f1a` — Tiffany 💍, manager on duty): **nine merges, pushed and backed up on Rick's 22:55 ritual order.** Rick ruled every open gate: both held rows admitted, batch won't-fix keeps no confirm (matching web), and the phone probe `c51e92da` **PARKED to 2026-10-19 — he has no cell service and no public IP for at least a month and told the fleet to stop asking. Do not re-raise it.** His own P0 `72e01fb3` closed on receipts against the tree. Sam's roster addressability guard merged (`488f189`, 71/71 green). Phase 5 is blocked on a SERVER defect Chloé traced — `commons_broadcast_ack` appears never to persist, so the ack drain can never contain acks. Three of my own rows were corrected by workers before a line was written.
Prior: 2026-09-19 (Session `cc9c1f1a` — Tiffany 💍): **no code, board cleared.** Three rows closed on receipts — `c3fc62bf` on Rick's own device tail (`POST /api/v2/transcribe` → 200), `b00e076c` on 9/9 green, P0 `cea58ee0` on `11f9f5e` + 10/10 green **after splitting its amended-on server half out to lupin `2184bebb`** so the close could not bury it. Four rows filed. A live bearer token turned up in Rick's paste, making `a7de7d69` self-demonstrating. Mr. Radio ruled option B and banned the fallback; he also caught an unverified green claim of mine and predicted a real sentinel gap — which I then measured, and which became `67c7a2e1`, merged tonight as `488f189`.
Prior: 2026-09-18 (Session `fe56dccd` — Tiffany 💍): **nine commits.** P0 `cea58ee0` (duplicate personas) root-caused to the server and fixed on the phone; 0% TTS now means silence on every path including the background wake; abstracts became progressive disclosure; the Fold gained a beside/below toggle that no longer re-fetches; an answer tapped offline is kept, resent and never dropped. Rick ruled six questions (see Pending decisions). Suite 1211 → 1234. Backed up and pushed.
Prior: 2026-09-14 (Session `b3e285b8` — Tiffany 💍, builder-manager): **spoken-ask door BUILT AND MERGED.** Rick's build go was given at 15:48, conditional on rev 13 being verified. Rev 13 verified 13/13 (`7a6ca84`), then revs 14–19 were folded during the build. §B phone transport (Rachel) merged as `83f19a7` and §C phone behaviour (Maya) as `16d73f8`; the §A server door merged in lupin (`993be2b6`). Same 46 already-failing tests before and after, 72 new passing. Device checks are parked for **2026-09-15 09:00** with Rick. Two P3 bugs are awaiting his admit.
Prior: 2026-09-11 (Session `afe9bfdc` — Tiffany 💍): **spoken-ask door cascade CLOSED — plan rev 8 → rev 12, six pins in git, NOTHING BUILT.** Nine review stages plus two verification passes; both passes found defects introduced *by the folds themselves*. Rick declined a build at 22:39 ("it's 1030 at night"); rev 13 is **held, not cancelled**, and its 11 items are a **list-to-verify** whose coordinates have drifted ~49 lines. Five items parked on Rick, chase 09:00. Row `9df9f1c2` handed to Mr. Radio with receipt.
Prior: 2026-09-02 (Session `5b101cc5` — Tiffany 💍): **AC-G3 `734bd1bf` CLOSED with receipts** (`ts-fee0022f`, Rio ⚡ implementing). **Backup fixed twice and verified end to end** — destination repointed to the standalone mirror, then the vendored 1.9 GB Flutter SDK excluded (1.79 GB → 6.22 MB); all 532 tracked files verified present at the mirror after the write run. Two stale facts corrected: the `:7999` bounce precondition was already satisfied, and `734bd1bf` had not been blocked on Rick since 2026-08-31.
Prior: 2026-08-30 (Session `0e3df8ca` — Tiffany 💍, MANAGER): **board driven down; two of the three items carried from 2026-08-29 are closed and the third is parked with a chase.** Arnold's row `82883a4e` closed with receipts (mutation-verified, not just green). AC-S2.8 resolved — it was never undefined (commit `0df6a66`). Rick ruled on `54589356`; handed to Pocholo. **New P1 `0e7c9214`** found live with Rick at the keyboard: a repeat ask computes its answer and never announces it — two independent server bugs, both root-caused the same evening.
Prior: 2026-08-29 (Session `4000b44a` — Tiffany 💍, MANAGER): **Quick Ask push-to-talk screen implemented end to end** across 62 commits after a cascaded review (doc `src/rnd/2026.08.29-quick-ask-push-to-talk-screen.md`, recon sheet `src/rnd/2026.08.29-cascade-quick-ask-recon-checklist.md`). Suite 710 → **835 passing**; 44 errors all inside `legacy_quarantine/`, zero outside. Crew of four stood down with verified mementos; mementos are now gitignored.
Prior: 2026-08-21 (Session `e082edd7` — Tiffany 💍): v2 cutover **wave 2 DONE** (nine submit doors → `/api/v2/submit`, against integration 799e43d0; doc `src/rnd/2026.08.21-v2-cutover-wave-2-readiness.md`); lane-2 harness door fix merged to integration (3c3f1f5e). **TODO horizon archive pass executed this session** — past content (2026-04-15 → 2026-06-12: postgame decisions, completed blocks, breadcrumb, superseded voice-persona runbook, parked conditionals, all `[x]` items) moved to `todo-archive/2026-04-15-to-06-12-todo.md`.
Prior: 2026-06-25 (Session `f53bc7b3` — Tiffany 💍): Focus UI active/history filter PLAN landed + review-ready (doc `src/rnd/2026.06.25-focus-ui-active-history-filter.md`).
Prior: 2026-06-12 SESSION-END (Session `dabf7fbb` — Mr. Radio 🦉): focus-mode milestone AI-IMPLEMENTATION + REVIEW COMPLETE; postgame decisions → archived (see pointer above).

> **▶ CLEARED-SESSION PRIORITIES (Rick, 2026-06-12 → Monday)**: GCP migration BACK-BURNERED.
> Two priorities for fresh sessions: **(1) the task-list functionality**, **(2) cosa-voice token
> efficiency** (~75% of inference budget — the dominant spend). Lead with token-frugal work.
>
> **▶ WORKING-PoC FAST PATH** (needs NO Firebase): `src/rnd/2026.06.12-poc-laptop-build-runbook.md`
> — rsync→build→adb install; real-device gotcha = repoint `assets/config/server-contexts.json`
> off `10.0.2.2` (emulator-only) to the dev-server LAN IP; ends at fm1–fm6 acceptance.

## 📦 Archived TODO content
- **[2026-08-21-to-09-22-todo.md](todo-archive/2026-08-21-to-09-22-todo.md)**: the dated sections 09-22 back to 08-21, plus the May and June "START HERE" blocks. Archived 2026-09-26.
- **[2026-04-15-to-06-12-todo.md](todo-archive/2026-04-15-to-06-12-todo.md)** — postgame decisions (2026-06-12), ✅ COMPLETED blocks (05-23, 06-12), 2026-05-07 breadcrumb, superseded voice-persona HUMAN-gate runbook, 2026-05-21 parked conditionals, all completed `[x]` items through 2026-08-21. Archived 2026-08-21.

## 🆕 Open from 2026-09-26 (Skeleton Shift)

### Decisions Log — 2026-09-26 (session `90e34e30`, Tiffany)

- **Row `e1e2c545` (the two re-spin doors read different memento files) stays with Mr. Radio.** Rick said yes: it's lupin tooling, not mobile work.
- **Test uploads are deleted after the check.** Rick's test JPEG was removed from `lupin/io` on his yes, following his ruling earlier that day that nothing temporary should accumulate in io.

### ⏳ Owed — 2026-09-26

- [ ] **Rick: close row `61ecfb22`** (doc viewer). It's parked, so only his login can close it. Evidence: `file_picker` built, installed and uploaded on his phone with no console errors.
- [ ] **Walk-through items 11-14**: the reply tally through the notification shade, backgrounding and navigation, then landscape. Item 10 (a real broadcast) passed on 09-26.
- [ ] **New task creation** (M4 is a disabled stub). Needs Rick's go before building.

## 🆕 Open from 2026-09-24 (Task List M1/M3/M4, doc-viewer parity with the web)

### Decisions Log — 2026-09-24 (session `ecb8e6e3`, Tiffany, skeleton crew)

- **Phase 2 status given to Rick**: all ten gaps from the 09-23 census are built. What stays open is the device walkthrough plus M1/M3/M4, and those three were built today.
- **Doc viewer parity**: Rick asked me to coordinate with Mr. Radio on everything. I sent him the plan before building, and he confirmed the existing server responses would not change.
- **Upload picker**: Rick approved the `file_picker` plugin. If it breaks the build, take it out and carry on without Upload for now, "but we will have to include this eventually".
- **Merge gates**: Rick said yes to all three merges (`6ce802e`, `312aa40`, `104401b`).

### ⏳ Owed — 2026-09-24

- [x] ✅ **2026-09-26: passed on Rick's phone.** **Rick's laptop APK build**, the first real test of `file_picker` 11.0.3 (this machine has no Android SDK). Then check on the device: Folder, Roots, an upload into io, and a second upload of the same name (clash sheet). Closes row `61ecfb22`.
- [ ] **Row `651e3956` (P1)**: investigate reviving the Android SDK on this machine. Rick is picking it up 09-25.
- [ ] **Holding-area rows only Rick can close**: `323d0f9c` (M1/M3/M4, merged), `f8f893ba` (duplicate of `61ecfb22`, drop it), ~~`d5bbd786`~~ ✅ admitted, built and closed 09-26 (`92a3fc0`).
- [x] ✅ Archived 2026-09-26. **TODO.md was 613 lines**, far past the ~200-line horizon signal; many 09-22 items are done (B1, N1 via mention chips, R1/N2, M1/M3/M4).

## 🆕 Open from 2026-09-23 (pane parity closed, broadcast ack recovery merged)

### Decisions Log — 2026-09-23 (session `693d5366`, Tiffany managing)

- **Task List hides illegal verbs** (Rick, 22:15, row 19190a5b closed). The legality reasons are still computed (`verbLegality`), so switching to greyed out later is small and reversible.
- **The ack window runs 5 minutes from the send, not from the last ack.** The web restarts its timer on each ack, so a broadcast nobody acks never expires there; a backgrounded phone produces exactly that case. The difference is deliberate (`AckAggregate.ackWindow`).
- **The saved ack wins for its seat unless that seat moved during the read.** The server's row is the latest only as of its answer, and a later live frame must not be rolled back (`0cdfe1a`).
- **No truncation guard on the ack read.** `limit` caps the rows scanned BEFORE the latest-per-seat merge, so `len == limit` means nothing. The server's `Query(500)` has no maximum.

### ⏳ Owed — 2026-09-23

1. **Rick: admit d5bbd786** (TaskRow call-site guard). He approved it at 22:15; only his board can admit it. Then staff a worker.
2. **On-device check** after the APK rebuild: walk-through items 7-14, and one real broadcast with the app backgrounded, then resumed, to see the ack read-back.

---

## Pending

### ⚡ First thing next session — hygiene-commit follow-ups (from 2026-04-23 gitignore cleanup, commit `edaec79`)
- [ ] [LUPIN-MOBILE] Decide whether to add a `history.md` one-liner for commit `edaec79` — the chore is fully documented in the commit message itself; decision is: keep history.md for feature/bug work only, or backfill a one-liner for this cleanup.
- [ ] [LUPIN-MOBILE] Decide whether to purge `build_runner.dart-3.8.0.snapshot` (~26MB binary) from git history — requires `git filter-repo` + force-push; permanently reduces clone size but rewrites history. Only worth it if the repo is mirrored/cloned frequently.
- [ ] [LUPIN-MOBILE] Audit parent Lupin + other sub-repos (cosa, lupin-plugin-firefox) for the same gitignore gaps — consistency pass; may not apply since those aren't Flutter projects, but .claude-session.md / __pycache__ gaps might recur elsewhere. (Out of scope for lupin-mobile repo; would need to be done in each repo's own context.)

### On-Device Sanity Pass (login confirmed on device 2026-04-17; remaining sanity checks still open)
- [ ] [LUPIN-MOBILE] Device sanity: open Inbox (widget-level covered by `inbox_screen_test.dart` × 4 cases)
- [ ] [LUPIN-MOBILE] Device sanity: respond to an ask_yes_no from Inbox (widget-level covered by `conversation_screen_test.dart` × 3 cases)
- [ ] [LUPIN-MOBILE] Device sanity: Trust Dashboard renders (widget-level covered by `trust_dashboard_screen_test.dart` × 3 cases)
- [ ] [LUPIN-MOBILE] Device sanity: DeepResearch dry-run submits (widget-level covered by `deep_research_form_test.dart` × 3 cases)
- [ ] [LUPIN-MOBILE] Device sanity: run `integration_test/smoke_hello_test.dart` via `flutter test integration_test/` on emulator (proves scaffolding)

### Tier 2 — Notifications + Decision Proxy (polish remaining)
- [ ] [LUPIN-MOBILE] ~~Decide whether to remove orphaned `lib/shared/models/notification_item.dart`~~ — **Revised finding 2026-04-21**: NOT orphan. Re-exported via `lib/shared/models/models.dart` and imported by 20+ production files (voice bloc, audio cache, repositories, use cases). There are now two `NotificationItem` classes — the old shared one and a newer differently-shaped one in `features/notifications/data/notification_models.dart`. Migration would require touching voice/audio/cache layers. **Reclassified: leave in place; no action unless voice/audio/cache layers are refactored.**

### Agent-narration TTS (new 2026-04-21)
- [ ] [LUPIN-MOBILE] On-device verify TTS: live ElevenLabs audio plays in the emulator (user's laptop); injected `quota_exceeded` falls back to `flutter_tts` cleanly. **Scenario #7 is the regression test for the 2026-04-24 overlap fix.**
- [ ] [LUPIN-MOBILE] Future: ElevenLabs voice/config customization per agent/context (currently uses backend defaults only)

### Notification audio-on-receipt (new 2026-04-21)
- [ ] [LUPIN-MOBILE] ~~Phase 5 — Background FCM handler~~ — **DEFERRED INDEFINITELY** per 2026-04-21 decision. Conditions for revisiting documented in R&D doc section 7. Mobile implementation notes remain in `2026.04.21-notification-audio-on-receipt-plan.md` Phase 5 (still accurate when triggered — switch to silent-relay variant per R&D recommendation).
- [ ] [LUPIN-MOBILE] On-device verify: urgent notification plays correct MP3 + speaks message (laptop + emulator; user to run)

### Tier 4 — Agentic (polish + deferred)
- [scope decision 2026-04-22] **TimeSavedDashboard + StatsRepository + StatsBloc + `fl_chart`** — deferred indefinitely per user; not in any current slate. Re-add only on explicit request.
- [ ] [LUPIN-MOBILE] On-device verify Phase 4a — load a podcast/research-podcast artifact (or any MP3 path until Phase 4b backend fix lands), test play/pause/stop/share + audio-focus interaction with TTS narration. Bucket with the existing TTS on-device verification.
- [ ] [LUPIN-MOBILE] **Phase 4b (deferred, blocked on cross-repo)**: switch `JobDetailScreen` for `pg-*`/`rp-*` jobs to use real `audioPath` field — blocked on parent Lupin exposing `artifacts['audio_path']` in queue metadata. See `bug-fix-queue.md` Cross-Repo entry.

### Testing Playbook — Stage 4+ (deferred with revisit triggers)
- [x] [LUPIN-MOBILE] **Legacy quarantine triage pass**: resolved 2026-09-16 by deletion (Rick's ruling, row `5ac999f5`). Files remain in git history before that commit.
- [ ] [LUPIN-MOBILE] Alchemist visual-regression goldens — revisit when inbox tile / DR form / trust chip sees ≥2 regressions in a month
- [ ] [LUPIN-MOBILE] Patrol 4.x native-dialog support — revisit when app requests runtime permissions (mic, notifications) and smokes can't pass them via taps
- [ ] [LUPIN-MOBILE] Maestro MCP flows — revisit after `integration_test/` has ≥5 flows and CI parallelization matters
- [ ] [LUPIN-MOBILE] Fixture coverage for agentic endpoints (DR submit, podcast, etc.) — Stages 2/3 covered auth/notifications/decision-proxy; agentic is the remaining domain
- [ ] [LUPIN-MOBILE] CI job that runs `capture-*-fixtures.py` on a schedule + opens a PR when fixtures diff — catches silent backend drift

### Cross-cutting

### Decisions pending — Rick (2026-09-17)
- [x] [LUPIN-MOBILE] **Focus rail's opening lens — RULED 2026-09-18: keep Live.** keep Live (activity within 1 hour, sent or received since `6dba6fc`) or default to 24h on the phone? One-line change plus tests, own commit. Asked 2026-09-17, unanswered.
- [x] [LUPIN-MOBILE] **Open Fold: documents beside or below? — RULED 2026-09-18: a toggle in the viewer, remembered.** Rick's idea (2026-09-18): open docs and abstracts in the bottom half so tables use the full ~840 dp instead of being crushed at ~420. Options put to him: (a) a beside/below toggle in the viewer's title bar, remembered — **recommended**, since tables want below and prose reads fine beside; (b) a Settings switch; (c) always below, at the cost of the conversation shrinking to about three bubbles; (d) not now. Asked 2026-09-18 three times: Rick says he answered the first two, but both came back to me as timeouts, so his answers never arrived. The ticket gate refused a store row, so it's tracked here.
- [x] [LUPIN-MOBILE] **Branch `tiffany/release-picker-2` — RULED 2026-09-18: deleted (was `8314a06`).** It has 2 commits from 09-15 (`7fd0e8c`, `8314a06`) that were never merged. The release-picker fix already shipped from `tiffany/release-picker` (`a012748`) and row `2070a906` is dropped. Recommended: **delete**. Alternative: diff its visibility tests against what shipped and merge anything stronger. Asked 2026-09-18, timed out.
- [x] [LUPIN-MOBILE] **`.heartbeat-hold-71d94067-…json` — RULED 2026-09-18: deleted.** It's my expired, untracked hold file from 09-15. The auto-mode check blocked `rm`, so it needs Rick's word (or María's cleanup script). Asked 2026-09-18, timed out.
- [ ] [LUPIN-MOBILE] **Device confirmation owed for seven local commits** (`bc98024` `cfb8285` `6dba6fc` `cf5280a` `91b2139` `d7aaacd` `fc8d9dc`) plus `a2f1d75` (v2 transcribe, row `c3fc62bf`). One rebuild covers all of them.
