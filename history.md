# LUPIN MOBILE - SESSION HISTORY

## 📚 Archived Sessions

Older session entries have been archived for token-limit hygiene. See:
- **[2026-09-19-to-10-05-history.md](history/2026-09-19-to-10-05-history.md)** — Surfaces drawer, FCM wake-ups, fleet pane parity, merge gate in the repo, logger (archived 2026-11-01)
- **[2026-09-01-to-18-history.md](history/2026-09-01-to-18-history.md)** — spoken-ask door, Quick Ask fixes, split screen, 0% means silence, the backup SDK finding (archived 2026-10-02)
- **[2026-05-21-to-08-31-history.md](history/2026-05-21-to-08-31-history.md)** — notif-client sync, focus-mode milestone, v2 cutover waves, Quick Ask push-to-talk, the backup incident (archived 2026-09-16)
- **[2026-05-06-to-11-history.md](history/2026-05-06-to-11-history.md)** — voice-persona milestone Phases 0–5 + CC-dispatch retirement sync + yes/no/neither tri-state (9 entries, May 6–11, 2026; archived 2026-08-21)
- **[2026-04-17-to-24-history.md](history/2026-04-17-to-24-history.md)** — WS hookup → TTS overlap fix (5 sessions, Apr 17-24, 2026; archived 2026-05-11)
- **[2026-04-15-to-16-history.md](history/2026-04-15-to-16-history.md)** — Tier 1-4 buildout (5 sessions, Apr 15-16, 2026)
- **[2025-07-06-to-08-17-history.md](history/2025-07-06-to-08-17-history.md)** — Initial era (7 sessions, Jul 2025 – Aug 2025; project then dormant for 8 months)

Most recent entries (2026-10-09 onward) are retained below.

---

## 2026.11.02 | Session `cfdbef0b` (Tiffany) — "Other" on choice asks, hands-free Quick Ask, no banner while the app is open

The work came from Rick by voice and from rows on my board. APK builds 1 to 4 were made; the last is `bd27502`, and the drawer reads "2026.11.02 build 4". Each change had an independent review, and every defect it found was fixed with a test that fails without the fix.

- **"Other" on every multiple-choice ask** (row `50ce6d46`): single- and multi-select, in the notification sheet and the focus pane. A typed answer is sent as the web client sends it. The review found that a cursor move re-ticked "Other" over a later pick; fixed. Merged `8048669`.
- **📋 view links** (row `3310b925`): the parser already keyed on the address, so tests now cover both 📋 and 📄. Merged `8048669`.
- **Quick Ask multiple choice** (row `6fd3ec4e`): Quick Ask shows the options and "Other", and answers `{"answers": ...}`. The review found that a replacing prompt reused the old one's state; the fix keys the prompt by id. Merged `63eadc5`.
- **Hands-free Quick Ask, screen on** (row `c643b1b0`, plan `src/rnd/2026.11.02-quick-ask-hands-free-earbud-taps-plan.md`): an earbud tap starts and stops recording, and a double tap sends, each with a tone.
  - The app now owns its media session: `LupinMediaHandler` on `audio_service`, replacing `just_audio_background`, which kept the press handler private.
  - The review found four defects, all fixed in `138f095`. The claim outlived the screen, and a podcast started under it couldn't be paused. The first tap could go to another app, and player errors were dropped.
  - Merged `174d54b`; the row waits on Rick's earbud check. The locked-screen step is row `3a8005c1`.
- **No system banner while the app is open** (row `66f6cf2f`, Rick's ruling): with the app in front, a notification dings and vibrates in-app. Nothing is posted to Android. The review found that two quick dings leaked audio focus and kept a podcast paused. It also found that vibrate mode got no signal. Both are fixed. Merged `bd27502`.
- **Filed for tonight**: the intermittent tap to start and stop (row `0f29b56e`), and ASR returning no transcript (row `bcc9cba3`).
- **Lessons**:
  - A TextEditingController notifies on cursor and composing changes too, so a listener must compare the text.
  - audioplayers takes audio focus on every `play()` and releases only the latest request, so stop before each play.
  - Renaming a test is a missing id to AC-G2; rename it in `test/fixtures/ac_g2_passing_baseline.json` in the same branch.
- **Memento sweep**: Sam's two 11-01 mementos (tester, row `a25f51b3`) were summarized and trashed.
  - `ws_stale_channel_test.dart` failed once in a full run and passed alone, so it may be flaky.
  - `Markdown( selectable: true )` draws no RichText; read the EditableText instead.

## 2026.11.01 | Session `6b2f0ab0` (Tiffany) — Drive podcasts on the phone, one-click approve links, download for offline

The work came from Mr. Radio's handoff and from Rick by voice. APK builds 1 to 3 were made; the last is `fefb4f4`, and the drawer reads "2026.11.01 build 3".

- **Drive podcasts list** (row `dc0dafdc`): the Podcasts screen lists every podcast in Google Drive under the phone's own. It reads them through the server endpoints `/api/podcast-drive/list` and `/stream` (lupin `269d72151`), so the phone needs no Google sign-in. A 401 goes through the token refresh. Mr. Radio confirmed that the desktop and phone podcast paths upload to the same Drive folder. Merged `478ac9b`; real-reply test `dddc6ad`.
- **Approve and view links in cards** (row `a25f51b3`): `approve ☐` approves in place and `📄` shows the row, matching both web clients. Built by a crew (Rio implemented, Krishna reviewed with two re-loops, Sam wrote 20 tests); all three were reaped with mementos. Merged `ea76434` and `b45b3aa`. Rick confirmed on the phone that the link renders.
- **Download for offline** (row `6430afac`, Rick's ask): a download button on each Drive row; on mobile data it asks first. An independent review found a double-sheet race and an unhandled connection-check error; both were fixed. Merged `fefb4f4`.
- **History archived**: 2026-09-19 to 10-05 moved to `history/2026-09-19-to-10-05-history.md`.
- **Lessons**:
  - A spinner behind an open sheet keeps `pumpAndSettle` from ever settling, so the tap guard and the spinner are now separate.
  - `spawn_sessions` already makes each seat's worktree, so a brief must not tell the implementer to add one.

## 2026.10.31 | Session `e3be888f` (Tiffany) — Explainer to podcast to playback on the phone

Rick's broadcast `ed04ca86`: row `3469e9db` (P0), coordinated with Mr. Radio. The crew was Krishna, Chloé and Tiberius, all Sonnet 5.5, all reaped with mementos. APK builds 1 to 7 were made; the last is `243aea6`.

- **Plan** `src/rnd/2026.10.31-explainer-to-podcast-phone-loop-plan.md` (`c9906e4`). Tiberius reviewed it. The afternoon explainer was added in `a12ec46`, and the earbud research in `39907c0`.
- **Player** (row `049d914a`): an app-wide player, lock-screen and earbud play/pause, and a pause while the app speaks. Merged `152146a` and `f8f5e27`.
- **Button and Play** (row `0c23edab`): a Podcast button in the doc viewer, using the server's from-viewer route, and Play on the done card. Merged `65ef6d8`.
- **Offline** (row `24a39e97`): a persistent cache, Wi-Fi prefetch, and an ask before mobile data. Merged `7aaeeaa`.
- **Rick passed the loop on the phone**, and row `3469e9db` closed.
- **Rewind** (row `807a4ed0`): back 15 seconds, with a long press to go to the start. Merged `dffeb1d`.
- **Podcasts list** (row `f13143d5`, `fe84492`), and its Surfaces entry (row `e12f5649`, `5fe702c`).
- **Bar on first Play** (row `a5c251e5`): just_audio's `play()` returns only when playback ends, so the player is no longer awaited. Merged `0cd7649` and `243aea6`.
- **Earbud research** (row `3d1bb844`): a double tap sends "next track", which does nothing on a one-item queue. A single tap works; the earlier failure was the laptop-paired buds.
- **Lessons**:
  - I merged one branch before its gate finished, and it failed; every merge after that was gated first.
  - Chloé's home card landed on the hidden Home grid. Surfaces is a separate list.

## 2026.10.20 | Session `31cd100e` (Tiffany) — Plans 1 and 2 on mobile, from zero to done

Rick's broadcast `be6e2010`: finish both plans and work with María on code reuse. Crew: Tiberius, Pocholo, Maya, Rachel and Rio, all Sonnet 5.5, all reaped with mementos.

- **Plan** `src/rnd/2026.10.20-plans-1-2-mobile-parity-plan.md` (`2cb4e0b`, status `caa2291`). Rick ruled exact lookups now, vectors later.
- **Dart index** (row `dad36ae1`): lupin's indexer, 2609 entries, two hand checks of 30 modules each.
- **Lookups** (row `55013536`): María's lupin `fc0517fc6` lets the reuse tools answer for mobile. I reviewed it, and a live `check_exists` returned Dart classes.
- **Wiki** (row `f45cf2cb`): 39 pages plus 28 sub-pages, merged `d2d5f03`, `a2ce0a5`, `5464459`, `dee7e11`. The gate passed. 16 of 2609 names have no page.
- **Recall baseline**: 37 of 40 known twins found, 0 of 200 random negatives. The set is in `projects-data/lupin-mobile/reuse-review/negatives-2026.10.20/`. The misses are lupin row `74d0db47`.
- **Reviewer skill** `.claude/skills/reuse-reviewer/SKILL.md`, merged `d925b94`.
- **Queue bug** `45140e2e`: deleting a job now re-fetches the queue, with a test that fails first. Merged `d19bfd8`; APK 2026.10.20 build 1.
- **Handed off**: the librarian tick to Cheech (row `874dff1a`). The cache duplicate `f3d4fc00` is parked until 2026-10-28.
- **Lesson**: check a claimed ruling against the card. Maya's row said P2, but the card said "a finding for later".

## 2026.10.14 | Session `8e50c76c` (Tiffany) — Plan 1 mobile done, then lupin rows from Cheech's list

Crew: Chloé, Pocholo, Tiberius, Rio, John and Extra 1, all Sonnet 5.5, all reaped with mementos. The last two seats went to Mr. Radio, by Rick's ruling.

- **Plan 1 mobile, 100%**: decisions record ruled A, scope class first (`2f422bb`), then the page (`1fd23e8`). María's wrappers merged `90fa022`.
- **Phone fixes**: speech requests carry an utterance id, merged `32f75fd` (row `b6f7f302`). The flaky gate test waits on its condition, merged `9e78016`.
- **Skeleton crew switch** (row `5da989df`): it sits beside the cap dial, and the poke switch is hidden. Merged `40c9d72` and `937d880`; APK 2026.10.14 build 2.
- **Lupin rows from Cheech's list**: Rick split the list among the managers. Landed on the lupin working branch:
  - `4007b4466`: tic rule skips code spans (`07d6d4c7`), dead vote buttons removed (`2650df28`), Retry-now test (`5a8bd0c6`).
  - `ef7256e58`: verifier fixes (`df767922`), real card votes (`ed6db05a`), markdownlint test fix.
- **markdownlint 0.18.1**: installed in lupin's main node_modules (row `47f8c955`). The test container sees it through a bind mount (row `2ac183c2`).
- **Gates**: mobile full gate PASS-WITH-WARNING at `937d880`. Lupin landings ran the unit tier and the bundle test.
- **Not pushed**: every mobile commit since `0ff5b47`.

## 2026.10.13 | Session `5f30c269` (Tiffany) — markdown blocks at commit, wrappers clean, R&D ledger

Crew: Chloé (author), Maya (author) and Tiberius (reviewer), all Sonnet 5.5, all reaped with mementos. Two Claude Code helper jobs ran first; Rick had them stopped and replaced by Lupin workers.

- **Plan 1, mobile steps** (lupin row `ec1854b7`, closed at `8dd037b`). `CLAUDE.md` and `README.md` are at 0 lint findings. An R&D ledger of 115 rows and the R&D read rule, with its test, are in.
- **Markdown gate blocks** (row `696b6744`, open): Rick ruled R1 to R5 on the plan. Each page has a class in `tool/data/markdown_scope.txt`, and the hook and the merge gate refuse by class. Merged `982172b`.
- **Reviews** (rows `ecd452ac`, `9d66ab24`, `105a343f`): Tiberius found nine holes in the gate by running them. All were fixed and re-run before the merge.
- **Command wrappers** (rows `afad632f`, `37fec485`, closed): reinstalled twice from María's cleaned sources, 992 findings to 0, then held at zero. Merged `2f60db8`, `7885efd`, `51333e5`.
- **Open, with Rick**: the decisions record holds 81 findings, and its header forbids editing old lines. Plan section 8 gives the two choices.
- **Plan**: `src/rnd/2026.10.13-plan-1-mobile-markdown-cleanup-and-blocking-plan.md`.
- **Tool tests**: 249 passed at `51333e5`. There is no full merge gate verdict yet; it cannot pass until the decisions record is ruled.
- **Mementos**: Chloé, Maya and Tiberius each left one in `io/mementos/`; the sweep was not run tonight.

## 2026.10.10 | Sessions `de4ce9d3` then `271cba01` (Tiffany 💍) — silent phone found, build line, doc rewrite closed

Crew: Tiberius (author), Chloé (reviewer), Maya (author) and Rio (reviewer), both released in the afternoon. Session `de4ce9d3` died at about 19:20 EDT; `271cba01` picked up from row `79d49618` and Rick's pasted notes. Everything before 19:21 EDT below is from commits, gate logs and `TODO.md`, not from memory.

- **Silent phone** (bug `e0f0faf0`, closed): Master mute was on. The outcome line added in `3bc7670` named it when Rick read the phone at 18:00 EDT; he heard speech at about 18:47 EDT. Also merged: a speech watchdog and four review rounds (`259531c`, `6a9ca61`, `4c26045`), and a banner naming each active silencer with its repaint and rebuild tests (`0dd0655`, `17750b7`, `a672945`, `37a6b20`).
- **Phone socket and logout**: an old listener can no longer tear down the live socket, the session id is taken once the socket is up, logout sends the refresh token and unregisters the push token first. Merged `98a497e`. The late-completion gap is a server change, lupin row `87d19d27`.
- **Build line**: the drawer shows branch, date and a per-day build number (`c07c65d`, `16fc44d`). Latest APK is 2026.10.10 build 8 at `44f723c`, push wake-ups on.
- **Command wrappers** refreshed and backup paths corrected (row `08c4e586`, merge `cbe1854`).
- **Doc-comment rewrite closed** (row `79d49618`): Rick turned all checking off and asked for the job finished. Six commits from Tiberius, each passed by Chloé, merged `d1c1e6e`: six dropped reasons restored, the last 3 public members documented, 92 linter findings in 22 `lib/` files cleared, rule 6 cites a commit (`R-DOC-reason-by-commit`). `lib/` reads 0 linter findings and 0 undocumented public members. The blind taste test before that: new comments preferred 39 to 6.
- **Merge gate runs the doc linter** (row `27548910`, admitted by Rick): no gate step ran it before, which is how the 92 findings went unseen. Merged `45819e4` (`836af40`, `d31726f`).
- **Dropped rows checked** (row `e0d17ef4`, closed): nothing new owed from `a246634e` or `9d7b62e9`; why they were dropped is unverified.
- **Merge gates**: PASS `5663197..44f723c`; PASS-WITH-WARNING `b941543..45819e4` (the range changes the gate's own files; the question whether Chloé's review counts as the human read is with Rick). Earlier in the day: ten PASS and one FAIL (`259531c..6a9ca61`, passed 15 minutes later on a wider range), logs in `io/2026.10.10/tiffany/`.
- **Post-game**: `src/docs/post-games/v0.2.2/2026.10.10-silent-phone-and-doc-closeout-crew-post-game.md`, rulings R19 to R25 (manager, reversible).
- **Held, waiting for Rick**: flaky foreground-gate test (`ff9cc9d3`), R&D ledger for mobile (`e40642c3`).

## 2026.10.09 | Session `de4ce9d3` (Tiffany 💍) — five held rows cleared, two connectivity rulings, blind Dart count

Crew (all Sonnet 5.5): Maya (reviewer), Clayton (author), Pocholo (author, then reviewer), one author seat that got no persona; all released with mementos by 12:05 EDT. Afternoon: Pocholo (tester, released 14:00), Clayton (author, running at this checkpoint). Tip `95c1c02`, not pushed (28 commits ahead of origin). I cleared my own context at 12:31 EDT (session `f6acc646`, same seat).

- **APK scripts build with FCM by default** (row `58ec8260`, closed): `--no-fcm` opts out, `--fcm` still accepted; a stamp test covers both. Merged `60d7be1`, stamp test in `869481b`.
- **Log masking** (bug `8398bfe8`, closed): quoted keys, whole arrays and objects, `secret_key` / `private_key` / `access_key` and plural names, a linear scanner. Maya refused my ruling that any plural name holding a bare number stays readable (`passwords=12345678` printed); only token-count names keep a number now. Merged `869481b`.
- **Analyzer notes** (decision `6f0e209d`, closed; Rick: "Fix both, with tests"): mounted guard in the inbox screen, four `withValues`, notifications and queue on the strict check. Merged `12acb7d`.
- **Connectivity timers never arm while the app is paused** (bug `1b192f22`): three rounds, each from a reviewer finding (pause during start-up, pause before the services start, usage state on a paused start). Merged `f244d73`, `d35feaf`, `4e15c9c`. Rick ruled both open questions at about 14:41 EDT: the phone checks the Lupin server instead of `google.com` and `cloudflare.com`, and `limited` counts as usable in the task list and holding area. Clayton wrote both (12 commits, red test before each fix); Maya reviewed in four rounds (one not yet with three findings, then three passes). Merged `13882d9`; merge gate PASS on `d572558..13882d9` (no new failure, 3 known); APK built, stamp `sha=13882d9 fcm=true dirty=false`. Not checked by anyone: a real phone, the real server, TLS. Both seats released with mementos.
- **Seat-worktree scripts share one library with lupin** (lupin row `c41c090a`, closed): byte-identical copy, the three scripts source it, a usage test that survives the reviewer's mutants. Merged `d5da690`, `95c1c02`. My merge turned lupin's `test_new_worktrees_come_up_tier_capable.py` red because I ran only one of the two lupin files that read mobile's scripts; Chloé's fixture fix landed at lupin `2c24f7fee`, and both files are green from the real checkouts (32 passed, 2 skipped). Closed after a spawn into a new worktree linked Flutter and the Gradle wrapper.
- **Merge gates**: PASS `29a612c..60d7be1`, PASS `60d7be1..f244d73`, PASS-WITH-WARNING `f244d73..d35feaf` (ignores and the exemption list read), PASS `d35feaf..95c1c02`. Suite: no new failure, 3 known. APK built at `95c1c02`, FCM on.
- **Blind Dart symbol count for Cheech** (lupin row `7a963ebf`, Dart leg): 227 of 227 changed files match the index at lupin `ab3fc4557`, 2,577 symbols each side; counter frozen by sha256 before the index ran. The row was missing from my handover; Cheech reminded me.
- **Fresh slice of Dart pairs for Cheech** (row `df97c02b`, closed): from my 819 pairs (45 pilot, 774 sweep), 639 share no symbol with dev 80 or gate 175, and 344 share no file either. Unlabelled, so they test false alarms only. Folder `projects-data/lupin-mobile/dart-fresh-slice-2026.10.09/`.
- **Claim judge** (rows `2847a900`, `9e0dd2dd`): Cheech's extractor revision 2 was not adopted; the gate run is no earlier than 2026-10-10 afternoon.
- **Post-game** for the crew: `src/docs/post-games/v0.2.2/2026.10.09-board-whittling-crew-post-game.md`, rulings R12 to R18 drafted.
- Logs and verdicts under `io/2026.10.09/{tiffany,maya,pocholo}/`.

- **Evening**: Rick's phone check passed all three steps (card, about 18:20 EDT); rows `1b192f22` and `b69dbf0b` closed. He dropped rulings R6 to R11 (row `ea96c8d7` closed) and admitted lupin row `879fe139`.

- **Documentation plan closed (P0 row `b707f92f`)**: both of Cheech's extractor variants failed at 19:02 EDT, so Rick ruled a hand read of a sample in place of the claim judge. Pocholo and Chloé read 242 of 819 pairs (214 kept, 18 moved, 3 to restore, 7 rightly gone; the random 60 found none; a blind cross-check of 25 agreed). A fresh author seat wrote seven comment-only commits, Chloé reviewed (one not yet, then pass), merged `4e317c8`, merge gate PASS. Along the way: mobile comments said the task write doors ignore an undeclared field; the server refuses it with a 422. The full judge run stays owed on held row `79d49618`. Files: `io/2026.10.09/hand-read/`.

- **Transcript console finished overnight (row `768e852f`)**: Rick said the test admin account already exists; María gave the method (`bash -ic`). Tiberius ran the capture and found the only frame with thinking text held live tokens that the capture's check missed; he wrote nothing. Fixes, each reviewed by Chloé (one not yet, then pass): the token check now lives inside `_fixture_lib.write_fixture`; `append_mixed_kinds.json` recaptured (C5.18 green); an empty thinking block shows "Thinking (not recorded)"; `append_thinking.json` captured; the `pending-capture` tag retired; the gate's known-failure list rebuilt to zero. Merges `efd683e`, `8e7132e`, `bade1da`, each merge gate passed; suite 2915 passed, 0 failed; APK built at `8e7132e`. Stop poke steps for Rick: `src/docs/phone-checks/2026.10.09-stop-poke-switch-phone-check.md`. Receipts: `io/2026.10.09/{chloe,tiberius,tiffany}/`.

- **2026-10-10 midday**: Rick ran the Stop poke phone check (off 11:45, on 11:46 EDT, both confirmed at my seat) and un-parked rows `ee68d5e7` and `768e852f`; both closed. He then reported no speech on the phone and asked for a build line in the main menu.
  - **Build line** (Maya, `84ba4b0`, Chloé PASS, merge `c07c65d`): `lib/core/build_info.dart`, a pinned drawer footer, stamped by `src/scripts/build-apk-on-server.sh`.
  - **Speech** (Tiberius; Chloé reviewed five hand-overs, two NOT YET): watchdog and bounded on-device speaks, an outcome line in the Speech queue sheet, serialized on-device speech, her 13 driven scenarios kept as `test/unit/services/tts/on_device_speech_serialization_test.dart`. Merges `259531c`, `6a9ca61`, `4c26045`. The gate failed once on `6a9ca61` (a renamed test id, AC-G2) and passed on `4c26045`; suite 2959 passed, 0 failed. Cause on Rick's phone still unproven.
  - APK built at `4c26045`, 13:12 EDT. Receipts: `io/2026.10.10/{tiffany,chloe,tiberius}/`.

  - **Version line** (afternoon; Maya `d689996`, `96fd562`; Rio NOT YET then PASS; merge `16fc44d`, gate PASS): the drawer shows the branch over `yyyy.mm.dd build N`, counter in `io/build-counter`. APK build 4 at `16fc44d`, 15:39 EDT. Receipts: `io/2026.10.10/rio/`.

  - **Evening**: phone socket and logout fixes (Tiberius `0d6f56b`, Chloé PASS, merge `98a497e`, gate PASS over `5eaaa2a..98a497e`): listeners bound to their own channel, the previous channel closed, one failure one reconnect, logout sends the refresh token and unregisters push first. Rick installed build 4 and at 18:00 EDT read the cause off the Speech queue sheet: Master mute was on. A census of every control that silences speech: `io/2026.10.10/tiberius/census-speech-silencing-controls.md`. Extractor A2 failed the Dart dev 80 check, so the judge run (row `79d49618`) stays held. I cleared my own context at 18:13 EDT (session `068dfb3b`, same seat).

  - **Late evening** (all Tiberius or Maya, each reviewed by Chloé, each merge gated, suite 0 failing):
    - Speech-silenced banner and logout keystore read guard, merge `0dd0655`; logout delete guard and quiet-hours wording, `17750b7`; banner repaints on a bypass toggle, `a672945` (APK build 7, 18:39 EDT); tests pinning banner rebuilds, `37a6b20`.
    - Command wrappers refreshed to planning-is-prompting `05ec88d` and backup paths corrected in the wrappers and `CLAUDE.md`, merge `cbe1854` (Maya; row `08c4e586` closed; sha sent to María).
    - Rick heard the phone speak after turning Master mute off; speech bug `e0f0faf0` closed.
    - Rick rejected the claim-judge premise and chose an automated blind taste test; brief `io/2026.10.10/tiffany/brief-blind-taste-test.md`, pilot running at this checkpoint (row `79d49618`).
    - Flaky test found and reproduced under load (held row `ff9cc9d3`).

**RESUME HERE (checkpoint, 2026-10-10 19:00 EDT; replaces the lines below):** (1) Tiberius's taste test pilot report in `io/2026.10.10/taste-test/`, Chloé's check, then the numbers and the code-check plan to Rick. (2) Flaky test row `ff9cc9d3` waits on Rick's admission. (3) Post-game for today's crew at session end. Seats up: Tiberius, Chloé; nothing pushed; APK build 7 ready.

**RESUME HERE (superseded, 2026-10-10 18:17 EDT):** (1) Chloé's verdict on the mute banner `0d6f56b..d5ccb9a` (Tiberius), then merge, gate, build 5. (2) Chloé's verdict on the wrappers `5eaaa2a..4db931e` (Maya), then merge, gate, the sha to María (row `08c4e586`, held). (3) Rick says Master mute is off; send a test; close `e0f0faf0` only when he says he heard speech. (4) Judge run: Rick's hold, run or drop. (5) Post-game for today's crew at session end. Seats up: Tiberius, Maya, Chloé; nothing pushed.

**RESUME HERE (superseded, 2026-10-10 16:02 EDT):** (1) Rick installs build 4 and says "installed"; respawn Tiberius from `io/mementos/tiberius.md`, send a test; if silent, Rick reads the top line of the Speech queue sheet (row `e0f0faf0`). (2) When Rick approves the admit request on `79d49618`, staff the judge run. (3) Phone socket defects are owed on `e0f0faf0`, not started. (4) Rick: rulings R12 to R18. No seats running; nothing pushed.

**RESUME HERE (superseded, 2026-10-10 13:14 EDT):** (1) Rick installs the 13:12 build and says "installed"; send a test; if silent, he reads the top line of the Speech queue sheet and that goes to Tiberius (seat `cc-author-tiffany-1`, up). (2) When the ticket gate opens, file rows for the speech bug, the build line and the socket teardown loop; they are recorded on row `79d49618` meanwhile. (3) Rick: admit `79d49618` (judge run ready), rulings R12 to R18, the `pubspec.yaml` version. Nothing pushed.

**RESUME HERE (superseded, 2026-10-10 00:26 EDT):** (1) Rick: approver sign-in to move `768e852f` and `ee68d5e7` out of parked; the Stop poke phone check; admit `79d49618`; rulings R12 to R18; deploy the APK. (2) When Cheech says the `final_absent` change landed, staff the judge run over all 819 pairs. (3) No seats running; seeds are `io/mementos/tiberius.md` and `io/mementos/chloe.md`; nothing pushed.

**RESUME HERE (superseded, 19:51 EDT):** (1) Rick: rulings R12 to R18 (link sent); admit row `79d49618`; the Stop poke flip (`ee68d5e7`: phone, Settings, Notifications, switch "Stop poke", admin sign-in) and transcript capture (`768e852f`). (2) When Cheech reports a passing Dart extractor, run the judge over all 819 pairs (row `79d49618`). (3) No seats running; nothing pushed. Earlier line: (2) Rick: rulings R6 to R11 (`ea96c8d7`) and R12 to R18; push. (3) Cheech's gate run, chase 2026-10-10 14:00 EDT, then the judge over the pilot and the sweep.
