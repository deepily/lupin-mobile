# TODO

## ▶ START HERE — 2026-10-10 (Tiffany 💍)

State at the 19:00 EDT checkpoint: merge tip `37a6b20`, every merge since `98a497e` reviewed by Chloé and gated (last gate PASS over `a672945..37a6b20`, suite 0 failing). APK build 7 made at `a672945`, 18:39 EDT, FCM on; `37a6b20` adds tests only, so build 7 is current. Rick has not said which build is on the phone. Nothing pushed. Seats up: Tiberius (author, re-spun 18:49 EDT), Chloé (reviewer); Maya released; seeds `io/mementos/{tiberius,maya,rio,chloe}.md`. I cleared my own context at 18:13 EDT (session `068dfb3b`, same seat). Rows closed this evening: speech bug `e0f0faf0`, wrapper refresh `08c4e586`.

| Next | Waits on |
|---|---|
| Automated blind taste test of old against new doc comments (row `79d49618`, re-scoped; the claim-judge run is off). Brief `io/2026.10.10/tiffany/brief-blind-taste-test.md`; outputs `io/2026.10.10/taste-test/` | Tiberius's pilot report (60 pairs, 10 planted), then Chloé's check, then the numbers to Rick; all 819 only if the controls hold |
| Check the new comments against the code on the risky symbols, rules that matter become tests, fix on contact elsewhere | the pilot report; Rick said "interested", not yet a go |
| Flaky test `notification_foreground_gate_test` (row `ff9cc9d3`, held): 4 failures of 10 under CPU load, fixed 50 ms waits; a sibling test passes without testing anything | Rick admits the row; then an author and a reviewer |
| No test pins the banner's 1 s poll default (Chloé, on `a08be6c`) | folded into the next banner change |
| Post-game for today's crew (`src/docs/post-games/v0.2.2/`) | session end |
| Post-game rulings R12 to R18 (2026-10-09 post-game) | Rick reads and rules |
| Whether `pubspec.yaml`'s `1.0.0+1` should change | Rick, at his convenience |

### Decisions Log — 2026-10-10, evening (Tiffany)

- **Rick, card, about 17:50 EDT, first-hand**: Judge run "Dart check first (Recommended)". The check then failed: A2 missed 6, 5 and 3 of 32 seeded losses and raised 2, 1 and 0 false alarms of 48 across three draws.
- **Rick, voice, 18:00 EDT, reading the phone**: "Last message not spoken, Master Mute is on."
- **Rick, voice, 18:03 EDT**: "I think that you've got two toggles in two different places that disable the or mute the TTS, I believe. So look into your code". The two are "Notifications" (key `notif.enabled`) and "Master mute" (key `notif_audio.master_mute`); neither shows the other's state. Census: `io/2026.10.10/tiberius/census-speech-silencing-controls.md`.
- **Rick, card, about 18:05 EDT, first-hand, on the two toggles**: "I'm inclined to keep both and show a marker per your recommendation but I'm really not certain what you mean by a marker on the main screen Names an Aeuntiser Where does that appear?" **My reading, his to correct**: keep both switches and show a banner at the top of the conversation screen, one row per active silencer, a tap opens the switch.
- **Rick, same card, on the judge run**: "Can you provide me with a quick ephemeral explainer doc about why this is important? I'm not certain I understand the significance of what's going on here And of course as you know need more context". Not a ruling; the run stays held.
- **Correction of the 2026-10-09 late-evening entry below**: extractor A2 never passed a Dart gate. What it passed was the exit test on the Python dev 70 set (Cheech, 17:41 EDT). I relayed "passes its gate" to Rick as fact and he admitted row `79d49618` on it.
- **Rick, card, about 18:31 EDT, first-hand**: Master mute "Off, send a test (Recommended)". On the judge run he rejected its premise: "I can't continue assuming that these original dock strings are 1 the gold standard for what a dock string should look like So propose multiple paths forward At the very least 5 ... I am not stopping the red documentation process because we might lose some of your theoretically Perfect Dockstrings." His full words are on row `79d49618`. Seven paths: `io/2026.10.10/tiffany/paths-forward-doc-checking.md`.
- **Rick, voice, about 18:45 EDT**: "Resend". I resent the speech test and the card; the phone had logged out at 18:38:37 EDT, so the test did not reach it.
- **Rick, card, about 18:47 EDT, first-hand**: Heard speech "Yes, I heard it". Doc check: "I love the idea of a blind taste test first but I'm not doing this by hand Automate everything After that I'm interested in your recommendation for the code check and the risky parts". **My reading, his to correct**: the taste test is a go and fully automated; the code check is not yet a go.
- **Rick, voice, about 18:56 EDT**: "What's the state of your test taste test? Does it need a ticket?" Answered: no new ticket, it is step 1 on admitted row `79d49618`; offered a fresh row with a true title if he wants one.
- **Taste test pilot** (Tiberius; Chloé PASS with conditions, `io/2026.10.10/chloe/verdict-taste-test-pilot.md`): 59 pairs read blind in both orders: new preferred 39, old 6, no difference 3, order-dependent 11; 10 of 10 planted false comments caught; no new comment found false. All six old-preferred pairs are real dropped reasons or specifics. Ten trials per reader costs 7.3k tokens a read against 61.6k but kept only 2 of the 6, so it is not used for a loss count.
- **I withdrew a card** (about 19:06 EDT): it recommended running all 819 with the batched reader; Chloé's verdict arrived minutes later and showed that reader hides losses.
- **Rick, card, about 19:13 EDT, first-hand, not a choice of option**: "Are you telling me that in general if we were to rewrite the dock strings in bulk right now that the resulting dock string would be of lower quality than the original ... That strains credibility and my imagination to think that a newer model with a better harness is going to write worse dock strings Please disabuse me of this idea!" Answered: no; the new comments win 39 to 6; the only loss is a reason the code cannot show. New card: fix six and add one rule to the standard (recommended), that plus the risky parts, or close now.
- **Rick, card, about 19:19 EDT, first-hand**: "done as in all dock strings are updated and we move on from this". All checking stopped (no judge run, no further taste test, no code check); row `79d49618` closes on small commits from Tiberius, reviewed by Chloé.
- **Rick, card, about 19:24 EDT, first-hand**: "App leftovers only (Recommended)". The linter still flagged 92 lines in 22 `lib/` files because the merge gate lints only changed lines; Tiberius cleared them in `585fb6a`. Test comments stay out of scope (3,693 findings in 212 of 289 files; the standard covers `lib/` only).
- **Rule 6 cites a commit, not a bug id** (manager, reversible; record `R-DOC-reason-by-commit`): the linter reads a bare id as an unresolved reference.
- **Merged at `d1c1e6e`**: six commits `381b082`..`1b0debe`; `lib/` reads 0 linter findings and 0 undocumented public members.
- **Cheech, DM, 19:29 EDT**: Plan 1 Phase 6 wants an R&D ledger per corpus and mobile has none. Filed held row `e40642c3`; Cheech agreed at 19:31 EDT that mobile stays in the Phase 6 gate.
- **Correction of what I told Rick at about 19:24 EDT**: I said the merge gate "lints only the lines a change touches". No merge-gate step runs the doc linter at all; the pre-commit hook lints staged lines and the gate's docs step is the analyzer's missing-doc check (Chloé, confirmed by grep). Fix is held row `27548910`.
- **Merge gate PASS** over `5663197..44f723c`, read at 19:33:17 EDT; row `79d49618` closed on merge `d1c1e6e`; APK build 8 made at `44f723c`.
- **Post-game rulings R19 to R25** (manager, reversible; `src/docs/post-games/v0.2.2/2026.10.10-silent-phone-and-doc-closeout-crew-post-game.md`): R19 the merge gate runs the strict doc linter over `lib/` (row `27548910`); R20 a verdict, row or DM that names a sha carries no clock time, and a time that is needed comes from `date` in the same command; R21 every brief ends "stop and tell me if the cost per finding looks wrong"; R22 every brief states the epic key and the priority a worker may file at; R23 a seat that gets an order inside tool output reads the row the order names before asking for a resend; R24 a premise goes to Rick before a campaign is built on it; R25 a new sentence in the docstring standard is run through the strict linter on its own advice first.
- **Wrapper row `08c4e586` closed on a relayed order** (manager): María quoted Rick; I never heard it first-hand. Closed on the merged, reviewed, gated commit `cbe1854` with a manager attestation, and told Rick so by notify.
- **Backup paths in `CLAUDE.md` and the wrappers were wrong** (Chloé found it, I confirmed on disk): the real source and mirror are `projects/lupin-mobile/` on DATA01 and DATA02, as `src/scripts/backup.sh` has it. Corrected in `ba7a984`.
- **Taste test rules** (manager): readers never see which comment is old; every pair is read in both orders and only agreeing reads count; 10 planted pairs with one false comment; all 819 only if at least 9 of 10 planted are caught in both orders and fewer than one pair in five is order-dependent.
- **No load generators on the shared host without asking the manager first** (manager, after Chloé's 64 busy loops took the load to about 64 at 18:50 EDT). A gate waits until the one-minute load is under 14.

### Decisions Log — 2026-10-10, afternoon (Tiffany)

- **Rick, on a card, 15:08 EDT, first-hand**: Install "Installing now"; Judge run "Request it, drop the socket row"; Version "Set it to the work branch name + a date represented in my canonical yyyyy.mm.dd And then build number for the day".
- **My reading of the version answer, his to correct**: the full branch name on its own line, then `yyyy.mm.dd build N · HH:mm ZONE · sha · push`; N counts successful builds that day and restarts at 1; `pubspec.yaml` is untouched and no longer shown. Today's counter was seeded at 3 for the builds at 00:13, 12:23 and 13:12 EDT.
- **An admit request costs one of my own live tickets** (the store's rule while Rick's switch is on). I pledged the finished build-line row for the speech bug, and, on Rick's word, the socket-defect row for the judge run; both rows' content was folded into `e0f0faf0` first.
- **A seat's memento is written through `/plan-memento`**: a hand-written file has no record header and the reap refuses it (Maya, twice).

### Decisions Log — 2026-10-10, midday (Tiffany)

- **Rick, by voice, first-hand**: 11:45 "Tiffany the stop-poke is now muted"; 11:47 "The stoppoke has been turned back on." Both read back from the Stop hook's reader at my seat; he then un-parked rows `ee68d5e7` and `768e852f` from approval cards and I closed them.
- **Rick, by voice, 11:48 EDT**: "I'm not hearing any TTS on the mobile app." On a card: "Yes, text but no sound" and "I'm using the latest Build from last night and still nothing". On the 11:56 test: "I heard nothing".
- **Rick, same card**: "we need to track build date build number version number ... easily parsable by a human ... obtainable from the main menu". Built as one pinned line at the foot of the drawer, stamped by `build-apk-on-server.sh`.
- **On-device speech is serialized by the app, with no engine queue mode** (Tiffany, accepting Tiberius's change of approach after Chloé's NOT YET): an utterance stays in flight until the voice engine reports it finished, so skip, stop-all, pause, the microphone hold and an urgent message reach it.
- **Known and accepted**: an engine cancelled from outside the app releases the speech queue only at the completion bound (30 s plus length / 8). A late completion from an abandoned server stream can still end the next utterance early; the real fix is an utterance id in the server's audio events.
- **A retraction I made to Rick**: the 11:51 socket connect burst was fleet seats, not the phone; the microphone-hold theory was also wrong (the uploads I saw came from another client).

### Decisions Log — 2026-10-10 (session `de4ce9d3` / `f6acc646`, Tiffany)

- **The gate's known-failure list is empty** (`tool/data/test_failures_baseline.json`, rebuilt by the tool over three full runs at `9959202`). The one flaky entry it used to carry was the ASR AC-S4.7 live probe, which posts to port 7999 and failed once during a bounce of that server; it is server-dependent, and the code has no flake. If it fails in a gate, the checker answers RERUN_REQUIRED first.
- **No fixture is rewritten outside `_fixture_lib.write_fixture`** (Tiffany, after Chloé's review): that function refuses any body holding a token, including one inside prose.

### Decisions Log — 2026-10-09, late evening (Tiffany)

- **Rick, on a card, about 23:20 EDT, first-hand.** Stop poke: "Build a transient link for me and I'll test it tomorrow But I need a document to point to". Transcript: "I don't have to create a test admin account It already exists Look in the environment variables in the BashRC file". Judge row: "Yeah I'll admit the held row, What is the ID?". Tonight: "I say that you work all night but you have to ascertain whether you have proper access to that test admin account".
- **How a seat uses the test admin account** (María's method): `LUPIN_TEST_ADMIN_EMAIL` and `LUPIN_TEST_ADMIN_PASSWORD` are not in a seat's shell; they are set when a command runs as `bash -ic '<command>'`. Values are never printed or written.
- **C5.22 reframed to the real contract** (Tiffany, standing authority, announced to Rick, his to overrule): Claude Code records most thinking with empty text (97.7% of blocks, Mr. Radio's count) and the server passes it through. An empty thinking block shows a dim "Thinking (not recorded)" label that cannot be expanded, as the web client does; a block with text keeps fold and expand.
- **C5.18 was a stale fixture, and the server was right**: it has carried tool names since 2026-09-29; `append_mixed_kinds.json` predated names on tool results.
- **The `pending-capture` test tag is retired**: every fixture exists, so a new fixture-dependent test lands together with its fixture.
- **Relayed by Cheech, not heard first-hand**: Rick ruled at 23:24 EDT on Cheech's row `9ce53ec2` that the claim-judge vote rule is "all three must agree"; extractor A2 then passes its gate. **Wrong, corrected 2026-10-10 evening above**: A2 passed the Python dev 70 exit test, not a Dart gate.

### Decisions Log — 2026-10-09 (sessions `de4ce9d3` / `f6acc646`, Tiffany)

- **Spin up a crew and whittle the board; there is fleet headroom** (Rick, voice, about 11:30 EDT; from my handover, not re-read).
- **Analyzer notes, row `6f0e209d`: "Fix both, with tests"** (Rick, card, about 11:33 EDT; from my handover).
- **One seat over the fleet cap of 12** (Rick, card, about 11:35 EDT; from my handover).
- **Phone check of the reconnect fix: "Not yet, keep it open"** (Rick, card, about 11:30 EDT; from my handover). Row `b69dbf0b` stays parked.
- **Internet check: the phone asks the Lupin server; the `google.com`, `cloudflare.com` and `8.8.8.8` lookups come out** (Rick, card, answered about 14:41 EDT, no default used). Row `1b192f22`.
- **`limited` counts as usable in the task list and holding area** (Rick, same card).
- **Rick admits the post-game row `41b0772d` himself** (same card; it read queued at 14:42 EDT).
- **Rick un-parked row `b69dbf0b`** (store, afternoon); it is blocked on his phone check.
- **The 30 s re-check also runs while `limited`; it still stops on pause and never runs on a Bluetooth-only connection** (manager, after Maya's first verdict; row `1b192f22`).
- **Retry and refetch fire on a move from not usable to `limited` or `connected`, and from `limited` to `connected`; never from `connected` to `limited` or on a repeated state** (manager; `shouldRetryOnNetworkEdge`).
- **A pane seeds its previous network state from the service when it starts** (manager, after Maya's round 3 finding).
- **`ws_reconnect_coordinator.dart:148` stays as it is**: it acts on `connected` to `limited`, but only does something when the socket is down (manager).
- **Metered polling (`isMobile`) is unchanged; Rick did not rule on it** (manager).
- **Phone check of the connectivity rulings and the reconnect fix: "All three steps passed"** (Rick, card, about 18:20 EDT). Rows `1b192f22` and `b69dbf0b` closed.
- **Rulings R6 to R11 of the 2026-10-03 post-game: "Drop them"** (Rick, same card). None is a rule; row `ea96c8d7` closed.
- **Rulings R12 to R18: Rick asked for a link to the document and has not ruled** (same card).
- **Lupin row `879fe139` admitted** (Rick; it read queued at 18:20 EDT).
- **Lupin row `879fe139` reassigned to Mr. Radio, owner and manager** (he agreed by DM, 18:21 EDT).
- **Cheech's extractor draws run tonight, not tomorrow: "That's a huge blocker. He should get that out of your way"** (Rick, voice, about 18:47 EDT). Both prompt variants failed at 19:02 EDT.
- **The mobile documentation plan closes on the six mechanical checks plus a hand-read sample of the 819 pairs; the claim judge is deferred until an extractor passes** (Rick, Cheech's card about 19:08 EDT; confirmed first-hand on my card about 19:10 EDT).
- **Sample: "About 240, risk first"**: all 45 pilot pairs, the 77 sweep pairs whose doc comment became a plain comment or vanished, the 60 largest word losses, 60 random with seed 20261009 (Rick, my card, about 19:10 EDT).
- **A real loss in the random part adds 60 more random pairs** (Rick, same card). It did not fire: the random 60 found none.
- **Result of the hand read**: 242 pairs, 214 kept, 18 moved, 3 restored, 7 rightly gone. Fixes merged `4e317c8` (seven comment-only commits; Chloé's review; merge gate PASS). Rows `9e0dd2dd`, `2847a900`, `c70a83b1`, `ef09dc19` and the P0 `b707f92f` closed.
- **The task write doors refuse an undeclared field with a 422; mobile comments that said "ignored" were wrong** (read in lupin `src/cosa/rest/routers/tasks.py` at `99ea8d5f9`; corrected in `4e317c8`).
- **A hand-written memento with no header may be accepted after the manager reads it** (manager; Chloé's, reaped knowingly at 19:47 EDT).
- **Mr. Radio's quiet windows also ran 18:23 to 18:49 and 18:50 to 19:26 EDT** (Rick's env keys run; the keys were not kept).
- **Mr. Radio's quiet window ran 16:22 to 16:25 EDT and nothing ran in it** (his DM: the permission classifier refused his run; it is now Rick's to run, and he will ask for a new window). The agreed terms for a window: no lupin host tests, no bounce of `:7999`, `:8000` or `:8001`, no docker compose, no spawn, no edit of lupin's `.env`.
- **Log masking: findings A (multi-line values) and B (quadratic scanner) are required before merge; `secret_key`, `private_key`, `access_key` and plural names are added** (manager, row `8398bfe8`).
- **Only token-count names keep a bare number readable: `tokens`, `max_tokens`, `prompt_tokens`, `completion_tokens`, `total_tokens`, `input_tokens`, `output_tokens`** (manager, after Maya refused my first, wider rule; commit `8927b28`).
- **Accepted gaps, named on the rows**: JSON inside a string and a secret in a URL path in debug builds (`8398bfe8`); a pipe split across lines in the usage test (`c41c090a`).
- **The lost-pause and usage-state findings stay on row `1b192f22`, not new rows** (manager).
- **Mobile's copy of `worktree-link-lib.sh` is never edited on the mobile side; lupin's byte-compare test fails on one byte** (Mr. Radio's test; manager's rule for the crew).
- **The Dart symbol index is compared at lupin `ab3fc4557`** (Cheech, DM 13:55 EDT).
- **Cheech's crew opens only `slice-b.jsonl` of the fresh slice, and not before a freeze says how it is used** (Cheech, DM 14:00 EDT).

## ▶ Earlier: 2026-10-05 close (Tiffany 💍)

State at the 23:05 EDT close: the WebSocket reconnect fix is merged (`4badc70`, merge gate PASS) and the APK is built with `--fcm` at that sha. No workers running; Chloé and the reviewer seat (persona Maya) were released with verified mementos under `io/mementos/`. Live owed work is in the store, owner `tiffany`.

| Next | Waits on |
|---|---|
| Phone check of the reconnect fix (row `b69dbf0b`): airplane mode over 75 s; server stopped over 75 s with the app on screen; leave the app 10 s and return. The row still reads parked | Rick: `deploy-apk-to-device.sh`, the check, and an un-park (approver login) |
| Plan 1 pilot gate (row `2847a900`) and claim judge over the pilot and the sweep (row `9e0dd2dd`): the two tool checks pass at merged lupin; only the judge is left. After Cheech's run: rebuild the pilot pairs (expect 45 pairs, 0 gone), build the sweep's pairs, run `run-check.sh` | Cheech: judge on the Dart set 2026-10-06, 10:00 to 13:00 EDT, and the merged `dart_pairs` fix (lupin bug `e19f2d9d`) |
| Lifecycle and connectivity services were never started (bug `1b192f22`, held): fixed inside `4badc70`; follow-ups are the timers arming during a pause in the first seconds, and two questions for Rick (the google.com and cloudflare.com lookups; `limited` on a LAN with no internet) | Rick admits and rules |
| APK scripts build with FCM by default, `--no-fcm` to opt out (row `58ec8260`, held) | Rick admits |
| Log masking gaps (bug `8398bfe8`, held): quoted keys, list and nested values, `passwd` / `secret` / `api_key` | Rick admits it |
| Post-games: the 2026-10-03 crew (row `ea96c8d7`), rulings R6 to R11; the 2026-10-05 crew (row `9a104a74`, held, not written) | Rick reads and rules; admits the second |
| 4 `withOpacity` and 1 `BuildContext` after await (decision `6f0e209d`); transcript fixtures (`768e852f`) and Stop poke flip (`ee68d5e7`), both parked with a passed chase date | Rick |
| Seeder defects (lupin bugs `e86e07b1`, `6737b017`, held, owner Cheech) | Rick admits; Cheech staffs |

### Decisions Log — 2026-10-05 (session `bca18ee2`, Tiffany)

- **Mobile runs lupin row `4cc9cd81` (the Dart labelled set after rule 8)** (Rick, ask card about 18:46 EDT, clean yes). Cheech admitted the row and reassigned it to Tiffany.
- **A mobile author and a reviewer may work in the lupin repository for that row** (Rick, ask card about 18:49 EDT, clean yes). The fleet cap of 8 refused the reviewer seat, so Cheech's seat Rio reviewed; Cheech made the merge call (`bf1d05d5b`).
- **Rick asked Tiffany to coordinate the fix for `4cc9cd81` with Cheech** (voice, about 18:50 EDT).
- **Rule 9's `DROPPED_CONDITION` keeps refusing every condition clause before ", and/or/but"** (manager as row owner; Cheech, the set's owner, agreed by DM 19:56 EDT). Measured on the Dart pool of 4,375 entries: 56 spans refused, 502 condition-clause deletes still offered. The numbers are in the rule's docstring.
- **Rule-1 failures that only miss the weak word are read by the key-holder (the manager) and accepted when a synonym keeps the weaker meaning** (manager; same practice as dev on 2026-10-03). Gate accept list: p005, p047, p051, p101, p134, p151.
- **Dart's writer allotment is 340 calls** (Cheech, DM 21:05 EDT; was 320). Used: 319.
- **Redactor gaps found in review are fixed inside the row when small and prefixed-name shaped; the rest go to a held bug** (manager, row `5e5b4ad2`; bug `8398bfe8`).
- **A test that imports a transitive package declares it in `pubspec.yaml`; it does not silence the note** (manager, following the 2026-10-03 ruling on three packages; the merge gate enforced it on `e654389`).
- **Log flush on pause: 3-second timeout, one follow-up flush at most, destinations flushed side by side** (manager on John's findings, row `f262281c`). Accepted: a timed-out destination keeps running in the background.
- **The WebSocket fix waits for Rick's choice of trigger; no fix is written before it** (manager). Recommended: resume, network restored, and a retry loop only while the app is on screen.
- **The Dart set is published by Tiffany: both assembled splits copied to `projects-data/lupin/v022-phase2-labelled-dart/`, manifest by the seeder's own command** (Cheech as set owner, DM 21:06 EDT, condensed in transit).
- **WebSocket reconnect trigger: Mix** (Rick, ask card about 21:40 EDT, a real keypress): resume, network restored, a foreground push wake-up, and a retry loop only while the app is on screen.
- **One seat over the fleet cap of 8 for the review of that fix** (Rick, ask card, clean yes). The pool gave the seat the persona Maya, seeded from John's memento.
- **Merge of the reviewed fix approved** (Rick, ask card, clean yes). The two refusals before and after it were my compound command, not a missing permission: `Bash(git merge:*)` is in the global settings.
- **The connectivity service's two DNS timers pause while the app is paused** (manager, on Maya's finding F3; in line with Mix, which has no background cost).
- **`main()` starts the lifecycle and connectivity services through one function, and a test fails if any start-up line is removed** (manager, on Maya's finding F4).
- **The judge must pass on the Dart gate split before any Dart judge run over the sweep; Cheech runs it, dev then gate once** (Cheech, lupin `io/tmp/2026.10.05-cheech-to-tiffany-dart-judge-answers.md`). The published folder is frozen.
- **Memento sweep: the two old dangling pointers are left alone; the newest files of Cheech, Krishna and Rachel are kept** (María for the first; my caution for the second).
- **Rick on FCM: no going back to builds without a remote wake-up** (typed, about 22:40 EDT). Filed as row `58ec8260`; not yet admitted, so not yet done.

## ▶ Earlier: 2026-10-03 close (Tiffany 💍)

Tip `e9a6d9c` plus the two checkpoint commits of 2026-10-03 night; pushed at the 23:15 ritual on Rick's broadcast `e0ab1f3f` (receipt in the session-end card). APK built with `--fcm` at `dec4a63`; only tool and CI files changed since, so it is current. Live owed work is in the store, owner `tiffany`.

| Next | Waits on |
|---|---|
| Post-game for the 2026-10-03 crew (row `ea96c8d7`): drafted; rulings R6 to R11. Tonight's later work is not in it | Rick reads it, then rules |
| Error-path prints to the app logger (row `5e5b4ad2`): slices 1 to 5 and fixes reviewed, holding at `761a2e9`; slice 6 not started. Commits at `refs/keep/tiberius-logger-slices`, nothing merged | respawn Tiberius (`io/mementos/tiberius-04654eec.md`) and John (`io/mementos/john-3e861249.md`); slice 6 with the word-boundary redactor fix, the Dio interceptor URL prints and the queued-request assertion; then gate, merge, APK rebuild with `--fcm` |
| Memento sweep (row `e5610916`, held): 42 old mementos; dry run only on 2026-10-03 | check the keep list against the pointer files first |
| Dart labelled set (row `eb5a05fe`, then `9e0dd2dd`, `2847a900`, `c70a83b1`, `ef09dc19`): dev and gate written, 292 of 320 Fable calls; dev blind check done, 7 pairs fail; gate rule 1 fails 9 of 74, gate text unread | Cheech's Dart cut rule (lupin row `9d3f4562`, 2026-10-04 10:00 to 13:00 EDT); then redraws, then Pocholo's blind check of the gate |
| Three bugs from the logger review, held: `f262281c` (no flush on pause), `92d911f4` (bare `password=` / `token=` not masked), `b69dbf0b` (WebSocket not retried after five failed tries until the next login) | Rick admits them |
| 4 `withOpacity` and 1 `BuildContext` after await (decision row `6f0e209d`, held) | Rick |
| Transcript fixtures (row `768e852f`) and one Stop poke flip on the phone (row `ee68d5e7`), both parked to 2026-10-05 | Rick, when convenient |

### Decisions Log — 2026-10-03 (session `576809a5`, Tiffany)

Rulings from the docs crew post-game (`src/docs/post-games/v0.2.2/2026.10.03-mobile-docs-track-crew-post-game.md`), approved by Rick on an ask card (clean yes, about 15:20 EDT).

- **A manager's merge gate script is a tracked file under `tool/` with a permission rule, never a scratchpad file** (R1; work is row `00db303b`).
- **Measure a gate's pass condition on every directory it must cover before building the gate** (R2).
- **Before sweeping a directory, check that it compiles and is referenced; if not, ask for a keep-or-delete ruling first** (R3).
- **Every worker brief on this repo asks for lessons posted to the commons `post-game` topic as they happen, with how the worker came to know them** (R4).
- **A demonstration closes a row only when the manager reruns it, or the evidence answers every gap the row names** (R5).
- **Card answers, about 15:12 EDT** (Rick): one seat for the gates demonstration; held rows `eb5a05fe`, `c05c6f8c` and `5a200e6c` approved; he gives Cheech a Fable figure for the Dart labelled set.
- **Delete the unreachable code: groups A and B, and the two test helpers that do not compile** (Rick, ask card about 16:27 EDT). 54 files; 70 tests went with the old code. Two author seats approved on the same card.
- **Held rows `00db303b` (gate script into the repo) and `d56061a4` (stale plan manifest) approved** (Rick, ask card about 16:30 EDT, clean yes).
- **Post-games live in `src/docs/post-games/<version>/`, tracked, one folder per work-branch version** (owner's ruling relayed in planning-is-prompting `7a17919`; applied here in `c8f9a52`).
- **Of the last four analyzer warnings, two were fixed on the manager's ruling as behaviour-neutral** (keep the storage call and drop its variable; drop an unreachable line in an unused test mock); the other two wait for Rick (row `fa6c1842`).
- **Last two warnings and the unused mock** (Rick, ask card about 19:10 EDT, row `fa6c1842`): remove the logger's `flushInterval` field and argument; mark `inFlightToken` `@visibleForTesting`; delete `test/mocks/mock_websocket_server.dart`. Merged at `97cf2ac`.
- **The merge gate's permission rule lives in Rick's `.claude/settings.local.json`, written by Rick** (Rick, same card and a follow-up about 19:15 EDT). He first chose a tracked `.claude/settings.json`; the permission check refused a seat writing it ("[Self-Modification]"), and he added the rule to his local settings himself. Untracked, so worktree seats do not get it; the gate runs only from the main checkout.
- **Approved on cards, about 20:32 and 20:47 EDT** (Rick): the post-game for today's crew, the style-note clean-up, closing row `00db303b`; later rows `91c260ef`, `08d4c9fb` and `5e5b4ad2` admitted and the two parked rows un-parked. The post-game's rulings R6 to R11 are **on hold** until he has read it.
- **`print` becomes `debugPrint` in 77 places** (Rick, ask card about 20:57 EDT, knowing the cost Pocholo measured: on a device output above about 12 KB a second is queued, so burst lines can arrive up to a second late and behind plain `print`; nothing is dropped). The manager had first ruled it behaviour-neutral, which the review showed was not quite true. 13 prints in `http_service.dart` stay, because a redaction test reads that output. Merged at `dec4a63`.
- **Every gated directory is strict (any analyzer finding fails the hook and CI) unless `tool/data/strict_exempt.txt` names it with a reason and a row** (manager, on Clayton's measurement of all 22: 19 pass; merged `f3bdf8a` after three review rounds). A new gated directory is strict by default.
- **Logger design, three manager calls reported to Rick** (row `5e5b4ad2`): release builds keep warnings and errors in logcat; the two "connectivity test failed" lines stay debug prints; the log file is flushed on an error, one flush in flight. The remote log destination is not touched.
- **The Dart pool builder is built on Cheech's side, not by a mobile seat in lupin** (the card asking Rick for a cross-project seat timed out, 21:19 EDT). Fable budget for Dart: 255 of Rick's single cap of 1,000 (read in lupin's Decisions Log), dev 80, gate 175, Dart's own size mix.
- **Dart labelled set, rulings by Cheech as the set's owner** (DMs 22:14 to 22:46 EDT): Dart's Fable allotment is 320 calls (measured need: dev 89 tasks, gate 198, not the 255 estimated); the second checker gets `verify-input.jsonl` only, never the spans file; the garbled deletes are a selection defect, so every redraw and the last 28 calls wait for a Dart-aware cut rule (lupin row `9d3f4562`); the gate stays unread until then.
- **Push and backup at the 23:15 ritual** (Rick, broadcast `e0ab1f3f`, 2026-10-03 about 22:51 EDT: "Managers Cheech, María and Tiffany, I want a backup and a push"; Last Call row `ec774e93`).
- **Logger review rulings** (manager, row `5e5b4ad2`): the `name=value` redactor gap is fixed inside this row because the websocket slice makes it reachable; a corrupt stored record is logged by exception type and offset, never by its text; the offline queue's request key stays out of every log line; a non-JSON websocket frame logs at warning.
- **Three packages the code already imported are declared in `pubspec.yaml`**, pinned to the locked versions (manager's ruling as behaviour-neutral; the lock file changed in labels only).

### Decisions Log — 2026-10-02 (sessions `27fa7f7e` / `e2c953ca`, Tiffany)

- **Stop poke is a plain on/off switch, admin-only write, no timer** (Rick, first-hand, about 11:00).
- **Convert tests that assert comment wording; delete `lib/features/voice` and the unused registry** (Rick, decisions `a1bbc3ef`, `32aedd1c`).
- **Docs gate: docs now, code clean-up later** (Rick, ask card about 20:50). The analyzer check fails only on missing doc comments, over all 24 swept directories; other findings are a separate backlog row.
- **Do not list Rick as a blocker** (Rick, broadcast `62334f19`). Work that waits on his own action is parked with a chase date, not blocked on him.
- **Held rows carry a persona, not a group label** (Rick, via María): held rows are keyed `epic:unassigned`.
- **Labelled sets** (Rick, via Cheech, lupin row `dad61023`): gate 190 pairs, 94 seeded, 59 short spans; Fable writes reworded text, one-shot calls, 500-call cap shared; no second extractor, no human arm. The cap does not cover the Dart set.

## ▶ Earlier: mobile docs track (2026-10-01 close, Tiffany 💍)

**Live row `b707f92f` (P0).** Merged tip `96f3768`: the whole sweep and the Phase 5 tooling are in (batch b9 green at 23:07, run by Rick with `!`).

| Next | Waits on |
|---|---|
| Close the sweep and Phase 5 Step 3/4 rows with receipts (`ed3a79c`, `96f3768`); remove the trial worktree `tiffany-trial-b9` and the two seat worktrees | next session (not done before lights out) |
| A Bash permission rule for the manager gate script, so a re-spun manager can gate | Rick (gate row `a6d3bd18`) |
| Two tests assert comment text, so `app_constants.dart` and `prompt_bodies.dart` are unswept | Rick, decision `a1bbc3ef` (recommend: convert the tests) |
| `lib/features/voice` does not compile, looks unused | Rick, decision `32aedd1c` (recommend: delete after checking reachability) |
| Phase 5 Step 1: 823 analyzer issues in 13 swept directories (code work); or hook fails on docs rules only | Rick, row `27a1d168` |
| Claim judge over pilot and sweep | Rick's D3, rows `9e0dd2dd`, `2847a900` |
| `ClaudeCodeRepository` posts to `/api/claude-code/submit` (reported retired) | bug `bdd60a1b`, unverified server-side |
| Post-game for the Clayton + Krishna crew | next session |

### Decisions Log — 2026-10-01 (session `fb9c89d0`, Tiffany)

- **Sweep started before the claim judge can run, with two workers; no more seats without Rick** (Rick, ask card 16:31).
- **A test that asserts comment text blocks its file, not the directory**: leave the file at base, do not edit the test, name the exception in the commit (manager; Rick to rule on `a1bbc3ef`).
- **Hook and CI cover only directories that pass `analyze --fatal-infos` today**, from `tool/data/gated_dirs.txt`; left-out directories listed with counts (manager, reversible; ungated at `2ccb028`).
- **A card answer does not clear an auto-mode denial.** Only the operator running the command, or a permission rule, does.

## ▶ Earlier: mobile docs track (2026-09-30 close, Tiffany 💍)

**Live row `b707f92f` (P0)**, lupin plan 1 §10a. M1 standard merged `0fe024e`; M0 analyzer half merged `55266af`.

| Next | Waits on |
|---|---|
| Confirm first-hand with Rick: M1 approved, drop the `dart format` gate, convert `lane_vocabulary_test` (relayed by María 21:50, unrecorded) | Rick |
| Record those in `src/docs/decisions/README.md`; flip the standard's Status line; staff the test conversion | Rick's confirm |
| M0 marker half (`dartdoc_lint.py --report`) | lupin Phase 1 |
| M2 pilot on `lib/features/holding_area/` (45 hits) | lupin Phases 1–2 |

### Decisions Log — 2026-09-30 (session `43b31a9d`, Tiffany)

- **D8 = zero undocumented public members per swept directory** (Rick, via María).
- **Seats commit on a detached HEAD; the manager lands by `merge --no-ff`.** A branch guard refuses branch creation in seats.

## ▶ v0.2.2 branch handoff (2026-09-30, Tiffany 💍, Rick's broadcast `0375db54`)

**Where we are.** `wip-v0.1.6-2026.04.16-tracking-lupin-work` is 445 commits ahead of `main`, all pushed; Rick merges it on the repo server. Last green suite: 2728 / 2 skipped / 0 failed at `bded008`; the `--fcm` APK was built there. No worktrees, no live crew.

**After the merge:** `git checkout main && git pull`, then `git checkout -b wip-v0.2.2-2026.09.30-tracking-lupin` (the name Rick gave). Wait for Rick's marching orders before starting new work.

| Thread | State | Next step |
|---|---|---|
| Transcript console `768e852f` (P1, only live store row) | Blocked on Rick | C5.18 recapture of `append_mixed_kinds` (needs the test admin env vars at seat start); C5.22 thinking stays pending-capture |
| FCM wake / WebSocket after wake | Wake-ups live; research answered | Read `src/rnd/2026.09.28-background-wake-socket-problem-statement-response.md` — it recommends (a) always notify + reconnect on tap, plus (c) an opt-in "live mode" foreground service. Needs Rick's go before any build |
| Mobile device_id + no reconnect on close 4004 `281a10d6` | Unstaffed | Mobile half of Mr. Radio's `dc446601` |
| Append mic rollout `cc4e73ed` | Most sites done (`c4e60ea`) | Notification sheet's mic |
| Stop-list undo defects `f27a61f4` | Open | Fixes listed under 09-27 below |
| Ask-audio contract fixture drift | Recurring | A permission rule for `test/fixtures/asr/ask_audio_ndjson_contract.json` would stop Rick running syncs by hand |
| Drawer route list duplicated from `home_screen.dart` | Follow-up | Extract a shared surface list |

**Stale remote branches** (safe to delete after the merge, Rick's call): `origin/feat/transcript-mobile` (its two commits were rebased into wip as `3cdbe32` and `bec7b4e`), `origin/feat/focus-p1-drawer-stoplist` (fully contained in wip).

**Rick's items** are unchanged from the dated sections below: the NDK 27 install, phone checks, and admit/drop rows `6f9c0fe4`, `1bc50bf5`, `61ecfb22`.

---

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

## 🆕 Open from 2026-09-28 (FCM wake live, tap-to-sender, notification controls, append mic)

### Decisions Log — 2026-09-28 (session `1b9a6410`, Tiffany)

- **Every APK build uses `--fcm`**; plain `deploy-apk-to-device.sh` installs the stamped server APK (CLAUDE.md, `5c62999`).
- **Keep the fingerprint lock** at cold start (Rick). The app now hosts in FlutterFragmentActivity so it actually works.
- **The wake notification title is WHO sent it**: "🌻 Maya", else the project, else "Lupin". The item's own title is no longer shown.
- **Background notifications OFF consume nothing**: no refresh, fetch or mark-played (gate-first). Denied priorities are never marked played.
- **The wake shows the oldest ALLOWED unplayed item** (list-based; client-side oldest-first sort; limit 500 until the server filter `e25f8868` exists).
- **WS supersede close code is 4004** "superseded" (4001 auth, 4003 subscription denied; with Mr. Radio).
- **The append mic is the default on every text box** (Rick). The rollout plan is `cc4e73ed`; the prompt card gets it in BOTH the Focus bubble and the notification sheet.
- **Rick chose a dev-only test admin account** for fixture capture (`f2f30810`, his to create); `768e852f` is blocked on him.
- **Pocholo's NDK install was allowed by Rick but refused by the permission layer**, so Rick runs it himself.
- **Owed work goes in tickets, not mementos** (Rick). Post-game: `src/rnd/2026.09.28-fcm-live-test-bug-chain-post-game.md`. Its proposed rule (mock network shapes from captured fixtures, not from memory) waits on Rick's word.

### ⏳ Owed — 2026-09-28

- [ ] **Rick:** create the dev test admin account `f2f30810`. It must pass both REST require_admin and the WS session_is_admin.
- [ ] **Rick:** `~/Android/Sdk/cmdline-tools/latest/bin/sdkmanager "ndk;27.0.12077973" "platforms;android-36"`, then verify `fix/compile-sdk-36-ndk-27` (22426f8).
- [ ] **Rick:** decide the wake backlog `6624dbc1` (show each vs one summary). The flood argues for a summary.
- [ ] **Merge if its gate passes:** Cheech's notification view `9cdd7b2` (P0 `7cac3a17`); Maya's prompt-card mic `c5c48e3`. Then the notification sheet's mic.
- [ ] **Unstaffed:** `281a10d6`, the mobile device_id plus not reconnecting on close 4004 (the mobile half of Mr. Radio's dc446601).
- [ ] **Unmerged:** `feat/transcript-dispatcher` (the 0fa608b rebase) and `feat/transcript-mobile-s4` `c310763` (the WS capture client).
- [ ] **Device repro for Mr. Radio's `ed76b897`**: app backgrounded, 2 sends 37 s apart, the trailing wake logs "submitted" and the second item plays.
- [ ] **Rick: drop the duplicate `1bc50bf5`** (folded into `0705bcce`).

## 🆕 Open from 2026-09-27 (transcript phase 3, drawer, phone deploy script)

### Decisions Log — 2026-09-27 (session `0fb2674f`, Tiffany, 5-seat SWE crew)

- **Slices merge by `merge --no-ff`, never squash, never a history rewrite.** To leave a held-back commit out, cherry-pick onto a new branch (done twice tonight: `-s3` and `focus-drawer-only`).
- **Coverage bar (ruling 10a):** ≥90% on every NEW file and on the lines a slice ADDS to a changed file. A changed file's older uncovered lines are not a breach.
- **Drawer header is "Surfaces"** (Rick, 20:53 EDT). The old drawer sits behind the injectable `FocusModeScreen.surfacesExperiment` switch, not a const.
- **Stop-list:** tapping the text edits, only the Checkbox toggles, and a colliding edit is refused (R2, R4).
- **`/coverage/` is gitignored** (Rick yes; `610f8c9`).
- **Rick added 2 seats** (5 total) for the stop-list and drawer.
- **The phone deploy script refuses a stale APK** unless `--allow-stale` is passed; the connect step times out at 10 s.

### ⏳ Owed — 2026-09-27

- [ ] **Rick: run `src/scripts/deploy-apk-to-device.sh` once from the laptop**, then close P0 `651e3956`. The APK is `f21b38c8`, built 21:55 at `bb8c72e`; the how-to is `tmp/install-apk-on-phone.md`. The script has never touched real hardware, so his run is the first real test.
- [ ] **Rick: phone checks** (`tmp/2026.09.28-phone-check-list.md`): New Task P0 `5e315760`, the edit button `8cc964ec`, the new drawer `c59457f0`, and a yes on the Submit button `4e936916` being fully visible. Already confirmed tonight: record button, mic hold, Files.
- [ ] **Stop-list `f27a61f4`:** fix the undo defects from Clayton's re-loop of `072fd40`. Invalidate or dismiss Undo on any other list change, make `insertAt` refuse duplicates, and add interleaved tests. Plan: `io/mementos/cheech.md`.
- [ ] **Phase 3 `768e852f`:** slice 4 (capture script plus 6 fixtures) and merging the held-back `0fa608b` (the dispatcher and C5.20). Both wait on Mr. Radio's server sending `cc_transcript_*`.
- [ ] **Follow-up:** the drawer's route list is copied from `home_screen.dart`, so extract a shared surface list before they drift. Also, `_load()` accepts duplicate stop patterns.
- [ ] **Rick: admit or drop `6f9c0fe4`** (stale AC-G2 fixture, 11 ids missing). It's being held.

## 🆕 Open from 2026-09-26 (Skeleton Shift)

### Decisions Log — 2026-09-26 (session `90e34e30`, Tiffany)

- **Row `e1e2c545` (the two re-spin doors read different memento files) stays with Mr. Radio.** Rick said yes: it's lupin tooling, not mobile work.
- **New Task is built now** (Rick, keypress): the phone card matches the web's `shared/task-create.js` field for field, including Project defaulting to `lupin`.
- **Test uploads are deleted after the check.** Rick's test JPEG was removed from `lupin/io` on his yes, following his ruling earlier that day that nothing temporary should accumulate in io.

### ⏳ Owed — 2026-09-26

- [ ] **Rick: close row `61ecfb22`** (doc viewer). It's parked, so only his login can close it. Evidence: `file_picker` built, installed and uploaded on his phone with no console errors.
- [ ] **Walk-through items 11-14**: the reply tally through the notification shade, backgrounding and navigation, then landscape. Item 10 (a real broadcast) passed on 09-26.
- [x] ✅ **New task creation** built on Rick's yes: row `b31a9ed9`, merged `30efd26` + `ce3fe8a`. Next: rebuild the APK and try it on the phone.

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
