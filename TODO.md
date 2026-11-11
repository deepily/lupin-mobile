# TODO

## Resume here: 2026-11-11 close (Tiffany)

The working branch is `wip-v0.2.3-2026.11.04-tracking-lupin`, and nothing is pushed. The APK is still "2026.11.09 build 3", because today changed only tests and docs. Owed work is in the store.

- [ ] Earbud check on build 3 (rows `c643b1b0` and `bcc9cba3`). Rick asked for a callback at 7 pm Eastern. After his check, read `docker logs --timestamps lupin-rest-dev | grep earbud_trace`, and respawn Clayton from `io/mementos/clayton-85dfc14c.md`.
- [ ] Code-health Phase 2 (rows `adc98845`, `4adc2850`, `032ee125`, `4ebc3c6e`) starts when Cheech's Phase 1 (`dbbe93a0`) is done. The umbrella row `e1778814` is still held for Rick.
- [x] Public APK pulled (`cbdec4ca`), re-pin (`df84ddae`), fixed-wait sweep (`065ee0ee`), wiki rollups, baseline cost (`2ee18321`). Session `14de3771`

### Decisions Log — 2026-11-11 (session `14de3771`, Tiffany)

- Rick: delete just the APK asset from the public v0.2.2 release (card answer); he ran the API delete himself.
- Rick: call him back for the earbud check at 7 pm Eastern (comment on the card).
- Tiffany: the baseline cost cites 0.9 judge calls per definition, the plan's only per-definition rate. The per-run figure (747 to 782 calls) is used only to price a call.

## Earlier: 2026-11-09 close (Tiffany)

The working branch is `wip-v0.2.3-2026.11.04-tracking-lupin` at `da3f69e`, and the APK is "2026.11.09 build 3". Owed work is in the store, and Rick's rows come back 10 Nov at 09:00 Eastern. The status report is `io/status/2026.11.09-tiffany-status-report.md`.

- [ ] Earbud check on build 3 (rows `c643b1b0` and `bcc9cba3`); respawn Clayton from `io/mementos/clayton.md`.
- [ ] Pull the public APK (row `cbdec4ca`): remove just the asset (recommended), delete the release, make the repo private, or restrict the key only.
- [ ] notification_bloc_test re-pin (row `df84ddae`): Rick runs the script named on the row; then Tiberius checks, and I merge `718a205` plus the pin.
- [ ] Fixed-wait sweep of about 80 tests (row `065ee0ee`, approved), plus three wiki-librarian rollups (P5).

### Decisions Log — 2026-11-09 (session `21b94fbc`, Tiffany)

- Rick: no CI for now ("I don't want CI I don't need it"). Row `23c5580e` is dropped, the session-start CI check is removed, and the workflows stay on until he says otherwise.
- Rick: drop the dart format check (house style), drop the PR-title check, and make the size check a warning.
- Rick: delete AudioCache.
- Rick: a timing-only re-pin of frozen notification_bloc_test is allowed (yes, 2026-11-10 03:16:23 UTC).
- Tiffany: the load-flake row closes on the tests found today; the full five-in-a-row goal moves to `065ee0ee`.

## Earlier: 2026-11-04 close (Tiffany)

v0.2.2 is merged (PR #4, `ccdc8fd`) and released with the APK. The working branch is `wip-v0.2.3-2026.11.04-tracking-lupin`. Four rows carry over, and all of them come back at 09:00 Eastern on 11-05.

- [ ] Earbud capture is likely silent, so Whisper returns "thank you" (row `bcc9cba3`). First capture the WAV with earbuds in and check its peak level.
- [ ] Earbud taps only click on the phone (row `c643b1b0`), then the phone-locked step (row `3a8005c1`).
- [ ] Firebase key restriction (row `cbdec4ca`): Rick changes it in the Cloud console, then I check that a push wake-up still reaches build 2.
- [x] Archive TODO.md horizon: done, 528 lines down to 101 (`09b1907`).
- [ ] Possible flake: `ws_stale_channel_test.dart` (carried from 11-01).

### Decisions Log — 2026-11-04 (session `5988cc00`, Tiffany)

- Rick: fix the transcript bug in the next branch and carry the tap bug forward. The version is 0.2.2.
- Rick: the whole-branch gate's exceptions are allowed: the analyzer config, three ignores, and the markdown check failing on older records. Each is documented in PR #4.
- Rick: the podcast Delete has an Undo snackbar. If the podcast is playing, it keeps playing and is deleted when it stops; a progress ring shows only while it downloads.
- Rick: the next branch is `wip-v0.2.3-2026.11.04-tracking-lupin`, and the release carries the debug APK.

## Earlier: 2026-11-02 close (Tiffany)

Five rows were done or merged today; APK build 4 is at `bd27502`. Two new bugs are filed for tonight, and both wait for Rick's approval.

- [ ] Tonight: Quick Ask tap to start and stop recording works only intermittently (row `0f29b56e`). First find which tap fails: the on-screen button or the earbud.
- [ ] Tonight: Quick Ask speech recognition returns no transcript (row `bcc9cba3`). First find whether the phone or the server loses it.
- [ ] Rick's earbud check on build 3 or later closes hands-free step 1 (row `c643b1b0`, blocked on him). Step 2, earbuds with the phone locked, is row `3a8005c1`, waiting for approval.
- [ ] Archive TODO.md horizon: the file is over 500 lines. Rick's archive question dropped in the 17:00 server bounce, so it defaulted to next session.
- [ ] Possible flake: `test/unit/services/websocket/ws_stale_channel_test.dart` failed once in a full run (Sam, 11-01).

### Decisions Log — 2026-11-02 (session `cfdbef0b`, Tiffany)

- Rick: every multiple-choice ask shows "Other" with a text field, single- and multi-select, and answers in the web client's shape (row `50ce6d46`).
- Rick: hands-free Quick Ask is built with the screen on first; the phone-locked step comes second (row `3a8005c1`).
- Rick: by default a notification doesn't pop up at the system level while the app is open, and the ding stays on. There is no setting for either (row `66f6cf2f`).

## Earlier: 2026-11-01 close (Tiffany)

Drive podcasts, approve links and offline download are done: three rows closed, APK build 3 at `fefb4f4`. One held row on my board waits for Rick: `50ce6d46`, the missing "Other" option on multiple-choice asks.

- [x] Archive history.md: done, 2026-09-19 to 10-05 moved to `history/`.
- [x] A podcasts list showing every generated podcast: done through Google Drive (row `dc0dafdc`).
- [ ] Possible next step, not yet a row: a "Download all" button for the Drive section, and playing while the file downloads. Rick heard both offered and asked only for the per-row button.
- [ ] Watch for Mr. Radio's server fix that removes the date prefix from Drive titles. The phone leaves it as the server sends it.

### Decisions Log — 2026-11-01 (session `6b2f0ab0`, Tiffany)

- Rick: the phone lists Drive through a server endpoint that uses the desktop's Google token, with no Google sign-in on the phone. The phone's Firebase project differs from the desktop's Drive project. This replaces the 10-31 ruling that Drive was for the desktop only.
- Rick: use the one-click approve link for every new held row, with the 📄 view link beside it (task-store-discipline §3.2).
- Rick: a download button on every Drive podcast, so it can be kept on the phone over Wi-Fi and played without mobile data (row `6430afac`).

## Earlier: 2026-10-31 close (Tiffany)

The podcast loop on the phone is done: seven rows closed, APK build 7 at `243aea6`. The plan and the explainer are in `src/rnd/2026.10.31-explainer-to-podcast-phone-loop-plan.md`. No live rows on my board.

- [ ] Possible next step, not yet a row: double tap on the earbuds to rewind. It needs our own audio_service handler in place of just_audio_background (medium cost, research at `39907c0`).

### Decisions Log — 2026-10-31 (session `e3be888f`, Tiffany)

- Rick: Google Drive is for the desktop only. The phone plays the podcasts it starts straight from the Lupin server.
- Rick: cache podcasts on Wi-Fi and play them offline; ask before using mobile data (row `24a39e97`).
- Rick: the rewind is back 15 seconds, with a long press to go back to the start. Ship it without a lock-screen rewind button, because just_audio_background fixes those buttons.
- Rick: add a Podcasts list, reached from Surfaces and the player bar (rows `f13143d5`, `e12f5649`).
- Rick: research the earbuds before building anything. A single tap was confirmed working once he had the phone-paired Pixel Buds Pro 2 in.
- Tiffany: the podcast pauses while the app speaks and then resumes; it does not just dip in volume.

## 📦 Archived TODO content
- **[2026-09-23-to-10-20-todo.md](todo-archive/2026-09-23-to-10-20-todo.md)**: dated blocks from the 10-20 close back to 09-23, including the v0.2.2 branch handoff of 09-30. Archived 2026-11-04.
- **[2026-08-21-to-09-22-todo.md](todo-archive/2026-08-21-to-09-22-todo.md)**: the dated sections 09-22 back to 08-21, plus the May and June "START HERE" blocks. Archived 2026-09-26.
- **[2026-04-15-to-06-12-todo.md](todo-archive/2026-04-15-to-06-12-todo.md)** — postgame decisions (2026-06-12), ✅ COMPLETED blocks (05-23, 06-12), 2026-05-07 breadcrumb, superseded voice-persona HUMAN-gate runbook, 2026-05-21 parked conditionals, all completed `[x]` items through 2026-08-21. Archived 2026-08-21.

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
