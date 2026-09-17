# LUPIN MOBILE - SESSION HISTORY

## 📚 Archived Sessions

Older session entries have been archived for token-limit hygiene. See:
- **[2026-05-21-to-08-31-history.md](history/2026-05-21-to-08-31-history.md)** — notif-client sync, focus-mode milestone, v2 cutover waves, Quick Ask push-to-talk, the backup incident (archived 2026-09-16)
- **[2026-05-06-to-11-history.md](history/2026-05-06-to-11-history.md)** — voice-persona milestone Phases 0–5 + CC-dispatch retirement sync + yes/no/neither tri-state (9 entries, May 6–11, 2026; archived 2026-08-21)
- **[2026-04-17-to-24-history.md](history/2026-04-17-to-24-history.md)** — WS hookup → TTS overlap fix (5 sessions, Apr 17-24, 2026; archived 2026-05-11)
- **[2026-04-15-to-16-history.md](history/2026-04-15-to-16-history.md)** — Tier 1-4 buildout (5 sessions, Apr 15-16, 2026)
- **[2025-07-06-to-08-17-history.md](history/2025-07-06-to-08-17-history.md)** — Initial era (7 sessions, Jul 2025 – Aug 2025; project then dormant for 8 months)

Most recent entries (2026-09-01 onward) are retained below.

---

## 2026.09.17 | Session `7e82da5f` (Tiffany 💍) — Seven commits: the split screen made real, one capture core, and every live seat on the rail

**RESUME HERE**: everything below is committed locally and **not pushed**, and all of it waits on ONE device rebuild (`build-and-deploy-lupin-mobile.sh`). Also confirm `a2f1d75` on that same run — type a message to a seat and Mr. Radio closes lupin `80f10bdd` when the `:7999` log shows `POST /api/notify` with `direction=human_to_ai`. Open question for Rick: should the rail keep opening on the Live hour, or default to 24h?

1. **UI tweaks `4672ac2c`** (`bc98024`): password survives a failed sign-in (AuthGate no longer swaps the form for the spinner mid-attempt), 👁️ show/hide on the field, voice-reply row and buttons 60 dp.
2. **Phone→session messages `cfb8285`**: the composer now uses the browsers' `POST /api/notify` (`user_initiated_message`, `direction=human_to_ai`) instead of `/api/dm/send`, which framed the phone as a peer nobody could reply to (lupin `80f10bdd`). `/api/dm/send` removed from the phone; the frozen `focus_chat_bloc_test.dart` re-pinned by blob in `frozen_surface_test.dart`, reason recorded.
3. **Live hour is two-way `6dba6fc`**: a message YOU send bumps that sender's activity, so writing to a quiet seat pulls it back onto the rail. A failed send does not.
4. **Live-seat roster + refresh `cf5280a`**: cold start and a new toolbar refresh read `GET /api/commons/active-sessions` and merge every live seat in, even one that has never notified him — the reason he had to start conversations in the browser. Pairs with lupin `82b163b9` (Mr. Radio added `sender_id`).
5. **The 50/50 split, for real `91b2139`** (`2416d2c5`, `e0843a8a`): the first fix was a half-screen dialog, which cannot resize what is under it, so the bubbles stayed full width behind the document. `DocSplitHost` lays conversation and viewer out as equal halves — side by side ≥600 dp, stacked below.
6. **Who sent it, and their colour `d7aaacd`** (`de12b7bc`): the accent bar was keyed to PRIORITY (`high` = orange), so every sender looked like Mr. Radio; it now carries the sender's own colour. The pane header gains the persona name in bold, sender id italic.
7. **One capture core `fc8d9dc`** (`0b40272e`): there was no second recording engine — both composers already drove the same `AsrService`. The duplicated WRAPPER is now `VoiceCaptureSession` (permission, cancel epoch, error strings, blank-transcript guard), called by both. The focus review box moved from a shared 4-line row to full width with the buttons below; that cramped row was the "truncation".
8. **Audit `168922f9`**: revision 2 of the mux parity plan — six Stage-1 findings dropped, four softened, five rulings faithful, and the reuse citations nobody had checked verified at the plan's own commit. One count changed work (`wireSectionCollapse` is in eight renderers, not five). Closed by María's manager attestation; revisions 3–5 had already fixed two of the three recommendations.

**Files**: `lib/features/{auth,focus_mode,docs,notifications,quick_ask}/…` · `lib/services/asr/voice_capture_session.dart` (new) · `lib/features/docs/presentation/doc_split_host.dart` (new) · 5 new test files · `history.md` · `.claude-session.md` · commits `bc98024` `cfb8285` `6dba6fc` `cf5280a` `91b2139` `d7aaacd` `fc8d9dc` on `wip-v0.1.6-2026.04.16-tracking-lupin-work`. Suite after each: **1211 passed / 0 failed / 1 skipped**.

---

## 2026.09.16 | Session `b0157e13` (Tiffany 💍) — Recording bug closed, seven phone commits, the fleet demo clip filmed

**RESUME HERE**: Rick said **yes** (~21:44, for real, during the take) to building today's fixes onto his phone after the video. Next: he runs `build-and-deploy-lupin-mobile.sh` on the laptop, asks by voice in Quick Ask with *Send immediately* OFF, and pastes the `[HTTP] Request: POST` line — expect `/api/v2/transcribe`. That closes `c3fc62bf` with commit `a2f1d75`. Then María's audit `168922f9` waits on his admit.

1. **Recording bug `4be8fe63` closed** (`225bc8c`): capture diagnostics in the log (held vs recorded seconds, SHORT CAPTURE, INPUT DROPOUT on exact-zero runs) and kept recordings moved to app-internal storage where `adb run-as` can fetch them. Root causes were the emulator mic (no permission → silence → "Thank you."; then DC offset) and Whisper stopping at the first pause (fixed lupin-side, `05ddc8f0`). A 400 ms tail-drain wait was built and withdrawn — the evidence did not support it.
2. **UUID sent as email `588c8dc9`** (`a2cde69`): the cold start and FCM registration now get the user's email.
3. **Opus accuracy `9b1f7701`** (`5524acd`): 0.57% WER on 9 real phone clips, so questions record as Ogg/Opus 48 kHz / 32 kbps, WAV below API 29.
4. **46 red tests `5ac999f5`** (`fe731d1`): deleted `test/legacy_quarantine`, cosa contract tests find `../lupin/src/cosa`. Suite fully green; failing baseline is now empty.
5. **Bubbles 90% wide** (`c9a3375`) and **doc links in focus bubbles** (`ceebacc`, opens over half the screen).
6. **v2 transcribe** (`a2f1d75`, `c3fc62bf`): contract proven live (401 unauthenticated; 200 "What's 2 plus 2?" on a 9 KB .ogg); device check still owed.
7. **Fleet demo clip** (lupin `src/rnd/2026.09.16-fleet-demo-clip-workflow.md`): spun up 8 silent stand-by seats, played the closing yes/no beat across ~10 takes; Rick ruled narration after a line ruins a take (§3b). Final take a keeper; seats dismissed without mementos; my 2 evening worker seats donated to Mr. Radio.

**Files**: `history.md` · `history/2026-05-21-to-08-31-history.md` (new archive) · `TODO.md` · commits `225bc8c` `a2cde69` `5524acd` `fe731d1` `c9a3375` `ceebacc` `a2f1d75` on `wip-v0.1.6-2026.04.16-tracking-lupin-work`

---

## 2026.09.15 | Session `71d94067` (Tiffany 💍) — Device-session build shipped, six fold-laters merged, release-picker reversal ruled

**RESUME HERE**: the release-picker flip is on branch `tiffany/release-picker` off `a349f0a`, and its row `2070a906` is still in the holding area waiting on Rick's admit. Both device rows (`c51e92da`, `9b1f7701`) remain parked on his laptop and handset.

1. **Device-session build merged** on `77b86b7`: the Settings→Debug network round-trip probe, the "Keep voice recordings" switch, and the LAN DEV / LAN TEST server switch on the sign-in screen. Script written at `src/rnd/2026.09.15-phone-device-session-script.md`. The switch was reviewed twice; the first review returned a BLOCK, which was fixed before merge.
2. **Six fold-laters merged** as `a349f0a` (row `8d9b2a0c`): the shared Dio baseUrl now set at registration, a dead event removed, the toggle re-subscribes on `didUpdateWidget`, recording names moved to UTC so a restart cannot collide, the probe's `unknown_length` branch covered through a real request, and the server switch gated to non-release builds. Suite 1100 pass / 1 fail / 46 known — the old "1071 pass" baseline was stale, the untouched tip is 1083.
3. **That release gate was then reversed by Rick** at ~20:39: the sign-in screen is the only pre-auth surface, since Settings sits behind `AuthGate`, so hiding the switch in release strands any phone installing a CI artifact at the emulator-only `10.0.2.2`. Filed as bug `2070a906`; builder staffed to flip it back and invert the `ca07b57` tests.
4. **Laptop build diagnosed**: JDK 25.0.3 against Gradle 8.12. Flutter 3.32 caps Gradle at 8.12 / AGP 8.7.3 — exactly our pins — and AGP 9.4.0 still lists JDK 17, so no upgrade path reaches 25. Written up in `src/rnd/2026.09.15-jdk-gradle-flutter-compatibility.md`, linked from the README; the recommendation is JDK 21 plus `flutter config --jdk-dir`, no repo change.
5. **rsync fixed**: `src/scripts/rsync-lupin-mobile.sh` now excludes `.claude/` and `io/`. The sync was carrying 878 MB of agent worktrees; it is 29 MB now. The laptop needs a one-time `rm -rf` of those two paths, because rsync never deletes what it excludes.

**Files**: `README.md` · `src/scripts/rsync-lupin-mobile.sh` · `src/rnd/2026.09.15-jdk-gradle-flutter-compatibility.md` · `src/rnd/2026.09.15-phone-device-session-script.md` · merges `77b86b7`, `a349f0a` on `wip-v0.1.6-2026.04.16-tracking-lupin-work` · nothing pushed

---

## 2026.09.15 evening | Session `71d94067` (Tiffany 💍) — Two merges, four reviews, and one defect shape that kept reappearing

**RESUME HERE**: both device rows are queued and wait only on Rick recording about ten voice memos — no device session, no emulator and no working laptop build are needed. Krishna's row `0b3f063a` is queued and approved with two open nits.

1. **Release picker merged** `dcc7263`. A context clear left a builder alive that I did not know about, so two independent implementations arrived for one bug; a reviewer ruled between them and found a third way to hide the picker — `bool.fromEnvironment("dart.vm.product")` — that escaped every assertion on both branches. The tests now strip comments before grepping, so the docstring can finally name the constant it warns against.
2. **Quick Ask overflow merged** `82c97cc`, nine commits, after **three review rounds that each found a real defect**: a question arriving post-scroll was never rendered; the re-anchor fixing that landed short on short cards; and the tests could not see either because all four used one content shape. Filed figures were wrong — prompt-plus-error is 114px, not 82, and an ordinary 360×640 phone clipped by 2px, voiding the P3 reasoning.
3. **JDK 21 proven, not just recommended**: a worker built a real debug APK end to end. Rick's own `flutter doctor -v` then killed his own JBR proposal and my stale research row — **Android Studio 2026.1 bundles JBR 25.0.3**, the very Java breaking his build. Corrected in `ac880d2`. Flutter 3.35.1 was investigated and changes nothing: its Gradle cap is identical.
4. **Peer reviews delivered**: Mr. Radio's janitor fix approved with nits (the summary card still made the false claim his commit was named after); Krishna's visual-normalizer fix blocked, reworked, then approved across 31 mutants.
5. **The through-line, worth more than any single fix**: five separate findings tonight were all **a check whose success condition is weaker than the claim it supports** — a dead selector, a stub that never ran its JS, a shared id resolving on the wrong page, a control that re-implemented its checker, and a measurement that was incomplete rather than mistaken.

**Files**: `src/rnd/2026.09.15-android-toolchain-briefing-for-outside-review.md` (new) · `src/rnd/2026.09.15-jdk-gradle-flutter-compatibility.md` · `README.md` · merges `dcc7263`, `82c97cc` · commits `6a07f64`, `ac880d2` · nothing pushed

---

## 2026.09.14 | Session `b3e285b8` (Tiffany 💍) — Spoken-ask door built and merged: §B `83f19a7`, §C `16d73f8`

**RESUME HERE**: the phone half of the spoken-ask door is merged on wip. At 09:00 on 09-15 Rick gives a device session for `c51e92da` (round-trip probe) and `9b1f7701` (Opus/AAC check). See TODO.md § Owed.

1. **Build go** 15:48 (`ccd7d20e`), conditional on rev 13. Sam folded rev 13 and Chloé verified it 13/13 (`7a6ca84`); revs 14–19 were folded while the build ran.
2. **Staffed two builders** from Rick's seat grant: Rachel on §B (5 commits) and Maya on §C (5 commits), each in its own worktree after the spawn dropped both into the main tree. Every handoff was pinned to a sha and checked on disk; the contract fixture blob `5b2ae802` was byte-identical across lupin → phone.
3. **Merged**: `83f19a7` and `16d73f8` (`--no-ff`, commit `-F`). `git diff d867576 HEAD -- lib test` is empty, and Mr. Radio verified it independently. Tests: the same 46 already failing before and after, 1030 passing, 72 of them new. §A merged in lupin (`993be2b6`).
4. **Filed**: `5ac999f5` (46 pre-existing failures) and `9cddb791` (320×568 overflow, 10/82px). Rick kept both.
5. **Post-game** (María): 6 own misses posted, including a duplicate María spawn, a hold file written where the hook never reads, and a reap run in the same batch as the memento edit it cited. Q4 was measured: the hold was ignored because of its location, not its fields. R2's wording was extended to cover claims carried in another call's arguments.

**Files**: `TODO.md` · `history.md` · merges on `wip-v0.1.6-2026.04.16-tracking-lupin-work` · memory `never-ask-rick-about-push.md`

---

## 2026.09.11 | Session `afe9bfdc` (Tiffany 💍) — Cascaded review closed; plan rev 8 → rev 12, nothing built

**RESUME HERE**: plan rev 12 committed `2def6e4` (sha256 `ccc0430b`, 646 lines); six pins in git. Nine-stage cascade closed plus two verification passes folded. **Nothing built** — Rick's plan-only ruling held all session, and he declined a build at 22:39.

1. **Cascade closed, 9/9 stages, 0 escalations, 0 votes.** Every finding folded across five committed revisions. The resumption point is task row `9df9f1c2` plus memento `38e7a298`.
2. **Verification found what the cascade could not.** Rev 9 scored 19 PASS / 1 FAIL; rev 10 scored 3 PASS / 4 FAIL. Both passes surfaced defects introduced *by the folds themselves* — a population no findings-checklist covers by construction.
3. **Five over-claims retracted**, mine and the manager's, each caught by re-measuring rather than trusting a summary. Rules earned: *a self-inconsistent file hashes perfectly* · *renumbering a list edits every reference to it* · *"same" is positional* · *a durable record needs revising when the world moves, not only when the work does*.
4. **Rev 13 is owed and held** — 11 items, framed as a **list-to-verify, not a list-to-apply**: measured at rev 11 against a rev-12 head, so coordinates have drifted ~49 lines.
5. **Five items parked on Rick**, chase 09:00 — build go/no-go `ccd7d20e` (answered *no* tonight), CB4's ruling `7b5458f5`, seat restart `79c4ad06`, and approval of `c51e92da` + `9b1f7701`, the last two being `9df9f1c2`'s own closing condition.

**Checkpoint**: rev 12 committed + manager-verified; row `9df9f1c2` reassigned to Mr. Radio with receipt (event `13786`); memento final `38e7a298`, record ≡ mirror; seat handed off at ~89% context.

**Files**: `src/rnd/2026.09.11-spoken-ask-streamed-door-implementation-plan.md` · `src/rnd/2026.09.11-voice-one-leg-ask-decision-brief.md` · `.claude-memento-tiffany-afe9bfdc.md` · `TODO.md` · `history.md`

**Detail**: task row `9df9f1c2` (all findings, rulings, parked items) · `projects-data/lupin/cascade-pins/` (reviewer findings files, fold queue, per-rev pins)

---

## 2026.09.08 | Session `a08d762c` (Tiffany 💍) — Abstracts render as markdown; doc links open in-app

**One commit `756ae43`, 69 new tests, suite 882 → 951 passing.** Analyze clean on every touched file.

A notification's `abstract` was rendered with a plain `Text` widget, so the markdown the fleet
already writes into it showed as literal brackets and parens and the doc links were dead. Now a
null/empty abstract renders nothing (unchanged), a present one renders formatted inline, and a doc
link inside it is tappable and opens the target in-app.

**The finding that shrank the job**: `GET /api/docs/file` returns RAW source text over the shared
Dio that already injects the Bearer token. No WebView, no second auth path, no backend change — the
expensive design (embed the Lupin SPA in a browser view) was never the design we needed.

| Phase | What landed |
|---|---|
| P1 | `flutter_markdown` → `flutter_markdown_plus`. Google discontinued the former 2025-05-30; we shipped it until today. Pinned 1.0.7 (not 1.0.12 — ≥1.0.8 needs Dart 3.9, toolchain is 3.8.0). New pure parser `doc_link.dart` + `doc_models.dart`. |
| P2 | `DocRepository` dispatching on content-type rather than file extension (a directory has no extension) + `DocViewerScreen` for markdown / source / image. Server refusals surface verbatim. |
| P3 | `AbstractBody` wired into both conversation card screens, with a document icon badge shown only when a *fetchable* link is present. |

**Rick's amendment**: modern link format only. A legacy `?scope=` link classifies `unknown` and
renders inert rather than being rewritten — the backend 400s on that parameter, so a tap would offer
a guaranteed failure. Detected explicitly so it stays a decision someone can find and reverse.

**Two defects the tests caught**: `DocViewerScreen`'s `FutureBuilder` did not subscribe until the
next frame, so a fast rejection escaped as an unhandled async error instead of reaching the error
view (replaced with explicit load state); and `setState()` was handed a closure returning a Future.

The 46 pre-existing suite failures are unchanged and identical test-for-test — 44 in
`legacy_quarantine/`, 2 requiring a sibling `../cosa` checkout this standalone clone lacks.

**Session end**: Rick scoped P4 down to the two loose ends and `2e8d02c` closed them — the
external-link confirm, which had shipped with zero tests, now has 7 (with `url_launcher` mocked at
its MethodChannel, so they assert what the platform was actually *asked* to do); and `flutter_html`
was removed, having been added and imported nowhere. The `.html` and directory renderers stay
descoped until a real abstract links one; both degrade to a readable source view.

**Final**: 76 new tests, suite 882 → **958 passing**, 46 pre-existing failures unchanged
test-for-test. Ticket `2df54cf6` closed with receipts. **Pushed** — `a55ed01..2e8d02c`, verified
0 ahead of origin.

One finding worth carrying: tapping a markdown link *embedded in prose* needs
`tester.tapOnText( find.textRange.ofSubstring(...) )`. `find.textContaining` returns the whole
paragraph, whose centre is the surrounding words rather than the link span, so a test written the
obvious way passes for the wrong reason.

Docs: `src/rnd/2026.09.08-abstract-doc-link-viewer-feasibility.md`,
`src/rnd/2026.09.08-abstract-doc-link-viewer-implementation-plan.md`.

---

## 2026.09.04 | Session `3d7921bc` (Tiffany 💍) — Quick Ask shipped three fixes; the cache bug I found was filed, not taken

**Five commits, 220/220 green** (was 130 at session start), analyze clean on every touched file.

| commit | what |
|---|---|
| `1ee125b` | Quick Ask tap-to-toggle recording with a deliberate send (15 files) |
| `32c7980` | card dismiss X, cancelling the job if it is still running (8 files) |
| `153ac19` | inject `isQuickAskJob` so answers speak in full — DI registration extracted to `ServiceLocator.buildFocusChatBloc()` so the seam is testable without `path_provider` |
| `649f458` | a progress notification is not the answer — belt channel guards on `n.type`, `QuickAskEntry.progressText`, spinner + muted status line rendered LAST so an answer outranks a stale milestone |
| `ff2e90c` | the long-running-jobs plan doc (507 lines) + README entry, on Rick's ruling |

Both behaviour commits were mutation-checked, not just run.

**The plan doc's bottom line corrects its own premise.** It is not "build a notification pane" — it is a **cap change**. All eleven agentic builders were checked: **10 of 11 already emit a per-job sender id**, so focus mode's sender-keyed windows already group by job; `claude_code` is the sole exception. What actually needs doing is revealing the `ask.flow` bucket the persona-less default rail scope hides, raising the per-sender cap of 7 (right for a chatty human, wrong for a job emitting ~10 milestones), and queuing the second interrupt. Two of my own mid-plan mechanisms are logged as wrong in its §11: `progress_group_id` is not the job key, and job grouping did not need building.

**A cache defect found, filed, and handed off — what I got wrong was the timing.** While chasing Rick's paraphrase-replay report I measured 5,028 trace records and found **103 PERFECT (100.0) cache matches refused and re-run as fresh jobs**. `_may_serve` (`flow.py:1099`) serves only on `answer_is_correct is True` and fails closed at None; **every refusal reads `:None`, not one `:False`** — nobody is ever asked, because the only confirmation sought lands on a daemon thread that times out. V1 (`todo_fifo_queue.py:534-640`, still present, not deleted) auto-accepted >=100 with no gate and asked the 90-band with 3 retries and backoff. Both V2 behaviours are regressions, and Rick diagnosed both from observable behaviour before either file was opened.

Filed as `fe1c0d3f`, reassigned to **Pocholo** with **Mr Radio** accountable, on Rick's instruction: *"file that as a bug and have someone else look into it, it's not your job to edit the Lupin repo."* I stayed read-only throughout, which was right — **but I should have found an owner at filing time instead of working the row for another ten minutes.**

**Rick corrected his own ruling and the row carries both readings.** First *"restore what version 1 did"*, then immediately: *"I don't need to restore V1 verbatim — I mean use the logic, or copy the logic, that V1 uses. Do NOT resuscitate V1. Do not!"* Amended under `user_direct` and relayed to Pocholo and Mr Radio, who had been about to route it back to Rick as an open proposal.

**Six of my hypotheses died today, every one refuted by someone checking recorded state.** tier-1 floor as mechanism · `_may_serve` as Rick's cause · silent exits as the diagnostic gap · "no score on this path" · `snapshotable` explaining `usage_count` · `confirmation_threshold is None`. The largest withdrawal: I argued "286 asks cleared the 90.0 bar and only 1 ever replayed, so the funnel is blocked downstream." Pocholo established that **`_near_match_replay` postdates the trace corpus** — those asks had no branch to traverse. **You cannot measure a gate on traffic that predates it.** Whether 90.0 is the right bar is open again. Every one of the six was reasoning forward from source; every refutation was measurement.

**🔴 An error at the wrap, recorded because a dropped row is easy to lose.** I dropped `3658ec66` — Pocholo's row, Mr Radio accountable — on standing authority. Mr Radio had already ruled it queued at 00:14Z; his DM reply reached me **condensed** as "not within my team's responsibility," which I read as a drop instruction when he almost certainly meant his crew were not working it during the wrap. `dropped` is terminal, so the correction is a post-terminal amendment on the row and reinstatement is his call. **The failure was not the misreading — `task_get` returned his full ruling to me seconds before I called the transition and I acted on the DM summary instead of the row I was acting on.** Same shape as the six above: a condensed secondhand account beat the recorded state that was already in my hands.

**Session ran through two self-respins** at the 50% context line, both clean — memento written, nonce verified, wake proof confirmed against `claude_code.session_id` rather than introspection.

**Files**: `lib/features/quick_ask/**`, `lib/features/focus_mode/domain/focus_chat_bloc.dart`, `lib/core/di/service_locator.dart`, `lib/core/testing/test_keys.dart`, `test/unit/quick_ask/**`, `test/widget/quick_ask/**`, `test/service_integration/quick_ask_probe_wiring_test.dart`, `src/rnd/2026.09.04-long-running-quick-ask-notification-pane.md`, `README.md`

---

## 2026.09.01 | Session `5b101cc5` (Tiffany 💍) — the backup was 99% Flutter SDK, and the bounce we were waiting on had already happened

**Backup fixed twice, then verified.** The 2026-08-30 fix corrected `SOURCE_DIR` but left `DEST_DIR` naming the retired subtree `lupin/src/lupin-mobile/`; repointed to the standalone mirror `projects/lupin-mobile/` (`1da5b72`). The first green dry run then turned out to be backing up the wrong thing: `flutter/` is a vendored 1.9 GB SDK clone, gitignored and re-obtainable, and the exclusion file was the generic Python list shipped with the canonical script — it knows `.venv/` and `build/` and nothing about Dart. Added `flutter/`, `.flutter/`, `.dart_tool/`, `.flutter-plugins*`, `.gradle/` (`717e94c`). **1.79 GB / 20,433 files → 6.22 MB / 794.**

**Verified rather than assumed.** Diffed `git ls-files` (532) against rsync's own `--out-format='%n'` list: 530 of 532 tracked files reach the mirror, the two absent being `.gitignore` and `android/.gitignore`, caught by the canonical list's own pattern. Rick ran the cleanup `rm` (858 MB → 47 MB) and then the `--write` run; walked all 532 against the destination filesystem afterwards — **missing: 0**. One residue noted: the destination's root `.gitignore` is a stale April copy, since rsync neither updates nor deletes excluded files on the receiving side.

**Two stale facts corrected** (`9f175bd`, `ce6e218`). `TODO.md` carried "bounce `:7999` first" as the next action; measured, the container had started 2026-09-01 23:13 UTC with both fixes (`c91bd1bb`, `7aac0061`, merged 2026-08-30) already ancestors of the served HEAD, over a live `/src` bind-mount — **a bounce would have changed nothing.** And I had twice told Rick row `734bd1bf` was "blocked on you at the mic"; it had not been since its 2026-08-31 amendment.

**`734bd1bf` (AC-G3) CLOSED — worked server-side, handed off, settled.** Ran `test_9b_the_read_guard.py` (14 passed, incl. "a confirmed exact hit is still served"), eliminating `_may_serve` as the explanation for Rick's probe. `path`/`route_reason` turned out to already ship in the response body (`_finish` → `_emit`); the web Q&A UI just does not surface them. Found `test_v2_ask_roundtrip.py`'s strict-xfail exit condition unreachable — it never confirms its answer, so a free consumer is necessary but not sufficient. **Two self-corrections**: my two-ask remedy hit the same drain wall on `:8000`, and my "seed a snapshot row" spec was half-written — tier 1 queries the *canonical-synonym* table, so a bare snapshot is unfindable. Rick ruled implementation is not a mobile seat's job; Mr Radio 🦉 ruled the relay was lossy and sent me to **Rio ⚡ direct** (spec carried search-strings, no line numbers — the lupin tree moved three times in the hour).

**Rio's version beat the spec twice.** He used `V2Cache.write_back()` (both writes, normalizer-computed fields — my drift warning made structurally moot), added a **negative arm** I failed to specify, and checked `replayed_snapshot_id` against the seed. `ts-fee0022f`: confirmed row → `path=replay`/`exact_hit`/`cache_hit=True`; unconfirmed → `path=agent`. **That negative arm killed the two-day ambiguity without the trace field I insisted was needed** — a refusal is visible from outside on a question the cache demonstrably holds. Row closed with receipts. He then fixed the roundtrip docstring, again better than instructed: rather than naming both blockers on both tests, he checked which test needs which (`ts-cdba4e5e`, 4 passed, 2 xfails holding). Nine amendments on the row carry the full trail.

**Files**: `src/scripts/backup.sh`, `src/scripts/conf/rsync-exclude.txt`, `TODO.md`, `history.md`

---
