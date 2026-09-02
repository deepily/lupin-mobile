# TODO

Last updated: 2026-08-31 (Session `0e3df8ca` — Tiffany 💍, MANAGER): **both `0e7c9214` fixes MERGED** (`0b57602f`→`c91bd1bb`, `6306a166`→`7aac0061`, verified by ancestry) but **not yet served** — auto-reload is off on `:7999`, so a probe now would measure the bug. **Third P1 `88347f65` filed**: the browser delivery path produced zero successful frame deliveries in six hours while printing a success tick each time. `734bd1bf` un-parked; both it and `88347f65` blocked on Rick with a 13:00Z chase.
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
- [~] [LUPIN-MOBILE] **AC-G3 cached-question clause — PROBED 2026-08-30, now PARKED** (store row `734bd1bf`, chase 2026-09-02). Two corrections to how this was written up: the venue is **`:7999`**, not `:8000`, and the question routed to **`MathAgent`**, not `CalculatorAgent`. Rick ran it himself in the web Q&A (no emulator): asked `what is 17 times 23`, answered the correctness prompt **yes**, re-asked. **Result: it did not replay** — so `answer_is_correct = true` is necessary but **not sufficient**. ⚠️ The result is **confounded** and must not be read as a verdict on the guard: two live server defects sit between it and any observable, so "guard refused it" and "served and lost in delivery" are indistinguishable. 🔴 **My instrument was also wrong** — I watched `total_replays`, which is written by `record_replay()` on the *queue cache* path, while the log shows `_handle_solution_snapshot`, a different branch. A zero there was never evidence either way. Settling it needs the `replay_refused_unconfirmed` trace field or an instrumented run — both server-side.

- [x] [LUPIN-MOBILE] ~~Store row `54589356` — blocked on Rick~~ **RULED 2026-08-30, unblocked, owner → Pocholo.** Rick's words: *"Incorrect answers should never be replayed no matter where they are called from"*, and re-executing cached code and re-reading a cached answer **both** gate on `answer_is_correct` being `True` — the distinction is real but buys no exemption. An unset flag from a confirmation timeout counts as not-correct (fail-closed). He accepted the cost on the record: unset is the common case, so a real number of today's exact-match hits become misses. Two call sites: `running_fifo_queue.py:307` and `:1846`. Pocholo then closed the last open question — `/api/v2/submit` never calls `_may_serve` at all, so it is the **front door**, and `v2 executor = queued` routes refusals into a queue whose `100.0` floor matches the very snapshot v2 just refused.
- [x] [LUPIN-MOBILE] ~~**NEXT ACTION — bounce `:7999` first**~~ **PRECONDITION ALREADY SATISFIED, measured 2026-09-02 01:41Z** (store amendment on `734bd1bf`). `lupin-rest-dev` started **2026-09-01 23:13:33 UTC**; both fixes merged 2026-08-30 (`c91bd1bb` 22:01 EDT, `7aac0061` 23:26 EDT) and are ancestors of the served `HEAD` `c34d0733`; `/src` is a host bind-mount. The process loaded code containing both fixes ~22 h after the later merge. **A bounce would change nothing.** ⚠️ Uptime is a coordinate, not a reference — re-read `docker inspect lupin-rest-dev --format '{{.State.StartedAt}}'` before relying on this. What still blocks the probe is server-side and unchanged: nobody has captured the v2 ask response's `path`/`route_reason` for the repeat, so "refused by `_may_serve`" and "served and lost in delivery" stay indistinguishable.
- [ ] [LUPIN-MOBILE] **Store row `88347f65` (P1, parent repo, UNASSIGNED, blocked on Rick 13:00Z)** — the browser delivery path produced **zero** successful frame deliveries in six hours. `slow zebra`: 3,775 drops / 152 `pre-WebSocket` registrations. `foolish goat`: 0 / 0 — silence, not health. Meanwhile `is_connected=True` and a ✓ printed before every drop, which is why nobody noticed. Pocholo declined it (fix is browser-client, not server — correct). Needs Rick to authorise a lupin worker or place it with a web-client seat. ⚠️ **Treat as TWO failures**: a subscription fix explains `slow zebra` and changes nothing for a session the emitter never addresses.
- [ ] [LUPIN-MOBILE] **Store row `0e7c9214` (P1, parent repo, owner Pocholo, I chase)** — found live 2026-08-30 with Rick at the keyboard. A repeat ask announces "New math job", runs it, completes it, and **never announces the answer**. Two *independent* causes, both root-caused the same evening: (1) dropped `job_state_transition` frames ⇐ `get_copy()` injects the requester's email but never their `user_id`, so a replayed snapshot emits to the original creator's stale id — **all 13 rows in `lupin_db_dev` carry the old-format key, zero carry the UUID**; (2) missing answer announcements ⇐ empty `user_email` upstream hitting a bare `return` in `FifoQueue._notify`. Counts close it with no residue: 4 asks, 1 answer, **3** skip warnings, 0 env fallbacks. Pocholo shipped the `user_id` fix and flagged himself that it does **not** reach (2). Still open: where the email is lost upstream.
- [ ] [LUPIN-MOBILE] `log_query()` dies with `expected 768 dimensions, not 0` on an empty embedding, *after* the match already scored `exact_match` / `100.0`. Every repeat ask loses its query-log row. Observed 2026-08-30, undiagnosed, recorded on `0e7c9214`.
- [ ] [LUPIN-MOBILE] Rachel flagged a **render-lens defect** and a **summariser that dropped a test name** as unresolved — read `io/mementos/rachel-a45a8132.md` before picking up her lane.
- [ ] [LUPIN-MOBILE] `android/app/google-services.json` is untracked and was left uncommitted deliberately (Firebase config, credentials-shaped). Decide: commit, gitignore, or leave.
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
- [ ] [LUPIN-MOBILE] **Legacy quarantine triage pass** (`test/legacy_quarantine/`, 22 files / 44 ❌, baseline since 2026-04-16) — produce a per-file mapping `quarantined-test → covered-by-new-test` (or "still meaningful → fix and re-admit"). Three buckets to resolve: (1) API drift / compile errors from Tier 1-4 migration (~16 files: `cacheAudioForText`, `PerformanceMonitorConfig`, `AppError`, `audio.jobId`, stale mocks); (2) live-WS-server dependencies (4 files: `connection_recovery`, `websocket_integration`, `event_system_integration`, `websocket_performance` — replace with BLoC-seam mocks or delete if redundant with current WS smoke suite); (3) test-infra rot (1 file: `user_repository_test.dart` missing `TestWidgetsFlutterBinding` init). Outcome: prune covered files to delete (drop `.mocks.dart` alongside), re-admit any still-meaningful files after fixing. Closes the standing 44 ❌ drift baseline. **Revisit trigger**: when the drift number changes (up or down) OR when the next major data-layer change lands. Reference: `test/legacy_quarantine/README.md` + `src/rnd/v0.1.6-migration/2026.04.16-legacy-test-triage.log`.
- [ ] [LUPIN-MOBILE] Alchemist visual-regression goldens — revisit when inbox tile / DR form / trust chip sees ≥2 regressions in a month
- [ ] [LUPIN-MOBILE] Patrol 4.x native-dialog support — revisit when app requests runtime permissions (mic, notifications) and smokes can't pass them via taps
- [ ] [LUPIN-MOBILE] Maestro MCP flows — revisit after `integration_test/` has ≥5 flows and CI parallelization matters
- [ ] [LUPIN-MOBILE] Fixture coverage for agentic endpoints (DR submit, podcast, etc.) — Stages 2/3 covered auth/notifications/decision-proxy; agentic is the remaining domain
- [ ] [LUPIN-MOBILE] CI job that runs `capture-*-fixtures.py` on a schedule + opens a PR when fixtures diff — catches silent backend drift

### Cross-cutting
