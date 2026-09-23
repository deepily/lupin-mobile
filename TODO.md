# TODO

Last updated: 2026-09-20 (Session `cc9c1f1a` — Tiffany 💍, manager on duty): **nine merges, pushed and backed up on Rick's 22:55 ritual order.** Rick ruled every open gate: both held rows admitted, batch won't-fix keeps no confirm (matching web), and the phone probe `c51e92da` **PARKED to 2026-10-19 — he has no cell service and no public IP for at least a month and told the fleet to stop asking. Do not re-raise it.** His own P0 `72e01fb3` closed on receipts against the tree. Sam's roster addressability guard merged (`488f189`, 71/71 green). Phase 5 is blocked on a SERVER defect Chloé traced — `commons_broadcast_ack` appears never to persist, so the ack drain can never contain acks. Three of my own rows were corrected by workers before a line was written.
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
- **[2026-04-15-to-06-12-todo.md](todo-archive/2026-04-15-to-06-12-todo.md)** — postgame decisions (2026-06-12), ✅ COMPLETED blocks (05-23, 06-12), 2026-05-07 breadcrumb, superseded voice-persona HUMAN-gate runbook, 2026-05-21 parked conditionals, all completed `[x]` items through 2026-08-21. Archived 2026-08-21.

## 🆕 Open from 2026-09-20 (the build night: five phases merged)

### Decisions Log — 2026-09-20 (session `cc9c1f1a`, Tiffany managing)

- **Source beats spec text wherever they disagree.** Applied twice against my own task items, both caught before a line was written: `FINISHED_DEFAULT_SHOWN = ["done"]` (dropped is dark too), and priority-before-status with terminal rows **filtered, not sorted** — the latter is Rick's own 2026-09-09 ruling, which names **both clients**, so it lands on mobile by his instruction and not by default.
- **The grouping key stays whole `created_by`**, unsplit, compared as an opaque string. Rachel's capture of 344 live rows contains **two-word personas** and **actors with no session id**; any splitter decides silently on every row and fails by quietly fragmenting or merging groups.
- **Eight facts survive at 360 dp; the single-row packing does not.** Fleet Status renders three bands. The requirement was legibility, not a row shape.
- **Detail opens a route rather than revealing in place** — opening a route **moves focus**, so a screen-reader user is carried to the detail and hears it.
- **No client-side clamp on the fleet-size cap.** The ceiling is read at call time, so a constant in the client would drift from what is enforced, silently.
- **Merge the shared base freely; never fix a defect found in it inside your own branch.** Report it and it lands once, for all four panes. Issued after a near-miss, and it closed a full loop within five minutes when Rachel found `_provenance()` missing `actor`.
- **Analyzer exclusions are justified by a measured number, not a category name.** "Generated code" ends an argument; "hides 7744, none ours" invites one. `build/**` is kept and labelled honestly as a claim about the future rather than a measured saving.

### ⏳ Owed — 2026-09-20 — **ALL FOUR CLOSED as of 2026-09-22**

1. ~~**Push.**~~ ✅ Done at his 22:55 ritual order on 09-20. This line was stale for two days — a list that carries a done item as owed teaches its reader to skim.
2. ~~**Admit `384591dd` Phase 5 Broadcast**~~ ✅ He admitted it. The row is now `queued`, unblocked, with its acceptance clause settled (see 09-22 below).
3. ~~**The phone confirm on batch won't-fix**~~ ✅ Ruled: keeps NO confirm, matching web. Closed.
4. ~~**Untracking `android/local.properties`**~~ ✅ **Done 2026-09-22** on Rick's keypress, `git rm --cached`. The measurement that had been missing: it was tracked AND already listed at `android/.gitignore:6` — the ignore never bit because the file reached the index first, which is the entire reason it kept churning. Index-only change; the file stays on disk and the SDK still resolves (Flutter 3.32.0 verified after).

---

## 🆕 Open from 2026-09-22 (skeleton crew: one P2 driven to merge, one P0 closed)

### Decisions Log — 2026-09-22 (session `f19a8996`, Tiffany, manager on duty)

- **Skeleton crew means NO workers** (Rick, by keypress, ~14:35Z): *"by definition skeleton crew means no workers So that's how we're going to run it today until 5 o'clock."* The fleet cap (2, against 3 live managers) had already refused my spawn — its own error text says *"a manager with no seat to spare works its own tickets."*
- 🔴 **CORRECTION, same day ~16:10Z — I had the second half of that rule wrong.** I recorded manage-not-build as *"waived by him for `c597c4fc` only"*, i.e. a one-off. It is not. Rick: *"All managers can perform implementation when they're on Skeleton Crew So you must have misunderstood what Skeleton Crew implies That's the way we work every day before 5 o'clock in the afternoon."* **Skeleton crew is the STANDING weekday mode before 17:00, and in it a manager implements its own rows without asking for a waiver each time.** The error mattered: it is why I listed Phase 5 as "needs a seat" and offered staffing it back to him as a decision, when the answer was that I am the seat.
- **A reviewer beats a waiver.** I recommended merging `c597c4fc` with the independent review downgraded to a follow-up check, arguing the mutation proof already answered what a reviewer would take on trust. **He declined and assigned María. She found the mutation proof could not fail.** Had he taken my recommendation, a hollow control would have merged wearing a green tick.
- **An author's run receipt counts when the reviewer who demanded it accepts it** (Rick, by keypress, after asking to be walked through it). That was the narrow question; everything else on the row was closed.
- **A `[default used]` answer is silence, not a ruling.** My first merge ask timed out and returned `[default used] no`. Recorded as silence in both directions — not permission, not refusal. The row was re-asked rather than resolved on a non-event.
- **Reconcile a changed count, never round past it.** The suite read 1583 on the branch and 1586 on the merge result. First suspicion (Sam's worktree-skip finding) was wrong; the branch simply predates `488f189`. 1578 + 3 + 5 = 1586, exactly.
- 🔴 **A PANE TEST AND A DISPATCH TEST ARE NOT THE SAME COVERAGE, AND I HAD BOTH GAPS** (post-re-spin audit, Rick asked whether widget testing was complete). Enumerated rather than recalled: **`PaneHostScreen` had zero tests of any kind** — the wrapper two of the five surfaces depend on, with three stated contracts and nothing checking them — and **the ack dispatch seam at `app.dart:132-137` had none either**, because every broadcast test dispatches `BroadcastAckReceived` by hand. Both filled, both mutation-proved (`pane_host_screen_test.dart` 4/4, `broadcast_ack_dispatch_test.dart` 5/5; suite 1586 → **1667**). ⇒ The lesson is the one this feature keeps teaching: **unit tests either side of a seam are structurally incapable of failing on the seam.**
- 🔴 **"ANALYZER CLEAN" WAS WRONG AS I STATED IT.** `./flutter.sh analyze` reports **978 issues — 244 errors, 98 warnings, 636 info** — all pre-existing, concentrated in `lib/core/**` scaffolding outside the app's compile graph, none touched by the 15 unpushed commits. What I should have written is *"clean on the files I touched."* ⚠️ The cost is not runtime: **a project reporting 978 issues cannot use the analyzer as a gate**, so a new error arrives pre-camouflaged.
- ⚠️ **TWO SELF-INFLICTED TEST-HARNESS LESSONS, both mine today.** (1) `addTearDown( cubit.close )` on an instance the `BlocProvider` also closes is a **second** close and deadlocks in a `testWidgets` body — five minutes at `+0` before elimination found it. (2) Two concurrent `flutter test` runs in one tree share `.dart_tool/` and both stalled; I then **read their `exit 0` as a result when I had killed them myself**. A kill that reports success is indistinguishable from a pass if you only read the exit code.

### 🔴 RICK AFK — DEADLINES AND THE THREE DELIVERABLES (broadcast `7d802286`, 2026-09-22 ~22:05 EDT)

**His words**: *"Managers @Tiffany @maria and @mr radio — set your timers for 10:45 as a 15 minutes to wrap-up signal and 11 o'clock for an end-of-session ritual. Each one of you managers will give me a push and a backup. I remember one of you guys forgot it last time, so make a note: it's a push AND a backup for every one of you managers I just mentioned."*

- [ ] **22:45 EDT — T-15 wrap-up signal.** Safe checkpoint, no new work, tree green, tracking docs current.
- [ ] **23:00 EDT — end-of-session ritual.** 🔴 **THREE deliverables, and the third is the one that gets forgotten: COMMIT · PUSH · BACKUP.**
  - ✅ **THE PUSH IS AUTHORISED BY THIS BROADCAST.** This is Rick's word, so it is not asked for and not skipped. 15+ commits go out.
  - ⚠️ **A dry-run backup is NOT a backup** — it needs the write mode.
  - `history.md` still has **no 09-22 entry**; that is ritual work and it is owed.

**Timers installed, both halves** — cron detects, a live session acts:
| Instrument | Covers | Dies when |
|---|---|---|
| CronCreate `fc109b33` (22:45) + `3a47b2de` (23:00) | wakes **this seat** to actually run it | the session exits |
| Detached `setsid` backstop, PID 1684144, `scratchpad/tiffany-deadline-backstop.sh` | **notifies Rick** at both times if this seat is gone | machine reboot |

⇒ The backstop does **not** run the ritual — it makes a dead seat visible instead of silent. If Rick gets the backstop message instead of my receipts, the ritual has not run.

### 🆕 Walk-through round 2 — Rick on the emulator, 2026-09-22 ~21:00 EDT

- [x] **Item 7 Finished Tasks spinner — ✅ FIXED.** Nothing ever dispatched the first load; `FinishedTasksScreen` was a `StatelessWidget` and every dispatcher was user-initiated. 🔴 **Rick's log was the evidence — it carried `/api/tasks` and NO `/api/tasks/events` at all**, so the fetch never happened rather than failed. Fixed to `StatefulWidget` + `initState`. Guard `finished_tasks_first_load_test.dart` (3 cases) mounted **as production mounts it**; mutation removed the dispatch → **all 3 new died, the original 15 stayed green.** Suite 1670 → **1673**.
  - ⚠️ **Why 15 tests missed it**: `_host()` builds the bloc as `..add( const FinishedTasksRequested() )`. **The harness sent the event production never sent.**
- [x] **Trust Dashboard hidden — ✅ DONE** (Rick's order). It had **two** doors, the card *and* an app-bar shield; both behind `_kShowTrustDashboard = false`. A flag, not a deletion — screen, bloc and its 3 tests still pass. Guard `trust_dashboard_hidden_test.dart` paired with the flag. 🔴 **My first version of that guard could not fail** — it dragged past the card, which disposes it in a lazy `ListView`. Mutation caught it; fixed with a tall viewport + a precondition.
- [x] **`--push-only` on the build script — ✅ DONE.** Skips rsync and build, installs the APK on disk, prints its timestamp ("I re-pushed and my change isn't there" is the failure it invites). Four paths verified incl. unknown-flag exit 2.
- [x] **`io/` in `.gitignore` — ✅ DONE** (Rick's ruling). Never was committed: `git ls-files io/` 0, `git log --all -- io/` empty.
- [x] **Work plan for the ten findings — ✅ WRITTEN**, `src/rnd/2026.09.22-walkthrough-findings-work-plan.md`, row `488ea102`, reviewed by María.
- [ ] 🔴 **B1 Fleet Status perpetual spinner** — highest priority, a whole accordion unusable. **B1b (debug line) FIRST** on María's order: it is the only item that can say whether Rick's spinner is the defect found or another still unidentified. Then both cancel fixes (data-in-hand emits the composite, no-data keeps returning) and **two** tests.
  - 🔴 **I WITHDREW MY OWN CAUSAL CLAIM.** I wrote "nothing retries"; verified false at `pane_polling_mixin.dart:96-107` — a lifecycle cancel **self-heals** on resume. So the mechanism probably does not explain what he saw. **Second time today I attached a true observation to the wrong mechanism.**
- [ ] **N1 Broadcast recipient picker** — biggest item. He cannot address a subset today; without it "this broadcast does have no use to me". ⚠️ **Gated on one question: does the endpoint accept a recipient list at all?** Ask before building, or the picker's selection is discarded.
- [ ] **M1 summary headline** — ✅ spec found, and **the rule is conditional**: `parked > 0` → `Live: L · Parked: P · Total: L+P`; `parked <= 0` → **`Live: L` alone**, not `L` and not a zero-padded triple (`notifications.js:11189-11207`). *"LIVE is unconditional; the parked split is not"* — the split is a disclosure that earns its space only when there is something to disclose. Parked is excluded from live deliberately: *"counting them alongside live work makes the remaining-work figure fiction."*
- [ ] **M4 new-task stub · B3 left padding** — cheap, independent, no rulings. ⚠️ B3's padding is not free: ~90 dp for the title at 360 dp, so measure at 360, do not eyeball at 800.
- [ ] **M3 search** — 🔴 **NOT A FILTER, and both options I offered Rick were wrong.** It is a paste-a-hash **lookup box** (`multiplexer/render/taskLookupBox.ts`). His words in that source: *"Every time someone refers to a row for a ticket by # I have no idea what they're talking about."* Three pinned constraints: (1) **must** hit `/api/tasks/<ref>`, **never** `/api/tasks?id_prefix=` — the query form chains an owed filter and hides held rows, **measured: 1 of 23 findable**; (2) a **result card**, not scroll-to-row, because the hashes he is handed are usually for rows NOT on his board; (3) **the status is part of the answer** — a held row without its status reads as an ordinary queued ticket. URL built by `shared/task-lookup.js`; **do not inline the path**.
- [ ] **M2 row-editor display toggle** — ✅ **ANSWERED FROM SOURCE: the `⋯` ellipsis disclosure**, and it is **Rick's own spec** quoted in `rowDisclosure.ts`: *"an ellipsis right-justified ON THE TITLE LINE indicating hidden functionality; clicking it discloses the controls as ONE narrow row spanning the full width of the item; that second row is NOT displayed by default."* Glyph `⋯` U+22EF, title "Show row controls". Behind it: Blocked by · Next chase · Accountable · Filed by · Project + nine controls. 🔴 **State lives in `aria-expanded` AND the `hidden` attribute — BOTH required**; keeping one makes it either unreachable by keyboard or never painted.
- [x] **Polling optimisation `de509b51` — ✅ RULED by Rick: "Leave it refreshing."** Option (a) **declined, not deferred**. Row closed on `{doc_path, manager_attestation}`; the comment correction was the whole delivery, comment-only, 58 tests green.
- 🔴 **PROCESS LESSON, and it cost him four interruptions.** He asked to be walked through the questions; I gave him a menu, re-fired the same form, then went off to read source **while he waited**. *"Take advantage of the fact that you have my attention now. Don't abuse my attention like that."* ⇒ While he is present, ask only what **source cannot answer** — that was exactly one question, the polling preference. M1, M2 and M3 were all written down in the clients he had already told me to read. **A question that source can answer is not a question; it is unfinished homework with a person attached.**
- [ ] 🔴 **R1 + N2 — Holding Area: group by PERSONA, sessions unlabelled, collapsed by default. RULED B by Rick 2026-09-22.** His words: *"group all sessions without any explicit labeling under each persona. Collapse it. I don't give a shit about your notion of session, it's irrelevant to me."* And on my framing: *"It's a bug because it does not mirror the behavior or the layout of the multiplexer or the legacy notification client. Don't try to defend a bad idea. It gets me the end user nothing."*
  - **My recommendation of C is withdrawn.** He is right about the requirement: mirroring the surfaces he actually uses is the point, and I argued an internal safety property at him instead of answering it. C kept a distinction he has told me is worthless — a compromise nobody asked for is a smaller version of ignoring the request.
  - **Shape**: one group per persona; sessions merged with **no** hash, **no** session count, no subtitle. Collapsed by default. Persona order case-insensitive as today. Trailing **Unattributed** group stays — a held row nobody can see is worse than an odd label.
  - **Inside B, not an objection to it**: approve-all now spans every session that persona filed, which is intended — so **the button and confirm must report that wider count**. A batch control whose label undercounts what it does is a defect under any scheme. Builds naturally: key `groupByFiler` on the persona portion, and the group's `ids` blast-radius value already covers it.
  - ⚠️ Some of the 22 cases in `filer_group_header_test.dart` will need to move from "is rendered" to "is rendered when expanded". **A case does not get deleted to make a layout change pass.**
  - ⇒ **R1 and N2 are now ONE piece of work** — with sessions invisible there is no inner level to collapse.
- [ ] **Bug `de509b51` — `pane_polling_mixin:95` documented an optimisation the code never implemented.** **Found by María.** Comment corrected (✅ landed, comment-only, verified by a diff filtered to non-comment lines returning nothing; 58 tests green). Row stays open for Rick on option (a), implementing it — which changes polling on three panes.
  - 🔴 **María corrected my framing twice**: the *absence* of a measured cost is the argument against (a), not a gap awaiting evidence; and since (b) has zero behaviour change, **it was mine to take under standing authority** and my "not Tiffany's to choose alone" was wrong.
- [ ] **A REBUILD is owed before items 8-14 can be walked** — the item-7 fix is in the tree, not in his APK.

### ⏳ Owed — 2026-09-22

- [ ] **Push.** ⚠️ **15 commits, not the 11 I recorded earlier** — `origin/wip-v0.1.6-2026.04.16-tracking-lupin-work` is at `9d6e396` (2026-09-19 22:46), so the set reaches back past Phase 5 to `0b7c5c1` and carries the whole cross-pane parity-guard arc. Not authorised. **Rick's word only; never ask him about push.**
- [x] **Widget-test completeness audit** (Rick asked directly, post-re-spin) — ✅ **DONE 2026-09-22.** Two seams had no test at all; both filled, both mutation-proved, suite 1658 → **1667 / 1 skipped / 0 failed**. New files: `test/widget/fleet/pane_host_screen_test.dart` (4/4 — Scaffold, bloc provided and drivable, factory called once, **bloc closed on route pop**, unopened pane has no bloc) and `test/service_integration/broadcast_ack_dispatch_test.dart` (5/5 — real dispatcher + real bloc + real parse; fold, idempotent redelivery, wrong-broadcast ignored, plain frame folds nothing, malformed frame dropped not fatal).
  - Mutation A — broadcast arm in `app.dart` disabled → **2 of 5 killed**; the 3 survivors are the *negative* cases and were always going to survive, since a disabled arm also folds nothing. Mutation B — `BlocProvider( create: )` → `.value( blocFactory( context ) )` → **killed the lifetime test and only it**. Both production files reverted **byte-identical**.
  - ⚠️ Placed the dispatch test in `service_integration/` not `widget/`: it drives the dispatcher, not a widget tree, and `single_dispatcher_test.dart` is the precedent. Filing it as a widget test would have been the more flattering label and the less accurate one.
- [x] **Orphan-surface audit, generalised** — ✅ **DONE, comes back CLEAN.** Enumerated every `*Screen` / `*Pane` / `*Sheet` class in `lib/` and checked for references outside its own file. One hit, `ChatScreen`, and it is **deliberate**: retired 2026-05-05 (`ee6f081`), kept as a banner-only screen so leftover navigation shows the retirement notice instead of crashing. ⇒ The orphan-surface defect family is closed **by measurement**.
- [ ] **244 pre-existing analyzer errors** in `lib/core/**` scaffolding outside the app's compile graph (978 issues total). None mine, none new. Not fixed — a sweep through dead code is a scope call. **Rick's.** If the analyzer is wanted back as a gate, the cheap version is an exclusion for the unreachable directories **with a measured file count beside it** (per the 09-20 post-game: an exclusion without that number is not honest).
- [ ] **`io/` — 11 MB untracked** (wav recordings, a git-delta-analysis png, macOS `.DS_Store`). Pure outputs; never belongs in the repo and currently unignored. One gitignore line. **Rick's call** — he has ruled on every gitignore addition here himself (`61270cf`).
- [x] **`addTearDown( bloc.close )` vs `runAsync`** — ✅ **DONE 2026-09-22, `212d39b`. María's form TAKEN.** Measured, not reasoned about: baseline `runAsync` 5 green / 5.068 s → `addTearDown` 5 green / 5.079 s, no pending-timer error, full suite unchanged at 1586 / 1 skipped / 0 failed. The named risk (both blocs open at once, `TaskListBloc`'s `Timer.periodic` live at flutter_test's pending-timer check) **did not fire** — the pane's dispose cancels the poll before teardown. ⚠️ **And the suggestion as given was invisible**: a bare `addTearDown( bloc.close )` that silently did nothing leaves all five tests green and the bloc leaked — the same hollow-control shape María caught here before. It is now paired with an `isClosed` check registered FIRST so LIFO ordering runs it LAST, after the close; **mutation-proved** at 0 passed / 5 failed.
- [x] **Phase 5 `384591dd` — ✅ DONE 2026-09-22**, `c990659` + `13ad75f` + `9702fe3` + `43342f0`. Built, wired, and **reachable**. Suite **1658 / 1 skipped / 0 failed**, from 1586 this morning. Row closed on `{commit, manager_attestation}`.
  - Acceptance in the settled *guard absence* shape: `AckConfidence.interrupted` renders "acks could not be confirmed" and **never a denominator**; `fold()` cannot restore confidence; the wording is about the attempt, not the world, so it stops firing rather than becoming a lie when the stores are bridged.
  - 🔴 **The plan's §6.2 drain is a REFUSAL that throws.** It cannot return an ack, so written as specified it would have run, recovered zero, and stayed green.
  - 🔴 **And until `43342f0` nothing could FIRE the interruption.** Every test dispatched the event by hand — proving the folding, proving nothing about whether the guard can trigger. The bloc now watches the lifecycle stream and the socket connection stream. `inactive` is deliberately excluded (a shade pull does not suspend delivery; a guard that cries wolf gets ignored). ⚠️ If that judgement is wrong the failure is a **false negative**, and **nobody has measured it on hardware** — the code says so.
  - Fixtures: 2 captured live, 3 transcribed from the producer, each labelled in `test/fixtures/commons/README-broadcast.md`. **No real broadcast was fired** — it would message every live seat.
  - Mutations **14/14 RED** across four batteries, every restore byte-identical.
- [ ] 🔴 **`props`-AS-SUMMARY — the defect I fixed in Broadcast (`9702fe3`) EXISTS ELSEWHERE, and I checked rather than assumed.** bloc skips an emit when the new state compares equal, so a `props` entry that is a **length or a count standing in for a value** silently drops rebuilds: no exception, no red test, just a screen that stops updating. Audited every `get props` in `lib/`:
  - 🔴 **`decision_proxy_state.dart:45` — `DecisionProxyTrustLoaded.props => [ trust.trustStates.length ]`. Length ONLY.** A trust state changing value while the count stays the same compares equal, so the Trust Dashboard stops updating. Changing trust in place at a constant count is the *normal* case for that surface, and it is reachable (`home_screen.dart:112`). This is the clearest instance and it is not mine to fix.
  - ⚠️ **`finished_tasks_state.dart:56-64` — WEAKER, and I am saying so rather than inflating the count.** It carries `eventsByStatus.length` (the number of status buckets, which barely moves) but ALSO `rows.map((e) => e.id).join(",")`, and the author left a comment explaining exactly that. The residual gap is narrow: a row whose content changes without its id changing. Worth a look, not an alarm.
  - `notification_state.dart:147-148` carries a length **plus** a summed count, which catches more; `notification_event.dart:107` is on an EVENT, where equality does not drive rebuilds.
  - **BACK-BURNERED by Rick, 2026-09-22 (keypress)**: *"Let's back burner the trust dashboard for the moment."* Filed, not dropped. The evidence above is the starting point for whoever takes it — it does not need re-deriving.
- [x] 🔴 **ORPHAN PANES — ✅ FIXED 2026-09-22 on Rick's go-ahead, `43342f0`.** All four now have home-screen cards; three build their bloc in-route because they poll, Broadcast uses `.value` because its bloc is app-root. New `PaneHostScreen` gives a pane a Scaffold **without** making it a screen — the panes stay body widgets so the cross-pane parity guard can still hold two at once and compare them.
  - 🔴 **The guard that would have caught it: `test/widget/home/fleet_panes_reachable_test.dart`.** It asserts the DOOR exists and is deliberately dumb about everything else. Four pane suites were green for days about panes nobody could reach, because **a pane test mounts the pane directly and therefore answers the reachability question "yes" by construction**. Mutation-proved by removing the Broadcast card again — the original defect now turns a test red.
  - The finding as originally measured, kept for the record: `TaskListPane`, `HoldingAreaPane`, `FinishedTasksScreen` and `BroadcastPane` are each referenced ONLY by their own file and their tests — no home-screen card, no route, no `BlocProvider` in `app.dart`. The home screen has six cards: Job Queue, Claude Code, Notifications, Trust Dashboard, Agentic Jobs, Fleet Status. Only `FleetStatusScreen` is reachable (`home_screen.dart:148`). Four phases of tested, merged, green work that nobody can open on a phone.
  - ⚠️ **My first write-up of this said `FinishedTasksPane`. No such class exists** — Phase 2 built `FinishedTasksScreen`, and its test file is nonetheless named `finished_tasks_pane_test.dart`, which is what misled me. Corrected here rather than left standing: a finding whose identifier lands on nothing is the same defect as a citation that lands on a look-alike, which is a shape this project has now hit three times.
  - Raised rather than absorbed, because fixing it touched three other phases' code. Rick's go-ahead came by keypress the same day.
- [x] **Untracking `android/local.properties`** — ✅ **DONE 2026-09-22**, Rick by keypress. `git rm --cached android/local.properties`; index-only, file untouched on disk. See the 09-20 list above for why the existing ignore rule never applied.
- [x] **`android/app/google-services.json` — ✅ DECIDED and DONE 2026-09-22**, Rick by keypress: gitignore it. Was untracked *and* matched by no ignore rule, i.e. one careless `git add` from committing Firebase config. Now `android/.gitignore:17`. No collateral — rsync backs up by explicit `--exclude` list (not a gitignore filter) so it is still backed up, and `link-worktree-artifacts.sh` already denied it by name.

### Carried, not minted as rows (the ticket gate was not worth spending on them)

- A text surface for **per-row won't-fix** on the shared row — in `734462c8`'s close reason.
- **`TaskListPage` moves to `fleet/data/`** — same place.
- **Appendix A item 7**, cross-cutting ordered cell-key parity across Task List and Holding Area only — specified in full on P0 `4b16174d`. Could not even be filed: one admit request at a time is Rick's rule, and Phase 5's is pending.
- **Items 8–11 routed to Mr. Radio** as a *filing* decision, not a row transfer — he was right to insist on the distinction, and there were no row ids because the gate had refused them.

---

## 🆕 Open from 2026-09-19 (board-driving session, no code)

### Decisions Log — 2026-09-19 (session `cc9c1f1a`)
- **Rick, three admits in one ask** (`ask_multiple_choice`, `answered=true`, `default_used=false`): admit and close `b00e076c`; **close `cea58ee0`'s phone half only** and "coordinate with Mr Radio (maria's not staffed tonight) to make sure that we have a ticket that's prioritized for work by him by his teams"; do the **transcribe check tonight on the emulator**. All three executed.
- **Rick: "Yes, go ahead and file it"** — the `/api/v2/ask` replay observation. Filed as `9511aa08`, **as a verify rather than a defect**, with my own flag corrected in the row: `status: waiting` means that payload is the enqueue response, so `spoke:false`/`answer:null` are what correct looks like.
- **Mr. Radio ruled the server half, option B** — the SessionStart hook writes its `sender_id` into the bridge; the server serves it verbatim and stops re-deriving an identity it cannot derive. **Option A is banned even as a silent fallback**: "a wrong identity that looks like a right one". Stricter than how I filed the row; my fallback offer is withdrawn.
- **Wire shape settled: null/absent, never a sentinel string.** Asked as one disambiguating question rather than inferred from a condensed DM. The phone already skips null (`focus_chat_bloc.dart:444`, pinned test), so option B needs **no phone change**.
- **`67c7a2e1` agreed P3 by Mr. Radio**, fix endorsed (`sessionHashOf( sid ) == null`) — insurance against a contract violation, not a live bug, which is why I recommended deferring it.

### Decisions Log — 2026-09-19 evening: the four (now five) fleet panes
Plan: `planning-is-prompting → src/rnd/2026.09.19-mobile-client-fleet-panes.md` · store row `72d16636` · epic `mobile-pane-parity` · author María 🌸
- **🛑 DO NOT IMPLEMENT** (Rick, by voice, ~19:02): *"you will not be implementing yet. We need to flesh it out and we need to run it through Cascade Review."* This **overrides María's "Phase 0 plumbing is safe to start"** — she sent that before he ruled, so it was current when written and is not now. My in-flight build-tonight ask was **stopped** rather than left to return an answer contradicting him.
- **Full parity, reads AND writes** (Rick, to María): she had assumed read-only for v1; he ruled the Holding Area's per-row and batch actions and the Task List's row actions all ship, in Phases 3–4 after the row and transport are proven. The disclosed controls row becomes the pane's primary verb surface on a phone.
- **A fifth navigation destination** (Rick, broadcast ~19:05): the broadcast-to-all-CC-sessions sub-accordion. *"Not a high-use piece of UI, but it is high value for sure."*
- **No socket for the task/fleet panes** — María measured all four at `subscribes=0`; lupin emits no task or fleet event type at all. Socket-first would be **lupin-side work first**, filed separately, not ours.
- **Open, Rick's to rule**: batch won't-fix has no confirm on web. María recommends adding one on a phone, where a mis-tap is likelier and it kills a filer's whole group. **Until he rules, build to match web — no confirm.**

### My contributions to the plan (research only, no code)
- **Destination 5 is the ONE surface that is genuinely socket-driven**, and it breaks §3/§6's "all panes poll" generalization: every `commons_broadcast_ack` arrives inside `notification_queue_update`, an event type lupin does emit and the phone **already subscribes to**. Polling it would be a downgrade. Endpoints: `GET /api/commons/active-sessions` (the focus rail already consumes it), `POST /api/commons/broadcast-to-cc-sessions`, `GET /api/commons/broadcast-history`. Source `commons.py:1046` / `:1089`, UI `static/js/broadcast-panel.js`.
- **`char_budget=0` is a byte-budget opt-out, not a truncation length** (`tasks.py:2958`, `Query( default=None, ge=0 )`; `:3196` shows 0 opts out). Answers §10 check 1 — and copying the web query verbatim hands a phone **500 unbudgeted rows**, backwards for LTE. Keep the server default on mobile.
- **The web is not uniformly confirm-free**: the broadcast panel has a confirm modal (`broadcast-panel.js:240`, AC8), which María confirmed. So a phone confirm on batch won't-fix would be *consistent* with an existing surface rather than a divergence — offered to make Rick's ruling easier.
- **The 5-minute ack TTL is a phone constraint**: background the app through it and the aggregate is gone on resume; the pane must say so rather than render an empty success.
- **Verified every claim the plan makes about this repo** — `lib/core/repositories/`, all three test tiers, and both cited lupin files exist at the stated paths; `ROW_SCHEMA` matches her table field-for-field.

### Cascade review — CLOSED 2026-09-19 ~19:32 EDT (Tiffany managing, row `4b16174d`)
Doc frozen at `planning-is-prompting` commit **`c65c41e`** · sha256 `be890581…` · 413 lines. Three reviewers, one dimension each, all delivered. Reports + fold directive: `projects-data/lupin-mobile/cascade-findings-2026.09.19/`.

| Reviewer | Dimension | Result |
|---|---|---|
| Chloé 🗼 | contract fidelity | 715 lines; the two-write-doors material |
| Rachel 🕊️ | shared row + accessibility | 9 MAJOR · 1 MINOR · 1 verified-correct · **0 BLOCKER** |
| Sam 🎙️ | phone behaviour + §6 refresh | 2 BLOCKER · 4 MAJOR · 3 MINOR · 1 NIT |

**The plan's spine held** — §6's polling-for-v1 call and the destination-5 carve-out were attacked directly and survived ("I tried to break both and could not").

**Four must-fix before minting**: (1) **two write doors, doc names one** — `PATCH /api/tasks/{id}` never changes status, `POST /api/tasks/{id}/transition` does, so approve-as-PATCH 404s or silently no-ops; (2) **§12 contradicts §8.3 — my error**: dropping `char_budget=0` yields ~24 rows of 500, `terse=true` was the lever; (3) **foreground-only polling has no mechanism** given app-root BLoC providers, and its own acceptance test passes without it; (4) **§5's architecture map wrong four ways**, including the BLoC layer being absent from the plan entirely.

**Best output was not a defect**: destination 5 needs **reconciliation** though it correctly needs no polling — a phone's socket stops every time the app backgrounds, making that pane the textbook case of the hazard §6 itself names. Remedy: drain `/api/notifications/undelivered` filtered on `commons_broadcast_ack`, then decide expired-vs-partial. Sam's.

**Process lessons worth keeping**: the pin caught the doc moving mid-cascade within two minutes, and all three reviewers halted rather than producing findings against dead coordinates · the DM condenser shredded every detailed report, so findings moved to files in `projects-data` · two reviewers inferred a body insertion from a new Version-history row, which line arithmetic refuted.

### Decisions Log — 2026-09-19, cascade rulings
- **Rick, §11 q1, on a corrected premise**: *keep the reason box required, ADD a confirm to approve-all.* He had been queued to rule on "won't-fix has no confirm — add one?"; two reviewers independently found won't-fix is **already gated** by a mandatory non-blank reason box (deliberately chosen over a dialog, because `confirm()` freezes the extension's event loop) and **approve-all is the ungated one** — the immediate DOM sibling, ~20px against Android's 48dp minimum, tooltips being `title` attributes that do not exist on a phone.
- **Rick, fleet cap**: raised 5 → 9 at my ask. Every session counts, managers included, so 3 managers + 3 workers had already exceeded 5 and zero reviewers could be spawned.
- **Tiffany (manager)**: freeze the doc + fold queue + **one fold at the end**, never rolling folds — the September spoken-ask cascade folded incrementally and both verification passes then found defects introduced *by the folds themselves*.
- **Tiffany (manager)**: Rachel's findings doc in `src/rnd/` **stays** — new file, nothing overwritten, declared in her manifest section; `src/rnd/` is this repo's conventional home for review records and `projects-data` stays the scratch drop.
- **Tiffany (manager)**: reviewers do **not** fold their own findings — the author folds, or nobody is left who read the change without having written it.

### ⏳ Owed — 2026-09-19
- [ ] **`a7de7d69` (P2, recommend P1) — the logcat token leak.** `LogInterceptor` at `lib/services/network/http_service.dart:55` prints `Authorization: Bearer …` on every request (Dio defaults `requestHeader: true`) and prints both tokens in the sign-in response body; **no `kDebugMode` guard**, so release builds do it too. Demonstrated live: Rick's own paste carried his JWT twice. Fix is one line plus tests; the narrow interceptor at line 63 that produces the device-check receipt stays. **Held, awaiting his admit.**
- [ ] **`67c7a2e1` (P3) — sentinel guard.** `""` is skipped, `"none"` is not (measured: 11 passed / 1 failed). Swap the absence test for `sessionHashOf( sid ) == null`; promote the two probes to named cases; ⚠️ first confirm no legitimate roster sender id lacks a `#`. **Held, awaiting his admit.**
- [ ] **`9511aa08` (P3) — verify a replayed answer actually reaches the phone.** Closes when Rick repeats a cached question and confirms he hears the answer, or when a WS assertion pins it. **Held.**
- [ ] **`2184bebb` (P1, lupin) — not mine.** Mr. Radio accountable; option B ruled, null-not-sentinel settled. He owes the server-side payload assertion (the phone test asserts behaviour, not wire shape, so nothing here can catch a server that starts emitting a sentinel).
- [ ] **`9cddb791` P3 re-rate** — still carried from 09-16, Mr. Radio accountable, figure now reproduced.

### Carried unchanged from earlier lists
The `[HTTP]` bearer-token hygiene note from 09-17 is now a real row (`a7de7d69`) and can be struck from that list. `c51e92da` stays parked to 2026-10-01 (needs a real handset). Worktree cleanup, the laptop `rm -rf`, the Temurin 21 install and the outside toolchain review are unchanged.

## 🆕 Open from 2026-09-11 (spoken Quick Ask: two legs or one)

### Decisions Log — 2026-09-11 (Rick, by keypress, walked through brief §7; row `9df9f1c2`)
Brief: `src/rnd/2026.09.11-voice-one-leg-ask-decision-brief.md`
1. **After speaking**: add a phone setting, *send immediately* / *review first*, **default review first**.
2. **Build path**: **streamed two-part reply** on a new opt-in spoken-ask door. Line 1 is the transcript (~280 ms), line 2 is `job_id`/`status`/`pending_id` (~745 ms). The wav door stays text-only for voice replies.
3. **Measurement**: **phone round-trip probe** on wifi and LTE only; the full 09-10 instrumentation plan is not built.
4. **Recording format**: **compressed Opus or AAC (~32 kbps) after an accuracy check** on real phone recordings. Changed by Rick ~14:35 from "16 kHz WAV". The `record` package has no MP3 encoder; the browser already sends WebM/Opus.
Rick is separately filing the bug that makes `/io/recording.mp3` unique per sender; `/io/last_response.json` has the same sharing. **Fixed and merged** as `91a45173` (row `27bcdd79`).
5. **Plan review** (`src/rnd/2026.09.11-spoken-ask-streamed-door-implementation-plan.md`, ~15:40): approved "for the most part" **pending a cascaded review** · toggle on the Quick Ask screen · auto-cancel before the job ID · staffing split (Mr. Radio staffs the server, Tiffany builds the phone). Mr. Radio has been asked to run the cascade.
6. **No build tonight** (~22:39, keypress, `default_used=false`): *"It's 1030 at night This is basically time to run the end of session ritual."* Session-end instead; all workers checkpoint and **resume exactly where we left off tomorrow morning**. Rev 13's fold is **held, not cancelled**.

### Cascade outcome — 2026-09-11 (row `9df9f1c2`, now Mr. Radio's)
Plan went **rev 8 → rev 12**; six pins in git (`b505bfb` `32b2055` `3a97776` `99c4eeb` `feda7bf` `2def6e4`). Nine stages closed, two verification passes folded, **nothing built**. Current pin: rev 12 `ccc0430b`, 646 lines, commit `2def6e4`. Memento `38e7a298`.

### Decisions Log — 2026-09-14 (session `b3e285b8`)
- **Build go** (`ccd7d20e`, keypress 15:48): *"Yes, after rev 13 verifies."* Closed by Mr. Radio with manager_attestation.
- **CB4 ruled by Rick** (~16:00): *"retry invisibly"*, delivered by `FormData.clone()` in `auth_interceptor.dart`. No longer provisional.
- **Buffer cleared at subscribe** (Mr. Radio 16:35, departs from §3.3 step 2; recorded in revs 15+).
- **Fleet cap 8** (Rick's own word, 15:46). An `ask_yes_no` returned a clean "no" he says he never pressed, so that verb's return is treated as suspect.
- **Push is Rick's prerogative; never ask him about it** (22:18). Saved to memory.
- **Device checks: "Tomorrow at nine"** (22:18 keypress). Both rows parked, not blocked on Rick.
- **Keep both P3 bugs** (22:20 keypress).

### ⏳ Owed — 2026-09-15
- [x] ~~**09:00 device session with Rick**~~ — superseded, see the 2026-09-15 log below. The build and the script were both delivered (`77b86b7`, `src/rnd/2026.09.15-phone-device-session-script.md`); the session slipped to 2 PM and then to the emulator, and Rick's laptop build is broken on JDK 25. Both rows stay parked.
- [x] `5ac999f5`: suite green (1155 passed / 0 failed) on 2026-09-16. Rick ruled delete, so `test/legacy_quarantine/` is gone, and the two cosa wire-contract tests find `../lupin/src/cosa` or skip with a reason. New empty baseline: `projects-data/lupin-mobile/2026.09.16-flutter-failing-baseline-empty.txt`.
- [ ] `9cddb791` (P3 bug): Quick Ask Door C overflows at 320×568, 10px in prompt and 82px in prompt+error; predates §C. The measuring test is in `projects-data/lupin/cascade-pins/overflow-320-measure-test.dart`. Awaiting Rick's admit.
- [ ] Nine leftover worktrees under `.claude/worktrees/` (seats, gates, Chloé's review copies): remove on Mr. Radio's OK. Rows `6698d40f` (hold poke text names no directory) and `2f0932ba` (no lupin-mobile seat-worktree script) are María's post-game follow-ups.

### ✅ Closed this cascade
`ccd7d20e` build go · `79c4ad06` seat restart (dropped, fresh seat) · `39639293` §C (commit `16d73f8`) · `136d1c1b` §B (commit `83f19a7`, closed by Mr. Radio). The rev-13 hold list folded into revs 13–19.

### Decisions Log — 2026-09-15 (session `71d94067`)
- **Device session moved to 2 PM, then to the emulator** (~18:45): *"emulator now, phone later."* Roughly ten real recordings on the emulator close `9b1f7701`; the wifi upload timings in `c51e92da` still need the handset, and the LTE half still waits for an address reachable from outside the house.
- **Server address settled**: desktop wired at `192.168.1.21`, phone on wifi. It is the only non-emulator address that exists anywhere, which is why "ship a better default" was dropped as an option on `2070a906`.
- **Release picker reversed** (~20:39): *show the picker on the sign-in screen in release builds too.* Mounting it in Settings was rejected because `AuthGate` sits in front of Settings (`auth_gate.dart:50-51` → `app.dart:272`), so a stranded phone could never reach it.
- **Branch triage gate `970940df` ruled**: Rachel's gitignore change lands (`fb9c099f`); Sam's legacy-JS guard, Rio's `local_state` fixture and the Tiberius doctrine branch are all dropped, branches kept.
- **Opus accuracy runs through the :8000 submit door**, not ad hoc.

### Decisions Log — 2026-09-15 evening (session `71d94067`, post-clear)
- **Release picker reversed and shipped** (`dcc7263`). Rick: *show the picker on the sign-in screen in release builds too.* The flag was deleted rather than relabelled — reviewer's reasoning: "hiding cannot be asked for at all" beats "hiding must be asked for by name", and no production code ever set it.
- **Mic shrink kept** (~21:55, `answered=true`): it drops 128→84 only while a question waits and only when nothing is recording. Two wrong gates were refused with measurements — the original would have shrunk the live stop control mid-capture, and my own suggested alternative would have shrunk it whenever a draft was held.
- **Voice memos: yes** — Rick records about ten on any device he owns. This replaces the device session entirely; the integration test takes a directory of WAVs and does the 32 kbps encode itself.
- **Both device rows un-parked** by Rick himself; their park reason had expired twelve hours earlier.
- **Java: a separate Temurin 21, not Android Studio's JBR.** His own `flutter doctor -v` settled it — Studio 2026.1 bundles JBR **25.0.3**, so his proposal pointed at the very Java breaking the build, and our research note's "JBR 21" row was stale. Flutter 3.35.1 investigated: Gradle cap identical, no path opens.
- **Fleet ticket gate refused a new row** at ratio 1.32, so the rebaseline work lives as an amendment on `0b3f063a` rather than its own row.

### Decisions Log — 2026-09-16 (session `b0157e13`)
- **Tail-drain wait withdrawn** — Rick: an ugly hack; the recorder drops at most one ~80 ms buffer, which cannot explain word loss.
- **Opus adopted** for questions after 0.57% WER on 9 real clips.
- **Phone build: yes, after the video** (Rick, ~21:44, answered during the demo take). Not a staged answer — act on it.
- **Demo takes**: say your scripted line, then nothing — no post-line notify, before or after "cut" (workflow doc §3b).
- **Evening seats**: mine donated to Mr. Radio; nothing on my board is worker-able while Rick edits.

### ⏳ Owed — 2026-09-17 (pick up here)
- [ ] **`c3fc62bf` device check** — Rick builds on the laptop, voice Quick Ask with *Send immediately* OFF, paste the `[HTTP] Request: POST` line (expect `/api/v2/transcribe`); close with `a2f1d75`. Gate row `372d82b8` closes with it.
- [ ] **`168922f9` María's Stage-1 audit** — admitted only after the phone check; read-only diff of plan rev 2 vs rev 1 and the five §3 rulings' file:line receipts.
- [ ] **`c51e92da` / `edba76c6`** — parked until 2026-10-01.
- [ ] **Hygiene**: the `[HTTP]` logger prints the full bearer token in logcat — consider a row.

### ⏳ Owed — 2026-09-16
- [x] ~~**release picker**~~ — merged `dcc7263` (row `1b11f18d`; `2070a906` dropped as superseded).
- [x] ~~**JDK ruling**~~ — settled by Rick's own `flutter doctor -v`. Install a separate Temurin 21 and `flutter config --jdk-dir`; his Android Studio bundles 25.0.3, so pointing at its JBR points at the problem. Proven end to end on the desktop.
- [ ] **Rick's laptop, three things in order**: install Temurin 21 → `flutter config --jdk-dir` → `flutter doctor --android-licenses` (the licence tool runs on the *selected* JDK, so it must come second). Expect ~2.7 GB of SDK download and a wall of NDK/compileSdk warnings from 18 plugins that look like failure and are not. His terminal also runs under Rosetta — costs speed, changes no compatibility.
- [ ] **Outside expert review** — briefing at `src/rnd/2026.09.15-android-toolchain-briefing-for-outside-review.md`, written for someone arriving cold. Three questions: is there a reason to distrust the JDK 21 fix we cannot see from inside; is the vendored-Flutter-versus-PATH arrangement worth paying down; are we right to treat the heap request and NDK skew as noise.
- [ ] **`9cddb791` priority re-rate** — closed and merged, but its P3 rested on "320-wide devices are rare" and a 360-wide phone clips too. Handed to Mr. Radio, who is accountable manager and deliberately declined to re-rate on a relayed figure before it was independently reproduced. It has been.
- [ ] **`9b1f7701` Opus accuracy** — tooling merged in lupin `74c9822a`; it skips until `LUPIN_OPUS_ACCURACY_DIR` points at recordings. Put them in `lupin/io/opus-accuracy/recordings/`, then submit integration with `-v -k opus_vs_wav` after `venue_idle`.
- [ ] **`c51e92da` phone round-trip probe** — parked until a real handset is in hand. Pull the JSONL and the recordings, report p50/p90 upload on wifi.
- [ ] **Laptop one-time cleanup** — `rm -rf ~/Projects/lupin-mobile/.claude ~/Projects/lupin-mobile/io`. The rsync script excludes them now, but rsync never deletes what it excludes.
- [ ] **Worktree cleanup** — the merged worktrees under `.claude/worktrees/` in both repos. An earlier removal was refused by the permission classifier.

## 🆕 Open from 2026-09-08 (abstract rendering + doc-link viewer)

### Decisions Log — 2026-09-08

- **Render abstracts as markdown, in-app, with no WebView.** `GET /api/docs/file` returns raw
  source text over the shared Dio that already carries the Bearer token, so the client fetches
  bytes and renders them natively. **Why**: the alternative — embedding the Lupin SPA in a browser
  view — would have cost WebView memory and a second auth path to buy nothing.
- **Modern doc-link format only; legacy `?scope=` is deliberately unsupported** (Rick's amendment).
  A legacy link classifies `unknown` and renders as inert text. **Why**: the backend answers 400 on
  that parameter, so offering a tap would offer a guaranteed failure. Detected explicitly rather
  than by fallthrough, so it stays reversible.
- **Link text is the only tap target**, not the whole card. **Why**: the card already carries a
  Respond tap target and a second whole-card gesture would collide with it.
- **Long abstracts collapse at 8 lines** behind Show more. **Why**: some abstracts are multi-row
  tables that would otherwise swamp the notification list.
- **External `http(s)` links open the system browser behind a confirm.** **Why**: leaving the app
  should be deliberate.
- **`flutter_markdown` → `flutter_markdown_plus`, landed as its own phase ahead of the feature.**
  **Why**: Google discontinued `flutter_markdown` on 2025-05-30 and we were still shipping it; the
  swap is standalone hygiene and de-risks everything built on top. Pinned to 1.0.7 because ≥1.0.8
  requires Dart 3.9 and the in-tree toolchain is 3.8.0 — **raise the ceiling when the bundled
  Flutter SDK moves.**

### Open — mine

- [x] **P4 — scoped down by Rick and CLOSED** (`2e8d02c`). He chose "close my loose ends only":
  the external-link confirm is now tested (7 widget tests, `url_launcher` mocked at its
  MethodChannel) and the unused `flutter_html` dependency is removed.
- [x] **Store row `2df54cf6`** — approved, then closed **done** with receipts.
- [x] **Pushed** — `a55ed01..2e8d02c` on origin, verified 0 ahead.

### Deliberately descoped — revisit only on a real case

- [ ] **`.html` and directory renderers.** Both currently fall to the source view, which is
  readable and honest rather than an error. `DocContentKind.html` survives as its own kind so the
  distinction is not lost. **Trigger to revisit**: a real notification abstract that links an
  `.html` file or a directory. Until then, building them is building for a hypothesis.
- [ ] **Live-server integration test** for the doc-fetch flow. Needs `:7999` up; an environment
  call, not a code one.
- [ ] **`flutter_markdown_plus` is pinned to 1.0.7**, not the current 1.0.12 — ≥1.0.8 requires
  Dart 3.9 and the in-tree toolchain is 3.8.0. **Raise the ceiling when the bundled Flutter SDK
  moves.**

---

## 🆕 Open from 2026-09-04 (Quick Ask + the cache handoff)

### Decisions Log — 2026-09-04

- **Rick ruled the plan doc ships as-is** (voice, ~22:47Z). Committed `ff2e90c` after being offered four times across two respins. No implementation authorised with it.
- **Rick corrected his own V1 ruling, twice in three minutes.** First "restore what version 1 did"; then *"I don't need to restore V1 verbatim — I mean use the logic, or copy the logic, that V1 uses. Do NOT resuscitate V1. Do not!"* Both readings are on `fe1c0d3f` under `user_direct`. V1 is a reference for the behaviour, never a target to revive.
- **Rick ruled the Lupin repo is off-limits to a mobile seat**: *"file that as a bug and have someone else look into it, it's not your job to edit the Lupin repo."* Filing is mine; editing and diagnosing are the server team's. `fe1c0d3f` handed to Pocholo, Mr Radio accountable.
- **Mr Radio ruled `3658ec66` queued under Pocholo** (00:14Z), deliberately NOT routing the threshold decision to Rick — a P3 he called not-burning does not earn an interrupt.

### Pending decisions — Rick's

- [ ] [LUPIN-MOBILE] **The `similarity threshold confirmation = 90.0` bar.** Rick's *"what's the sum of 2 plus 2"* scores **84.85**, five points under, so it silently falls through to a new job. Three options, none chosen: **(a)** lower the bar — widens what is *offered*, not what is served silently, since the user still confirms; **(b)** leave it, 84.85 may be correctly below; **(c)** converge paraphrases upward via normalisation/gist. ⚠️ The tier-1 floor of `100.0` is **irrelevant** to this symptom — do not touch it. Mr Radio holds this for the next decisions walk.
- [x] [LUPIN-MOBILE] **README entry corrected** — it called the progress-as-answer case a live defect; `649f458` fixed it. Offered twice and unruled, so I made the correction myself at shutdown: a factual staleness in my own doc is not a decision worth carrying overnight.

⇒ **ONE decision goes into the night, and it is durable in the store, not only here**: the 90.0 bar below, carried on Mr Radio's row `0b11bd5a` for his next decisions walk with Rick.

### Carried forward — not mine, named so they are not lost

- [x] [LUPIN-MOBILE] **`3658ec66` was dropped in error by me and is now RESOLVED — Mr Radio minted `0b11bd5a` and took it himself** (P3, owner and accountable both him, `queued`, verified in the store). `dropped` is terminal so neither of us could walk it back; the replacement row carries the reinstatement in its own title. **Root cause worth keeping: `task_get` returned his full ruling seconds before I called the transition and I acted on a condensed DM summary instead of the row in front of me.** Same shape bit me twice in one hour — see the `35404747` stale relay below.
- [x] [LUPIN-MOBILE] **Reported `35404747` to Rick as "blocked on María" when it had already shipped.** Merged `59465317`, served token `20260904g`, verified running. I read the row at its 21:39 state and it had moved twice since. María's own note: the row moved four times in two hours. **The lesson is the same one: a condensed or stale account is not the row.**
- [ ] [LUPIN-MOBILE] **The plan doc's cap change is written but unbuilt.** Reveal the `ask.flow` bucket the persona-less default rail scope hides; raise the per-sender cap of 7; queue the second interrupt via the browser's deferred-countdown trick. `claude_code` is the one builder of eleven not emitting a per-job sender id — a one-line fix in the parent repo, not mine to make.

## 🆕 Open from 2026-09-01 (backup)

> Rick's **new-ticket moratorium** in force — carried as narrative, not filed as store rows.

- [ ] [LUPIN-MOBILE] **DATA02 mirror holds ~812 MB of now-excluded content that `--delete` will never reclaim.** The destination is 858 MB: `flutter/` 625 MB, `build/` 117 MB, `.venv/` 35 MB, `.dart_tool/` 35 MB, plus a 47 MB `.git`. Those paths are now in the exclusion list, and **rsync protects excluded files on the receiving side** — so `--delete` reports 0 deletions and the stale copy sits there forever. Needs a **one-time manual cleanup, Rick's word required** (destructive op on a backup, moratorium in force). Safe form, leaves `.git` and the real work alone:
  ```
  rm -rf /mnt/DATA02/include/www.deepily.ai/projects/lupin-mobile/{flutter,build,.venv,.dart_tool,.idea}
  ```
  ⚠️ Do **not** reach for `--delete-excluded` in the script instead — it would also delete the destination's `.git`, which is in the exclusion list.

- [x] [LUPIN-MOBILE] **Backup coverage VERIFIED, and the mirror is now clean but nearly empty.** Diffed `git ls-files` (532) against rsync's own `--out-format='%n'` transfer list (573): **530 of 532 tracked files are backed up.** The only two absent are `.gitignore` and `android/.gitignore`, caught by the canonical list's own `.gitignore` pattern — deliberate upstream, not collateral from the Flutter additions. The 43 backed-up-but-untracked files are wanted: `io/mementos/*`, `android/app/google-services.json`, `pubspec.lock`, `CLAUDE.local.md`, the gradle wrapper. Rick ran the cleanup `rm` 2026-09-02 ~01:40Z: **858 MB → 47 MB**, all five target dirs gone, `.git`/`src`/`android` intact. `history/` and `.claude/` are absent at the destination but were never restored there in the first place (the 2026-08-31 restore was partial — dest `src/` was 100 KB against the source's 1.8 MB). ⚠️ **The mirror is therefore correct-but-stale until a `--write` run repopulates it.**

- [ ] [LUPIN-MOBILE] **Upstream gap in planning-is-prompting: the canonical exclusion list has no Flutter/Dart block.** Both copies (`scripts/rsync-exclude-default.txt` and `src/scripts/conf/rsync-exclude.txt`, identical at line 74) carry a commented `# Node.js (if applicable)` block — `node_modules/`, `npm-debug.log`, `yarn-error.log` — and **nothing for Flutter/Dart at all**. The list's design is "uncomment what applies", so a Flutter project copying it silently backs up its vendored SDK, which is exactly what happened here (1.79 GB → 6.22 MB once fixed, commit `717e94c`). Suggested upstream change: a parallel commented block — `# flutter/`, `# .dart_tool/`, `# .flutter-plugins*`, `# .gradle/`. **Not this repo's file to change**; hand to whoever owns planning-is-prompting.

## 🆕 Open from 2026-08-29 (Quick Ask)

> Rick's **new-ticket moratorium** was in force at session end (2026-08-29 22:52 broadcast) — these
> are carried here as narrative rather than filed as task-store rows. Promote them to rows tomorrow.

- [x] [LUPIN-MOBILE] ~~**AC-S2.8 is undefined.**~~ **RESOLVED 2026-08-30 — the premise was wrong** (commit `0df6a66`). It *is* defined, in `src/rnd/2026.06.11-focus-mode-voice-chat/11-section-s2-focus-chat-bloc.md:163`, pinned by `test/service_integration/focus_app_wiring_test.dart:212`. A cross-document citation nobody followed. The real defect was smaller: the plan instructed an amendment *from* the phrase "sole caller", which appears in **no** document — every source already says "sole dispatcher". Replaced with a pointer to the definition.
- [x] [LUPIN-MOBILE] **AC-G3 cached-question clause — CLOSED 2026-09-02** (store row `734bd1bf` → `done`, receipts `ts-fee0022f` + `lupin/src/tests/integration/test_v2_ask_serves_a_confirmed_row.py`). Rio ⚡ wrote a two-arm integration test: a seeded row with `answer_is_correct=True` returns `path="replay"` / `route_reason="exact_hit"` / `cache_hit=True` with `replayed_snapshot_id` matching the seed; the same seed unconfirmed returns `path="agent"`. **The negative arm closed the guard-vs-delivery ambiguity without the `replay_refused_unconfirmed` trace field I had insisted was a prerequisite** — a refusal is visible from outside on a question the cache demonstrably holds. My 2026-08-30 confounded read is superseded; the instrument error (watching `total_replays` on a branch that never calls `record_replay`) stands as recorded.

- [x] [LUPIN-MOBILE] ~~Store row `54589356` — blocked on Rick~~ **RULED 2026-08-30, unblocked, owner → Pocholo.** Rick's words: *"Incorrect answers should never be replayed no matter where they are called from"*, and re-executing cached code and re-reading a cached answer **both** gate on `answer_is_correct` being `True` — the distinction is real but buys no exemption. An unset flag from a confirmation timeout counts as not-correct (fail-closed). He accepted the cost on the record: unset is the common case, so a real number of today's exact-match hits become misses. Two call sites: `running_fifo_queue.py:307` and `:1846`. Pocholo then closed the last open question — `/api/v2/submit` never calls `_may_serve` at all, so it is the **front door**, and `v2 executor = queued` routes refusals into a queue whose `100.0` floor matches the very snapshot v2 just refused.
- [x] [LUPIN-MOBILE] ~~**NEXT ACTION — bounce `:7999` first**~~ **PRECONDITION ALREADY SATISFIED, measured 2026-09-02 01:41Z** (store amendment on `734bd1bf`). `lupin-rest-dev` started **2026-09-01 23:13:33 UTC**; both fixes merged 2026-08-30 (`c91bd1bb` 22:01 EDT, `7aac0061` 23:26 EDT) and are ancestors of the served `HEAD` `c34d0733`; `/src` is a host bind-mount. The process loaded code containing both fixes ~22 h after the later merge. **A bounce would change nothing.** ⚠️ Uptime is a coordinate, not a reference — re-read `docker inspect lupin-rest-dev --format '{{.State.StartedAt}}'` before relying on this. What still blocks the probe is server-side and unchanged: nobody has captured the v2 ask response's `path`/`route_reason` for the repeat, so "refused by `_may_serve`" and "served and lost in delivery" stay indistinguishable.
- [ ] [LUPIN-MOBILE] **Store row `88347f65` (P1, parent repo, UNASSIGNED, blocked on Rick 13:00Z)** — the browser delivery path produced **zero** successful frame deliveries in six hours. `slow zebra`: 3,775 drops / 152 `pre-WebSocket` registrations. `foolish goat`: 0 / 0 — silence, not health. Meanwhile `is_connected=True` and a ✓ printed before every drop, which is why nobody noticed. Pocholo declined it (fix is browser-client, not server — correct). Needs Rick to authorise a lupin worker or place it with a web-client seat. ⚠️ **Treat as TWO failures**: a subscription fix explains `slow zebra` and changes nothing for a session the emitter never addresses.
- [ ] [LUPIN-MOBILE] **Store row `0e7c9214` (P1, parent repo, owner Pocholo, I chase)** — found live 2026-08-30 with Rick at the keyboard. A repeat ask announces "New math job", runs it, completes it, and **never announces the answer**. Two *independent* causes, both root-caused the same evening: (1) dropped `job_state_transition` frames ⇐ `get_copy()` injects the requester's email but never their `user_id`, so a replayed snapshot emits to the original creator's stale id — **all 13 rows in `lupin_db_dev` carry the old-format key, zero carry the UUID**; (2) missing answer announcements ⇐ empty `user_email` upstream hitting a bare `return` in `FifoQueue._notify`. Counts close it with no residue: 4 asks, 1 answer, **3** skip warnings, 0 env fallbacks. Pocholo shipped the `user_id` fix and flagged himself that it does **not** reach (2). Still open: where the email is lost upstream.
- [ ] [LUPIN-MOBILE] `log_query()` dies with `expected 768 dimensions, not 0` on an empty embedding, *after* the match already scored `exact_match` / `100.0`. Every repeat ask loses its query-log row. Observed 2026-08-30, undiagnosed, recorded on `0e7c9214`.
- [ ] [LUPIN-MOBILE] Rachel flagged a **render-lens defect** and a **summariser that dropped a test name** as unresolved — read `io/mementos/rachel-a45a8132.md` before picking up her lane.
- [x] [LUPIN-MOBILE] **DECIDED 2026-09-22 (Rick, keypress): gitignore it.** `android/app/google-services.json` was untracked AND matched by no ignore rule anywhere in the repo — one careless `git add` from committing Firebase config. Now `android/.gitignore:17`. Verified no collateral: the rsync backup excludes by an explicit `--exclude` list, not a gitignore-derived filter, so the file is **still backed up**; and `link-worktree-artifacts.sh` already denied it **by name**, so worktree provisioning is unchanged.
- [ ] [LUPIN-MOBILE] Device check of the Quick Ask screen — laptop APK rebuild runbook `src/rnd/2026.06.12-poc-laptop-build-runbook.md`.

## 🆕 Open from 2026-08-21 (wave 2 / lane 2)
- [ ] [LUPIN-MOBILE] Live check of the nine `/api/v2/submit` doors against `:7999` once integration `799e43d0` reaches wip + a bounce (mobile tests are mock-backed; one real DR dry-run + one podcast submit through the app).
- [ ] [LUPIN-MOBILE] Prune merged worktrees `lupin-wt-tiffany-{salutations,v2eval,lane2-door}` (classifier denied `git worktree remove` in-session — Rick or a fresh session).
- [ ] [LUPIN-MOBILE] Lane-2 rig goes green only after `b7fe8941` (ask-side agentic dispatch, Rachel) — no mobile action; watch.
- [ ] [LUPIN-MOBILE] Ruling wanted: speak-system-senders default (ON today) — §5h.
- [ ] [LUPIN-MOBILE] Device check of the 2026-08-21 day (rail grouping, voice DM to chip, TTS queue sheet, stop-list) — laptop APK rebuild runbook `src/rnd/2026.06.12-poc-laptop-build-runbook.md`.

## ⭐ NEXT SESSION — START HERE: focus-mode HUMAN device items (laptop, 2026-06-12)

**Plan-of-record**: `src/rnd/2026.06.11-focus-mode-voice-chat/00-index.md` — 🚀 AI-IMPLEMENTATION
COMPLETE 2026-06-12T09:14Z (lifecycle + per-section status in the index banner/table).

> **🔥 FCM LIVE-SERVICE TRACK REACTIVATED 2026-06-23** (Rick directive — un-back-burnered).
> Coordinated with Tiberius 👑 (session 3d7c4c2e, thread f27e53be); division of labor LOCKED:
> **Tiffany = CLIENT** (gradle plugin + google-services.json + runbook-92 on-device probe),
> **Tiberius = SERVER** (firebase-admin>=6.5 image rebuild + key at `FCM_SERVICE_ACCOUNT_JSON`
> PATH + restart `lupin-rest-cloud-test`). **NEW Firebase project `lupin-mobile`** (Rick
> confirmed); **authoritative console-pass spec** is now
> `src/rnd/2026.06.23-firebase-android-provisioning-for-live-fcm.md` (supersedes the runbook-91
> pointer below). Grounded: `applicationId`/`namespace` = `ai.deepily.lupin_mobile` matches the
> registration. Client work is HELD until Tiberius's **live-service-up ping**; gradle plugin +
> JSON ride ONE bundled laptop pass per runbook 92 step 2 (do NOT pre-wire — apply without the
> JSON breaks every build). Store task: `63790ce3`. Rick's move: the 5 console clicks per the
> spec doc. ETA pending Tiberius's rebuild-runbook worker report.
>
> **UPDATE 2026-06-23 ~15:55Z**: Standup AUTHORIZED + IN PROGRESS (Rick gave full go, then
> stepped into a ~1hr meeting; Tiberius executing autonomously, now re-spinning via memento per
> Rick's "prepare for re-spin" broadcast — state preserved). Auth model = **keyless ADC**
> (`fcm wake auth mode=adc`; VM SA grant roles/firebasecloudmessaging.admin) — **no
> service-account JSON key needed** after all. CLIENT SIDE READY: `android/app/google-services.json`
> present + **gradle plugin pre-wired** (settings.gradle.kts 4.4.2 + app/build.gradle.kts) →
> runbook-92 laptop pass now collapses to **on-device probe only** (needs laptop build-verify).
> Project-alignment VERIFIED no-403 (device-reg project == server-send project, both
> `hello-world-foo-423219`). **NON-BLOCKING DECISION FOR RICK (later):** the Android app
> registered under the existing `hello-world-foo-423219` project (where VM/SQL/AR live) rather
> than a fresh dedicated `lupin-mobile` Firebase project — works + aligned now, but clean
> separation may be preferred long-term. Tiberius is also raising this with Rick. Only remaining
> wait = Tiberius's **live-service-up ping** → then run the on-device probe.
>
> **✅ CLOSED 2026-06-23 (Rick-directed "mark it done")**: store task `63790ce3` →
> **done** (receipts: commit `be03dd9` + status doc; 15/15 ASR tests; APK build
> device-confirmed builds+loads; FCM server LIVE). Client-side live-FCM enablement is
> DELIVERED. Redundant probe-tracking task `81430c6b` dropped (board hygiene).
> **HUMAN CARVE-OUT (Rick-owned verification, NOT Tiffany-owed):** the runbook-92
> on-device wake probe (register token → wake with WS closed → confirm push) remains
> Rick's hardware test on his timeline; when he runs it, Tiffany observes + reports the
> receipt to Tiberius (thread d9f4c1a3) → §3.2.4 milestone declared (or shape-3 fallback).
> **PARKED NON-BLOCKING DECISION for Rick:** reuse `hello-world-foo-423219` vs a dedicated
> `lupin-mobile` Firebase project — recommendation: keep reuse (works + aligned, zero
> rework), prove the feature first, treat clean separation as a deliberate later migration.
>
> **🎉 DEVICE-VERIFIED 2026-06-23**: Rick built + ran the focus-mode UI on device/emulator —
> **it works** (APK builds + loads; UI interactive). Milestone functionally validated.
> **NEW BACKLOG — focus-mode UX polish**: Rick found the UX "a little weird and clunky."
> Deferred follow-up: a UX-refinement pass on the focus-mode surface (interaction flow /
> affordances / pacing) — scope in a later session; not blocking.

> **🆕 2026-08-21 — Focus rail Live/24h + persona icons (A ✅ + B ✅ + C ✅ committed `557e037`; device-feedback round — stop-list render lens, lower-left timestamps, newest-first, TTS-fraction slider (web parity, default 20%) — committed `b9fa06b`; round 2: rail Personas/All scope + persona/system grouping + oldest-session-first (§5f) implemented, uncommitted; voice-DM-to-chip built (§5g); TTS queue viewer + speak-system-senders switch (§5h); login enter-to-submit — all uncommitted)**
> (Tiffany 💍). Rick's rulings by voice: Live(<1h) default + 24h history toggle; persona icon w/ NAME-initial fallback
> (never repo id); one checkbox = hide + mute; order A→B→C. Measured: cold start fetches ALL senders (146 vs 6 in 24h);
> personas seeded only by live events; `/senders-visible` carries `voice_persona`. Plan:
> `src/rnd/2026.08.21-focus-rail-liveness-icons-and-notification-stop-list.md` (extends the 06-25 rail plan below).

> **🆕 2026-08-21 — v2 cutover WAVE 1 DONE (Tiffany 💍, store `94ae726e`)**: `/api/push` + `/api/job-history/{id}/retry`
> → `/api/v2/ask` with the synchronous-response shape carried through repo/BLoC/UI; 30/30 queue tests, 0 failures
> outside `legacy_quarantine/`, live `:7999` probe key-identical. Record: `src/rnd/2026.08.21-v2-cutover-wave1-ask.md`.
> **WAVE 2 BACKLOG (blocked on parent `/api/v2/submit`)**: the eleven submit-shaped doors (9× `agentic_repository.dart`,
> `/api/push-agentic`, `/api/jobs/{id}/resume-from-checkpoint`) → one `/api/v2/submit` call each; do NOT touch
> `/api/deep-research/report` (a read). Follow-ups: wire a retry UI passing `job.questionText`; in-app `/api/v2/resume`
> for `pendingId`. Plan: lupin `src/rnd/v0.2.0/2026.08.21-lupin-mobile-v2-cutover-plan.md`.

> **🆕 NEW BACKLOG — Focus UI active/history filter + exit-visibility (Tiffany 💍, 2026-06-25)**
> — PLAN COMPLETE + REVIEW-READY, no code written yet:
> `src/rnd/2026.06.25-focus-ui-active-history-filter.md` (linked in README index). Part of the
> focus-mode UX refinement above.
> - **What**: make the Focus rail default to currently-LIVE sessions, with a Material-3
>   `SegmentedButton` toggle to a rolling 24h history (live counts + 🟢/🟡 status dots + empty
>   state). Rail is 56px so the control sits in a slim toolbar above the rail+pane.
> - **Core contract (Rick ruling)**: filter = **VISIBILITY, not deletion** — keep ALL cards in
>   state, toggle a derived `visible` flag. Live mode hides exited + aged cards (icon AND card);
>   History re-reveals them within the window. Nothing is destroyed.
> - **Recency math** mirrors the web notifications + multiplexer clients VERBATIM (Mr Radio-verified,
>   DM thread 77099736): 🟢 `<1h` = Live, 🟡 `<24h` = History, ⚪ `≥24h`/null = dropped. Pure
>   client-side; NO server liveness/presence signal exists.
> - **Implementation**: add `lastActivityBySender` to `FocusChatState` (the bloc currently sorts
>   by `lastActivity` then DISCARDS the timestamps) + a 30s aging `Timer.tick` + recompute-on-resume
>   (web dodges the timer via WS re-render; mobile can't for the 1h boundary) + switch cold-start
>   from `senders()` → `sendersVisible(hours:24)` for web parity (already exists in repo).
> - **Exit handling (§4.8)**: on `voice_persona_released`, mark-exited + hide in Live; guard with a
>   3–5s **debounce** (cancel if a same-session `voice_persona_assigned` lands — benign seat-handback
>   vs true exit are wire-identical; payload has no `reason`). Honor `session_reaped` as an immediate
>   worker-exit. Switch off today's grey-to-initial fallback (it diverges from web, which REMOVES the
>   glyph).
> - **⬆ UPSTREAM DEPENDENCY**: parent-repo task **`69edd619`** (Mr Radio-owned, P2 queued) adds
>   `reason={exit|reassigned|borrowed_return|clear}` to the release payload at `voice_persona.py:570`
>   + `notifications.py:609` catalog; **mobile swaps off the debounce when it lands**.
> - **Phasing** (doc §6): P1 state+bloc+predicate+repo-switch; P2 widget; P3 tests (100% L/B/F) +
>   optional filter persistence.
> - **OPEN non-blocking (#8)**: History as single-24h view vs a 1h/24h sub-selector — Rick to
>   confirm; speced as single-24h for now.

1. [ ] [LUPIN-MOBILE] **OSQ-7 Firebase console pass** (EXECUTOR: HUMAN, ~10 min) — follow
   `src/rnd/2026.06.11-focus-mode-voice-chat/91-osq7-firebase-console-runbook.md` Parts A–D;
   then say "Firebase done" and the AI runs the validation checklist.
2. [ ] [LUPIN-MOBILE] **Laptop build wiring + S5 Phase-0 on-device probe** (EXECUTOR: HUMAN,
   AI-scripted) — gradle plugin + `google-services.json` per runbook 92 prelude, then probe
   p1–p11 (`92-s5-phase0-fcm-probe-runbook.md`); receipt lands in 14-section-s5 §8 and DECLARES
   (or shape-3-falls-back) the §3.2.4 milestone.
3. [ ] [LUPIN-MOBILE] **On-device gates**: S5 HUMAN doze gate + Stage-1 "Focus-mode milestone
   gate" fm1–fm6 (runbook section authored; riders: S1 TTS-pacing, S4 ≤2-word transcript bar,
   OSQ-3 boot-order note).
3a. [ ] [LUPIN-MOBILE] **(BACK-BURNERED 2026-06-12 per Rick — GCP migration paused until
   further notice)** Coordinate w/ Tiberius: Firebase Cloud Messaging (FCM) wake-up service
   INTO SERVICE on the test VM (originally Rick's order ~17:15Z). S6 code is merged
   (`83990552`) + locally verified only; get it deployed/configured/live on the test VM.
   Opening DM on `dm-tiberius` 16:58Z (GCP-bundling status + deployed-parent needs beyond the
   OSQ-7 key). Dependency: runbook-91 console pass provisions the service-account key — no
   push emission without it. Done = endpoints + sender verified live on the test VM, receipt
   in section docs §8.
   *Tiberius's answer 17:06Z + Krishna's verdict 17:08Z (CLAUSE CLOSED)*: endpoints +
   `fcm_tokens` persistence are IN-SERVICE at bring-up — compose pulls the pre-S6
   `lupin:1.1.0` image BUT the Decision-3 mount model bind-mounts the on-VM checkout
   `37e5c695` (⊇ S6 merge) over it. Remaining for wake-SENDS: (a) image rebuild with
   `firebase-admin>=6.5` (not in 1.1.0; lazy import → FcmWakeService runs DISABLED, no boot
   risk) + (b) the OSQ-7 service-account key — both batch naturally with Rick's runbook-91
   console pass. In-service verification rides the Phase G probe.
4. [x] [LUPIN-MOBILE] **Fleet wrap** — DONE 2026-06-12 ~12:40Z on Rick's ritual broadcast
   d86c7faf: all 4 seats dismissed with mementos (Arnold badge-Sam, Cheech, Rio; Tiffany's
   parked seat killed — memento impossible at the rate-limit dialog, continuity preserved via
   manifest + section files + her 0259Z memento).
5. [ ] [LUPIN-MOBILE] **FULL legacy-voice-stack retirement incl. flutter_sound** (OSQ-2
   amendment debt, expanded 2026-06-12): scoped GO by read-only audit —
   `src/rnd/2026.06.12-legacy-voice-stack-retirement-scoping.md` (Tier A 3 files ~2,179 LoC +
   Tier B 16 files ~4,931 LoC, all zero-active-importers; zero functionality blockers; 7
   quarantined test files drop per convention; pubspec/flutter_sound removal LAST).
   **Rick's disposition (postgame, ~17:05Z): WAIT — return to this AFTER we have a working
   PoC together.** Full Tier A+B shape when it runs; P5 pub-get/registrant tail on laptop.
6. [x] [LUPIN-MOBILE] **Commit the implementation batch** — DONE 2026-06-12 `b34fa01`
   (Rick authorized via ask_yes_no; Mr. Radio staged selectively from manifest sections
   dabf7fbb + 472b7468 + ad7692cc: 55 files +7,046/−441; `io/` session scratch excluded;
   NOT pushed — push remains Rick-gated).

---

## ⭐ NEXT SESSION — START HERE: 2 laptop-side closures for notif-client-sync Section D (2026-05-23)

**Triggers**: implementation landed but two AC-D tests need laptop-side validation + plumbing.

1. **[LUPIN-MOBILE] Capture AC-D4 fixture** — `test/fixtures/notifications/voice_persona_pool.json` does NOT exist yet. The dev-server probe returned `401 "Missing auth"` (no Bearer token / X-API-Key available in dev-server session). On laptop:
   - Authenticate via `LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL` / `LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD` env vars; obtain Bearer token via `/api/auth/login` OR use X-API-Key
   - `curl -H "Authorization: Bearer <jwt>" http://localhost:7999/api/cosa-voice/voice-persona/pool > test/fixtures/notifications/voice_persona_pool.json`
   - Add a `_capture` provenance metadata block to the JSON root: capture UTC timestamp + endpoint path + server build hash
   - Commit the fixture. AC-D4 then passes as a regression that pins the wire contract every test run.
   - Full capture procedure documented in-line in the AC-D4 test body (`test/unit/notifications/notification_repository_test.dart`).

2. **[LUPIN-MOBILE] Un-skip AC-D6 live probe** — currently `skip:`-documented in `notification_repository_test.dart`. Requires: running `:7999` + authenticated HTTP client + WebSocket test client (reuse `lib/services/websocket/websocket_service.dart` or write a thin test-only ws client). The cascade-ratified probe shape (auth → POST allocate → WS observe `assigned_at` → POST release for net-zero mutation) is documented in-line in the test body. Un-skip by removing the `skip:` argument once laptop plumbing lands.

## ⭐ NEXT SESSION — START HERE: forward-compat items from 2026-05-11 CC sync

**Triggers waiting on parent-Lupin work**:

1. **`artifacts.transcript_path` link in QueueDashboardScreen job detail (cc-* job type)** — forward-compat. Triggers when parent ships ClaudeCodeJob redesign Phase 4 (currently blocked on parent-side PIP plan-review at 4/11 findings; see `<lupin>/src/rnd/v0.1.7/2026.05.07-claude-code-bounded-redesign/`). When the field appears on completed-job records, expose it as a downloadable transcript link in `QueueDashboardScreen` job detail. Out of scope for this session per documentation-first principle — field doesn't exist server-side yet.

2. **INTERACTIVE controls restoration (chat_screen + session_list_screen)** — forward-compat. Triggers when parent restores `inject` / `interrupt` / `end_session` methods on `ClaudeCodeJob` (Q1 of the Bounded redesign reserves stubs for these; future plan). Current state: `chat_screen.dart` + `session_list_screen.dart` are preserved as banner-only screens; route entries still wired. When the parent ships restoration, rebuild these screens from the pre-2026-05-11 git history (commit chain available via `git log --oneline`) + repoint to the new parent endpoints. Plan: file a new session and reverse-port from voice-persona-style Pattern A doc-set.

3. **Canonical URL propagation verification** — when next session opens, re-run pre-Phase-1 gates G1 / G2 from `src/rnd/v0.1.7/2026.05.09-cc-dispatch-retirement-sync/01-plan.md` against `:7999`. If G1 returns HTTP 401 (instead of 404 as of 2026-05-11), parent's rename has propagated to dev server. Update execution log; ready to ship real submissions.

4. **[LUPIN-CC-SUBMIT-RENAME] Update Claude Code submit endpoint from /api/claude-code/queue/submit to /api/claude-code/submit. Alias active for one release cycle from `<commit-date pending parent commit authorization>`. See parent Lupin `src/rnd/v0.1.7/2026.05.09-cc-card-normalization/02-handoff-summary.md` for full context. [Q8 verdict: PRIMARY]** — Parent's CC card normalization (2026-05-11, session 658ea35d, Mr. Radio) renamed the canonical submit URL. The old URL works as a `deprecated=True` alias for one release cycle (through next stable release tag, e.g. v0.1.8). Q8 verdict resolved as PRIMARY — FastAPI 0.115.12 accepts stacked decorators; both routes register. Mobile has the full migration window. Migrate `claude_code_repository.dart` and update BLoC + repository tests. Coordinates with item #2 above (INTERACTIVE controls forward-compat) — same migration epic.

---

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
