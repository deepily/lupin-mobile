# LUPIN MOBILE - SESSION HISTORY

## 📚 Archived Sessions

Older session entries have been archived for token-limit hygiene. See:
- **[2026-09-01-to-18-history.md](history/2026-09-01-to-18-history.md)** — spoken-ask door, Quick Ask fixes, split screen, 0% means silence, the backup SDK finding (archived 2026-10-02)
- **[2026-05-21-to-08-31-history.md](history/2026-05-21-to-08-31-history.md)** — notif-client sync, focus-mode milestone, v2 cutover waves, Quick Ask push-to-talk, the backup incident (archived 2026-09-16)
- **[2026-05-06-to-11-history.md](history/2026-05-06-to-11-history.md)** — voice-persona milestone Phases 0–5 + CC-dispatch retirement sync + yes/no/neither tri-state (9 entries, May 6–11, 2026; archived 2026-08-21)
- **[2026-04-17-to-24-history.md](history/2026-04-17-to-24-history.md)** — WS hookup → TTS overlap fix (5 sessions, Apr 17-24, 2026; archived 2026-05-11)
- **[2026-04-15-to-16-history.md](history/2026-04-15-to-16-history.md)** — Tier 1-4 buildout (5 sessions, Apr 15-16, 2026)
- **[2025-07-06-to-08-17-history.md](history/2025-07-06-to-08-17-history.md)** — Initial era (7 sessions, Jul 2025 – Aug 2025; project then dormant for 8 months)

Most recent entries (2026-09-19 onward) are retained below.

---

## 2026.10.02 | Session `27fa7f7e` (Tiffany 💍) — stop poke switch, Claude Code submit fix, docs track loose ends

Crew: Pocholo (one reviewer seat, Rick's yes; review row `4c62c7b9` PASS, no blockers; seat released 14:45 EDT with a memento at `io/mementos/pocholo.md`).

- **Stop poke switch** (row `ee68d5e7`): `HeartbeatPokeRepository` and `HeartbeatPokeSection` on the Notifications screen, over `GET`/`PUT /api/heartbeat/poke-mute` (lupin row `3526fb95`, served as lupin `49f987d75`). Plain on/off, admin-only write, no timer (Rick's ruling). Commits `99acbe0`, `2ad3abb` (recorded GET answer as a fixture), `d0c5da8` (review fix: a refused switch stays disabled).
- **Claude Code dispatch** (bug `bdd60a1b`): the phone posted to `/api/claude-code/submit`, which the server answers with 410. Now posts the `/api/v2/submit` body. Commit `22f7847`.
- **Rick's rulings applied**: tests that assert comment wording are converted (`0823137`, record `R-comment-text-tests`); `lib/features/voice` and `lib/core/use_cases/use_case_registry.dart` deleted (`222e9a0`).
- **Docs track**: `prompt_bodies.dart` swept and `lib/shared` gated (`7dac4dc`); doc standard example fixed (`ffb13ec`, record `R-record-id-form`); AC-G2 baseline recaptured (`4ecb178`, `ffb13ec`); pilot report sent to María. Undocumented public members in `lib/`: 6. Gated directories: 13 of 24.
- Suite: NO_NEW_FAILURE (3 known failures) and AC-G2 PASS at `d0c5da8`. APK built with `--fcm` at `d0c5da8`. Not pushed.
- **Claim judge**: Rick ruled Haiku as the provisional judge for pilots (via Cheech). The Dart labelled set is built on the lupin side (rows `ec1854b7`, `dad61023`); mobile supplies the blind second check (row `eb5a05fe`), tomorrow at the earliest.

**RESUME HERE:** (1) No workers running; respawn Pocholo from his memento when work exists (command on row `eb5a05fe`). (2) Rick: docs gate scope (row `27a1d168`, blocked, direct ask timed out 14:39; briefing in `io/2026.10.02-docs-gate-scope-decision.md`, untracked). (3) Rick runs the transcript capture with his admin login (`bash -ic "python3 src/scripts/capture-transcript-fixtures.py"`), then commit the fixtures (row `768e852f`). (4) Rick flips the stop poke switch once on the phone; record the PUT answer. (5) Cheech DMs the Dart dev split for the second check. (6) `history.md` is over the 17k-token warning line; archive at session end.

---

## 2026.10.01 | Session `fb9c89d0` (Tiffany 💍) — mobile docs track: pilot, sweep, ratchet tooling

Crew: Clayton, Krishna (two seats, Rick's ruling). Umbrella row `b707f92f`; manifest `src/docs/plan-stubs/mobile-docs-track.stubs.json`.

- **Merged and pushed** (tip `28a7307` plus this entry): Phases 1 and 2 closed; pilot steps 1-3; ignore checker (`tool/check_doc_ignores.py`); sweep of `lib/services`, and `lib/features/` fleet, fleet_status, task_list, transcript, broadcast. Comments only, each batch gated (comments-stripped comparison, lupin `docs_only_diff`, linter, full suite). Undocumented public members in `lib/`: 4,914 → 3,188.
- **UPDATE 23:08: batch b9 green (Rick ran the gate script himself); both merged as `ed3a79c` and `96f3768`, tree identical to the gated trial `4121f84`, and pushed.** Suite: NO_NEW_FAILURE, 3,136 tests. The "RESUME HERE" merge item below is done; the permission rule for the gate script is still needed.
- Gated late (see update above; was committed-but-unmerged at the first close): Krishna `2ccb028` = `lib/core` (all but `app_constants.dart`), session, audio, artifacts, home, claude_code, auth, pre-commit hook and installer, CI step, `tool/data/gated_dirs.txt` (12 directories gated, 13 left out with counts). Clayton `907a178` = focus_mode, notifications, queue, finished_tasks, quick_ask, shared (all but `prompt_bodies.dart`), docs, agentic, settings, decision_proxy, voice (comments only; the module does not compile).
- Decisions file `src/docs/decisions/README.md` grew to 53 records on the merged branch.

**RESUME HERE:** after my re-spin at 17:18 the auto-mode classifier denied the manager gate script (`batch.sh`), and kept denying it after Rick said yes at about 23:00 (gate row `a6d3bd18`). First thing: get a Bash permission rule for it, or have Rick run it with `!`, then gate and merge `2ccb028` and `907a178` in one batch. Then Rick's rulings: `a1bbc3ef` (two tests assert comment text), `32aedd1c` (`lib/features/voice`), Phase 5 Step 1 scope (`27a1d168`, 823 analyzer issues in 13 directories), claim judge (`9e0dd2dd`, `2847a900`), bug `bdd60a1b` (Claude Code submit endpoint). Post-game for this crew is owed.

---

## 2026.09.30 | Session `43b31a9d` (Tiffany 💍) — PR prep for the v0.2.2 branch

- Rick's broadcast `0375db54`: wip is being PR'd to `main`; next branch is `wip-v0.2.2-2026.09.30-tracking-lupin`.
- TODO.md gained a START HERE handoff table (open threads, stale remote branches, post-merge steps).
- Committed the deep-research response to the wake-socket problem statement, with frontmatter; removed an empty stray file `workers.`.
- PR #3 merged (`cf5be6f`); Rick pushed `wip-v0.2.2-2026.09.30-tracking-lupin`.

**Mobile docs track started** (María's plan 1 §10a, handed off 18:26 on Rick's go; row `b707f92f`, crew Clayton + John, reaped with mementos):
- **M1** Dart doc-comment standard: `src/docs/docstring-standard.md`, `src/docs/decisions/README.md`, CLAUDE.md pointer. Merged `0fe024e`.
- **M0 analyzer half**: `tool/doc_coverage.py` baseline (4,914 undocumented public members at `cf5be6f`), nested-options enforcement verified with controls, `tool/check_test_failures.py` known-failures gate (3 always, 1 sometimes), census of tests that read `lib/` text with 6 converted to strip comments. Merged `55266af`; gate NO_NEW_FAILURE.
- Findings posted to María (commons `handoff-v022-mobile-docs`): `dart format` not viable (536/539 files, house style); `JobStatus` test vs rule 6.

**RESUME HERE:** Rick's rulings relayed by María at 21:50 (M1 approved; drop the format gate; convert `lane_vocabulary_test`) are NOT recorded: auto mode refused a relayed ruling and his direct confirm timed out. Re-ask him first-hand, then record them in `src/docs/decisions/README.md` and staff the test conversion. Details on row `b707f92f`.

---

## 2026.09.29 | Session `3ecf2f22` (Tiffany 💍) — Wake backlog, dictation field, push pause, "off means off", transcript fixtures

**RESUME HERE:**

1. **Only live row: `768e852f`** (transcript console). C5.18 needs a recapture of `append_mixed_kinds` now that the server puts `name` on tool_result (Mr. Radio `687310b7`, live). The capture needs the admin test account: the script now reads `LUPIN_TEST_ADMIN_EMAIL` / `_PASSWORD` (Rick's `.bashrc`), and seats get them at the 09-30 fleet restart. C5.22 (thinking) stays pending-capture: no seat records thinking text.
2. **The ask-audio contract fixture drifts** whenever lupin touches the ask response, and the guard blocks worker syncs, so Rick ran it twice today. A permission rule for `test/fixtures/asr/ask_audio_ndjson_contract.json` would stop the recurrence.
3. Branches: only `main` + wip remain (Rick deleted 8 merged/stale ones). No worktrees.

**Shipped** (crew: Pocholo, Tiberius, Chloé, Cheech, Maya, Clayton; every commit reviewed and cherry-picked; suite 2728/2/0 at `bded008`, `--fcm` APK built there):
- **Wake fetch** asks the server for only the allowed priorities, oldest first: `95b7095` (`1a7678ff`). Also closes `33ee7329`.
- **Wake backlog, show each**: up to 5 items per wake, each with its own notification id (review caught a same-second id collision): `8aebb59` (`8e91d937`). One whole-handler 27 s deadline: `416450b` (`5365750f`).
- **DictationTextField**: all 15 mic-yes sites, census-guarded, plus a fix for a start completing on a dead widget: `c4e60ea` (`c67f9781`).
- **Pause push from server** (P0 `67ee93b0`): admin toggle on the Notifications screen, 30 min to 24 h or until resumed: `29579af`.
- **Off means off** (Rick's ruling): Focus speech honors Notifications off, Master mute, muted senders, and quiet hours: `bb12bd1` (`ea716d77`).
- **A push-registration throw at login no longer skips the permission prompt**: `ab4f895` (`dfea49e7`, from Maya's review `20df4428`).
- **Transcript fixtures**: `state_refused` captured (C5.21 green), `append_mixed_kinds` recaptured, the JWT-shape guard: `fed43e7`, `aab5824`; the capture script reads `LUPIN_TEST_ADMIN_*`: `e789f07`.
- Fixture syncs to lupin: `d596526`, `bded008`.

---

## 2026.09.28 | Session `1b9a6410` (Tiffany 💍) — FCM wake-ups live on the phone, tap-to-sender, notification controls, the append mic

**RESUME HERE:**

1. **Rick owes:** the dev test admin account (`f2f30810`, which unblocks `768e852f` slice 4) and the NDK 27 install (`sdkmanager "ndk;27.0.12077973" "platforms;android-36"`, for P3 `5cbd2e42`).
2. **Merged late:** Cheech's notification management view `370e491` (P0 `7cac3a17`, awaiting Rick's device check) and Maya's prompt-bubble mic `286e02c` (Focus half of `928c5808`). Next for Maya: the mic in the notification sheet (Rick: "both"). Tip `286e02c`, suite 2558/1/8, `--fcm` APK built from it.
3. **Unmerged:** `feat/transcript-dispatcher` (the 0fa608b rebase), `feat/transcript-mobile-s4` (`c310763`), and 281a10d6 (device_id / close 4004), which isn't staffed yet.

**Shipped** (crew: Maya, Pocholo, Chloé, Cheech; every merge independently reviewed; suite 2484/1/8 at `ea0d2f3`, the 8 being the known pending-capture reds):
- **FCM background wake proven on the emulator and the phone** (row `8ff78c69`, closed): live bugs fixed along the way: `ba07dc8` notification permission never requested, `f827e7a` fingerprint unlock never worked (FlutterFragmentActivity).
- **Tap a notification → that sender's conversation**, sender emoji and name in the title: `265947d` (Maya; `d9bc6f6c`, `1ae4c68c`; Rick confirmed on the phone).
- **Review F1–F9 + C1–C4** (Pocholo, reviewed by Chloé): `62a319d`, `e004517`: speech/network budgets, the token-rotation race, the wake switch, the v2 channel at default importance, APK build stamp.
- **Append mic in the Focus reply draft**: `ea0d2f3` (Maya; `570c2fce`; Rick confirmed).
- **pubspec.lock tracked**, dio switch made total, seat provisioning fixed: Chloé (`0705bcce`); stale AC-G2 fixture `f113473` (`6f9c0fe4`).
- CLAUDE.md: always build with `--fcm` (`5c62999`).

---

## 2026.09.27 | Session `0fb2674f` (Tiffany 💍) — Transcript phase 3 slices 1–3, the Surfaces drawer, and a one-command phone deploy

**RESUME HERE:**

1. **Rick's two P0s:** run `src/scripts/deploy-apk-to-device.sh` once from the laptop, which closes `651e3956`, and file a ticket from the phone with New Task, which closes `5e315760`. The check list is `tmp/2026.09.28-phone-check-list.md`.
2. **Stop-list `f27a61f4`** is re-looped for its undo defects; the fix plan is in `io/mementos/cheech.md`.
3. **Phase 3** waits on Mr. Radio's server: slice 4, and merging `0fa608b`.

**Shipped** (5-seat crew: Maya, Pocholo, Chloé, Cheech, Clayton; each merge reviewed and tested):
- **Transcript phase 3** (row `768e852f`): slice 1 `a086a0c` (PaneVisibilityMixin extraction), slice 2 `fad452e` (fleet-row watch button), slice 3 `9962f59` (router, route-scoped bloc, Live Console). The dispatcher `0fa608b` is held back until the server emits.
- **Surfaces drawer** `bb8c72e` (row `c59457f0`).
- **Phone deploy script** `d15210f` + `c6db075` (row `651e3956`): installs the server-built APK over the SMB mount to whatever adb sees, phone first, and refuses a stale APK.
- `686576b` CLAUDE.md dev commands; `610f8c9` `/coverage/` gitignored.
- **Rick confirmed on the device:** record button `3f2a7dab`, mic hold `a1c12c6e`, Files `0534b50d`.

**Suite: 2055 → 2299 passed / 1 skipped / 0 failed** at `bb8c72e` (8 pending-capture reds by design).

**Lesson:** twice, a fix commit was stacked on something that must not merge (the C9 hold-back, then row A). A one-line `git merge-base --is-ancestor` check before every merge caught both.

---

## 2026.09.26 | Session `90e34e30` (Tiffany 💍) — Skeleton Shift: five-accordion status report, the TaskRow call-site guard, and file_picker passing on the phone

**RESUME HERE:**

1. **Row `61ecfb22` (doc viewer) is ready to close, and only Rick can close it** because it is parked. He confirmed on the phone that `file_picker` 11.0.3 builds, installs, logs no errors, and uploads.
2. **Device walk-through**: item 10 is done. Rick's test broadcast `f670a706` reached this seat, the first real send from the app. Items 11-13 (the reply tally through the notification shade, backgrounding and navigation) and item 14 (landscape) are still owed.
3. **Rebuild the APK** to get New Task on the phone. It's merged and pushed, and never yet tapped on a device. The Project field defaults to `lupin`, as on the web.

**Shipped:**
- `1d61d2d` + `db9162c`, merged as `92a3fc0`, row `d5bbd786`: a source-scan test that fails when any `TaskRow(` call in `lib/` drops a constructor argument, unless a `// taskrow-omit: <param> <why>` comment explains it. It was mutation-tested on four breakages. María reviewed it; her two points (a `//` inside a string hid a call, and `super.x` parameters were not counted) are fixed.
- A done-versus-remaining report on the five accordions, sent to Rick as a notification card (broadcast `7938c019`).
- `a36ef40`, merged as `30efd26`, plus fix `e7f2bcc` merged as `ce3fe8a`, row `b31a9ed9`: **New Task**, the web's new-ticket card on the phone (M4, on Rick's keypress yes). It's ported from lupin `shared/task-create.js`: nine fields, the same defaults, validation and outcome text, and a POST to `/api/tasks`. A petition or no answer keeps the card open; a created ticket closes it and refreshes the board. Title and Details have mics. It was mutation-tested on 7 breakages. A test caught the Approval dropdown overflowing by 156 px at 360 dp. María reviewed the rules layer and the card; she found that a cancelled capture left the mics dead, which is now fixed with two tests that fail on `30efd26`.

**Rulings:** row `e1e2c545` (the two re-spin doors read different memento files) stays with Mr. Radio, because it is lupin tooling. Rick's test upload was deleted from `lupin/io` on his yes.

**Housekeeping:** the memento sweep trashed 6 stale records and kept 3.

**Suite: 1999 → 2035 passed / 1 skipped / 0 failed.**

**Lesson:** a review DM that is condensed in transit can drop a finding. María's first accept on `a36ef40` lost the stale-mic point, and it only surfaced when she resent it after the merge. When a reviewer says there are nits, ask for the list in full before merging.

---

## 2026.09.24 | Session `ecb8e6e3` (Tiffany 💍) — Task List M1/M3/M4, and doc-viewer parity with the web: Download, Folder, listing, Roots, Upload

**RESUME HERE:**

1. 🔴 **Rick's laptop APK build is the first real test of `file_picker` 11.0.3**, because this machine has no Android SDK. If it breaks: take it out of `pubspec.yaml` and set `platformDocFilePicker = null` in `lib/features/docs/presentation/doc_upload_sheet.dart`. Row `61ecfb22` is blocked on that build (chase 09-25 09:00 EDT).
2. **Row `651e3956` (P1)**: investigate reviving the Android SDK here. Rick is picking it up 09-25.
3. The device walkthrough from 09-23 is still owed (items 7-14 plus one real broadcast).

**Shipped** (21 files, +2100/−28):
- `84ebb4d` / merge `6ce802e`: Task List headline ("Live: N", split only while a park is active), paste-a-ticket-number lookup via `GET /api/tasks/<ref>` (finds held rows), and a disabled New task button. Row `323d0f9c`.
- `8bc9b9e` / merge `312aa40`: doc viewer ⬇ Download (original bytes through the share sheet), 📁 Folder, a real folder listing, and a folded 🗂 Roots panel. Row `61ecfb22`, agreed with Mr. Radio before building.
- `0528f11` / merge `104401b`: ⬆ Upload for admins. It sends refuse first; on a name clash, a sheet offers Replace, Rename or Cancel. It adds `file_picker`.

**Bugs found on the way**:
- The listing parser read `type`/`path` while the server sends `kind`/`rel_path`, so every entry was a pathless file. This was invisible because nothing rendered listings.
- PDF, audio and video were decoded as text.

**Coordination**: Mr. Radio's upload endpoint shipped as lupin `627ef22c8`. Only io and lupin accept uploads; the other mounts answer 403 until Rick makes them writable.

**suite 1936 → 1999 passed / 1 skipped / 0 failed** on the merged tree.

## 2026.09.23 | Session `693d5366` (Tiffany 💍) — Fleet pane parity closed, broadcast ack recovery built on the new server read, two rulings in hand

**RESUME HERE:**

1. 🔴 **REBUILD THE APK AND CHECK ON DEVICE**: the P0 DM editor, the B1 spinner (walk-through item 8), items 7-14 of `src/rnd/2026.09.22-emulator-walkthrough-five-accordions.md`, and now **one real broadcast** that exercises the ack read-back after backgrounding the app. ⚠️ A broadcast reaches every live seat, so warn the fleet first.
2. **d5bbd786 TaskRow call-site guard**: Rick **approved** it (22:15), but it's still `not_approved` because only he can admit it. Once admitted, staff a worker.
3. **c51e92da** phone probe stays parked until about 10-19. Don't raise it.

**Shipped**: 73ce4cb inbox hidden + Task List indent · d80419b logout pops routes, Lupin Focus first on the grid · 7e005e8+125f37f Broadcast @mention chips · da54a06 B1 Fleet Status spinner · 67500ca P0 DM editor (composer capped at 60% above the keyboard) · aac32aa Broadcast history disabled state · crew merges a9d0d0d, e397c9c, 0952925, dd8de55, 3c1ebe7, ae75043, 39c8a14 · 5ad3fc8 post-game · **19b8c6e broadcast ack recovery** (Sam, row 973e4b6b): `drainMissedAcks()` now reads `GET /api/notifications/broadcast-acks/{id}` (lupin 1c7da903) on resume/reconnect. It merges saved acks per seat, ignores other broadcasts, lets a seat that moved during the read keep its live ack (a race caught in review, fixed in 0cdfe1a), and leaves a failed read "interrupted". Expired vs partial runs on a 5-minute window from the **send**, which differs from the web on purpose.

**Rulings**: 19190a5b Task List **hides** illegal verbs (Rick, closed). Server `limit` is `Query(500)` with no maximum, so going over 500 is not an error (Sam, verified at `notifications.py:2444`).

**suite 1904 → 1936 passed / 1 skipped / 0 failed** on the merge result. One self-respin (wake proof written). The Last Call bell (row 3d741e8b) never fired because `last_call.py` isn't executable (María's bug 8a838de5), so the close was run by hand.

## 2026.09.23 | Memento sweep (María 🌸, row `5b29a807`) — 50 mementos moved to the trash (3 kept for Tiffany); per Rick's ruling, only the last two days summarized

- **09-22**: `await bloc.close()` inside `testWidgets` never returns for a bloc with an `on<Event>` handler. Four of five fleet panes were unreachable, referenced only by their own files and tests. Untrack `local.properties` and gitignore `google-services.json` (Rick).

## 2026.09.22 | Session `f19a8996` (Tiffany 💍) — Phase 5 shipped, five accordions wired, then Rick walked them on the emulator and found ten things

**RESUME HERE — FIRST THING IN THE MORNING, IN THIS ORDER:**

1. 🔴 **REBUILD AND FINISH THE WALK-THROUGH.** Nothing else is blocked. `src/scripts/build-and-deploy-lupin-mobile.sh` (or `--push-only` if the APK is current), then **items 8-14** of `src/rnd/2026.09.22-emulator-walkthrough-five-accordions.md`. Item 7 is fixed and pushed but **not in Rick's APK**, so it has to be re-checked too. Items 10-13 are the four no test can reach: the first real broadcast ever fired from this app, the `inactive` guard measured in **both** directions, and the ack tally surviving navigation.
   ⚠️ **A broadcast send hits every live seat.** Tell the fleet first or send something that reads as a test.
2. **B1 Fleet Status spinner — highest-priority code work.** Order is **B1b first** (the debug line), on María's call: it is the only item that can say whether Rick's spinner is the defect we found or another one still unidentified. Then both cancel fixes — data-in-hand emits the composite, no-data keeps returning — and **two** tests so the second cannot regress into the first. ⚠️ **My causal claim is withdrawn**: a lifecycle cancel self-heals on resume, so the path I found probably does **not** explain what he saw.
3. **R1+N2 Holding Area, one piece of work.** Ruled **B**: group by persona, **sessions unlabelled** (no hash, no count, no subtitle), **collapsed by default**. Inside B: approve-all now spans all of a persona's sessions, so **the button and confirm must report that wider count**.
4. **Cheap and independent, no rulings needed**: **M1** the conditional headline (`Live: L` alone when parked is 0; the three-part form only when parked > 0) · **M4** the new-task stub · **B3** left padding — **measure at 360 dp, do not eyeball at 800**; the title only has ~90 dp there.
5. **M2** the `⋯` disclosure (state in `aria-expanded` **and** `hidden`, both required) and **M3** the paste-a-hash lookup box — which is **not** a filter: it must hit `/api/tasks/<ref>`, never `/api/tasks?id_prefix=`, because the query form hid 22 of 23 held rows.
6. **N1 Broadcast recipient picker** — the biggest item, and **still gated on one question for Rick**: does the endpoint accept a recipient list at all? Ask before building, or the picker's selection gets discarded.

**Two implementers were offered and not yet staffed.** The split: seat 1 takes B1 then N1; seat 2 takes M1/M4/B3 then R1+N2.

**Still Rick's, not started**: the 244 pre-existing analyzer errors in `lib/core/**` scaffolding (none new, none mine — and they mean the analyzer cannot serve as a gate). `c51e92da` phone probe stays held to 2026-10-19; **do not re-raise it.**

**Where the evening ended**: commit `75f1291`, **16 commits pushed**, backup verified off the mirror, board at **0 live rows**, tree clean.

---

**suite 1586 → 1673 passed / 1 skipped / 0 failed.** All five fleet accordions are built, merged and **reachable**. Rick walked them on the emulator and filed ten findings; one is fixed, one he ruled on, and the rest are scoped in a peer-reviewed work plan with **nothing blocked on him but a rebuild**. Two self-respins this session (`fc9e316a`, then `a9df00ea`).

**Shipped**
- **Phase 5 Broadcast** — data layer, bloc, pane, 59 tests, mutation-proved 14/14; bloc at **app root** on Rick's ruling so the ack tally survives navigation.
- **The orphan-pane fix** (`43342f0`) — four of five accordions had no door: no card, no route, no provider. Four phases of green work nobody could open.
- **Finished Tasks first load** — the pane was a spinner forever because *nothing ever dispatched the load*. His log carried `/api/tasks` and **no `/api/tasks/events` at all**; the absence was the evidence.
- **Trust Dashboard hidden** on his order — both doors, the card and the app-bar shield, behind one flag rather than a deletion.
- **`--push-only`** on the build-and-deploy script; **`io/`** into `.gitignore`; a false docstring in `pane_polling_mixin` corrected.
- **Three new test files, 10 cases, every one mutation-proved.**

**The three defects that were all the same defect**
`PaneHostScreen` had zero tests; the ack **dispatch** seam had none; Finished Tasks' first load had none. In each case the tests either side proved their own half — and for Finished Tasks the harness literally sent the event production never sent. **Unit tests either side of a seam cannot fail on the seam.**

**Rick's rulings**
- Skeleton crew is the **standing** weekday mode before 17:00, and in it a manager implements its own rows — I had recorded it as a one-off waiver and was corrected.
- Broadcast bloc at **app root**; **wire the orphan panes**; Trust Dashboard **back-burnered then hidden**; `io/` ignored; **Holding Area grouping by persona with sessions unlabelled and collapsed** — overruling my recommendation, and he was right that mirroring the clients he uses is the requirement.
- **"Leave it refreshing"** on the polling question.

**What I got wrong, because it is the useful part**
Twice I attached a true observation to the wrong mechanism — the parity-guard hang (blamed the poll timer; it was `bloc.close()`), and the Fleet Status spinner (claimed "nothing retries"; María proved a lifecycle cancel self-heals, and I withdrew the diagnosis). My first Trust Dashboard guard **could not fail** — it scrolled past the card, which disposes it. I read two killed background runs' `exit 0` as a pass. And I spent four of Rick's interruptions asking questions whose answers were written in the clients he had already told me to read: *"a question that source can answer is not a question."*

**María reviewed the plan and changed it three times** — smaller fix, withdrawn causal claim, and a finding of her own (`de509b51`) that made my own document weaker. Mr. Radio's `1c7da903` shape accepted; I withdrew a reconcile proposal of mine as unsound after he showed two counts from the same source prove nothing.

**Docs**: check-in briefing · emulator walk-through checklist · walk-through findings work plan, all in `src/rnd/`, all linked in the README.

---

## 2026.09.20 | Session `cc9c1f1a` (Tiffany 💍) — Manager on duty: a three-seat cascade review, then five fleet-pane phases built, reviewed and merged in one evening

**RESUME HERE**: **nine merges on `wip-v0.1.6-2026.04.16-tracking-lupin-work`, union verified green, PUSHED AND BACKED UP at Rick's 22:55 ritual order.** Rick ruled everything outstanding tonight: admit both held rows (done), batch won't-fix keeps NO confirm matching web (closed), and the phone round-trip probe `c51e92da` is **PARKED to 2026-10-19** — he has no cell service and no public-IP server for at least a month, and told the fleet to stop asking. **Do not re-raise it.** Still owed by him: untracking `android/local.properties`. P0 `4b16174d` remains `blocked` on `user:rick` with a chase at 09:00Z; Rick's own P0 `72e01fb3` (four legacy accordions) was CLOSED on receipts this session.

**CLOSED AFTER THE POST-GAME WAS WRITTEN** (this session continued past `e7afbbb`):

| row | outcome |
|---|---|
| `67c7a2e1` roster addressability guard | **merged `488f189`**, 71/71 focus_mode tests green on the merge result |
| `72e01fb3` Rick's four legacy accordions | **closed on receipts** — verified `lib/features/` carries `fleet_status`, `finished_tasks`, `task_list`, `holding_area`, not taken from a report |
| `c597c4fc` cross-pane cell-key parity | minted, admitted, **scope and mutation proof both corrected by Rachel before she started** |
| `384591dd` Phase 5 Broadcast | **blocked on a server defect**, not on Rick — see below |
| `c51e92da` phone round-trip probe | **parked to 2026-10-19 on Rick's direct order** |
| `e1e2c545` two re-spin doors read different memento slots | filed to Mr. Radio (Chloé's find) |

**THREE MANAGER ERRORS CAUGHT BY WORKERS BEFORE ANY CODE WAS WRITTEN**, all mine, all recorded on their rows rather than quietly fixed:
1. I specified a guard that had already shipped with Phase 2 (Rachel).
2. I prescribed a mutation proof that **could not fail** — both panes render the same shared widget, so mutating a cell key changes both identically and the comparison stays green (Rachel). Her fix: a wrapper at one pane's call site so exactly one side diverges.
3. I asked Rick to schedule a device sitting whose every option assumed the work was possible. It never was — he has told this fleet repeatedly that he has no cell service and no public IP. **A well-formed answer to a badly-framed question reads exactly like a ruling.** The wrong amendment is left on the row with the correction underneath.

**THE FINDING THAT STOPPED PHASE 5**, and it surfaced only because Chloé was held: `commons_broadcast_ack` appears never to write a notification row. Persistence lives in the `notify_user` route behind a `persist` flag; the ack watcher never goes through that route. If it holds, the DB-backed undelivered drain can never contain acks, so the pane renders **zero** acks after every resume — not a truncated count. Phase 5's entire acceptance clause would have been built, tested, mutation-proven and merged **green** while protecting something unreachable. Filed to Mr. Radio **labelled traced, not measured** — and Chloé caught a defect in her own probe first (reading an error body as an empty population), which is why the trace is trustworthy.

**Durable fact saved to project memory**: no cell service, no public IP, not before ~2026-10-20. The row was never the problem; the repeated asking was.

**THE MERGE CHAIN**, every one reviewed against the tree rather than the worker's report:

| sha | what |
|---|---|
| `6781674` | seat-worktree provisioning scripts (Sam, reviewed by Rachel) |
| `a9a7f49` | Phase 2 Finished Tasks (Rachel) |
| `3265c6b` | Phase 0 shared plumbing + Phase 3 Task List (Sam) |
| `d9b15a3` | Phase 1 Fleet Status (Chloé) |
| `06884c9` | Phase 4 Holding Area + guard fix (Rachel) |
| `20c0c17` | replay-ask verification (Sam) |
| `2c8e131` | measurement integrity (Sam) |
| `05fbfd8` | analyzer exclusions narrowed to what was authorised (Sam) |

**Verified**: 1578 passed / 1 skipped in the main checkout, that skip genuinely environmental. Analyze **978 issues — identical to the pre-phase baseline `3f807f0`**, so five phase merges introduced zero new issues and zero errors in any new pane. `test_keys.dart` clean by resolve check: 219 keys, 216 refs, no dangling, no duplicates.

1. **The crew corrected me five times and was right every time.** Rachel: my item text said the default filter pills were done+dropped; the source says `FINISHED_DEFAULT_SHOWN = ["done"]`. Sam: my sort wording predated Rick's own 2026-09-09 ruling, which names **both clients** — priority before status, and terminal rows **filtered**, not sorted to the bottom. Sam again: I told him to move verb logic into a directory where his own implementation already lived. Chloé: I routed a fleet-cap write through a task repository that cannot even produce the 202 condition I was guarding — `awaiting_human_approval` has **zero hits** in the arbiter app. Sam a third time: a count overturned my exclusion ruling. **Each was caught before a line was written**, because each seat read the source before building to the spec.
2. **Every ruling landed as an amendment on the row**, so the correct build cannot later be "fixed" back to match my wrong sentence — the same failure shape Rachel's negative assertion defends against.
3. **Five defects Chloé found in her own code, all by test, none findable by reading**: `isOffline` inverted in both directions (the liveness verdict is a **free-form string**, not an enum — live seats reported "LIVE", "quiet 3m", "stale 21m"); a 360 dp overflow; cancellation read as "arbiter down"; a failed cap read blanking the table; and **a leaked poll timer**, which ships as a battery bug nobody can attribute.
4. **Her arm C is the night's best single measurement.** Breaking the dial's wiring **killed 4 tests while 22 stayed green** — every pane and bloc test among them. Three files *looked* like they covered the dial; each proved one half while handing in the other. She watched the ceiling too: a near-total kill would have been a syntax error wearing a finding's clothes.
5. **My own miss, recorded**: the Phase 2 merge landed a **red** test I did not catch — a guard scanning source for the substring `"TaskRow("`, which also matches `"FinishedTaskRow("`, the pane's own row. It accused the pane of exactly what it was built not to do and sat red for half an hour until Rachel picked up her branch. **I reviewed the guard I was shown and never looked for one I had not been told about.** Rachel's reframe is better than my self-reproach and names an installable control: *the thing that would have caught it is running the suite on the merge result, not on the branch.*
6. **Sam hit both signs of one defect family in one night.** A substring guard and an authored fixture manufactured **false alarm** — the fixture produced a false defect report that reached me and got a row amended twice. A worktree measuring the wrong specimen manufactured **false comfort**: a bare `flutter analyze` walked the symlinked 2.3 GB SDK for 7801 phantom errors, and two wire-contract tests **silently skipped** in every worktree because the cosa probe was CWD-relative, so a seat saw green with less coverage than the main tree. His line: **a worktree that reports different results from the main tree is a measuring instrument that changes the thing it measures.**
7. **Asking for a measurement beat both positions.** I ruled Sam's unauthorised generated-file exclusions should go; he defended them. The count said **they match zero files** — this repo has no `.g.dart` or `.freezed.dart`. His reason is better than mine was: **an exclusion that hides nothing is not free.** What remains is labelled with its measured cost, including `build/**` kept and honestly marked as *a claim about the future rather than a measured saving*.
8. **Gates I refused to game**: the fleet ticket gate offers a P0 exemption and the create gate refuses live status below P0. I declined both rather than relabel honest P1/P2 rows, routing content to `task_amend` and the committed doc instead. Minting reached 5 of 10; items 6–7 are specified in full on P0 `4b16174d`, items 8–11 routed to Mr. Radio as a **filing** decision after I corrected my own implication that rows were being transferred.

**Crew standards earned tonight**, now carried in every memento: tests at **360×800**, never the 800×600 default · fixtures **captured from the real producer**, never authored · **mutation-prove** any test written against a known defect · drive a real tap through the real widget tree and assert the request that went out · when you cut a delta, **look for a second count someone else produced independently**.

---

## 2026.09.19 | Session `cc9c1f1a` (Tiffany 💍) — Board cleared: three rows closed on receipts, the P0 split before it could bury its server half, and a live token found in a paste

**RESUME HERE**: **no code was written this session** — it was a board-driving session, and the working tree carries only one new doc. Three rows closed with receipts, four filed. Two rows wait on Rick's admit (`a7de7d69` the token leak, `67c7a2e1` the sentinel guard); an `ask_multiple_choice` for both was live at the time of writing, defaulting to "not tonight" so a timeout cannot authorize work.

1. **`c3fc62bf` closed on Rick's own device evidence** (P1, commit `a2f1d75`). He ran the emulator build and pasted the tail: `POST http://10.0.2.2:7999/api/v2/transcribe` → **200**, `{"transcription":"What's the sum of 2 plus 2?","trace":{"stt_ms":313.1,"upload_bytes":19220}}`. Three facts beyond the path: 19,220 bytes of OGG/Opus confirms the `5524acd` encode is live **on device**; STT took 313 ms; the pre-v2 wav door appears nowhere in the tail. Downstream `/api/v2/ask` → 200 and `/api/notify/response` recorded his "yes", so the whole spoken-ask chain works on a device, not just the transcribe leg. Script written for him first: `src/rnd/2026.09.19-emulator-transcribe-check-script.md`.
2. **`b00e076c` closed** (P1, `a8c30b3`) — Rick admitted and ruled close. **Verified at HEAD rather than trusted from the commit**: 9/9 green across the two dedicated files.
3. **P0 `cea58ee0` closed — but split first, which is the point.** The server half had been **amended onto that same row as part (2)**, so closing it as ruled would have silently buried the server fix. Split out verbatim as lupin row `2184bebb` (P1, Mr. Radio accountable) carrying the docker-exec root cause, then closed the phone half on `11f9f5e` + 10/10 green — including the test that reproduces Rick's literal three-seat report.
4. **The receipt discipline refused me twice, correctly.** `operator_attestation` for Rick's paste → **403**: his click is his to mint, not mine to assert for him. A full sha I wrote from memory → **422**, object not found on any branch; I had extended a short sha instead of running `git rev-parse`. Both fixed by citing the commit and quoting his tail in the reason.
5. **A live bearer token arrived in a paste** — Rick's logcat tail carried his full JWT twice, with `sub` and email inside, a 30-minute token. That is `a7de7d69` (filed earlier the same hour) demonstrating itself, so I recommended re-rating it P1. Root cause read in code, not guessed: Dio's `LogInterceptor` at `http_service.dart:55` defaults `requestHeader: true` and the file has **no `kDebugMode` guard**, so a release APK logs it too; `AuthInterceptor` is registered at `service_locator.dart:247` *before* `HttpService` at `:261`, so the header is populated by the time the logger reads it.
6. **Mr. Radio ruled the server half and was right twice about my own work.** He chose option B (the hook writes its sender id into the bridge) and **banned option A even as a silent fallback** — "a wrong identity that looks like a right one" — which is stricter than how I filed it. He then caught me claiming 10/10 green *after* restoring a mutant **without re-running it** (re-ran: green, measured), and predicted a gap I had not tested: `""` is skipped but **`"none"` is not**, because the guard tests absence rather than addressability. Measured 11 passed / 1 failed, filed as `67c7a2e1` with his endorsed one-line fix.
7. **Two condensed DMs were not acted on.** Both arrived garbled and I asked one disambiguating question instead of inferring a wire contract — the same shape that cost a wrongly-dropped row on 09-04. Answer came back "null, no sentinel", now durable on `2184bebb`.
8. **Filed**: `a7de7d69` (P2→recommended P1, token leak) · `2184bebb` (P1, lupin, server half) · `9511aa08` (P3, verify a replayed answer reaches the phone) · `67c7a2e1` (P3, sentinel guard). **`9511aa08` is filed as a *verify*, not a defect** — I had flagged `spoke:false` as a possible `0e7c9214` recurrence, then read it properly: `status` is `waiting`, so it is the enqueue response and those nulls are correct. Corrected to Rick in the same breath.

**Files**: `src/rnd/2026.09.19-emulator-transcribe-check-script.md` (new) · `history.md` · `TODO.md` · `.claude-session.md` · **no `lib/` or `test/` changes** — the mutant at `focus_chat_bloc.dart:444` and both sentinel probes were reverted and the tree verified clean with `git diff --quiet`.

---

